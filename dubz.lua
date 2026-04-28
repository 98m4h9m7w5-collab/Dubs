--[[
    NPC Void v4.1 — Boss Edition + Diagnostics
    ─────────────────────────────────────────────────────────────────────────────
    New in v4:
      · Full diagnostic system — tracks every step of every void attempt
      · Server correction detector — checks if the server snapped the NPC back
      · NPC structure inspector — reports anchored state, HP system type, etc.
      · RemoteEvent finder — logs every remote found and fired
      · Copyable report panel — paste directly back to get a fix
    ─────────────────────────────────────────────────────────────────────────────
--]]

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

-- ═══════════════════════════════════════════════════════════════════════════════
-- 1 · Config
-- ═══════════════════════════════════════════════════════════════════════════════
local cfg = {
    enabled    = false,
    killAll    = false,
    range      = 50,
    nameFilter = "",
    debugLog   = false,
    useBodyVel = true,
    useSpam    = true,
    useAlign   = true,
    useRemotes = true,
}

-- ═══════════════════════════════════════════════════════════════════════════════
-- 2 · Diagnostic System
-- ═══════════════════════════════════════════════════════════════════════════════
local Diag = {}
Diag.entries = {}        -- full structured log
Diag.maxEntries = 200    -- cap so memory doesn't blow up

-- Log levels
local L = { INFO = "INFO", WARN = "WARN", FAIL = "FAIL", OK = "OK  ", STEP = "STEP" }

function Diag.log(level, category, msg)
    local entry = {
        time     = os.clock(),
        level    = level,
        category = category,
        msg      = msg,
    }
    table.insert(Diag.entries, entry)
    if #Diag.entries > Diag.maxEntries then
        table.remove(Diag.entries, 1)
    end
    if cfg.debugLog then
        print(("[NVoid4][%s][%s] %s"):format(level, category, msg))
    end
    -- notify the GUI
    if Diag.onEntry then Diag.onEntry(entry) end
end

-- Build a plain-text report for pasting
function Diag.buildReport()
    local lines = {
        "═══════════════════════════════════════════",
        "  NPC VOID v4 — DIAGNOSTIC REPORT",
        ("  Generated: %s"):format(os.date and os.date("%X") or tostring(os.clock())),
        "═══════════════════════════════════════════",
        "",
    }
    for _, e in ipairs(Diag.entries) do
        table.insert(lines, ("[%s][%s] %s"):format(e.level, e.category, e.msg))
    end
    table.insert(lines, "")
    table.insert(lines, "═══════════════════════════════════════════")
    return table.concat(lines, "\n")
end

function Diag.clear()
    Diag.entries = {}
    if Diag.onClear then Diag.onClear() end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- 3 · State
-- ═══════════════════════════════════════════════════════════════════════════════
local processed   = {}
local liveNPCs    = {}
local spamTargets = {}
local voidCount   = 0
local statusLabel

-- ═══════════════════════════════════════════════════════════════════════════════
-- 4 · Utilities
-- ═══════════════════════════════════════════════════════════════════════════════
local VOID = CFrame.new(0, -2500, 0)

local function getMyRoot()
    local c = player.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

-- Models that should never be treated as NPCs regardless of contents
local NPC_BLACKLIST = { server=true, workspace=true, lighting=true }

local function isNPC(model)
    if not model:IsA("Model") then return false end

    -- FIX: block ALL player characters including local player
    -- GetPlayerFromCharacter has a race condition on respawn, so we
    -- also check every player's .Character directly for safety
    if Players:GetPlayerFromCharacter(model) then return false end
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character == model then return false end
    end

    -- FIX: block model name blacklist ('Server' appeared in report)
    if NPC_BLACKLIST[model.Name:lower()] then return false end

    local hum = model:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    return model:FindFirstChildWhichIsA("BasePart", true) ~= nil
end

local function getRootPart(npc)
    return npc:FindFirstChild("HumanoidRootPart")
        or npc.PrimaryPart
        or npc:FindFirstChildWhichIsA("BasePart", true)
end

local function hasOwnership(rootPart)
    if cfg.killAll then return true end
    local myRoot = getMyRoot()
    if not myRoot then return false end
    local myDist = (rootPart.Position - myRoot.Position).Magnitude
    if myDist > cfg.range then return false end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player and p.Character then
            local r = p.Character:FindFirstChild("HumanoidRootPart")
            if r and (rootPart.Position - r.Position).Magnitude < myDist then
                return false
            end
        end
    end
    return true
end

local function passesFilter(npc)
    if cfg.nameFilter == "" then return true end
    return npc.Name:lower():find(cfg.nameFilter:lower(), 1, true) ~= nil
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- 5 · NPC Inspector  (diagnostic — runs before void attempt)
-- ═══════════════════════════════════════════════════════════════════════════════
local function inspectNPC(npc)
    local name = npc.Name
    local hum  = npc:FindFirstChildOfClass("Humanoid")
    local root = getRootPart(npc)

    Diag.log(L.STEP, "INSPECT", ("═ NPC: '%s'"):format(name))

    -- HP system
    if hum then
        Diag.log(L.INFO, "INSPECT", ("HP: %g / %g"):format(hum.Health, hum.MaxHealth))
    else
        Diag.log(L.WARN, "INSPECT", "No Humanoid found — may use custom HP system")
    end

    -- Check for custom HP values (NumberValue named Health/HP etc.)
    local customHP = false
    for _, v in ipairs(npc:GetDescendants()) do
        if v:IsA("NumberValue") or v:IsA("IntValue") then
            local n = v.Name:lower()
            if n == "health" or n == "hp" or n == "hitpoints" or n == "maxhealth" then
                Diag.log(L.WARN, "INSPECT",
                    ("Custom HP value found: '%s' = %s"):format(v.Name, tostring(v.Value)))
                customHP = true
            end
        end
    end
    if not customHP then
        Diag.log(L.INFO, "INSPECT", "No custom HP values detected")
    end

    -- Root part info
    if root then
        Diag.log(L.INFO, "INSPECT",
            ("RootPart: '%s'  Anchored=%s  CanCollide=%s"):format(
                root.Name,
                tostring(root.Anchored),
                tostring(root.CanCollide)))
        Diag.log(L.INFO, "INSPECT",
            ("Position: (%.1f, %.1f, %.1f)"):format(
                root.Position.X, root.Position.Y, root.Position.Z))

        -- Try to read network owner (server-only but attempt it)
        local ownerOk, ownerResult = pcall(function()
            return root:GetNetworkOwner()
        end)
        if ownerOk then
            local ownerStr = ownerResult and ownerResult.Name or "SERVER (nil)"
            Diag.log(L.INFO, "INSPECT", ("NetworkOwner: %s"):format(ownerStr))
            if ownerResult == nil then
                Diag.log(L.WARN, "INSPECT",
                    "NetworkOwner is SERVER — physics changes may be corrected!")
            elseif ownerResult == player then
                Diag.log(L.OK,   "INSPECT", "NetworkOwner is YOU — void should work")
            else
                Diag.log(L.WARN, "INSPECT",
                    ("NetworkOwner is another player: %s"):format(ownerResult.Name))
            end
        else
            Diag.log(L.WARN, "INSPECT",
                "GetNetworkOwner() blocked (client-side) — cannot confirm ownership")
        end
    else
        Diag.log(L.FAIL, "INSPECT", "No root part found — void will be skipped")
    end

    -- Count anchored parts
    local total, anchored = 0, 0
    for _, p in ipairs(npc:GetDescendants()) do
        if p:IsA("BasePart") then
            total = total + 1
            if p.Anchored then anchored = anchored + 1 end
        end
    end
    Diag.log(L.INFO, "INSPECT",
        ("%d BaseParts total, %d anchored"):format(total, anchored))

    -- Check for existing BodyMovers fighting us
    if root then
        local movers = {}
        for _, inst in ipairs(root:GetChildren()) do
            if inst:IsA("BodyMover") or inst:IsA("Constraint") then
                table.insert(movers, inst.ClassName .. ":" .. inst.Name)
            end
        end
        if #movers > 0 then
            Diag.log(L.WARN, "INSPECT",
                ("Existing movers on root: %s"):format(table.concat(movers, ", ")))
        else
            Diag.log(L.INFO, "INSPECT", "No conflicting movers on root")
        end
    end

    -- Ownership distance
    local myRoot = getMyRoot()
    if myRoot and root then
        local dist = (root.Position - myRoot.Position).Magnitude
        Diag.log(L.INFO, "INSPECT",
            ("Distance to NPC: %.1f studs (range: %d)"):format(dist, cfg.range))
        if dist > cfg.range and not cfg.killAll then
            Diag.log(L.FAIL, "INSPECT",
                "OUT OF RANGE — increase range or enable 'Void All'")
        end
    end

    Diag.log(L.STEP, "INSPECT", "Inspection complete")
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- 6 · Server Correction Detector
--     Sets the NPC to void, waits 3 ticks, checks if server snapped it back
-- ═══════════════════════════════════════════════════════════════════════════════
local function detectServerCorrection(npc, root)
    local testPos = Vector3.new(0, -500, 0)   -- not full void, just far enough to test
    local before  = root.CFrame

    pcall(function() root.CFrame = CFrame.new(testPos) end)

    task.wait(0.1)   -- give server time to respond

    local after = root.CFrame
    local moved = (after.Position - testPos).Magnitude

    if moved > 50 then
        Diag.log(L.FAIL, "CORRECTION",
            ("SERVER IS CORRECTING '%s' — snapped back %.0f studs in 0.1s"):format(
                npc.Name, moved))
        Diag.log(L.WARN, "CORRECTION",
            "SetNetworkOwner(nil) likely active — CFrame spam or remotes needed")
        -- Restore roughly original position
        pcall(function() root.CFrame = before end)
        return true   -- server IS correcting
    else
        Diag.log(L.OK, "CORRECTION",
            ("No server correction on '%s' — client owns physics"):format(npc.Name))
        return false  -- server is NOT correcting
    end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- 7 · Kill Methods (with diagnostic logging)
-- ═══════════════════════════════════════════════════════════════════════════════

local function methodBodyVel(npc)
    Diag.log(L.STEP, "BODYVEL", ("Applying to '%s'"):format(npc.Name))
    local root = getRootPart(npc)
    if not root then
        Diag.log(L.FAIL, "BODYVEL", "No root part — skipped")
        return false
    end

    local unanchored = 0
    for _, p in ipairs(npc:GetDescendants()) do
        if p:IsA("BasePart") and p.Anchored then
            pcall(function() p.Anchored = false end)
            unanchored = unanchored + 1
        end
    end
    if unanchored > 0 then
        Diag.log(L.INFO, "BODYVEL", ("Unanchored %d parts"):format(unanchored))
    end

    local removed = 0
    for _, inst in ipairs(root:GetChildren()) do
        if inst:IsA("BodyMover") then
            pcall(function() inst:Destroy() end)
            removed = removed + 1
        end
    end
    if removed > 0 then
        Diag.log(L.INFO, "BODYVEL", ("Removed %d conflicting BodyMovers"):format(removed))
    end

    local ok, err = pcall(function()
        local bv = Instance.new("BodyVelocity")
        bv.Name     = tostring(math.random(1e5, 9e5))
        bv.Velocity = Vector3.new(0, -9999, 0)
        bv.MaxForce = Vector3.new(0, 1e9, 0)
        bv.P        = 1e9
        bv.Parent   = root
    end)

    if ok then
        Diag.log(L.OK, "BODYVEL", "BodyVelocity applied")
    else
        Diag.log(L.FAIL, "BODYVEL", ("BodyVelocity failed: %s"):format(tostring(err)))
    end

    task.delay(0.08, function()
        if root and root.Parent then
            local ok2, err2 = pcall(function() root.CFrame = VOID end)
            if ok2 then
                Diag.log(L.OK,   "BODYVEL", "Fallback CFrame teleport fired")
            else
                Diag.log(L.FAIL, "BODYVEL",
                    ("Fallback CFrame failed: %s"):format(tostring(err2)))
            end
        end
    end)

    return ok
end

local function methodSpam(npc)
    Diag.log(L.STEP, "SPAM", ("CFrame spam started on '%s'"):format(npc.Name))
    spamTargets[npc] = true
    local ticks = 0
    task.delay(5, function()
        spamTargets[npc] = nil
        Diag.log(L.INFO, "SPAM",
            ("Spam ended for '%s' after ~%d ticks"):format(npc.Name, ticks))
    end)
    -- count ticks externally (incremented in heartbeat)
    spamTargets[npc] = { active = true, ticks = 0 }
end

local function methodAlign(npc)
    Diag.log(L.STEP, "ALIGN", ("Applying AlignPosition to '%s'"):format(npc.Name))
    local root = getRootPart(npc)
    if not root then
        Diag.log(L.FAIL, "ALIGN", "No root part — skipped")
        return
    end

    for _, p in ipairs(npc:GetDescendants()) do
        if p:IsA("BasePart") then
            pcall(function() p.Anchored = false end)
        end
    end

    local ok, err = pcall(function()
        local att0 = Instance.new("Attachment")
        att0.Name   = tostring(math.random(1e5, 9e5))
        att0.Parent = root

        local att1 = Instance.new("Attachment")
        att1.Name     = tostring(math.random(1e5, 9e5))
        att1.Position = Vector3.new(0, -2500, 0)
        att1.Parent   = workspace.Terrain

        local align = Instance.new("AlignPosition")
        align.Name            = tostring(math.random(1e5, 9e5))
        align.Attachment0     = att0
        align.Attachment1     = att1
        align.MaxForce        = 1e9
        align.MaxVelocity     = 9999
        align.Responsiveness  = 200
        align.RigidityEnabled = true
        align.Parent          = root

        task.delay(3, function()
            pcall(function() att0:Destroy() end)
            pcall(function() att1:Destroy() end)
            pcall(function() align:Destroy() end)
            Diag.log(L.INFO, "ALIGN", ("AlignPosition cleaned up for '%s'"):format(npc.Name))
        end)
    end)

    if ok then
        Diag.log(L.OK, "ALIGN", "AlignPosition applied successfully")
    else
        Diag.log(L.FAIL, "ALIGN", ("AlignPosition error: %s"):format(tostring(err)))
    end
end

local DAMAGE_KEYS = {
    "damage", "takedamage", "hurt", "hit", "kill",
    "attack", "dealdamage", "inflict", "reducehp",
    "bossdamage", "npcdamage", "enemydamage"
}

local function methodRemotes(npc)
    Diag.log(L.STEP, "REMOTES", ("Scanning remotes for '%s'"):format(npc.Name))
    local hum  = npc:FindFirstChildOfClass("Humanoid")
    local dmg  = hum and (hum.MaxHealth + 99999) or 99999
    local fired = 0

    -- Direct health attempt
    -- FIX: hum.Health = 0 only changes the CLIENT-SIDE value.
    -- The server may reject it and correct back. We verify after 1s
    -- by checking if the model is GONE from workspace (real death)
    -- rather than just reading .Health which can be a stale client value.
    pcall(function()
        if hum then hum.Health = 0 end
    end)

    task.wait(1)  -- let server respond

    -- If model was removed by the server → it actually died
    if not npc.Parent then
        Diag.log(L.OK, "REMOTES", "Direct Health=0 confirmed — model removed by server")
        return
    end

    -- Re-read health after server correction window
    local humNow = npc:FindFirstChildOfClass("Humanoid")
    local hpNow  = humNow and humNow.Health or -1

    if hpNow <= 0 then
        -- Still showing 0 — could be real or still a stale client value
        Diag.log(L.WARN, "REMOTES",
            "Health reads 0 but model still exists — may be client-side only (false positive)")
    else
        Diag.log(L.INFO, "REMOTES",
            ("Direct Health rejected by server — HP corrected back to %g"):format(hpNow))
    end

    for _, remote in ipairs(game:GetDescendants()) do
        if remote:IsA("RemoteEvent") or remote:IsA("RemoteFunction") then
            local nameLower = remote.Name:lower():gsub("[%s_%-]", "")
            for _, key in ipairs(DAMAGE_KEYS) do
                if nameLower:find(key, 1, true) then
                    local path = remote:GetFullName()
                    local ok1 = pcall(function()
                        if remote:IsA("RemoteEvent") then
                            remote:FireServer(npc, dmg)
                        else
                            remote:InvokeServer(npc, dmg)
                        end
                    end)
                    Diag.log(ok1 and L.OK or L.FAIL, "REMOTES",
                        ("Fired '%s' [%s] → %s"):format(
                            remote.Name, path, ok1 and "sent" or "blocked"))
                    fired = fired + 1
                    break
                end
            end
        end
    end

    if fired == 0 then
        Diag.log(L.WARN, "REMOTES",
            "No damage remotes found — game may handle damage purely server-side")
    else
        Diag.log(L.INFO, "REMOTES", ("%d remote(s) fired"):format(fired))
    end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- 8 · Main void dispatcher (with full diagnostic flow)
-- ═══════════════════════════════════════════════════════════════════════════════
local function attemptVoid(npc, forced)
    Diag.log(L.STEP, "VOID", ("▶ Starting void attempt on '%s'"):format(npc.Name))

    -- Step 1: inspect
    inspectNPC(npc)

    local root = getRootPart(npc)
    if not root then
        Diag.log(L.FAIL, "VOID", "Aborting — no root part")
        return
    end

    -- Step 2: server correction test (async — runs in background)
    task.spawn(function()
        local serverCorrecting = detectServerCorrection(npc, root)

        -- Step 3: apply methods based on what we learned
        if not serverCorrecting then
            if cfg.useBodyVel then methodBodyVel(npc) end
        else
            Diag.log(L.WARN, "VOID",
                "Skipping BodyVelocity (server correcting) — using Spam + Align + Remotes")
        end

        if cfg.useAlign   then methodAlign(npc)   end
        if cfg.useSpam    then methodSpam(npc)     end
        if cfg.useRemotes then methodRemotes(npc)  end

        -- Step 4: verify death properly
        -- FIX: wait 4s (not 2s) so server has time to correct client values.
        -- Only trust .Health if the model is also GONE from workspace.
        -- If model still exists but Health=0, that is likely a client-side false positive.
        task.wait(4)

        -- Check 1: model removed from workspace = definitive death
        if not npc.Parent then
            Diag.log(L.OK, "VOID", ("✔ CONFIRMED DEAD — '%s' removed from workspace"):format(npc.Name))
            voidCount = voidCount + 1
            if statusLabel then statusLabel.Text = ("● %d voided"):format(voidCount) end
            return
        end

        -- Check 2: re-read humanoid after server correction window
        local humNow = npc:FindFirstChildOfClass("Humanoid")
        if not humNow then
            Diag.log(L.OK, "VOID", ("✔ CONFIRMED DEAD — '%s' Humanoid gone"):format(npc.Name))
            voidCount = voidCount + 1
            if statusLabel then statusLabel.Text = ("● %d voided"):format(voidCount) end
            return
        end

        local hpNow = humNow.Health
        if hpNow <= 0 and not npc.Parent then
            -- Model gone AND health 0 — definitely dead
            Diag.log(L.OK, "VOID", ("✔ CONFIRMED DEAD — '%s'"):format(npc.Name))
            voidCount = voidCount + 1
            if statusLabel then statusLabel.Text = ("● %d voided"):format(voidCount) end
        elseif hpNow <= 0 and npc.Parent then
            -- Health 0 but model still in workspace — false positive
            Diag.log(L.WARN, "VOID",
                ("⚠ FALSE POSITIVE — '%s' Health=0 client-side but model still exists (server rejected)"):format(npc.Name))
            Diag.log(L.INFO, "VOID", "Server is likely blocking all health changes — void drop is only option")
            Diag.log(L.INFO, "VOID", "Copy report and paste it back for a targeted fix")
        else
            Diag.log(L.FAIL, "VOID",
                ("✘ FAILED — '%s' alive  HP=%g/%g"):format(npc.Name, hpNow, humNow.MaxHealth))
            Diag.log(L.INFO, "VOID", "Copy this report and paste it back for a targeted fix")
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- 9 · Teleport + Instant Kill
-- ═══════════════════════════════════════════════════════════════════════════════

-- Finds an NPC by exact or partial name match from liveNPCs
local function findNPCByName(name)
    local lower = name:lower()
    for npc in pairs(liveNPCs) do
        if npc.Name:lower():find(lower, 1, true) then
            return npc
        end
    end
    return nil
end

-- Returns all live NPCs sorted by distance from player
local function getSortedNPCs()
    local myRoot = getMyRoot()
    local list = {}
    for npc in pairs(liveNPCs) do
        local root = getRootPart(npc)
        local dist = (root and myRoot)
            and (root.Position - myRoot.Position).Magnitude
            or math.huge
        table.insert(list, { npc = npc, dist = dist })
    end
    table.sort(list, function(a, b) return a.dist < b.dist end)
    return list
end

-- Teleports the player directly next to the NPC's root part
local function teleportToNPC(npc)
    local myChar = player.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    local npcRoot = getRootPart(npc)
    if not myRoot or not npcRoot then
        Diag.log(L.FAIL, "TELEPORT", "Missing root part — cannot teleport")
        return false
    end
    -- Offset slightly so we don't clip inside the NPC
    local offset = Vector3.new(3, 0, 3)
    myRoot.CFrame = CFrame.new(npcRoot.Position + offset)
    Diag.log(L.OK, "TELEPORT",
        ("Teleported to '%s' at (%.1f, %.1f, %.1f)"):format(
            npc.Name,
            npcRoot.Position.X,
            npcRoot.Position.Y,
            npcRoot.Position.Z))
    return true
end

-- Stepped teleport: moves in increments each frame.
-- Use this for games with anti-teleport that kick you back if you move too far.
local function steppedTeleport(npc, onDone)
    local npcRoot = getRootPart(npc)
    if not npcRoot then
        Diag.log(L.FAIL, "TELEPORT", "No NPC root — stepped teleport aborted")
        return
    end

    local STEP_SIZE = 200   -- studs per step
    local STEP_DELAY = 0.06 -- seconds between steps
    local MAX_STEPS = 60    -- give up after 60 steps (~3600 studs max)

    Diag.log(L.INFO, "TELEPORT",
        ("Stepped teleport to '%s' starting (step=%d studs)"):format(npc.Name, STEP_SIZE))

    task.spawn(function()
        for i = 1, MAX_STEPS do
            local myRoot = getMyRoot()
            if not myRoot then break end
            local target = npcRoot.Position + Vector3.new(3, 0, 3)
            local dist   = (myRoot.Position - target).Magnitude
            if dist <= STEP_SIZE then
                -- Close enough — do final snap
                myRoot.CFrame = CFrame.new(target)
                Diag.log(L.OK, "TELEPORT",
                    ("Stepped teleport done in %d steps"):format(i))
                if onDone then onDone() end
                return
            end
            -- Move one step toward target
            local dir = (target - myRoot.Position).Unit
            myRoot.CFrame = CFrame.new(myRoot.Position + dir * STEP_SIZE)
            task.wait(STEP_DELAY)
        end
        Diag.log(L.WARN, "TELEPORT", "Stepped teleport hit max steps — may not have reached NPC")
        if onDone then onDone() end
    end)
end

-- Master function: teleport → wait for ownership → void
local function teleportAndKill(npc, useStepped)
    if not npc or not liveNPCs[npc] then
        Diag.log(L.WARN, "TPKILL", "Target NPC not found or already dead")
        return
    end

    local hum = npc:FindFirstChildOfClass("Humanoid")
    Diag.log(L.STEP, "TPKILL",
        ("▶ Teleport+Kill on '%s' (HP: %g)  stepped=%s"):format(
            npc.Name,
            hum and hum.Health or -1,
            tostring(useStepped)))

    local function doKill()
        -- Wait 2 frames for Roblox to transfer network ownership
        task.wait(0.1)
        processed[npc] = nil   -- reset so attemptVoid runs fresh
        attemptVoid(npc, true)
    end

    if useStepped then
        steppedTeleport(npc, doKill)
    else
        local ok = teleportToNPC(npc)
        if ok then doKill() end
    end
end

-- ── NPC Tracker
-- ═══════════════════════════════════════════════════════════════════════════════
local function onAdded(obj)
    if isNPC(obj) then
        liveNPCs[obj] = true
    end
end
local function onRemoving(obj)
    if liveNPCs[obj] then
        liveNPCs[obj]    = nil
        processed[obj]   = nil
        spamTargets[obj] = nil
    end
end
for _, v in ipairs(workspace:GetDescendants()) do onAdded(v) end
workspace.DescendantAdded:Connect(onAdded)
workspace.DescendantRemoving:Connect(onRemoving)
workspace.DescendantAdded:Connect(function(obj)
    if obj:IsA("Humanoid") then
        obj:GetPropertyChangedSignal("Health"):Connect(function()
            if obj.Health <= 0 and obj.Parent then
                liveNPCs[obj.Parent]    = nil
                spamTargets[obj.Parent] = nil
            end
        end)
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- 10 · Heartbeat
-- ═══════════════════════════════════════════════════════════════════════════════
RunService.Heartbeat:Connect(function()
    -- CFrame spam for server-locked NPCs
    for npc, state in pairs(spamTargets) do
        if type(state) == "table" and state.active and liveNPCs[npc] then
            state.ticks = state.ticks + 1
            for _, part in ipairs(npc:GetDescendants()) do
                if part:IsA("BasePart") then
                    pcall(function() part.CFrame = VOID end)
                end
            end
        end
    end

    if not cfg.enabled then return end

    for npc in pairs(liveNPCs) do
        if not processed[npc] and passesFilter(npc) then
            local root = getRootPart(npc)
            if root and hasOwnership(root) then
                processed[npc] = true
                attemptVoid(npc, false)
            end
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- 11 · GUI
-- ═══════════════════════════════════════════════════════════════════════════════
local C = {
    bg      = Color3.fromRGB(11, 11, 16),
    surface = Color3.fromRGB(20, 20, 30),
    card    = Color3.fromRGB(26, 26, 40),
    border  = Color3.fromRGB(50, 50, 78),
    accent  = Color3.fromRGB(108, 92, 231),
    accentH = Color3.fromRGB(140, 122, 255),
    txt     = Color3.fromRGB(225, 222, 240),
    txtD    = Color3.fromRGB(120, 116, 148),
    on      = Color3.fromRGB(92, 214, 140),
    off     = Color3.fromRGB(55, 52, 75),
    knob    = Color3.fromRGB(240, 238, 255),
    danger  = Color3.fromRGB(220, 60, 60),
    warn    = Color3.fromRGB(240, 180, 60),
    ok      = Color3.fromRGB(92, 214, 140),
    fail    = Color3.fromRGB(220, 60, 60),
    info    = Color3.fromRGB(120, 160, 240),
    step    = Color3.fromRGB(180, 140, 255),
}

local LEVEL_COLORS = {
    [L.OK]   = C.ok,
    [L.FAIL] = C.fail,
    [L.WARN] = C.warn,
    [L.INFO] = C.info,
    [L.STEP] = C.step,
}

-- ═══════════════════════════════════════════════════════════════════════════════
-- 11 · GUI  — Streamlined
--
--   Layout (main window):
--   ┌──────────────────────────────┐
--   │ ⚡ NPC Void  v4.2      [−]  │
--   ├──────────────────────────────┤
--   │ ● 0 voided   tracking 0      │
--   ├──────────────────────────────┤
--   │ 🎯 Boss name (blank=nearest) │
--   │ [ e.g. DIO               ]  │
--   │                              │
--   │ ┌── NPC LIST ──────────────┐ │
--   │ │ .Heaven DIO  50k  4252s  │ │  ← click any row = one-click kill
--   │ │ Netherstar1  1k   126s   │ │
--   │ └──────────────────────────┘ │
--   │                              │
--   │  [  ☠  KILL TARGET / NEAR  ] │  ← THE one button
--   │                              │
--   │  ▸ Advanced           [open] │  ← collapsible settings
--   └──────────────────────────────┘
--
--   Diagnostic window stays exactly the same.
-- ═══════════════════════════════════════════════════════════════════════════════

local sg = Instance.new("ScreenGui")
sg.Name = tostring(math.random(1e6, 9e6))
sg.ResetOnSpawn = false; sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.IgnoreGuiInset = true; sg.Parent = player.PlayerGui

local ti2 = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- ── Shared helpers ────────────────────────────────────────────────────────────
local function makeWindow(name, w, h, x, y)
    local win = Instance.new("Frame", sg)
    win.Name = name; win.Size = UDim2.new(0, w, 0, h)
    win.Position = UDim2.new(0, x, 0.5, y)
    win.BackgroundColor3 = C.bg; win.BorderSizePixel = 0
    win.Active = true; win.Draggable = true; win.ClipsDescendants = true
    Instance.new("UICorner", win).CornerRadius = UDim.new(0, 12)
    local s = Instance.new("UIStroke", win); s.Color = C.border; s.Thickness = 1
    return win
end

local function makeTitleBar(parent, title, icon, onMinimize)
    local tb = Instance.new("Frame", parent)
    tb.Size = UDim2.new(1, 0, 0, 40); tb.BackgroundColor3 = C.surface
    tb.BorderSizePixel = 0; Instance.new("UICorner", tb).CornerRadius = UDim.new(0, 12)
    local fix = Instance.new("Frame", tb)
    fix.Size = UDim2.new(1, 0, 0, 12); fix.Position = UDim2.new(0, 0, 1, -12)
    fix.BackgroundColor3 = C.surface; fix.BorderSizePixel = 0
    local ic = Instance.new("TextLabel", tb)
    ic.Size = UDim2.new(0, 28, 1, 0); ic.Position = UDim2.new(0, 10, 0, 0)
    ic.BackgroundTransparency = 1; ic.Text = icon
    ic.TextSize = 15; ic.Font = Enum.Font.GothamBold; ic.TextColor3 = C.accentH
    local tl = Instance.new("TextLabel", tb)
    tl.Size = UDim2.new(1, -80, 1, 0); tl.Position = UDim2.new(0, 34, 0, 0)
    tl.BackgroundTransparency = 1; tl.Text = title; tl.TextSize = 13
    tl.Font = Enum.Font.GothamBold; tl.TextColor3 = C.txt
    tl.TextXAlignment = Enum.TextXAlignment.Left
    local mb = Instance.new("TextButton", tb)
    mb.Size = UDim2.new(0, 28, 0, 28); mb.Position = UDim2.new(1, -36, 0.5, -14)
    mb.BackgroundColor3 = C.card; mb.Text = "−"; mb.TextColor3 = C.txtD
    mb.TextSize = 18; mb.Font = Enum.Font.GothamBold; mb.BorderSizePixel = 0
    Instance.new("UICorner", mb).CornerRadius = UDim.new(0, 7)
    mb.MouseButton1Click:Connect(onMinimize)
    return tb, mb
end

local function makeContent(parent, yOff)
    local c = Instance.new("Frame", parent)
    c.Size = UDim2.new(1, 0, 1, -yOff); c.Position = UDim2.new(0, 0, 0, yOff)
    c.BackgroundTransparency = 1; c.BorderSizePixel = 0; c.ClipsDescendants = true
    local l = Instance.new("UIListLayout", c)
    l.Padding = UDim.new(0, 7); l.SortOrder = Enum.SortOrder.LayoutOrder
    l.HorizontalAlignment = Enum.HorizontalAlignment.Center
    local p = Instance.new("UIPadding", c)
    p.PaddingTop = UDim.new(0, 10); p.PaddingBottom = UDim.new(0, 10)
    p.PaddingLeft = UDim.new(0, 12); p.PaddingRight = UDim.new(0, 12)
    return c
end

local function cardFrame(parent, h, order)
    local f = Instance.new("Frame", parent)
    f.Size = UDim2.new(1, 0, 0, h); f.BackgroundColor3 = C.card
    f.BorderSizePixel = 0; f.LayoutOrder = order
    Instance.new("UICorner", f).CornerRadius = UDim.new(0, 8)
    return f
end

local function dividerRow(parent, txt, order)
    local r = Instance.new("Frame", parent)
    r.Size = UDim2.new(1, 0, 0, 18); r.BackgroundTransparency = 1
    r.BorderSizePixel = 0; r.LayoutOrder = order
    local l = Instance.new("Frame", r)
    l.Size = UDim2.new(1, 0, 0, 1); l.Position = UDim2.new(0, 0, 0.5, 0)
    l.BackgroundColor3 = C.border; l.BorderSizePixel = 0
    local lb = Instance.new("TextLabel", r)
    lb.Size = UDim2.new(0, 110, 1, 0); lb.Position = UDim2.new(0.5, -55, 0, 0)
    lb.BackgroundColor3 = C.bg; lb.BorderSizePixel = 0; lb.Text = txt
    lb.TextColor3 = C.txtD; lb.TextSize = 10; lb.Font = Enum.Font.GothamBold
    lb.TextXAlignment = Enum.TextXAlignment.Center
end

-- Small pill toggle used inside advanced panel
local function toggleRow(parent, lbl, order, default, cb)
    local c = cardFrame(parent, 44, order)
    local l = Instance.new("TextLabel", c)
    l.Size = UDim2.new(0.7, 0, 1, 0); l.Position = UDim2.new(0, 12, 0, 0)
    l.BackgroundTransparency = 1; l.Text = lbl; l.TextColor3 = C.txt
    l.TextSize = 12; l.Font = Enum.Font.Gotham; l.TextXAlignment = Enum.TextXAlignment.Left
    local pill = Instance.new("Frame", c)
    pill.Size = UDim2.new(0, 44, 0, 22); pill.Position = UDim2.new(1, -56, 0.5, -11)
    pill.BorderSizePixel = 0; Instance.new("UICorner", pill).CornerRadius = UDim.new(1, 0)
    local knob = Instance.new("Frame", pill)
    knob.Size = UDim2.new(0, 18, 0, 18); knob.BorderSizePixel = 0
    knob.BackgroundColor3 = C.knob; Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)
    local state = default
    local function ref(anim)
        local col = state and C.on or C.off
        local pos = state and UDim2.new(0,24,0.5,-9) or UDim2.new(0,2,0.5,-9)
        if anim then
            TweenService:Create(pill, ti2, {BackgroundColor3=col}):Play()
            TweenService:Create(knob, ti2, {Position=pos}):Play()
        else pill.BackgroundColor3=col; knob.Position=pos end
    end
    ref(false)
    local btn = Instance.new("TextButton", c)
    btn.Size=UDim2.new(1,0,1,0); btn.BackgroundTransparency=1; btn.Text=""
    btn.ZIndex=2
    btn.MouseButton1Click:Connect(function() state=not state; ref(true); cb(state) end)
end

local function inputRow(parent, lbl, placeholder, default, order, cb)
    local c = cardFrame(parent, 56, order)
    local l = Instance.new("TextLabel", c)
    l.Size = UDim2.new(1,-12,0,18); l.Position = UDim2.new(0,10,0,4)
    l.BackgroundTransparency=1; l.Text=lbl; l.TextColor3=C.txtD
    l.TextSize=11; l.Font=Enum.Font.Gotham; l.TextXAlignment=Enum.TextXAlignment.Left
    local box = Instance.new("TextBox", c)
    box.Size=UDim2.new(1,-20,0,24); box.Position=UDim2.new(0,10,0,26)
    box.BackgroundColor3=C.surface; box.BorderSizePixel=0
    box.PlaceholderText=placeholder; box.PlaceholderColor3=C.txtD
    box.Text=default; box.TextColor3=C.txt; box.TextSize=13
    box.Font=Enum.Font.GothamBold; box.ClearTextOnFocus=false
    Instance.new("UICorner", box).CornerRadius = UDim.new(0,6)
    local p = Instance.new("UIPadding", box); p.PaddingLeft = UDim.new(0,6)
    box.FocusLost:Connect(function() cb(box.Text, box) end)
    return box
end

local function actionBtn(parent, lbl, col, order, cb)
    local c = cardFrame(parent, 36, order)
    c.BackgroundTransparency=1
    Instance.new("UIStroke", c).Color = col
    local b = Instance.new("TextButton", c)
    b.Size=UDim2.new(1,0,1,0); b.BackgroundTransparency=1
    b.Text=lbl; b.TextColor3=col; b.TextSize=12
    b.Font=Enum.Font.GothamBold; b.BorderSizePixel=0
    b.MouseButton1Click:Connect(cb)
    return b
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- ── Window 1: Main  (streamlined)
-- ═══════════════════════════════════════════════════════════════════════════════
local MAIN_H   = 490
local ADV_H    = 210   -- height of the collapsible advanced panel
local mainWin  = makeWindow("Main", 275, MAIN_H, 24, -(MAIN_H/2))
local miniMain = false

local _, mainMinBtn = makeTitleBar(mainWin, "NPC Void  ·  v4.2", "⚡", function()
    miniMain = not miniMain
    mainWin.Size = miniMain and UDim2.new(0,275,0,40) or UDim2.new(0,275,0,MAIN_H)
    mainMinBtn.Text = miniMain and "+" or "−"
end)

-- ── Status strip ──────────────────────────────────────────────────────────────
local ss = Instance.new("Frame", mainWin)
ss.Size=UDim2.new(1,-2,0,28); ss.Position=UDim2.new(0,1,0,40)
ss.BackgroundColor3=C.surface; ss.BorderSizePixel=0

statusLabel = Instance.new("TextLabel", ss)
statusLabel.Size=UDim2.new(0.5,0,1,0); statusLabel.Position=UDim2.new(0,12,0,0)
statusLabel.BackgroundTransparency=1; statusLabel.Text="● 0 voided"
statusLabel.TextColor3=C.txtD; statusLabel.TextSize=11
statusLabel.Font=Enum.Font.Gotham; statusLabel.TextXAlignment=Enum.TextXAlignment.Left

local trackLbl = Instance.new("TextLabel", ss)
trackLbl.Size=UDim2.new(0.5,-12,1,0); trackLbl.Position=UDim2.new(0.5,0,0,0)
trackLbl.BackgroundTransparency=1; trackLbl.Text="tracking 0"
trackLbl.TextColor3=C.txtD; trackLbl.TextSize=11
trackLbl.Font=Enum.Font.Gotham; trackLbl.TextXAlignment=Enum.TextXAlignment.Right

task.spawn(function()
    while true do
        local n=0; for _ in pairs(liveNPCs) do n=n+1 end
        trackLbl.Text=("tracking %d"):format(n)
        task.wait(2)
    end
end)

local dv = Instance.new("Frame", mainWin)
dv.Size=UDim2.new(1,-24,0,1); dv.Position=UDim2.new(0,12,0,68)
dv.BackgroundColor3=C.border; dv.BorderSizePixel=0

local mc = makeContent(mainWin, 70)

-- ── Boss name filter ───────────────────────────────────────────────────────────
local targetBox = inputRow(mc, "🎯  Boss Name  (blank = nearest NPC)", "e.g. DIO, Heaven, Boss", "", 1,
    function() end)  -- read on button press, not FocusLost

-- ── NPC list (auto-refresh every 3s) ─────────────────────────────────────────
local listCard = cardFrame(mc, 150, 2)
listCard.BackgroundColor3 = C.surface

local listScroll = Instance.new("ScrollingFrame", listCard)
listScroll.Size=UDim2.new(1,-4,1,-4); listScroll.Position=UDim2.new(0,2,0,2)
listScroll.BackgroundTransparency=1; listScroll.BorderSizePixel=0
listScroll.ScrollBarThickness=3; listScroll.ScrollBarImageColor3=C.border
listScroll.CanvasSize=UDim2.new(0,0,0,0)
listScroll.AutomaticCanvasSize=Enum.AutomaticSize.Y
local listLayout=Instance.new("UIListLayout",listScroll)
listLayout.Padding=UDim.new(0,2); listLayout.SortOrder=Enum.SortOrder.LayoutOrder
local lp=Instance.new("UIPadding",listScroll)
lp.PaddingLeft=UDim.new(0,6); lp.PaddingTop=UDim.new(0,4)

local listRowCount = 0

local function rebuildList()
    for _, c in ipairs(listScroll:GetChildren()) do
        if c:IsA("TextButton") or c:IsA("TextLabel") then c:Destroy() end
    end
    listRowCount = 0

    local sorted = getSortedNPCs()
    if #sorted == 0 then
        local e=Instance.new("TextLabel",listScroll)
        e.Size=UDim2.new(1,0,0,18); e.BackgroundTransparency=1
        e.Text=" No NPCs tracked yet"; e.TextColor3=C.txtD
        e.TextSize=11; e.Font=Enum.Font.Gotham
        e.TextXAlignment=Enum.TextXAlignment.Left
        return
    end

    for i, entry in ipairs(sorted) do
        listRowCount = listRowCount + 1
        local npc  = entry.npc
        local hum  = npc:FindFirstChildOfClass("Humanoid")
        local hp   = hum and math.floor(hum.Health)    or "?"
        local mhp  = hum and math.floor(hum.MaxHealth) or "?"
        local dist = math.floor(entry.dist)
        local inRange = dist <= cfg.range

        local row = Instance.new("TextButton", listScroll)
        row.Size=UDim2.new(1,-2,0,20); row.BorderSizePixel=0
        row.LayoutOrder=i
        row.BackgroundColor3=C.card; row.AutoButtonColor=false
        Instance.new("UICorner",row).CornerRadius=UDim.new(0,4)

        -- Highlight row on hover
        row.MouseEnter:Connect(function()
            TweenService:Create(row,ti2,{BackgroundColor3=C.accent}):Play()
        end)
        row.MouseLeave:Connect(function()
            TweenService:Create(row,ti2,{BackgroundColor3=C.card}):Play()
        end)

        local nameTag = Instance.new("TextLabel", row)
        nameTag.Size=UDim2.new(0.55,0,1,0); nameTag.Position=UDim2.new(0,6,0,0)
        nameTag.BackgroundTransparency=1
        nameTag.Text=npc.Name:sub(1,22)
        nameTag.TextColor3=inRange and C.on or C.txt
        nameTag.TextSize=10; nameTag.Font=Enum.Font.GothamBold
        nameTag.TextXAlignment=Enum.TextXAlignment.Left
        nameTag.TextTruncate=Enum.TextTruncate.AtEnd

        local statsTag = Instance.new("TextLabel", row)
        statsTag.Size=UDim2.new(0.45,-6,1,0); statsTag.Position=UDim2.new(0.55,0,0,0)
        statsTag.BackgroundTransparency=1
        statsTag.Text=("%s/%s  %ds"):format(tostring(hp),tostring(mhp),dist)
        statsTag.TextColor3=C.txtD; statsTag.TextSize=10
        statsTag.Font=Enum.Font.Code
        statsTag.TextXAlignment=Enum.TextXAlignment.Right
        statsTag.TextTruncate=Enum.TextTruncate.AtEnd

        -- One click = fill name box + run full kill pipeline
        row.MouseButton1Click:Connect(function()
            targetBox.Text = npc.Name
            Diag.log(L.INFO, "LIST", ("Clicked '%s' — running kill pipeline"):format(npc.Name))
            -- auto-detect stepped: use stepped if NPC is far away
            local root = getRootPart(npc)
            local myRoot = getMyRoot()
            local dist2 = (root and myRoot)
                and (root.Position - myRoot.Position).Magnitude or 0
            teleportAndKill(npc, dist2 > 500)
        end)
    end
end

-- Auto-refresh every 3 seconds
task.spawn(function()
    while true do
        rebuildList()
        task.wait(3)
    end
end)

-- ── THE one kill button ───────────────────────────────────────────────────────
-- Big, prominent, full-width.  Does the entire pipeline automatically:
--   find → auto-detect distance → stepped/instant teleport → all methods → report
local killCard = Instance.new("Frame", mc)
killCard.Size=UDim2.new(1,0,0,52); killCard.LayoutOrder=3
killCard.BackgroundColor3=C.accent; killCard.BorderSizePixel=0
Instance.new("UICorner",killCard).CornerRadius=UDim.new(0,10)
local killStroke=Instance.new("UIStroke",killCard)
killStroke.Color=C.accentH; killStroke.Thickness=1.5

local killBtn=Instance.new("TextButton",killCard)
killBtn.Size=UDim2.new(1,0,1,0); killBtn.BackgroundTransparency=1
killBtn.Text="☠   KILL TARGET"; killBtn.TextColor3=Color3.fromRGB(255,255,255)
killBtn.TextSize=16; killBtn.Font=Enum.Font.GothamBold; killBtn.BorderSizePixel=0

-- Pulse animation when idle
local pulseTween = TweenService:Create(killCard, TweenInfo.new(0.8,
    Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
    {BackgroundColor3 = C.accentH})
pulseTween:Play()

killBtn.MouseButton1Click:Connect(function()
    -- Stop pulse, flash white to confirm press
    pulseTween:Cancel()
    killCard.BackgroundColor3 = Color3.fromRGB(255,255,255)
    task.delay(0.1, function()
        killCard.BackgroundColor3 = C.accent
        pulseTween:Play()
    end)

    -- Resolve target
    local name   = targetBox.Text:match("^%s*(.-)%s*$")
    local target = (name ~= "") and findNPCByName(name) or nil

    if not target then
        -- fallback to nearest
        local sorted = getSortedNPCs()
        target = sorted[1] and sorted[1].npc or nil
    end

    if not target then
        Diag.log(L.WARN, "KILL", "No NPCs tracked — nothing to kill")
        return
    end

    -- Auto-detect whether stepped teleport is needed
    local root   = getRootPart(target)
    local myRoot = getMyRoot()
    local dist   = (root and myRoot)
        and (root.Position - myRoot.Position).Magnitude or 0
    local stepped = dist > 500

    Diag.log(L.INFO, "KILL",
        ("Target: '%s'  dist=%.0f  stepped=%s"):format(target.Name, dist, tostring(stepped)))

    teleportAndKill(target, stepped)
end)

-- ── Advanced (collapsible) ────────────────────────────────────────────────────
local advOpen = false

local advToggleCard = Instance.new("Frame", mc)
advToggleCard.Size=UDim2.new(1,0,0,32); advToggleCard.LayoutOrder=4
advToggleCard.BackgroundColor3=C.surface; advToggleCard.BorderSizePixel=0
Instance.new("UICorner",advToggleCard).CornerRadius=UDim.new(0,8)

local advToggleBtn=Instance.new("TextButton",advToggleCard)
advToggleBtn.Size=UDim2.new(1,0,1,0); advToggleBtn.BackgroundTransparency=1
advToggleBtn.Text="⚙  Advanced Settings   ▸"
advToggleBtn.TextColor3=C.txtD; advToggleBtn.TextSize=12
advToggleBtn.Font=Enum.Font.GothamBold; advToggleBtn.BorderSizePixel=0

-- Advanced panel (hidden by default)
local advPanel = Instance.new("Frame", mc)
advPanel.Size=UDim2.new(1,0,0,0); advPanel.LayoutOrder=5
advPanel.BackgroundColor3=C.surface; advPanel.BorderSizePixel=0
advPanel.ClipsDescendants=true
Instance.new("UICorner",advPanel).CornerRadius=UDim.new(0,8)

local advLayout=Instance.new("UIListLayout",advPanel)
advLayout.Padding=UDim.new(0,4); advLayout.SortOrder=Enum.SortOrder.LayoutOrder
advLayout.HorizontalAlignment=Enum.HorizontalAlignment.Center
local advPad=Instance.new("UIPadding",advPanel)
advPad.PaddingLeft=UDim.new(0,10); advPad.PaddingRight=UDim.new(0,10)
advPad.PaddingTop=UDim.new(0,6); advPad.PaddingBottom=UDim.new(0,6)

advToggleBtn.MouseButton1Click:Connect(function()
    advOpen = not advOpen
    advToggleBtn.Text = advOpen and "⚙  Advanced Settings   ▾" or "⚙  Advanced Settings   ▸"
    TweenService:Create(advPanel, TweenInfo.new(0.2,Enum.EasingStyle.Quad),
        {Size=UDim2.new(1,0,0, advOpen and ADV_H or 0)}):Play()
    -- Grow/shrink main window too
    local newH = advOpen and (MAIN_H + ADV_H) or MAIN_H
    TweenService:Create(mainWin, TweenInfo.new(0.2,Enum.EasingStyle.Quad),
        {Size=UDim2.new(0,275,0,newH)}):Play()
end)

-- Advanced controls
local function advToggle(lbl, order, default, cb)
    local row = Instance.new("Frame", advPanel)
    row.Size=UDim2.new(1,0,0,30); row.BackgroundTransparency=1
    row.BorderSizePixel=0; row.LayoutOrder=order
    local l=Instance.new("TextLabel",row)
    l.Size=UDim2.new(0.72,0,1,0); l.Position=UDim2.new(0,2,0,0)
    l.BackgroundTransparency=1; l.Text=lbl; l.TextColor3=C.txt
    l.TextSize=11; l.Font=Enum.Font.Gotham; l.TextXAlignment=Enum.TextXAlignment.Left
    local pill=Instance.new("Frame",row)
    pill.Size=UDim2.new(0,38,0,18); pill.Position=UDim2.new(1,-40,0.5,-9)
    pill.BorderSizePixel=0; Instance.new("UICorner",pill).CornerRadius=UDim.new(1,0)
    local knob=Instance.new("Frame",pill)
    knob.Size=UDim2.new(0,14,0,14); knob.BorderSizePixel=0
    knob.BackgroundColor3=C.knob; Instance.new("UICorner",knob).CornerRadius=UDim.new(1,0)
    local state=default
    local function ref(a)
        local col=state and C.on or C.off
        local pos=state and UDim2.new(0,22,0.5,-7) or UDim2.new(0,2,0.5,-7)
        if a then TweenService:Create(pill,ti2,{BackgroundColor3=col}):Play()
               TweenService:Create(knob,ti2,{Position=pos}):Play()
        else pill.BackgroundColor3=col; knob.Position=pos end
    end
    ref(false)
    local btn=Instance.new("TextButton",row)
    btn.Size=UDim2.new(1,0,1,0); btn.BackgroundTransparency=1
    btn.Text=""; btn.ZIndex=2
    btn.MouseButton1Click:Connect(function() state=not state; ref(true); cb(state) end)
end

local function advInput(lbl, placeholder, default, order, cb)
    local row=Instance.new("Frame",advPanel)
    row.Size=UDim2.new(1,0,0,44); row.BackgroundTransparency=1
    row.BorderSizePixel=0; row.LayoutOrder=order
    local l=Instance.new("TextLabel",row)
    l.Size=UDim2.new(1,0,0,16); l.BackgroundTransparency=1; l.Text=lbl
    l.TextColor3=C.txtD; l.TextSize=10; l.Font=Enum.Font.Gotham
    l.TextXAlignment=Enum.TextXAlignment.Left
    local box=Instance.new("TextBox",row)
    box.Size=UDim2.new(1,0,0,22); box.Position=UDim2.new(0,0,0,20)
    box.BackgroundColor3=C.card; box.BorderSizePixel=0
    box.PlaceholderText=placeholder; box.PlaceholderColor3=C.txtD
    box.Text=default; box.TextColor3=C.txt; box.TextSize=11
    box.Font=Enum.Font.GothamBold; box.ClearTextOnFocus=false
    Instance.new("UICorner",box).CornerRadius=UDim.new(0,5)
    local p=Instance.new("UIPadding",box); p.PaddingLeft=UDim.new(0,5)
    box.FocusLost:Connect(function() cb(box.Text,box) end)
end

-- Advanced settings rows
advToggle("  Auto-Kill (proximity scan)",  1, false, function(on)
    cfg.enabled=on
    statusLabel.TextColor3=on and C.on or C.txtD
end)
advToggle("  Void All (ignore range)",     2, false, function(on) cfg.killAll=on    end)
advToggle("  BodyVelocity method",         3, true,  function(on) cfg.useBodyVel=on end)
advToggle("  CFrame Spam method",          4, true,  function(on) cfg.useSpam=on    end)
advToggle("  AlignPosition method",        5, true,  function(on) cfg.useAlign=on   end)
advToggle("  Remote Scan method",          6, true,  function(on) cfg.useRemotes=on end)
advToggle("  Debug Log",                   7, false, function(on) cfg.debugLog=on   end)
advInput("📡  Range (studs)", "50", "50",  8, function(v,box)
    local n=tonumber(v); cfg.range=(n and n>=1) and n or cfg.range
    if not n then box.Text=tostring(cfg.range) end
end)

-- Reset button at bottom of advanced
local resetRow=Instance.new("Frame",advPanel)
resetRow.Size=UDim2.new(1,0,0,28); resetRow.BackgroundTransparency=1
resetRow.BorderSizePixel=0; resetRow.LayoutOrder=9
local resetBtn=Instance.new("TextButton",resetRow)
resetBtn.Size=UDim2.new(1,0,1,0); resetBtn.BackgroundColor3=C.card
resetBtn.Text="↺  Reset Voided List"; resetBtn.TextColor3=C.danger
resetBtn.TextSize=11; resetBtn.Font=Enum.Font.GothamBold; resetBtn.BorderSizePixel=0
Instance.new("UICorner",resetBtn).CornerRadius=UDim.new(0,6)
resetBtn.MouseButton1Click:Connect(function()
    processed={}; spamTargets={}
    voidCount=0; statusLabel.Text="● 0 voided"; statusLabel.TextColor3=C.txtD
    Diag.log(L.INFO,"RESET","Voided list cleared")
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- ── Window 2: Diagnostic Panel (unchanged)
-- ═══════════════════════════════════════════════════════════════════════════════
local diagWin = makeWindow("Diag", 340, 480, 315, -240)
local miniDiag = false

local _, diagMinBtn = makeTitleBar(diagWin, "Diagnostics", "🔍", function()
    miniDiag = not miniDiag
    diagWin.Size = miniDiag and UDim2.new(0,340,0,40) or UDim2.new(0,340,0,480)
    diagMinBtn.Text = miniDiag and "+" or "−"
end)

-- Toolbar
local diagBar = Instance.new("Frame", diagWin)
diagBar.Size=UDim2.new(1,0,0,32); diagBar.Position=UDim2.new(0,0,0,40)
diagBar.BackgroundColor3=C.surface; diagBar.BorderSizePixel=0

local function toolbarBtn(txt, xPos, color, onClick)
    local b = Instance.new("TextButton", diagBar)
    b.Size=UDim2.new(0,72,0,24); b.Position=UDim2.new(0,xPos,0.5,-12)
    b.BackgroundColor3=C.card; b.Text=txt; b.TextColor3=color
    b.TextSize=11; b.Font=Enum.Font.GothamBold; b.BorderSizePixel=0
    Instance.new("UICorner", b).CornerRadius=UDim.new(0,6)
    b.MouseButton1Click:Connect(onClick)
    return b
end

-- Log scroll frame
local logScroll = Instance.new("ScrollingFrame", diagWin)
logScroll.Size=UDim2.new(1,-16,1,-130); logScroll.Position=UDim2.new(0,8,0,76)
logScroll.BackgroundColor3=C.surface; logScroll.BorderSizePixel=0
logScroll.ScrollBarThickness=4; logScroll.ScrollBarImageColor3=C.border
logScroll.CanvasSize=UDim2.new(0,0,0,0); logScroll.AutomaticCanvasSize=Enum.AutomaticSize.Y
Instance.new("UICorner", logScroll).CornerRadius=UDim.new(0,8)
local logLayout = Instance.new("UIListLayout", logScroll)
logLayout.Padding=UDim.new(0,1); logLayout.SortOrder=Enum.SortOrder.LayoutOrder
local logPad = Instance.new("UIPadding", logScroll)
logPad.PaddingLeft=UDim.new(0,6); logPad.PaddingRight=UDim.new(0,6)
logPad.PaddingTop=UDim.new(0,4); logPad.PaddingBottom=UDim.new(0,4)

-- Copy report box
local copyBox = Instance.new("TextBox", diagWin)
copyBox.Size=UDim2.new(1,-16,0,46); copyBox.Position=UDim2.new(0,8,1,-54)
copyBox.BackgroundColor3=C.surface; copyBox.BorderSizePixel=0
copyBox.Text="← click 'Copy Report' then select all and copy (Ctrl+A, Ctrl+C)"
copyBox.TextColor3=C.txtD; copyBox.TextSize=11; copyBox.Font=Enum.Font.Gotham
copyBox.MultiLine=true; copyBox.TextWrapped=true; copyBox.ClearTextOnFocus=false
copyBox.TextXAlignment=Enum.TextXAlignment.Left; copyBox.TextYAlignment=Enum.TextYAlignment.Top
Instance.new("UICorner", copyBox).CornerRadius=UDim.new(0,8)
local cbPad=Instance.new("UIPadding",copyBox)
cbPad.PaddingLeft=UDim.new(0,6); cbPad.PaddingTop=UDim.new(0,4)

local entryCount = 0

local function addLogRow(entry)
    entryCount = entryCount + 1
    local row = Instance.new("TextLabel", logScroll)
    row.Size = UDim2.new(1,0,0,16)
    row.BackgroundTransparency = 1
    row.TextColor3 = LEVEL_COLORS[entry.level] or C.txt
    row.TextSize = 11; row.Font = Enum.Font.Code
    row.TextXAlignment = Enum.TextXAlignment.Left
    row.TextTruncate = Enum.TextTruncate.AtEnd
    row.Text = ("[%s][%s] %s"):format(entry.level, entry.category, entry.msg)
    row.LayoutOrder = entryCount
    row.Name = tostring(entryCount)
    -- Auto-scroll to bottom
    task.defer(function()
        logScroll.CanvasPosition = Vector2.new(0, logScroll.AbsoluteCanvasSize.Y)
    end)
end

-- Wire up Diag callbacks
Diag.onEntry = addLogRow
Diag.onClear = function()
    for _, c in ipairs(logScroll:GetChildren()) do
        if c:IsA("TextLabel") then c:Destroy() end
    end
    entryCount = 0
    copyBox.Text = "Log cleared"
end

-- Toolbar buttons
toolbarBtn("🗑 Clear", 8, C.danger, function()
    Diag.clear()
end)

toolbarBtn("📋 Copy", 88, C.accentH, function()
    copyBox.Text = Diag.buildReport()
    copyBox:CaptureFocus()
    copyBox.SelectionStart = 1
    copyBox.CursorPosition = #copyBox.Text + 1
end)

toolbarBtn("🔍 Inspect", 168, C.warn, function()
    -- Inspect nearest NPC immediately without voiding
    local myRoot = getMyRoot()
    if not myRoot then
        Diag.log(L.WARN, "MANUAL", "Your character isn't loaded")
        return
    end
    local nearest, nearestDist = nil, math.huge
    for npc in pairs(liveNPCs) do
        local r = getRootPart(npc)
        if r then
            local d = (r.Position - myRoot.Position).Magnitude
            if d < nearestDist then nearest=npc; nearestDist=d end
        end
    end
    if nearest then
        inspectNPC(nearest)
    else
        Diag.log(L.WARN, "MANUAL", "No live NPCs found nearby")
    end
end)

toolbarBtn("⚠ Test Fix", 248, C.on, function()
    local myRoot = getMyRoot()
    if not myRoot then return end
    local nearest, nearestDist = nil, math.huge
    for npc in pairs(liveNPCs) do
        local r = getRootPart(npc)
        if r then
            local d=(r.Position-myRoot.Position).Magnitude
            if d<nearestDist then nearest=npc; nearestDist=d end
        end
    end
    if nearest then
        local r = getRootPart(nearest)
        if r then
            task.spawn(function()
                detectServerCorrection(nearest, r)
            end)
        end
    else
        Diag.log(L.WARN, "MANUAL", "No live NPCs found")
    end
end)

-- Startup message
Diag.log(L.INFO, "SYSTEM", "NPC Void v4.2 loaded")
Diag.log(L.INFO, "SYSTEM", "Click any NPC in the list  OR  type a name + press ☠ KILL TARGET")
Diag.log(L.INFO, "SYSTEM", "Script auto-detects distance and picks stepped vs instant teleport")
Diag.log(L.INFO, "SYSTEM", "If void fails: click 📋 Copy → paste report back for a fix")

print("[NPCVoid v4.2] Loaded")
rebuildList()

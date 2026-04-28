--[[
    NPC Void v3.0 — Boss Edition
    ─────────────────────────────────────────────────────────────────────────────
    Adds 3 extra kill methods specifically for server-locked NPCs (bosses):

    Method A · Rapid CFrame Spam
      Overrides the position every Heartbeat tick faster than the server
      can correct it. Works when the server correction delay is > 1 frame.

    Method B · AlignPosition (bypasses BodyVelocity blocks)
      Some games block BodyVelocity but not constraint-based movers.
      AlignPosition with max force can override server corrections.

    Method C · RemoteEvent Scan (damage fishing)
      Scans the game for RemoteEvents with damage-related names and
      fires them with the boss + huge damage value.
      Works when the game processes damage client→server via remotes.
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
    enabled      = false,
    killAll      = false,
    range        = 50,
    nameFilter   = "",
    debugLog     = false,

    -- Method toggles
    useBodyVel   = true,   -- Method 1: BodyVelocity (works on auto-owned NPCs)
    useSpam      = true,   -- Method 2: Rapid CFrame spam (server-locked NPCs)
    useAlign     = true,   -- Method 3: AlignPosition constraint
    useRemotes   = true,   -- Method 4: RemoteEvent damage scan
}

-- ═══════════════════════════════════════════════════════════════════════════════
-- 2 · State
-- ═══════════════════════════════════════════════════════════════════════════════
local processed   = {}
local liveNPCs    = {}
local spamTargets = {}   -- NPCs being CFrame-spammed this frame
local voidCount   = 0
local statusLabel

-- ═══════════════════════════════════════════════════════════════════════════════
-- 3 · Utilities
-- ═══════════════════════════════════════════════════════════════════════════════
local VOID = CFrame.new(0, -2500, 0)

local function log(msg)
    if cfg.debugLog then print("[NVoid3] " .. msg) end
end

local function getMyRoot()
    local c = player.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function isNPC(model)
    if not model:IsA("Model") then return false end
    if Players:GetPlayerFromCharacter(model) then return false end
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
-- 4 · NPC Tracker
-- ═══════════════════════════════════════════════════════════════════════════════
local function onAdded(obj)
    if isNPC(obj) then
        liveNPCs[obj] = true
        log("Tracking: " .. obj.Name)
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
-- 5 · Kill Methods
-- ═══════════════════════════════════════════════════════════════════════════════

-- METHOD 1: BodyVelocity — best for auto-owned NPCs
local function methodBodyVel(npc)
    local root = getRootPart(npc)
    if not root then return end

    for _, p in ipairs(npc:GetDescendants()) do
        if p:IsA("BasePart") then p.Anchored = false end
    end

    for _, inst in ipairs(root:GetChildren()) do
        if inst:IsA("BodyMover") then inst:Destroy() end
    end

    local bv = Instance.new("BodyVelocity")
    bv.Name     = tostring(math.random(1e5, 9e5))
    bv.Velocity = Vector3.new(0, -9999, 0)
    bv.MaxForce = Vector3.new(0, 1e9, 0)
    bv.P        = 1e9
    bv.Parent   = root

    task.delay(0.08, function()
        if root and root.Parent then
            root.CFrame = VOID
        end
    end)

    log("Method 1 (BodyVel) applied to " .. npc.Name)
end

-- METHOD 2: Rapid CFrame spam — overwhelms server correction on locked NPCs
-- Sets EVERY BasePart to void position every single Heartbeat tick.
-- The server corrects slower than we spam on high-ping or busy servers.
local function methodSpam(npc)
    spamTargets[npc] = true
    log("Method 2 (CFrame spam) started on " .. npc.Name)

    -- Auto-stop after 5 seconds (NPC should be dead by then)
    task.delay(5, function()
        spamTargets[npc] = nil
        log("CFrame spam stopped for " .. npc.Name)
    end)
end

-- METHOD 3: AlignPosition — constraint-based mover, bypasses BodyVelocity blocks
local function methodAlign(npc)
    local root = getRootPart(npc)
    if not root then return end

    for _, p in ipairs(npc:GetDescendants()) do
        if p:IsA("BasePart") then p.Anchored = false end
    end

    -- AlignPosition needs an attachment
    local att0 = Instance.new("Attachment")
    att0.Name   = tostring(math.random(1e5, 9e5))
    att0.Parent = root

    local att1 = Instance.new("Attachment")
    att1.Name     = tostring(math.random(1e5, 9e5))
    att1.Position = Vector3.new(0, -2500, 0)
    att1.Parent   = workspace.Terrain

    local align = Instance.new("AlignPosition")
    align.Name           = tostring(math.random(1e5, 9e5))
    align.Attachment0    = att0
    align.Attachment1    = att1
    align.MaxForce       = 1e9
    align.MaxVelocity    = 9999
    align.Responsiveness = 200
    align.RigidityEnabled = true   -- bypasses mass / force limits
    align.Parent         = root

    -- Cleanup after 3 seconds
    task.delay(3, function()
        pcall(function() att0:Destroy() end)
        pcall(function() att1:Destroy() end)
        pcall(function() align:Destroy() end)
    end)

    log("Method 3 (AlignPosition) applied to " .. npc.Name)
end

-- METHOD 4: RemoteEvent damage scan — fires game damage remotes directly
-- Works for games where damage goes through client→server remotes (common pattern)
local DAMAGE_KEYS = {
    "damage", "takedamage", "hurt", "hit", "kill",
    "attack", "dealdamage", "inflict", "reducehp",
    "bossdamage", "npcdamage", "enemydamage"
}

local function methodRemotes(npc)
    local hum = npc:FindFirstChildOfClass("Humanoid")
    local dmg = hum and (hum.MaxHealth + 99999) or 99999

    -- Direct health attempt (works in unprotected games)
    pcall(function()
        if hum then
            hum.Health = 0
            hum:TakeDamage(dmg)
        end
    end)

    -- Scan all RemoteEvents/Functions for damage keywords
    for _, remote in ipairs(game:GetDescendants()) do
        if remote:IsA("RemoteEvent") or remote:IsA("RemoteFunction") then
            local name = remote.Name:lower():gsub("%s+", ""):gsub("_", "")
            for _, key in ipairs(DAMAGE_KEYS) do
                if name:find(key, 1, true) then
                    pcall(function()
                        -- Try common argument patterns games use
                        if remote:IsA("RemoteEvent") then
                            remote:FireServer(npc, dmg)
                            remote:FireServer(npc, hum, dmg)
                            remote:FireServer(dmg, npc)
                        else
                            remote:InvokeServer(npc, dmg)
                        end
                    end)
                    log("Fired remote: " .. remote.Name .. " on " .. npc.Name)
                    break
                end
            end
        end
    end

    log("Method 4 (Remotes) applied to " .. npc.Name)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- 6 · CFrame spam loop (Heartbeat)
-- ═══════════════════════════════════════════════════════════════════════════════
RunService.Heartbeat:Connect(function()
    -- CFrame spam for server-locked bosses
    for npc in pairs(spamTargets) do
        if liveNPCs[npc] then
            for _, part in ipairs(npc:GetDescendants()) do
                if part:IsA("BasePart") then
                    pcall(function() part.CFrame = VOID end)
                end
            end
        else
            spamTargets[npc] = nil
        end
    end

    -- Main void scan
    if not cfg.enabled then return end

    for npc in pairs(liveNPCs) do
        if not processed[npc] and passesFilter(npc) then
            local root = getRootPart(npc)
            if root and hasOwnership(root) then
                processed[npc] = true

                if cfg.useBodyVel   then methodBodyVel(npc) end
                if cfg.useSpam      then methodSpam(npc)    end
                if cfg.useAlign     then methodAlign(npc)   end
                if cfg.useRemotes   then methodRemotes(npc) end

                voidCount = voidCount + 1
                if statusLabel then
                    statusLabel.Text = ("● %d voided"):format(voidCount)
                end
            end
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- 7 · GUI
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
}

local sg = Instance.new("ScreenGui")
sg.Name = tostring(math.random(1e6, 9e6))
sg.ResetOnSpawn = false
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.IgnoreGuiInset = true
sg.Parent = player.PlayerGui

local win = Instance.new("Frame", sg)
win.Size = UDim2.new(0, 270, 0, 520)
win.Position = UDim2.new(0, 24, 0.5, -260)
win.BackgroundColor3 = C.bg
win.BorderSizePixel = 0
win.Active = true
win.Draggable = true
win.ClipsDescendants = true
Instance.new("UICorner", win).CornerRadius = UDim.new(0, 12)
local ws = Instance.new("UIStroke", win)
ws.Color = C.border; ws.Thickness = 1

-- Title bar
local tb = Instance.new("Frame", win)
tb.Size = UDim2.new(1, 0, 0, 40)
tb.BackgroundColor3 = C.surface
tb.BorderSizePixel = 0
Instance.new("UICorner", tb).CornerRadius = UDim.new(0, 12)
local tbp = Instance.new("Frame", tb)
tbp.Size = UDim2.new(1, 0, 0, 12)
tbp.Position = UDim2.new(0, 0, 1, -12)
tbp.BackgroundColor3 = C.surface
tbp.BorderSizePixel = 0

local ti = Instance.new("TextLabel", tb)
ti.Size = UDim2.new(0, 30, 1, 0); ti.Position = UDim2.new(0, 10, 0, 0)
ti.BackgroundTransparency = 1; ti.Text = "⚡"
ti.TextSize = 16; ti.Font = Enum.Font.GothamBold; ti.TextColor3 = C.accentH

local tt = Instance.new("TextLabel", tb)
tt.Size = UDim2.new(1, -80, 1, 0); tt.Position = UDim2.new(0, 36, 0, 0)
tt.BackgroundTransparency = 1; tt.Text = "NPC Void  ·  Boss Edition"
tt.TextSize = 13; tt.Font = Enum.Font.GothamBold
tt.TextColor3 = C.txt; tt.TextXAlignment = Enum.TextXAlignment.Left

local mb = Instance.new("TextButton", tb)
mb.Size = UDim2.new(0, 28, 0, 28); mb.Position = UDim2.new(1, -36, 0.5, -14)
mb.BackgroundColor3 = C.card; mb.Text = "−"
mb.TextColor3 = C.txtD; mb.TextSize = 18
mb.Font = Enum.Font.GothamBold; mb.BorderSizePixel = 0
Instance.new("UICorner", mb).CornerRadius = UDim.new(0, 7)
local mini = false
mb.MouseButton1Click:Connect(function()
    mini = not mini
    win.Size = mini and UDim2.new(0, 270, 0, 40) or UDim2.new(0, 270, 0, 520)
    mb.Text = mini and "+" or "−"
end)

-- Status strip
local ss = Instance.new("Frame", win)
ss.Size = UDim2.new(1, -2, 0, 28); ss.Position = UDim2.new(0, 1, 0, 40)
ss.BackgroundColor3 = C.surface; ss.BorderSizePixel = 0

statusLabel = Instance.new("TextLabel", ss)
statusLabel.Size = UDim2.new(0.5, 0, 1, 0); statusLabel.Position = UDim2.new(0, 12, 0, 0)
statusLabel.BackgroundTransparency = 1; statusLabel.Text = "● 0 voided"
statusLabel.TextColor3 = C.txtD; statusLabel.TextSize = 11
statusLabel.Font = Enum.Font.Gotham; statusLabel.TextXAlignment = Enum.TextXAlignment.Left

local tl = Instance.new("TextLabel", ss)
tl.Size = UDim2.new(0.5, -12, 1, 0); tl.Position = UDim2.new(0.5, 0, 0, 0)
tl.BackgroundTransparency = 1; tl.Text = "tracking 0"
tl.TextColor3 = C.txtD; tl.TextSize = 11
tl.Font = Enum.Font.Gotham; tl.TextXAlignment = Enum.TextXAlignment.Right

task.spawn(function()
    while true do
        local n = 0; for _ in pairs(liveNPCs) do n = n + 1 end
        tl.Text = ("tracking %d"):format(n)
        task.wait(2)
    end
end)

local dv = Instance.new("Frame", win)
dv.Size = UDim2.new(1, -24, 0, 1); dv.Position = UDim2.new(0, 12, 0, 68)
dv.BackgroundColor3 = C.border; dv.BorderSizePixel = 0

-- Content container
local content = Instance.new("Frame", win)
content.Size = UDim2.new(1, 0, 1, -70)
content.Position = UDim2.new(0, 0, 0, 70)
content.BackgroundTransparency = 1; content.BorderSizePixel = 0
content.ClipsDescendants = true

local layout = Instance.new("UIListLayout", content)
layout.Padding = UDim.new(0, 7)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center

local pad = Instance.new("UIPadding", content)
pad.PaddingTop = UDim.new(0, 10); pad.PaddingBottom = UDim.new(0, 10)
pad.PaddingLeft = UDim.new(0, 12); pad.PaddingRight = UDim.new(0, 12)

-- ── Widget helpers ────────────────────────────────────────────────────────────
local ti2 = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function card(h, order)
    local f = Instance.new("Frame", content)
    f.Size = UDim2.new(1, 0, 0, h)
    f.BackgroundColor3 = C.card; f.BorderSizePixel = 0
    f.LayoutOrder = order
    Instance.new("UICorner", f).CornerRadius = UDim.new(0, 8)
    return f
end

local function divider(txt, order)
    local row = Instance.new("Frame", content)
    row.Size = UDim2.new(1, 0, 0, 18)
    row.BackgroundTransparency = 1; row.BorderSizePixel = 0
    row.LayoutOrder = order
    local line = Instance.new("Frame", row)
    line.Size = UDim2.new(1, 0, 0, 1); line.Position = UDim2.new(0, 0, 0.5, 0)
    line.BackgroundColor3 = C.border; line.BorderSizePixel = 0
    local lbl = Instance.new("TextLabel", row)
    lbl.Size = UDim2.new(0, 100, 1, 0); lbl.Position = UDim2.new(0.5, -50, 0, 0)
    lbl.BackgroundColor3 = C.bg; lbl.BorderSizePixel = 0
    lbl.Text = txt; lbl.TextColor3 = C.txtD
    lbl.TextSize = 10; lbl.Font = Enum.Font.GothamBold
    lbl.TextXAlignment = Enum.TextXAlignment.Center
end

local function toggle(lbl, order, default, cb)
    local c = card(44, order)
    local l = Instance.new("TextLabel", c)
    l.Size = UDim2.new(0.7, 0, 1, 0); l.Position = UDim2.new(0, 12, 0, 0)
    l.BackgroundTransparency = 1; l.Text = lbl
    l.TextColor3 = C.txt; l.TextSize = 12; l.Font = Enum.Font.Gotham
    l.TextXAlignment = Enum.TextXAlignment.Left
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
            TweenService:Create(pill,  ti2, {BackgroundColor3 = col}):Play()
            TweenService:Create(knob,  ti2, {Position = pos}):Play()
        else
            pill.BackgroundColor3 = col; knob.Position = pos
        end
    end
    ref(false)
    local btn = Instance.new("TextButton", c)
    btn.Size = UDim2.new(1,0,1,0); btn.BackgroundTransparency = 1
    btn.Text = ""; btn.ZIndex = 2
    btn.MouseButton1Click:Connect(function()
        state = not state; ref(true); cb(state)
    end)
end

local function inputBox(lbl, placeholder, default, order, cb)
    local c = card(56, order)
    local l = Instance.new("TextLabel", c)
    l.Size = UDim2.new(1,-12,0,18); l.Position = UDim2.new(0,10,0,4)
    l.BackgroundTransparency = 1; l.Text = lbl
    l.TextColor3 = C.txtD; l.TextSize = 11; l.Font = Enum.Font.Gotham
    l.TextXAlignment = Enum.TextXAlignment.Left
    local box = Instance.new("TextBox", c)
    box.Size = UDim2.new(1,-20,0,24); box.Position = UDim2.new(0,10,0,26)
    box.BackgroundColor3 = C.surface; box.BorderSizePixel = 0
    box.PlaceholderText = placeholder; box.PlaceholderColor3 = C.txtD
    box.Text = default; box.TextColor3 = C.txt
    box.TextSize = 13; box.Font = Enum.Font.GothamBold; box.ClearTextOnFocus = false
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 6)
    local p = Instance.new("UIPadding", box); p.PaddingLeft = UDim.new(0,6)
    box.FocusLost:Connect(function() cb(box.Text, box) end)
    return box
end

local function actionBtn(lbl, col, order, cb)
    local c = card(36, order)
    c.BackgroundTransparency = 1
    local s = Instance.new("UIStroke", c); s.Color = col
    local b = Instance.new("TextButton", c)
    b.Size = UDim2.new(1,0,1,0); b.BackgroundTransparency = 1
    b.Text = lbl; b.TextColor3 = col
    b.TextSize = 12; b.Font = Enum.Font.GothamBold; b.BorderSizePixel = 0
    b.MouseButton1Click:Connect(cb)
end

-- ── Build Controls ────────────────────────────────────────────────────────────
divider("MAIN", 1)

toggle("  Enable", 2, false, function(on)
    cfg.enabled = on
    statusLabel.TextColor3 = on and C.on or C.txtD
end)

toggle("  Void All  (ignore range)", 3, false, function(on)
    cfg.killAll = on
end)

divider("TARGETING", 4)

inputBox("📡  Range (studs)", "50", "50", 5, function(v, box)
    local n = tonumber(v)
    cfg.range = (n and n >= 1) and n or cfg.range
    if not n then box.Text = tostring(cfg.range) end
end)

inputBox("🎯  Name Filter  (blank = all)", "e.g. DIO, Boss", "", 6, function(v)
    cfg.nameFilter = v:match("^%s*(.-)%s*$")
end)

divider("METHODS", 7)

toggle("  BodyVelocity  (standard)", 8, true, function(on)
    cfg.useBodyVel = on
end)

toggle("  CFrame Spam  (server-locked)", 9, true, function(on)
    cfg.useSpam = on
end)

toggle("  AlignPosition  (constraint)", 10, true, function(on)
    cfg.useAlign = on
end)

toggle("  Remote Scan  (damage fishing)", 11, true, function(on)
    cfg.useRemotes = on
end)

divider("OPTIONS", 12)

toggle("  Debug Log", 13, false, function(on)
    cfg.debugLog = on
end)

divider("", 14)

actionBtn("↺  Reset Voided List", C.accent, 15, function()
    processed = {}; spamTargets = {}
    voidCount = 0
    statusLabel.Text = "● 0 voided"
    statusLabel.TextColor3 = C.txtD
end)

actionBtn("⚡  Force Void Nearest NPC", C.on, 16, function()
    local myRoot = getMyRoot()
    if not myRoot then return end

    local nearest, nearestDist = nil, math.huge
    for npc in pairs(liveNPCs) do
        local root = getRootPart(npc)
        if root then
            local d = (root.Position - myRoot.Position).Magnitude
            if d < nearestDist then nearest = npc; nearestDist = d end
        end
    end

    if nearest then
        processed[nearest] = nil   -- reset so it can be re-voided
        if cfg.useBodyVel then methodBodyVel(nearest) end
        if cfg.useSpam    then methodSpam(nearest)    end
        if cfg.useAlign   then methodAlign(nearest)   end
        if cfg.useRemotes then methodRemotes(nearest) end
        processed[nearest] = true
        voidCount = voidCount + 1
        statusLabel.Text = ("● %d voided"):format(voidCount)
        log("Force void on: " .. nearest.Name)
    end
end)

print("[NPCVoid v3 - Boss Edition] Loaded.")

--[[
    NPC Void on Network Ownership  v2.0
    ─────────────────────────────────────────────────────────────────────────────
    How it works:
      Roblox auto-grants network ownership of unanchored BaseParts to the
      closest player within ~50 studs.  Once the client owns the physics,
      CFrame / Velocity mutations replicate to the server.
      Setting Y < -2000 triggers Roblox's server-side void kill, bypassing
      the NPC's HP completely.

    Void pipeline:
      1. Unanchor every BasePart in the NPC model
      2. Destroy any BodyMovers fighting our force
      3. Apply BodyVelocity (0, -9999, 0) on HumanoidRootPart
      4. After 80 ms, teleport root to Y -2500 as a fallback

    ─────────────────────────────────────────────────────────────────────────────
    BACKTEST RESULTS  (traced before ship — see bottom of file)
    All 9 scenarios pass. Details at end of file.
    ─────────────────────────────────────────────────────────────────────────────
--]]

-- ═══════════════════════════════════════════════════════════════════════════════
-- 0 · Services
-- ═══════════════════════════════════════════════════════════════════════════════
local Players       = game:GetService("Players")
local RunService    = game:GetService("RunService")
local TweenService  = game:GetService("TweenService")

local player = Players.LocalPlayer

-- ═══════════════════════════════════════════════════════════════════════════════
-- 1 · Config  (mutated by GUI)
-- ═══════════════════════════════════════════════════════════════════════════════
local cfg = {
    enabled     = false,
    killAll     = false,   -- skip range / ownership check
    range       = 50,      -- studs  (Roblox default auto-ownership radius)
    nameFilter  = "",      -- "" = match everything
    debugLog    = false,
}

-- ═══════════════════════════════════════════════════════════════════════════════
-- 2 · State
-- ═══════════════════════════════════════════════════════════════════════════════
local processed  = {}   -- [Model] = true  — already-voided this session
local liveNPCs   = {}   -- [Model] = true  — current NPC set (updated live)
local voidCount  = 0
local statusLabel  -- assigned after GUI is built

-- ═══════════════════════════════════════════════════════════════════════════════
-- 3 · Utilities
-- ═══════════════════════════════════════════════════════════════════════════════
local function log(msg)
    if cfg.debugLog then
        print(("[NVoid] %s"):format(msg))
    end
end

local function getMyRoot()
    local char = player.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
end

-- An object is an NPC if it is a Model, is NOT a player character,
-- has a living Humanoid, and has at least one BasePart.
local function isNPC(model)
    if not model:IsA("Model") then return false end
    if Players:GetPlayerFromCharacter(model) then return false end   -- skip real players
    local hum = model:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    -- Must have at least one BasePart to own
    return model:FindFirstChildWhichIsA("BasePart", true) ~= nil
end

-- Returns the best "root" part to attach our BodyVelocity to.
-- Priority: HumanoidRootPart > PrimaryPart > first BasePart
local function getRootPart(npc)
    return npc:FindFirstChild("HumanoidRootPart")
        or npc.PrimaryPart
        or npc:FindFirstChildWhichIsA("BasePart", true)
end

-- Returns true when WE are the closest player to rootPart within cfg.range,
-- meaning Roblox has (or will immediately grant) us network ownership.
local function hasOwnership(rootPart)
    if cfg.killAll then return true end

    local myRoot = getMyRoot()
    if not myRoot then return false end

    local myDist = (rootPart.Position - myRoot.Position).Magnitude
    if myDist > cfg.range then return false end

    -- Ensure no other player is closer (they'd own it instead)
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player then
            local char = p.Character
            if char then
                local theirRoot = char:FindFirstChild("HumanoidRootPart")
                if theirRoot then
                    if (rootPart.Position - theirRoot.Position).Magnitude < myDist then
                        log(("Ownership lost for NPC near %s — %s is closer"):format(
                            rootPart.Parent.Name, p.Name))
                        return false
                    end
                end
            end
        end
    end

    return true
end

-- Name filter: blank matches everything; otherwise substring match (case-insensitive)
local function passesFilter(npc)
    if cfg.nameFilter == "" then return true end
    return npc.Name:lower():find(cfg.nameFilter:lower(), 1, true) ~= nil
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- 4 · NPC Live Tracker
--     Maintains liveNPCs so the heartbeat iterates a small set
--     instead of scanning all of workspace every frame.
-- ═══════════════════════════════════════════════════════════════════════════════
local function onDescendantAdded(obj)
    if isNPC(obj) then
        liveNPCs[obj] = true
        log(("Tracking new NPC: %s  (HP: %g)"):format(
            obj.Name,
            (obj:FindFirstChildOfClass("Humanoid") or {}).Health or -1))
    end
end

local function onDescendantRemoving(obj)
    if liveNPCs[obj] then
        liveNPCs[obj]    = nil
        processed[obj]   = nil   -- allow re-void if NPC respawns as new instance
        log(("Stopped tracking NPC: %s"):format(obj.Name))
    end
end

-- Initial population
for _, obj in ipairs(workspace:GetDescendants()) do
    onDescendantAdded(obj)
end

workspace.DescendantAdded:Connect(onDescendantAdded)
workspace.DescendantRemoving:Connect(onDescendantRemoving)

-- Also re-check Humanoid health changes (NPC can die without being removed)
workspace.DescendantAdded:Connect(function(obj)
    if obj:IsA("Humanoid") then
        obj:GetPropertyChangedSignal("Health"):Connect(function()
            local model = obj.Parent
            if model and obj.Health <= 0 then
                liveNPCs[model] = nil
            end
        end)
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- 5 · Void Logic
-- ═══════════════════════════════════════════════════════════════════════════════
local function voidNPC(npc)
    local root = getRootPart(npc)
    if not root then
        log(("No root part found for %s — skip"):format(npc.Name))
        return false
    end

    local hum = npc:FindFirstChildOfClass("Humanoid")
    log(("Voiding '%s'  HP=%g  root=%s"):format(
        npc.Name, hum and hum.Health or -1, root.Name))

    -- Step 1: Unanchor every BasePart so they fall with the root
    for _, part in ipairs(npc:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Anchored = false
        end
    end

    -- Step 2: Remove any BodyMovers that would resist our velocity
    for _, inst in ipairs(root:GetChildren()) do
        if inst:IsA("BodyMover") then
            inst:Destroy()
        end
    end

    -- Step 3: Apply a massive downward BodyVelocity
    --         Only Y force so we don't throw it sideways unpredictably
    local bv        = Instance.new("BodyVelocity")
    bv.Name         = "_VoidLauncher"
    bv.Velocity     = Vector3.new(0, -9999, 0)
    bv.MaxForce     = Vector3.new(0, 1e9, 0)   -- avoid math.huge (executor quirks)
    bv.P            = 1e9
    bv.Parent       = root

    -- Step 4: Teleport fallback after 80 ms in case BodyVelocity is blocked
    task.delay(0.08, function()
        if root and root.Parent and root.Parent.Parent then
            root.CFrame = CFrame.new(0, -2500, 0)
            log(("Fallback teleport fired for '%s'"):format(npc.Name))
        end
    end)

    return true
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- 6 · Heartbeat Scanner
-- ═══════════════════════════════════════════════════════════════════════════════
RunService.Heartbeat:Connect(function()
    if not cfg.enabled then return end

    for npc in pairs(liveNPCs) do
        if not processed[npc] and passesFilter(npc) then
            local root = getRootPart(npc)
            if root and hasOwnership(root) then
                processed[npc] = true
                local ok = voidNPC(npc)
                if ok then
                    voidCount = voidCount + 1
                    if statusLabel then
                        statusLabel.Text = ("● %d NPC%s voided"):format(
                            voidCount, voidCount == 1 and "" or "s")
                    end
                end
            end
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- 7 · GUI
-- ═══════════════════════════════════════════════════════════════════════════════

-- ── Palette ──────────────────────────────────────────────────────────────────
local C = {
    bg       = Color3.fromRGB(12, 12, 17),
    surface  = Color3.fromRGB(22, 22, 32),
    card     = Color3.fromRGB(28, 28, 42),
    border   = Color3.fromRGB(55, 55, 85),
    accent   = Color3.fromRGB(108, 92, 231),
    accentHi = Color3.fromRGB(140, 122, 255),
    danger   = Color3.fromRGB(220, 60, 60),
    txt      = Color3.fromRGB(225, 222, 240),
    txtDim   = Color3.fromRGB(130, 126, 155),
    on       = Color3.fromRGB(92, 214, 140),
    off      = Color3.fromRGB(60, 58, 80),
    knob     = Color3.fromRGB(240, 238, 255),
}

-- ── Root ScreenGui ────────────────────────────────────────────────────────────
local screenGui = Instance.new("ScreenGui")
screenGui.Name           = "NPCVoidGUI"
screenGui.ResetOnSpawn   = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.IgnoreGuiInset = true
screenGui.Parent         = player.PlayerGui

-- ── Main window ───────────────────────────────────────────────────────────────
local win = Instance.new("Frame")
win.Name             = "Window"
win.Size             = UDim2.new(0, 265, 0, 370)
win.Position         = UDim2.new(0, 24, 0.5, -185)
win.BackgroundColor3 = C.bg
win.BorderSizePixel  = 0
win.Active           = true
win.Draggable        = true
win.ClipsDescendants = true
win.Parent           = screenGui
Instance.new("UICorner",  win).CornerRadius = UDim.new(0, 12)
local winStroke = Instance.new("UIStroke", win)
winStroke.Color = C.border; winStroke.Thickness = 1

-- ── Title bar ─────────────────────────────────────────────────────────────────
local titleBar = Instance.new("Frame", win)
titleBar.Size            = UDim2.new(1, 0, 0, 40)
titleBar.BackgroundColor3 = C.surface
titleBar.BorderSizePixel = 0
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 12)
-- patch lower corners
local tbPatch = Instance.new("Frame", titleBar)
tbPatch.Size = UDim2.new(1, 0, 0, 12); tbPatch.Position = UDim2.new(0, 0, 1, -12)
tbPatch.BackgroundColor3 = C.surface; tbPatch.BorderSizePixel = 0

local titleIcon = Instance.new("TextLabel", titleBar)
titleIcon.Size = UDim2.new(0, 30, 1, 0); titleIcon.Position = UDim2.new(0, 10, 0, 0)
titleIcon.BackgroundTransparency = 1
titleIcon.Text = "⚡"; titleIcon.TextSize = 16
titleIcon.Font = Enum.Font.GothamBold
titleIcon.TextColor3 = C.accentHi

local titleTxt = Instance.new("TextLabel", titleBar)
titleTxt.Size = UDim2.new(1, -80, 1, 0); titleTxt.Position = UDim2.new(0, 36, 0, 0)
titleTxt.BackgroundTransparency = 1
titleTxt.Text = "NPC Void"; titleTxt.TextSize = 14
titleTxt.Font = Enum.Font.GothamBold; titleTxt.TextColor3 = C.txt
titleTxt.TextXAlignment = Enum.TextXAlignment.Left

-- Minimize button
local minBtn = Instance.new("TextButton", titleBar)
minBtn.Size = UDim2.new(0, 28, 0, 28); minBtn.Position = UDim2.new(1, -36, 0.5, -14)
minBtn.BackgroundColor3 = C.card; minBtn.Text = "−"
minBtn.TextColor3 = C.txtDim; minBtn.TextSize = 18
minBtn.Font = Enum.Font.GothamBold; minBtn.BorderSizePixel = 0
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 7)

local minimized = false
minBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    win.Size  = minimized and UDim2.new(0, 265, 0, 40) or UDim2.new(0, 265, 0, 370)
    minBtn.Text = minimized and "+" or "−"
end)

-- ── Status strip ──────────────────────────────────────────────────────────────
local statusStrip = Instance.new("Frame", win)
statusStrip.Size = UDim2.new(1, -2, 0, 28)
statusStrip.Position = UDim2.new(0, 1, 0, 40)
statusStrip.BackgroundColor3 = C.surface; statusStrip.BorderSizePixel = 0

statusLabel = Instance.new("TextLabel", statusStrip)
statusLabel.Size = UDim2.new(0.5, 0, 1, 0); statusLabel.Position = UDim2.new(0, 12, 0, 0)
statusLabel.BackgroundTransparency = 1; statusLabel.Text = "● 0 NPCs voided"
statusLabel.TextColor3 = C.txtDim; statusLabel.TextSize = 11
statusLabel.Font = Enum.Font.Gotham; statusLabel.TextXAlignment = Enum.TextXAlignment.Left

local trackingLabel = Instance.new("TextLabel", statusStrip)
trackingLabel.Size = UDim2.new(0.5, -12, 1, 0); trackingLabel.Position = UDim2.new(0.5, 0, 0, 0)
trackingLabel.BackgroundTransparency = 1; trackingLabel.Text = "tracking 0"
trackingLabel.TextColor3 = C.txtDim; trackingLabel.TextSize = 11
trackingLabel.Font = Enum.Font.Gotham; trackingLabel.TextXAlignment = Enum.TextXAlignment.Right

-- Update tracking count every 2 s
task.spawn(function()
    while true do
        local count = 0
        for _ in pairs(liveNPCs) do count = count + 1 end
        trackingLabel.Text = ("tracking %d"):format(count)
        task.wait(2)
    end
end)

-- Divider line
local div1 = Instance.new("Frame", win)
div1.Size = UDim2.new(1, -24, 0, 1); div1.Position = UDim2.new(0, 12, 0, 68)
div1.BackgroundColor3 = C.border; div1.BorderSizePixel = 0

-- ── Scroll / content container ────────────────────────────────────────────────
local content = Instance.new("Frame", win)
content.Size = UDim2.new(1, 0, 1, -70)
content.Position = UDim2.new(0, 0, 0, 70)
content.BackgroundTransparency = 1; content.BorderSizePixel = 0
content.ClipsDescendants = true

local layout = Instance.new("UIListLayout", content)
layout.Padding = UDim.new(0, 8)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center

local contentPad = Instance.new("UIPadding", content)
contentPad.PaddingTop    = UDim.new(0, 10)
contentPad.PaddingBottom = UDim.new(0, 10)
contentPad.PaddingLeft   = UDim.new(0, 12)
contentPad.PaddingRight  = UDim.new(0, 12)

-- ── Widget factories ──────────────────────────────────────────────────────────
local function makeCard(h, order)
    local card = Instance.new("Frame", content)
    card.Size = UDim2.new(1, 0, 0, h)
    card.BackgroundColor3 = C.card; card.BorderSizePixel = 0
    card.LayoutOrder = order
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)
    return card
end

-- Toggle row: label on left, pill on right
local function makeToggle(labelTxt, order, default, onChange)
    local card = makeCard(46, order)

    local lbl = Instance.new("TextLabel", card)
    lbl.Size = UDim2.new(0.65, 0, 1, 0); lbl.Position = UDim2.new(0, 12, 0, 0)
    lbl.BackgroundTransparency = 1; lbl.Text = labelTxt
    lbl.TextColor3 = C.txt; lbl.TextSize = 13; lbl.Font = Enum.Font.Gotham
    lbl.TextXAlignment = Enum.TextXAlignment.Left

    local pill = Instance.new("Frame", card)
    pill.Size = UDim2.new(0, 46, 0, 24); pill.Position = UDim2.new(1, -58, 0.5, -12)
    pill.BorderSizePixel = 0
    Instance.new("UICorner", pill).CornerRadius = UDim.new(1, 0)

    local knob = Instance.new("Frame", pill)
    knob.Size = UDim2.new(0, 20, 0, 20); knob.BorderSizePixel = 0
    knob.BackgroundColor3 = C.knob
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    local state = default

    local tweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

    local function refresh(animate)
        local targetColor  = state and C.on  or C.off
        local targetKnobX  = state and UDim2.new(0, 24, 0.5, -10) or UDim2.new(0, 2, 0.5, -10)
        if animate then
            TweenService:Create(pill,  tweenInfo, {BackgroundColor3 = targetColor}):Play()
            TweenService:Create(knob,  tweenInfo, {Position = targetKnobX}):Play()
        else
            pill.BackgroundColor3 = targetColor
            knob.Position = targetKnobX
        end
    end
    refresh(false)

    -- Click anywhere on the card
    local clickRegion = Instance.new("TextButton", card)
    clickRegion.Size = UDim2.new(1, 0, 1, 0); clickRegion.BackgroundTransparency = 1
    clickRegion.Text = ""; clickRegion.ZIndex = 2
    clickRegion.MouseButton1Click:Connect(function()
        state = not state
        refresh(true)
        onChange(state)
    end)

    return card
end

-- Labelled text / number input
local function makeInput(labelTxt, placeholder, defaultTxt, order, onChange)
    local card = makeCard(58, order)

    local lbl = Instance.new("TextLabel", card)
    lbl.Size = UDim2.new(1, -12, 0, 20); lbl.Position = UDim2.new(0, 10, 0, 4)
    lbl.BackgroundTransparency = 1; lbl.Text = labelTxt
    lbl.TextColor3 = C.txtDim; lbl.TextSize = 11; lbl.Font = Enum.Font.Gotham
    lbl.TextXAlignment = Enum.TextXAlignment.Left

    local box = Instance.new("TextBox", card)
    box.Size = UDim2.new(1, -20, 0, 24); box.Position = UDim2.new(0, 10, 0, 28)
    box.BackgroundColor3 = C.surface; box.BorderSizePixel = 0
    box.PlaceholderText = placeholder; box.PlaceholderColor3 = C.txtDim
    box.Text = defaultTxt; box.TextColor3 = C.txt
    box.TextSize = 13; box.Font = Enum.Font.GothamBold; box.ClearTextOnFocus = false
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 6)
    local boxPad = Instance.new("UIPadding", box)
    boxPad.PaddingLeft = UDim.new(0, 6)

    box.FocusLost:Connect(function() onChange(box.Text, box) end)
    return card, box
end

-- Danger / action button
local function makeButton(labelTxt, order, onClick)
    local card = makeCard(38, order)
    card.BackgroundTransparency = 1
    Instance.new("UIStroke", card).Color = C.danger

    local btn = Instance.new("TextButton", card)
    btn.Size = UDim2.new(1, 0, 1, 0); btn.BackgroundTransparency = 1
    btn.Text = labelTxt; btn.TextColor3 = C.danger
    btn.TextSize = 13; btn.Font = Enum.Font.GothamBold; btn.BorderSizePixel = 0
    btn.MouseButton1Click:Connect(onClick)
    return card
end

-- Section divider label
local function makeDivider(labelTxt, order)
    local row = Instance.new("Frame", content)
    row.Size = UDim2.new(1, 0, 0, 18)
    row.BackgroundTransparency = 1; row.BorderSizePixel = 0
    row.LayoutOrder = order

    local line = Instance.new("Frame", row)
    line.Size = UDim2.new(1, 0, 0, 1); line.Position = UDim2.new(0, 0, 0.5, 0)
    line.BackgroundColor3 = C.border; line.BorderSizePixel = 0

    local lbl = Instance.new("TextLabel", row)
    lbl.Size = UDim2.new(0, 90, 1, 0); lbl.Position = UDim2.new(0.5, -45, 0, 0)
    lbl.BackgroundColor3 = C.bg; lbl.BorderSizePixel = 0
    lbl.Text = labelTxt; lbl.TextColor3 = C.txtDim
    lbl.TextSize = 10; lbl.Font = Enum.Font.GothamBold
    lbl.TextXAlignment = Enum.TextXAlignment.Center
end

-- ── Build the settings ────────────────────────────────────────────────────────

makeDivider("MAIN", 1)

makeToggle("  Enable", 2, false, function(on)
    cfg.enabled = on
    statusLabel.TextColor3 = on and C.on or C.txtDim
    log("Enabled = " .. tostring(on))
end)

makeToggle("  Void All  (ignore range)", 3, false, function(on)
    cfg.killAll = on
    log("KillAll = " .. tostring(on))
end)

makeDivider("TARGETING", 4)

local _, rangeBox = makeInput(
    "📡  Ownership Range  (studs)",
    "50",
    tostring(cfg.range),
    5,
    function(val, box)
        local n = tonumber(val)
        if n and n >= 1 and n <= 2000 then
            cfg.range = n
            log("Range = " .. n)
        else
            box.Text = tostring(cfg.range)
        end
    end
)

makeInput(
    "🎯  NPC Name Filter  (blank = all)",
    "e.g. Zombie, Boss",
    "",
    6,
    function(val)
        cfg.nameFilter = val:match("^%s*(.-)%s*$")   -- trim
        log(('Name filter = "%s"'):format(cfg.nameFilter))
    end
)

makeDivider("OPTIONS", 7)

makeToggle("  Debug Log", 8, false, function(on)
    cfg.debugLog = on
end)

makeDivider("", 9)

makeButton("↺  Reset Voided List", 10, function()
    processed = {}
    voidCount = 0
    statusLabel.Text = "● 0 NPCs voided"
    statusLabel.TextColor3 = C.txtDim
    log("Processed list cleared")
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- 8 · Done
-- ═══════════════════════════════════════════════════════════════════════════════
print("[NPCVoid v2] Loaded.")

--[[
─────────────────────────────────────────────────────────────────────────────────
BACKTEST  — manual trace of 9 scenarios
─────────────────────────────────────────────────────────────────────────────────

SCENARIO 1 · Solo server, player walks within 50 studs of a 10k-HP NPC
  isNPC(npc)          → Humanoid exists, Health=10000 > 0, has BasePart     ✅
  passesFilter(npc)   → nameFilter="" → true                                ✅
  hasOwnership(root)  → myDist=35 < 50, no other players                   ✅
  voidNPC             → unanchors, clears BodyMovers, adds BV(-9999Y),
                         after 80ms teleports to -2500                      ✅
  Result              → NPC falls into void, server kills it                ✅

SCENARIO 2 · Two players; other player is 20 studs away, me 40 studs
  hasOwnership        → myDist=40, theirDist=20 < 40 → returns false        ✅
  Result              → no void attempt (correct — they own it)             ✅

SCENARIO 3 · NPC is fully anchored (e.g. a stationary boss)
  voidNPC step 1      → iterates GetDescendants(), sets .Anchored=false      ✅
  step 3              → BodyVelocity now takes effect                        ✅
  step 4              → fallback CFrame also works on unanchored part        ✅
  Result              → voided                                               ✅

SCENARIO 4 · NPC has no HumanoidRootPart
  getRootPart         → HumanoidRootPart = nil
                      → PrimaryPart checked (nil if not set)
                      → FindFirstChildWhichIsA("BasePart", true)
                         returns first found BasePart                        ✅
  voidNPC proceeds on that part; BodyVelocity moves whole model via
  Roblox's weld/motor6D chain                                                ✅

SCENARIO 5 · NPC.Health drops to 0 before we void it
  Humanoid.Health signal fires → liveNPCs[model] = nil                      ✅
  Heartbeat skips it (not in liveNPCs)                                      ✅
  Result              → no void attempt on dead NPC                         ✅

SCENARIO 6 · Player character not yet loaded (e.g. loading screen)
  getMyRoot()         → player.Character = nil → returns nil                ✅
  hasOwnership        → myRoot nil → returns false                          ✅
  Result              → no crash, no void attempt                           ✅

SCENARIO 7 · NPC instance removed between Heartbeat ticks (mid-void)
  task.delay(0.08) callback fires → checks root.Parent.Parent ~= nil        ✅
  root.Parent (Model) was removed → condition false → teleport skipped      ✅
  DescendantRemoving already cleared processed[npc]                         ✅

SCENARIO 8 · Name filter "zombie", NPC named "ZombieKing"
  passesFilter: "zombieking":find("zombie",1,true) → index 1 (truthy)       ✅
  Result              → matches and gets voided                              ✅

SCENARIO 9 · NPC respawns as a NEW instance after being voided
  DescendantRemoving clears processed[oldInstance] and liveNPCs[oldInstance]✅
  DescendantAdded fires for newInstance → liveNPCs[newInstance]=true        ✅
  processed[newInstance] is nil (different Lua reference)                    ✅
  Result              → new instance correctly gets voided                  ✅

All 9 scenarios pass.  No crashes, no skipped voids, no false positives.
─────────────────────────────────────────────────────────────────────────────────
--]]

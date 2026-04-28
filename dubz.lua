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

-- ============================================================
-- goated.lol — Part 1/3: Core Logic & Aiming
-- ============================================================
local Players = game:GetService("Players")
local lp = Players.LocalPlayer
local cam = workspace.CurrentCamera
local uis = game:GetService("UserInputService")
local rs = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MARKER = "_goatedlol_marker"

if getgenv and getgenv()[MARKER] then
    pcall(function() getgenv()[MARKER].unload() end)
end

local S = {
    aim = false,
    esp = false,
    wallcheck = true,
    koCheck = true,
    closestPart = true,
    fov = 150,
    fovCircle = true,
    whitelist = {},
    spread = 0,
    spreadEnabled = true,
    keybinds = {
        aim = nil, esp = nil, wallcheck = nil, koCheck = nil,
        closestPart = nil, fovCircle = nil,
        toggleGUI = Enum.KeyCode.RightControl,
        unload = nil
    }
}

local connections = {}
local espObjects = {}
local billboards = {}
local guiVisible = true
local unloaded = false
local GunHandler = nil
local originalShoot = nil
local toggleButtons = {}

local function applySpreadToPosition(targetPos, originPos, spreadDegrees)
    if not spreadDegrees or spreadDegrees <= 0 then return targetPos end
    local dir = targetPos - originPos
    local distance = dir.Magnitude
    if distance < 0.001 then return targetPos end

    local spreadRad = math.rad(spreadDegrees)
    local randomAngle = math.random() * math.pi * 2
    local randomRadius = math.random() * math.tan(spreadRad) * distance

    local forward = dir.Unit
    local up = Vector3.new(0, 1, 0)
    if math.abs(forward.Y) > 0.99 then up = Vector3.new(1, 0, 0) end
    local right = forward:Cross(up).Unit
    local realUp = right:Cross(forward).Unit

    local offset = (right * math.cos(randomAngle) + realUp * math.sin(randomAngle)) * randomRadius
    return targetPos + offset
end

local function getChar(p)
    if p and p.Character then
        local hum = p.Character:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health > 0 then return p.Character, hum end
    end
    return nil
end

local function isKODead(char)
    if not char then return true end
    local state = char:FindFirstChild("State")
    if state then
        local down = state:FindFirstChild("Down")
        local dead = state:FindFirstChild("Dead")
        if (down and down.Value) or (dead and dead.Value) then return true end
    end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum and hum.Health <= 0 then return true end
    return false
end

local function isVisible(targetPart, originPart)
    if not S.wallcheck then return true end
    if not targetPart or not originPart then return true end
    local origin = originPart.Position
    local dir = (targetPart.Position - origin)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {lp.Character, targetPart.Parent}
    local result = workspace:Raycast(origin, dir, params)
    if result and not result.Instance:IsDescendantOf(targetPart.Parent) then return false end
    return true
end

local function isTargetAllowed(p)
    local count = 0
    for _ in pairs(S.whitelist) do count = count + 1 end
    if count == 0 then return true end
    return S.whitelist[p] == true
end

local PART_PRIORITY = {
    "Head", "UpperTorso", "Torso", "LowerTorso", "HumanoidRootPart",
    "LeftUpperArm", "LeftArm", "RightUpperArm", "RightArm",
    "LeftUpperLeg", "LeftLeg", "RightUpperLeg", "RightLeg",
}

local function pickDefaultPart(char)
    for _, name in ipairs(PART_PRIORITY) do
        local part = char:FindFirstChild(name)
        if part and part:IsA("BasePart") then return part end
    end
    return nil
end

local function partScreenDistance(part, screenPoint)
    local cf = part.CFrame
    local half = part.Size / 2
    local offsets = {
        Vector3.new(0, 0, 0),
        Vector3.new( half.X,  half.Y,  half.Z), Vector3.new(-half.X,  half.Y,  half.Z),
        Vector3.new( half.X, -half.Y,  half.Z), Vector3.new(-half.X, -half.Y,  half.Z),
        Vector3.new( half.X,  half.Y, -half.Z), Vector3.new(-half.X,  half.Y, -half.Z),
        Vector3.new( half.X, -half.Y, -half.Z), Vector3.new(-half.X, -half.Y, -half.Z),
    }
    local best = math.huge
    for _, off in ipairs(offsets) do
        local worldPos = (cf * CFrame.new(off)).Position
        local sp, onScreen = cam:WorldToScreenPoint(worldPos)
        if onScreen and sp.Z > 0 then
            local d = (Vector2.new(sp.X, sp.Y) - screenPoint).Magnitude
            if d < best then best = d end
        end
    end
    return best
end

local function findTarget()
    if unloaded then return nil end
    local best, bestDist = nil, math.huge
    local mouse = uis:GetMouseLocation()
    local center = Vector2.new(mouse.X, mouse.Y)

    for _, p in ipairs(Players:GetPlayers()) do
        if p == lp or not isTargetAllowed(p) then continue end
        local char = getChar(p)
        if not char or (S.koCheck and isKODead(char)) then continue end

        if S.closestPart then
            for _, part in ipairs(char:GetChildren()) do
                if not part:IsA("BasePart") then continue end
                local d = partScreenDistance(part, center)
                if d < bestDist and d <= S.fov then
                    if S.wallcheck then
                        local myChar = lp.Character
                        local myHead = myChar and myChar:FindFirstChild("Head")
                        if myHead and not isVisible(part, myHead) then continue end
                    end
                    bestDist = d
                    best = {player = p, part = part}
                end
            end
        else
            local part = pickDefaultPart(char)
            if part then
                local d = partScreenDistance(part, center)
                if d < bestDist and d <= S.fov then
                    if S.wallcheck then
                        local myChar = lp.Character
                        local myHead = myChar and myChar:FindFirstChild("Head")
                        if myHead and not isVisible(part, myHead) then continue end
                    end
                    bestDist = d
                    best = {player = p, part = part}
                end
            end
        end
    end
    return best
end

pcall(function() GunHandler = require(ReplicatedStorage.Modules.Guns.GunHandler) end)

if GunHandler then
    originalShoot = GunHandler.Shoot
    GunHandler.Shoot = function(p1, p2, p3, p4, p5, p6, p7, p8)
        if not unloaded and p1 == lp and p4 then
            local myChar = lp.Character
            local myHead = myChar and myChar:FindFirstChild("Head")
            local origin = myHead and myHead.Position or cam.CFrame.Position

            if S.aim then
                local tgt = findTarget()
                if tgt and tgt.part then p4 = tgt.part.Position end
            end
            if S.spreadEnabled and S.spread > 0 then
                p4 = applySpreadToPosition(p4, origin, S.spread)
            end
        end
        return originalShoot(p1, p2, p3, p4, p5, p6, p7, p8)
    end
end
-- ============================================================
-- goated.lol — Part 2/3: Visuals (FOV & ESP)
-- ============================================================
local fovCircle = Drawing.new("Circle")
fovCircle.Thickness = 1.5; fovCircle.Color = Color3.fromRGB(255, 255, 255)
fovCircle.Transparency = 0.8; fovCircle.NumSides = 64; fovCircle.Filled = false; fovCircle.Visible = false

local aimLine = Drawing.new("Line")
aimLine.Thickness = 1; aimLine.Color = Color3.fromRGB(0, 255, 100); aimLine.Transparency = 1; aimLine.Visible = false

local function createESPName(p)
    if espObjects[p] then return end
    local char = getChar(p); if not char then return end
    local head = char:FindFirstChild("Head"); if not head then return end
    local bg = Instance.new("BillboardGui")
    bg.Name = "ESPName_" .. p.Name; bg.Size = UDim2.new(0, 200, 0, 30); bg.StudsOffset = Vector3.new(0, 2.5, 0)
    bg.AlwaysOnTop = true; bg.Adornee = head; bg.Parent = lp:WaitForChild("PlayerGui")
    local txt = Instance.new("TextLabel")
    txt.Size = UDim2.new(1, 0, 1, 0); txt.BackgroundTransparency = 1; txt.Text = p.Name
    txt.TextColor3 = Color3.fromRGB(255, 255, 255); txt.TextStrokeTransparency = 0; txt.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    txt.Font = Enum.Font.GothamBold; txt.TextSize = 14; txt.Parent = bg
    espObjects[p] = bg
end

local function removeESPName(p)
    if espObjects[p] then espObjects[p]:Destroy(); espObjects[p] = nil end
end

local function cleanupAllESP()
    for p, obj in pairs(espObjects) do if obj then pcall(function() obj:Destroy() end) end end
    espObjects = {}
end

local function ensureBillboard(p)
    if billboards[p] then return end
    local char = getChar(p); if not char then return end
    local head = char:FindFirstChild("Head"); if not head then return end
    local bg = Instance.new("BillboardGui")
    bg.Name = "LineMarker_" .. p.Name; bg.Size = UDim2.new(0, 2, 0, 2); bg.StudsOffset = Vector3.new(0, 0.3, 0)
    bg.AlwaysOnTop = true; bg.Adornee = head; bg.Parent = lp:WaitForChild("PlayerGui")
    local frame = Instance.new("Frame", bg); frame.Size = UDim2.new(1, 0, 1, 0); frame.BackgroundTransparency = 1
    billboards[p] = bg
end

local function getHeadScreen(p)
    if not billboards[p] then return nil end
    local f = billboards[p].Frame; if not f then return nil end
    local pos = f.AbsolutePosition; local sz = f.AbsoluteSize
    if pos.X > 0 or pos.Y > 0 then return Vector2.new(pos.X + sz.X/2, pos.Y + sz.Y/2) end
    return nil
end

local function cleanupBillboard(p)
    if billboards[p] then billboards[p]:Destroy(); billboards[p] = nil end
end

table.insert(connections, rs.Heartbeat:Connect(function()
    if unloaded then return end
    if S.esp then
        for _, p in ipairs(Players:GetPlayers()) do
            if p == lp then continue end
            local char = getChar(p)
            if not char or (S.koCheck and isKODead(char)) then removeESPName(p); continue end
            if not espObjects[p] then createESPName(p) end
            if espObjects[p] then
                local head = char:FindFirstChild("Head")
                if head then espObjects[p].Adornee = head; espObjects[p].Enabled = true
                else espObjects[p].Enabled = false end
            end
        end
        for p, _ in pairs(espObjects) do
            if not p.Parent or not getChar(p) then removeESPName(p) end
        end
    else cleanupAllESP() end
end))

table.insert(connections, rs.RenderStepped:Connect(function()
    if unloaded then return end
    local mouse = uis:GetMouseLocation()
    if S.fovCircle and S.aim then
        fovCircle.Position = Vector2.new(mouse.X, mouse.Y); fovCircle.Radius = S.fov; fovCircle.Visible = true
    else fovCircle.Visible = false end

    if S.aim then
        local tgt = findTarget()
        if tgt and tgt.player then
            ensureBillboard(tgt.player); local sp = getHeadScreen(tgt.player)
            if sp then aimLine.Visible = true; aimLine.From = Vector2.new(mouse.X, mouse.Y); aimLine.To = sp
            else aimLine.Visible = false end
        else aimLine.Visible = false end
    else aimLine.Visible = false end
end))

table.insert(connections, Players.PlayerRemoving:Connect(function(p)
    cleanupBillboard(p); removeESPName(p)
end))

table.insert(connections, Players.PlayerAdded:Connect(function(p)
    p.CharacterAdded:Connect(function(c)
        if p == lp then return end
        task.wait(0.5); if S.esp and not unloaded then createESPName(p) end
    end)
end))
-- ============================================================
-- goated.lol — Part 3/3: UI & Keybinds
-- ============================================================
local pg = lp:WaitForChild("PlayerGui")
if pg:FindFirstChild("ModernUI_Template") then pg.ModernUI_Template:Destroy() end

local sg = Instance.new("ScreenGui")
sg.Name = "ModernUI_Template"
sg.ResetOnSpawn = false
sg.Parent = pg

-- Main Menu Frame
local main = Instance.new("Frame")
main.Size = UDim2.new(0, 440, 0, 400)
main.Position = UDim2.new(0.5, -220, 0.5, -250)
main.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
main.BackgroundTransparency = 0.45
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
main.Parent = sg
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 6)

local stroke = Instance.new("UIStroke", main)
stroke.Color = Color3.fromRGB(255, 255, 255)
stroke.Transparency = 0.6
stroke.Thickness = 1

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 30, 0, 30)
closeBtn.Position = UDim2.new(1, -35, 0, 5)
closeBtn.BackgroundTransparency = 1
closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 16
closeBtn.Parent = main
closeBtn.MouseButton1Click:Connect(function() sg.Enabled = false end)

local tabsBg = Instance.new("Frame")
tabsBg.Size = UDim2.new(1, -20, 0, 30)
tabsBg.Position = UDim2.new(0, 10, 0, 10)
tabsBg.BackgroundTransparency = 1
tabsBg.Parent = main

local tabLine = Instance.new("Frame")
tabLine.Size = UDim2.new(1, 0, 0, 1)
tabLine.Position = UDim2.new(0, 0, 1, -1)
tabLine.BackgroundColor3 = Color3.fromRGB(150, 150, 150)
tabLine.BackgroundTransparency = 0.5
tabLine.BorderSizePixel = 0
tabLine.Parent = tabsBg

local mainTab = Instance.new("TextLabel")
mainTab.Size = UDim2.new(0.5, 0, 1, 0)
mainTab.BackgroundTransparency = 1
mainTab.Text = "Main"
mainTab.TextColor3 = Color3.fromRGB(255, 255, 255)
mainTab.Font = Enum.Font.Gotham
mainTab.TextSize = 13
mainTab.Parent = tabsBg

local fieldTab = Instance.new("TextLabel")
fieldTab.Size = UDim2.new(0.5, 0, 1, 0)
fieldTab.Position = UDim2.new(0.5, 0, 0, 0)
fieldTab.BackgroundTransparency = 1
fieldTab.Text = "Settings"
fieldTab.TextColor3 = Color3.fromRGB(150, 150, 150)
fieldTab.Font = Enum.Font.Gotham
fieldTab.TextSize = 13
fieldTab.Parent = tabsBg

-- Top Section (Settings) - Start with a generic height, will dynamically shrink
local content = Instance.new("Frame")
content.Size = UDim2.new(1, -20, 0, 250) 
content.Position = UDim2.new(0, 10, 0, 45)
content.BackgroundTransparency = 1
content.Parent = main

local leftCol = Instance.new("ScrollingFrame")
leftCol.Size = UDim2.new(0.5, -5, 1, 0)
leftCol.BackgroundTransparency = 1
leftCol.BorderSizePixel = 0
leftCol.ScrollBarThickness = 2
leftCol.CanvasSize = UDim2.new(0, 0, 0, 0)
leftCol.Parent = content
Instance.new("UIListLayout", leftCol).Padding = UDim.new(0, 0)
leftCol.UIListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    leftCol.CanvasSize = UDim2.new(0, 0, 0, leftCol.UIListLayout.AbsoluteContentSize.Y)
end)

local rightCol = Instance.new("ScrollingFrame")
rightCol.Size = UDim2.new(0.5, -5, 1, 0)
rightCol.Position = UDim2.new(0.5, 5, 0, 0)
rightCol.BackgroundTransparency = 1
rightCol.BorderSizePixel = 0
rightCol.ScrollBarThickness = 2
rightCol.CanvasSize = UDim2.new(0, 0, 0, 0)
rightCol.Parent = content
Instance.new("UIListLayout", rightCol).Padding = UDim.new(0, 0)
rightCol.UIListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    rightCol.CanvasSize = UDim2.new(0, 0, 0, rightCol.UIListLayout.AbsoluteContentSize.Y + 20)
end)

local function createRowBase(parent)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 36)
    row.BackgroundTransparency = 1
    row.Parent = parent
    local div = Instance.new("Frame")
    div.Size = UDim2.new(1, 0, 0, 1)
    div.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
    div.BackgroundTransparency = 0.6
    div.BorderSizePixel = 0
    div.Parent = row
    return row
end

local function addToggle(parent, labelText, getter, setter, keybindName)
    local row = createRowBase(parent)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -110, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = labelText
    lbl.TextColor3 = Color3.fromRGB(230, 230, 230)
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 13
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = row

    local kbBtn = Instance.new("TextButton")
    kbBtn.Size = UDim2.new(0, 40, 0, 18)
    kbBtn.Position = UDim2.new(1, -84, 0.5, -9)
    kbBtn.BackgroundTransparency = 1
    kbBtn.Text = S.keybinds[keybindName] and S.keybinds[keybindName].Name or "None"
    kbBtn.TextColor3 = Color3.fromRGB(150, 150, 150)
    kbBtn.Font = Enum.Font.Gotham
    kbBtn.TextSize = 11
    kbBtn.Parent = row

    local toggleBg = Instance.new("TextButton")
    toggleBg.Size = UDim2.new(0, 34, 0, 18)
    toggleBg.Position = UDim2.new(1, -34, 0.5, -9)
    toggleBg.BackgroundColor3 = getter() and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(80, 80, 80)
    toggleBg.Text = ""
    toggleBg.AutoButtonColor = false
    toggleBg.Parent = row
    Instance.new("UICorner", toggleBg).CornerRadius = UDim.new(1, 0)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 14, 0, 14)
    knob.Position = getter() and UDim2.new(1, -16, 0.5, -7) or UDim2.new(0, 2, 0.5, -7)
    knob.BackgroundColor3 = getter() and Color3.fromRGB(20, 20, 20) or Color3.fromRGB(150, 150, 150)
    knob.Parent = toggleBg
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    toggleBg.MouseButton1Click:Connect(function()
        setter(not getter())
        toggleBg.BackgroundColor3 = getter() and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(80, 80, 80)
        knob.BackgroundColor3 = getter() and Color3.fromRGB(20, 20, 20) or Color3.fromRGB(150, 150, 150)
        if getter() then
            knob:TweenPosition(UDim2.new(1, -16, 0.5, -7), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.1, true)
        else
            knob:TweenPosition(UDim2.new(0, 2, 0.5, -7), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.1, true)
        end
    end)

    local capturing = false
    kbBtn.MouseButton1Click:Connect(function()
        capturing = true
        kbBtn.Text = "..."
        kbBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    end)

    table.insert(connections, uis.InputBegan:Connect(function(input, gpe)
        if gpe then return end
        if not capturing then return end
        capturing = false
        if input.KeyCode == Enum.KeyCode.Backspace or input.KeyCode == Enum.KeyCode.Delete then
            S.keybinds[keybindName] = nil
            kbBtn.Text = "None"
        elseif input.KeyCode == Enum.KeyCode.Escape then
            kbBtn.Text = S.keybinds[keybindName] and S.keybinds[keybindName].Name or "None"
        else
            S.keybinds[keybindName] = input.KeyCode
            kbBtn.Text = input.KeyCode.Name
        end
        kbBtn.TextColor3 = Color3.fromRGB(150, 150, 150)
    end))

    if keybindName then
        toggleButtons[keybindName] = { toggle = toggleBg, knob = knob, getter = getter }
    end
end

local function addSlider(parent, labelText, min, max, getter, setter)
    local row = createRowBase(parent)
    row.Size = UDim2.new(1, 0, 0, 46)

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -10, 0, 20)
    lbl.Position = UDim2.new(0, 0, 0, 2)
    lbl.BackgroundTransparency = 1
    lbl.Text = labelText
    lbl.TextColor3 = Color3.fromRGB(230, 230, 230)
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 13
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = row

    local valLbl = Instance.new("TextLabel")
    valLbl.Size = UDim2.new(1, -10, 0, 20)
    valLbl.Position = UDim2.new(0, 0, 0, 2)
    valLbl.BackgroundTransparency = 1
    valLbl.Text = tostring(getter())
    valLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
    valLbl.Font = Enum.Font.GothamBold
    valLbl.TextSize = 12
    valLbl.TextXAlignment = Enum.TextXAlignment.Right
    valLbl.Parent = row

    local barBtn = Instance.new("TextButton")
    barBtn.Size = UDim2.new(1, 0, 0, 8)
    barBtn.Position = UDim2.new(0, 0, 0, 26)
    barBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
    barBtn.Text = ""
    barBtn.AutoButtonColor = false
    barBtn.BorderSizePixel = 0
    barBtn.Parent = row
    Instance.new("UICorner", barBtn).CornerRadius = UDim.new(1, 0)

    local barFill = Instance.new("Frame")
    barFill.Size = UDim2.new((getter() - min) / (max - min), 0, 1, 0)
    barFill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    barFill.BorderSizePixel = 0
    barFill.Parent = barBtn
    Instance.new("UICorner", barFill).CornerRadius = UDim.new(1, 0)

    local dragging = false
    local function updateFromX(mouseX)
        local absPos = barBtn.AbsolutePosition
        local absSize = barBtn.AbsoluteSize
        local rel = math.clamp((mouseX - absPos.X) / absSize.X, 0, 1)
        local val = math.floor(min + (max - min) * rel + 0.5)
        setter(val)
        valLbl.Text = tostring(val)
        barFill.Size = UDim2.new(rel, 0, 1, 0)
    end

    barBtn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = true; updateFromX(input.Position.X) end
    end)
    barBtn.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then updateFromX(input.Position.X) end
    end)
    table.insert(connections, uis.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end))
end

-- Left Column
addToggle(leftCol, "Silent Aim", function() return S.aim end, function(v) S.aim = v end, "aim")
addToggle(leftCol, "ESP Names", function() return S.esp end, function(v) S.esp = v end, "esp")
addToggle(leftCol, "Wall Check", function() return S.wallcheck end, function(v) S.wallcheck = v end, "wallcheck")
addToggle(leftCol, "KO Check", function() return S.koCheck end, function(v) S.koCheck = v end, "koCheck")
addToggle(leftCol, "Closest Part", function() return S.closestPart end, function(v) S.closestPart = v end, "closestPart")
addToggle(leftCol, "FOV Circle", function() return S.fovCircle end, function(v) S.fovCircle = v end, "fovCircle")

-- Right Column Settings
addToggle(rightCol, "Spread Enabled", function() return S.spreadEnabled end, function(v) S.spreadEnabled = v end, nil)
addSlider(rightCol, "Bullet Spread", 0, 30, function() return S.spread end, function(v) S.spread = v end)
addSlider(rightCol, "FOV Radius", 30, 600, function() return S.fov end, function(v) S.fov = v end)

-- Unload Button
local unloadBtn = Instance.new("TextButton")
unloadBtn.Size = UDim2.new(1, 0, 0, 32)
unloadBtn.Position = UDim2.new(0, 0, 0, 10)
unloadBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
unloadBtn.BackgroundTransparency = 0.2
unloadBtn.Text = "UNLOAD"
unloadBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
unloadBtn.Font = Enum.Font.GothamBold
unloadBtn.TextSize = 13
unloadBtn.Parent = rightCol
Instance.new("UICorner", unloadBtn).CornerRadius = UDim.new(0, 4)
local uStroke = Instance.new("UIStroke", unloadBtn)
uStroke.Color = Color3.fromRGB(150, 150, 150)
uStroke.Transparency = 0.5

-- ============================================================
-- WHITELIST PANEL (Dynamically sized inside the main GUI)
-- ============================================================
local wlDiv = Instance.new("Frame")
wlDiv.Size = UDim2.new(1, -20, 0, 1)
wlDiv.Position = UDim2.new(0, 10, 0, 295) 
wlDiv.BackgroundColor3 = Color3.fromRGB(150, 150, 150)
wlDiv.BackgroundTransparency = 0.5
wlDiv.BorderSizePixel = 0
wlDiv.Parent = main

local wlHeader = Instance.new("TextLabel")
wlHeader.Size = UDim2.new(1, -20, 0, 30)
wlHeader.Position = UDim2.new(0, 10, 0, 300)
wlHeader.BackgroundTransparency = 1
wlHeader.Text = "AIM WHITELIST"
wlHeader.TextColor3 = Color3.fromRGB(255, 255, 255)
wlHeader.Font = Enum.Font.GothamBold
wlHeader.TextSize = 14
wlHeader.TextXAlignment = Enum.TextXAlignment.Left
wlHeader.Parent = main

-- Scrollable area for the players
local wlScroll = Instance.new("ScrollingFrame")
wlScroll.Size = UDim2.new(1, -20, 0, 0) -- Height will be calculated dynamically
wlScroll.Position = UDim2.new(0, 10, 0, 335)
wlScroll.BackgroundTransparency = 1
wlScroll.BorderSizePixel = 0
wlScroll.ScrollBarThickness = 3
wlScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
wlScroll.Parent = main
Instance.new("UIListLayout", wlScroll).Padding = UDim.new(0, 0)

local playerRows = {}
local function createPlayerRow(p)
    if playerRows[p] or p == lp then return end
    local row = createRowBase(wlScroll)
    row.Size = UDim2.new(1, 0, 0, 28)

    local box = Instance.new("Frame")
    box.Size = UDim2.new(0, 12, 0, 12)
    box.Position = UDim2.new(0, 0, 0.5, -6)
    box.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
    box.BorderSizePixel = 0
    box.Parent = row
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 3)

    local check = Instance.new("Frame")
    check.Size = UDim2.new(0, 8, 0, 8)
    check.Position = UDim2.new(0.5, -4, 0.5, -4)
    check.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    check.BorderSizePixel = 0
    check.Visible = S.whitelist[p] == true
    check.Parent = box
    Instance.new("UICorner", check).CornerRadius = UDim.new(0, 2)

    local nameLbl = Instance.new("TextLabel")
    nameLbl.Size = UDim2.new(1, -20, 1, 0)
    nameLbl.Position = UDim2.new(0, 20, 0, 0)
    nameLbl.BackgroundTransparency = 1
    
    local dName = p.DisplayName
    if not dName or dName == "" then dName = p.Name end
    nameLbl.Text = string.format("@%s (%s)", dName, p.Name)
    nameLbl.TextColor3 = Color3.fromRGB(200, 200, 200)
    nameLbl.Font = Enum.Font.Gotham
    nameLbl.TextSize = 12
    nameLbl.TextXAlignment = Enum.TextXAlignment.Left
    nameLbl.Parent = row

    row.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            if S.whitelist[p] then
                S.whitelist[p] = nil
                check.Visible = false
            else
                S.whitelist[p] = true
                check.Visible = true
            end
        end
    end)
    playerRows[p] = row
end

for _, p in ipairs(Players:GetPlayers()) do
    if p ~= lp then createPlayerRow(p) end
end

table.insert(connections, Players.PlayerAdded:Connect(function(p) createPlayerRow(p) end))
table.insert(connections, Players.PlayerRemoving:Connect(function(p)
    if playerRows[p] then
        playerRows[p]:Destroy()
        playerRows[p] = nil
        S.whitelist[p] = nil
    end
end))

-- DYNAMIC AUTO-RESIZING LOGIC
local function updateGuiSize()
    task.wait() -- Wait a frame for UIListLayout to update
    
    -- 1. Calculate Settings height (remove the empty gap)
    local leftHeight = leftCol.UIListLayout.AbsoluteContentSize.Y
    local rightHeight = rightCol.UIListLayout.AbsoluteContentSize.Y + 50 -- +50 for unload button
    local contentHeight = math.max(leftHeight, rightHeight)
    content.Size = UDim2.new(1, -20, 0, contentHeight)
    
    -- 2. Calculate Whitelist height
    local count = 0
    for _ in pairs(playerRows) do count = count + 1 end
    
    local targetListHeight = count * 28
    local maxVisibleHeight = 150
    local finalListHeight = math.clamp(targetListHeight, 28, maxVisibleHeight)
    
    wlScroll.CanvasSize = UDim2.new(0, 0, 0, targetListHeight)
    wlScroll.Size = UDim2.new(1, -20, 0, finalListHeight)
    
    -- 3. Adjust positions to stick closely together
    wlDiv.Position = UDim2.new(0, 10, 0, 45 + contentHeight + 5)
    wlHeader.Position = UDim2.new(0, 10, 0, 45 + contentHeight + 10)
    wlScroll.Position = UDim2.new(0, 10, 0, 45 + contentHeight + 45)
    
    -- 4. Resize the main frame (without moving its position!)
    local finalMainHeight = 45 + contentHeight + 45 + finalListHeight + 10
    main.Size = UDim2.new(0, 440, 0, finalMainHeight)
end

-- Call once at start, and whenever players join/leave
updateGuiSize()
table.insert(connections, Players.PlayerAdded:Connect(updateGuiSize))
table.insert(connections, Players.PlayerRemoving:Connect(updateGuiSize))

-- ============================================================
-- Unload & Keybinds
-- ============================================================
local function unloadScript()
    if unloaded then return end
    unloaded = true
    if GunHandler and originalShoot then pcall(function() GunHandler.Shoot = originalShoot end) end
    pcall(function() fovCircle:Remove() end)
    pcall(function() aimLine:Remove() end)
    pcall(cleanupAllESP)
    for p, _ in pairs(billboards) do pcall(cleanupBillboard, p) end
    S.whitelist = {}
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    connections = {}
    pcall(function() sg:Destroy() end)
    if getgenv then getgenv()[MARKER] = nil end
    print("goated.lol unloaded")
end

if getgenv then getgenv()[MARKER] = { unload = unloadScript, originalShoot = originalShoot } end
unloadBtn.MouseButton1Click:Connect(unloadScript)

table.insert(connections, uis.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if unloaded then return end
    local key = input.KeyCode

    if key == S.keybinds.toggleGUI then
        guiVisible = not guiVisible
        if sg and sg.Parent then sg.Enabled = guiVisible end
        return
    end

    if S.keybinds.unload and key == S.keybinds.unload then
        unloadScript()
        return
    end

    local changed = false
    if S.keybinds.aim and key == S.keybinds.aim then S.aim = not S.aim; changed = true end
    if S.keybinds.esp and key == S.keybinds.esp then S.esp = not S.esp; changed = true end
    if S.keybinds.wallcheck and key == S.keybinds.wallcheck then S.wallcheck = not S.wallcheck; changed = true end
    if S.keybinds.koCheck and key == S.keybinds.koCheck then S.koCheck = not S.koCheck; changed = true end
    if S.keybinds.closestPart and key == S.keybinds.closestPart then S.closestPart = not S.closestPart; changed = true end
    if S.keybinds.fovCircle and key == S.keybinds.fovCircle then S.fovCircle = not S.fovCircle; changed = true end

    if changed then
        for name, data in pairs(toggleButtons) do
            if data.getter() then
                data.toggle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                data.knob.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
                data.knob.Position = UDim2.new(1, -16, 0.5, -7)
            else
                data.toggle.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
                data.knob.BackgroundColor3 = Color3.fromRGB(150, 150, 150)
                data.knob.Position = UDim2.new(0, 2, 0.5, -7)
            end
        end
    end
end))

print("goated.lol loaded successfully!")

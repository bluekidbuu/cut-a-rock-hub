-- Cut a Rock | Simple Hub v1.0 (client-side, executor)
-- Auto Train (near detected anvil), Auto Cut, Auto Collect.
-- Inventory check uses UUID stone cards displayed by the game's CuttingMenu.
-- Does NOT guess/replay game RemoteEvent arguments, teleport, sell, upgrade or buy.
-- PlaceId 113742027864370 / GameId 10766468833

if not game:IsLoaded() then game.Loaded:Wait() end
if game.PlaceId ~= 113742027864370 and game.GameId ~= 10766468833 then
    warn("[Cut A Rock] This is not the supported game")
    return
end

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")
local env = type(getgenv) == "function" and getgenv() or _G
if type(env.CutARockSimpleStop) == "function" then pcall(env.CutARockSimpleStop) end

local running = true
local modes = {train = false, cut = false, collect = false}
local settings = {tick = 0.8, trainCooldown = 1.25, promptCooldown = 3.0, uiCooldown = 1.5}
local lastClick, nextCut, nextTrain, nextCollect = {}, 0, 0, 0
local stats = {train = 0, open = 0, cut = 0, collect = 0, errors = 0, available = "?", status = "Siap"}
local ui, main, statusLabel, toggleLabels = nil, nil, nil, {}
local connections = {}

local function currentRoot()
    return player.Character and player.Character:FindFirstChild("HumanoidRootPart")
end
local function getPosition(item)
    if item:IsA("BasePart") then return item.Position end
    if item:IsA("Attachment") then return item.WorldPosition end
    local p = item.Parent
    if p and p:IsA("Attachment") then return p.WorldPosition end
    if p and p:IsA("BasePart") then return p.Position end
    if p and p:IsA("Model") then
        return p:GetPivot().Position
    end
    local part = item:FindFirstAncestorWhichIsA("BasePart")
    if part then return part.Position end
    return nil
end
local function inRange(pos, limit)
    local root = currentRoot()
    return root and pos and (root.Position-pos).Magnitude <= limit
end
local function activeGui(obj)
    if not obj or not obj.Parent or not obj:IsA("GuiObject") then return false end
    if not obj.Visible or obj.AbsoluteSize.X < 5 or obj.AbsoluteSize.Y < 5 then return false end
    local p = obj.Parent
    while p do
        if p:IsA("GuiObject") and not p.Visible then return false end
        if p:IsA("ScreenGui") and not p.Enabled then return false end
        p = p.Parent
    end
    return true
end
local function uuid(name)
    if type(name) ~= "string" or #name ~= 36 then return false end
    if name:sub(9,9) ~= "-" or name:sub(14,14) ~= "-"
        or name:sub(19,19) ~= "-" or name:sub(24,24) ~= "-" then return false end
    return name:gsub("-", ""):match("^%x+$") ~= nil
end
local function stamp(key, seconds)
    local now = os.clock()
    if now - (lastClick[key] or -1000) < seconds then return false end
    lastClick[key] = now
    return true
end
local function trySyntheticClick(pos)
    -- Different executors expose different input capabilities.
    local okService, vim = pcall(function() return game:GetService("VirtualInputManager") end)
    if okService and vim then
        local ok = pcall(function()
            vim:SendMouseButtonEvent(pos.X, pos.Y, 0, true, game, 0)
            task.wait(0.055)
            vim:SendMouseButtonEvent(pos.X, pos.Y, 0, false, game, 0)
        end)
        if ok then return true end
    end
    local okInput, virtualInput = pcall(function() return UserInputService:CreateVirtualInput() end)
    if okInput and virtualInput then
        local ok = pcall(function()
            virtualInput:SendMouseButton(pos, Enum.UserInputType.MouseButton1, true, 0)
            task.wait(0.055)
            virtualInput:SendMouseButton(pos, Enum.UserInputType.MouseButton1, false, 0)
        end)
        if ok then return true end
    end
    return false
end
local function clickGui(button)
    if not activeGui(button) or not button:IsA("GuiButton") then return false end
    if button.Interactable == false or button.Active == false then return false end
    if not stamp(button, settings.uiCooldown) then return false end
    local pos = button.AbsolutePosition + button.AbsoluteSize/2
    if trySyntheticClick(pos) then return true end
    if type(firesignal) == "function" then
        local ok = pcall(firesignal, button.Activated)
        if ok then return true end
    end
    stats.errors += 1
    stats.status = "Executor tidak mendukung klik GUI otomatis"
    return false
end
local function triggerPrompt(prompt)
    if not prompt or not prompt.Parent or not prompt.Enabled then return false end
    if not inRange(getPosition(prompt), prompt.MaxActivationDistance) then return false end
    if not stamp(prompt, settings.promptCooldown) then return false end
    local ok = false
    if type(fireproximityprompt) == "function" then
        ok = pcall(fireproximityprompt, prompt)
    else
        ok = pcall(function()
            prompt:InputHoldBegin()
            task.wait(math.max(0.08, prompt.HoldDuration + 0.08))
            prompt:InputHoldEnd()
        end)
    end
    if not ok then stats.errors += 1 end
    return ok
end
-- One workspace scan per interval rather than every scheduler tick.
local cachedCutPrompts, cachedAnvils, refreshAt = {}, {}, 0
local function refreshWorldCache()
    if os.clock() < refreshAt then return end
    refreshAt = os.clock() + 7
    table.clear(cachedCutPrompts)
    table.clear(cachedAnvils)
    for _,obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("ProximityPrompt") and obj.Name == "CutMachinePrompt" then
            cachedCutPrompts[#cachedCutPrompts+1] = obj
        end
        local name = obj.Name:lower()
        local training = name:find("anvil", 1, true)
            or name == "ors" or name:match("^ors[%_%-]?")
            or name:find("training", 1, true)
        if training and (obj:IsA("ProximityPrompt") or obj:IsA("ClickDetector")
                or obj:IsA("BasePart")) then
            cachedAnvils[#cachedAnvils+1] = obj
        end
    end
end
local function findCutPrompt(mode)
    local root = currentRoot()
    if not root then return nil end
    local best, bestDist = nil, math.huge
    refreshWorldCache()
    for _, obj in ipairs(cachedCutPrompts) do
        if obj.Parent and obj.Enabled then
            local action = obj.ActionText:lower()
            local isCollect = action:find("collect",1,true) ~= nil
            local isPlace = action:find("place",1,true) ~= nil
            if (mode == "collect" and isCollect) or (mode == "place" and isPlace) then
                local pos = getPosition(obj)
                if pos then
                    local dist = (root.Position-pos).Magnitude
                    if dist <= obj.MaxActivationDistance and dist < bestDist then
                        best, bestDist = obj, dist
                    end
                end
            end
        end
    end
    return best
end
local function cuttingMenu()
    return pg:FindFirstChild("CuttingMenu")
end
local function getCuttingStoneCards()
    -- Audit evidence: normal stone-choice buttons named UUIDs in CuttingMenu.
    -- No UUID card => *no selectable stone displayed*, not proven empty server inventory.
    local menu = cuttingMenu()
    local cards = {}
    if not menu or not menu:IsA("ScreenGui") or not menu.Enabled then return cards end
    for _,obj in ipairs(menu:GetDescendants()) do
        if obj:IsA("GuiButton") and uuid(obj.Name) and activeGui(obj)
            and obj.Active and obj.Interactable then
            cards[#cards+1] = obj
        end
    end
    table.sort(cards, function(a,b)
        if a.AbsolutePosition.Y ~= b.AbsolutePosition.Y then
            return a.AbsolutePosition.Y < b.AbsolutePosition.Y
        end
        return a.AbsolutePosition.X < b.AbsolutePosition.X
    end)
    return cards
end
local function getButtonByPath(path)
    local obj = pg
    for name in string.gmatch(path, "[^.]+") do
        obj = obj and obj:FindFirstChild(name)
    end
    return obj
end
local function getCutBtn()
    return getButtonByPath("CuttingMenu.MainFrame.Panel.KesimPaneli.KesButonu")
end
local function getCollectBtn()
    return getButtonByPath("CuttingMenu.MainFrame.Panel.CurrentCut.CollectTap")
end
local selectedAt, awaitingCollect = 0, false
local function collectStep()
    if not modes.collect or os.clock() < nextCollect then return false end
    local prompt = findCutPrompt("collect")
    if prompt then
        if triggerPrompt(prompt) then
            awaitingCollect = false
            stats.collect += 1
            stats.status = "Collect: prompt dikirim"
            nextCollect = os.clock() + 2.5
            return true
        end
    end
    local button = getCollectBtn()
    if button and clickGui(button) then
        awaitingCollect = false
        stats.collect += 1
        stats.status = "Collect: tombol ditekan"
        nextCollect = os.clock() + 2.5
        return true
    end
    return false
end
local function cutStep()
    if not modes.cut or os.clock() < nextCut then return end
    if awaitingCollect and modes.collect then
        local closeMenu = getButtonByPath("CuttingMenu.MainFrame.Panel.KapatButonu")
        if closeMenu and activeGui(closeMenu) then clickGui(closeMenu) end
        stats.status = "Menunggu hasil cutting siap dikumpulkan"
        return
    end
    local menu = cuttingMenu()
    local content = menu and menu:FindFirstChild("MainFrame")
    local isOpen = menu and menu:IsA("ScreenGui") and menu.Enabled
        and (not content or (content:IsA("GuiObject") and activeGui(content)))
    if isOpen then
        local cards = getCuttingStoneCards()
        stats.available = tostring(#cards) .. " pilihan pada menu"
        if selectedAt > 0 and os.clock() - selectedAt > 8 then selectedAt = 0 end
        if selectedAt > 0 then
            local cut = getCutBtn()
            if cut and clickGui(cut) then
                stats.cut += 1
                stats.status = "Mulai potong: tombol KesButonu"
                selectedAt = 0
                awaitingCollect = true
                nextCut = os.clock() + 8
                return
            end
            stats.status = "Menunggu tombol potong aktif"
            nextCut = os.clock() + 1
            return
        end
        if #cards > 0 then
            if clickGui(cards[1]) then
                selectedAt = os.clock()
                stats.status = "Batu dipilih dari inventory UI"
                nextCut = os.clock() + 1.1
                return
            end
        else
            stats.status = "Tidak ada batu pilihan dalam CuttingMenu"
            local closeMenu = getButtonByPath("CuttingMenu.MainFrame.Panel.KapatButonu")
            if closeMenu then clickGui(closeMenu) end
            nextCut = os.clock() + 12
        end
        return
    end
    selectedAt = 0
    stats.available = "cek lewat mesin"
    local prompt = findCutPrompt("place")
    if not prompt then
        stats.status = "Dekati Cutting Machine untuk periksa batu"
        nextCut = os.clock() + 2.5
        return
    end
    if triggerPrompt(prompt) then
        stats.open += 1
        stats.status = "Membuka mesin untuk cek batu"
        nextCut = os.clock() + 1.5
    end
end

-- Training is less certain: audit has not captured a verified OrsVurusu signature.
-- Use the normal, detected anvil/training input instead of guessing a remote payload.
local function findAnvil()
    local root = currentRoot()
    if not root then return nil end
    refreshWorldCache()
    local best, bestDist = nil, math.huge
    for _, obj in ipairs(cachedAnvils) do
        if obj.Parent then
            local pos = getPosition(obj)
            if pos then
                local dist = (root.Position-pos).Magnitude
                if dist < bestDist and dist <= 18 then
                    best,bestDist = obj,dist
                end
            end
        end
    end
    return best
end
local function trainStep()
    if not modes.train or os.clock() < nextTrain then return end
    -- Don't let world mouse presses interfere with the rock selection menu.
    local menu = cuttingMenu()
    if menu and menu:IsA("ScreenGui") and menu.Enabled then return end
    nextTrain = os.clock() + settings.trainCooldown
    local object = findAnvil()
    if not object then
        stats.status = "Train: mendekat ke anvil (belum terdeteksi)"
        return
    end
    local ok = false
    if object:IsA("ProximityPrompt") then
        ok = triggerPrompt(object)
    elseif object:IsA("ClickDetector") and type(fireclickdetector) == "function" then
        ok = pcall(fireclickdetector, object)
    elseif object:IsA("BasePart") then
        local camera = workspace.CurrentCamera
        if camera then
            local pos, visible = camera:WorldToViewportPoint(object.Position)
            if visible then ok = trySyntheticClick(Vector2.new(pos.X, pos.Y)) end
        end
    end
    if ok then
        stats.train += 1
        stats.status = "Train: input dikirim (hasil belum diverifikasi)"
    else
        stats.status = "Train: tidak ada interaksi yang didukung"
    end
end

-- Minimal mobile UI
local function create(class, props, parent)
    local item = Instance.new(class)
    for k,v in pairs(props) do item[k] = v end
    item.Parent = parent
    return item
end
ui = create("ScreenGui", {Name="CutARock_SimpleHub_v1", ResetOnSpawn=false,
    ZIndexBehavior=Enum.ZIndexBehavior.Sibling}, pg)
main = create("Frame", {Size=UDim2.fromOffset(294,276), Position=UDim2.new(0,12,0.23,0),
    BackgroundColor3=Color3.fromRGB(23,28,38), BorderSizePixel=0}, ui)
create("UICorner", {CornerRadius=UDim.new(0,12)}, main)
create("UIStroke", {Color=Color3.fromRGB(87,100,125), Thickness=1}, main)
local title = create("TextLabel", {Text="CUT A ROCK  |  SIMPLE HUB", Size=UDim2.fromOffset(246,35),
    Position=UDim2.fromOffset(12,4), BackgroundTransparency=1, TextColor3=Color3.new(1,1,1),
    TextSize=14, Font=Enum.Font.GothamBold, TextXAlignment=Enum.TextXAlignment.Left}, main)
local close = create("TextButton", {Text="X", Size=UDim2.fromOffset(30,28),
    Position=UDim2.fromOffset(255,7), BackgroundColor3=Color3.fromRGB(127,52,57),
    TextColor3=Color3.new(1,1,1), TextSize=14, BorderSizePixel=0}, main)
create("UICorner", {CornerRadius=UDim.new(0,6)}, close)
local function makeToggle(key, text, y)
    local b = create("TextButton", {Text="", Size=UDim2.fromOffset(269,38),
        Position=UDim2.fromOffset(12,y), BackgroundColor3=Color3.fromRGB(43,52,69),
        BorderSizePixel=0}, main)
    create("UICorner", {CornerRadius=UDim.new(0,7)}, b)
    create("TextLabel", {Text=text, Size=UDim2.fromOffset(205,38),
        Position=UDim2.fromOffset(10,0), BackgroundTransparency=1,
        TextColor3=Color3.new(1,1,1), TextSize=13, Font=Enum.Font.GothamMedium,
        TextXAlignment=Enum.TextXAlignment.Left}, b)
    local indicator = create("TextLabel", {Text="OFF", Size=UDim2.fromOffset(45,27),
        Position=UDim2.fromOffset(216,5), BackgroundColor3=Color3.fromRGB(112,51,62),
        TextColor3=Color3.new(1,1,1), TextSize=11,
        Font=Enum.Font.GothamBold, BorderSizePixel=0}, b)
    create("UICorner", {CornerRadius=UDim.new(0,5)}, indicator)
    toggleLabels[key] = indicator
    connections[#connections+1] = b.Activated:Connect(function()
        modes[key] = not modes[key]
        indicator.Text = modes[key] and "ON" or "OFF"
        indicator.BackgroundColor3 = modes[key] and Color3.fromRGB(38,126,87)
            or Color3.fromRGB(112,51,62)
        stats.status = key .. (modes[key] and " ON" or " OFF")
    end)
end
makeToggle("train", "Auto Train", 44)
makeToggle("cut", "Auto Cut + cek batu", 87)
makeToggle("collect", "Auto Collect", 130)
statusLabel = create("TextLabel", {Text="Inventory: ?\nSiap", Size=UDim2.fromOffset(267,60),
    Position=UDim2.fromOffset(13,174), BackgroundTransparency=1,
    TextColor3=Color3.fromRGB(176,204,230), Font=Enum.Font.Gotham,
    TextWrapped=true, TextSize=11, TextXAlignment=Enum.TextXAlignment.Left,
    TextYAlignment=Enum.TextYAlignment.Top}, main)
local hint = create("TextLabel", {Text="Jarak dekat • tidak teleport • tanpa remote tebakan",
    Size=UDim2.fromOffset(267,24), Position=UDim2.fromOffset(13,243),
    BackgroundTransparency=1, TextColor3=Color3.fromRGB(131,145,164), TextSize=10},main)
local drag, startPointer, startFrame = false, nil, nil
connections[#connections+1] = title.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1 then
        drag=true; startPointer=input.Position; startFrame=main.Position
        local c; c=input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                drag=false; c:Disconnect()
            end
        end)
    end
end)
connections[#connections+1] = UserInputService.InputChanged:Connect(function(input)
    if drag and startPointer and (input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseMovement) then
        local delta = input.Position - startPointer
        main.Position = UDim2.new(startFrame.X.Scale, startFrame.X.Offset+delta.X,
            startFrame.Y.Scale, startFrame.Y.Offset+delta.Y)
    end
end)
local function stop()
    running = false
    for _,c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    if ui then ui:Destroy() end
    env.CutARockSimpleStop = nil
end
env.CutARockSimpleStop = stop
connections[#connections+1] = close.Activated:Connect(stop)

task.spawn(function()
    while running do
        local ok, err = pcall(function()
            if modes.collect then collectStep() end
            if modes.cut then cutStep() end
            if modes.train then trainStep() end
        end)
        if not ok then
            stats.errors += 1
            stats.status = "Error: "..tostring(err):sub(1,90)
        end
        if statusLabel then
            statusLabel.Text = "Batu di menu: "..stats.available
                .. " | Train "..stats.train.." Cut "..stats.cut.." Collect "..stats.collect
                .. "\n"..stats.status
        end
        task.wait(settings.tick)
    end
end)
print("[Cut A Rock] Simple Hub v1 ready. Train needs a detectable anvil; Cut/Collect use normal prompts and GUI.")

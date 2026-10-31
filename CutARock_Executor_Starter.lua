-- Cut a Rock | Executor Starter v0.1
-- Place ID: 113742027864370 | Universe ID: 10766468833
-- Self-contained: no downloads, web requests, or unknown remotes fired.
-- The game-specific action system has not been verified.

if not game:IsLoaded() then game.Loaded:Wait() end

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer

if game.PlaceId ~= 113742027864370 and game.GameId ~= 10766468833 then
    warn("[Cut a Rock] This script is intended only for Cut a Rock.")
    return
end

local env = (type(getgenv) == "function" and getgenv()) or _G
if env.CutARockStarter and type(env.CutARockStarter.Stop) == "function" then
    pcall(env.CutARockStarter.Stop)
end

local running = true
local enabled = {train = false, mine = false, cut = false, sell = false, tool = false}
local candidates = {}
local lastAction = setmetatable({}, {__mode = "k"})
local actionsDone, scanCount = 0, 0
local status = nil

local gui = Instance.new("ScreenGui")
gui.Name = "CAR_Executor_Starter"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local function stop()
    running = false
    if gui and gui.Parent then gui:Destroy() end
end
env.CutARockStarter = {Stop = stop}

local function make(class, props, parent)
    local obj = Instance.new(class)
    for k, v in pairs(props) do obj[k] = v end
    obj.Parent = parent
    return obj
end

local frame = make("Frame", {
    Size = UDim2.fromOffset(300, 389),
    Position = UDim2.new(0, 16, 0.18, 0),
    BackgroundColor3 = Color3.fromRGB(24, 27, 36),
    BorderSizePixel = 0
}, gui)
make("UICorner", {CornerRadius = UDim.new(0, 11)}, frame)
make("UIStroke", {Color = Color3.fromRGB(65, 72, 91), Thickness = 1}, frame)

local header = make("TextLabel", {
    Size = UDim2.new(1, -50, 0, 36), Position = UDim2.fromOffset(12, 3),
    Text = "CUT A ROCK  |  STARTER", TextColor3 = Color3.new(1, 1, 1),
    BackgroundTransparency = 1, TextSize = 16, Font = Enum.Font.GothamBold,
    TextXAlignment = Enum.TextXAlignment.Left
}, frame)
local close = make("TextButton", {
    Size = UDim2.fromOffset(30, 27), Position = UDim2.new(1, -38, 0, 7),
    Text = "X", TextSize = 16, Font = Enum.Font.GothamBold,
    BackgroundColor3 = Color3.fromRGB(93, 45, 49), TextColor3 = Color3.new(1, 1, 1),
    BorderSizePixel = 0
}, frame)
make("UICorner", {CornerRadius = UDim.new(0, 6)}, close)
close.MouseButton1Click:Connect(stop)

-- Mobile-friendly drag; grab the header to move the window.
do
    local dragging, dragStart, startPos = false, nil, nil
    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging, dragStart, startPos = true, input.Position, frame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if not running or not dragging or not dragStart then return end
        if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
        local delta = input.Position - dragStart
        frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end)
end

make("TextLabel", {
    Size = UDim2.new(1, -24, 0, 29), Position = UDim2.fromOffset(12, 39),
    Text = "Nearby interactions only; no remote spam",
    BackgroundTransparency = 1, TextColor3 = Color3.fromRGB(161, 169, 188),
    TextSize = 11, Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left
}, frame)

local function toggleRow(key, title, y)
    local b = make("TextButton", {
        Size = UDim2.new(1, -24, 0, 35), Position = UDim2.fromOffset(12, y),
        Text = "", BackgroundColor3 = Color3.fromRGB(42, 47, 60),
        BorderSizePixel = 0
    }, frame)
    make("UICorner", {CornerRadius = UDim.new(0, 7)}, b)
    local label = make("TextLabel", {
        Size = UDim2.new(1, -80, 1, 0), Position = UDim2.fromOffset(10, 0),
        Text = title, TextSize = 13, TextColor3 = Color3.new(1, 1, 1),
        BackgroundTransparency = 1, Font = Enum.Font.GothamMedium,
        TextXAlignment = Enum.TextXAlignment.Left
    }, b)
    local indicator = make("TextLabel", {
        Size = UDim2.fromOffset(51, 25), Position = UDim2.new(1, -59, 0, 5),
        Text = "OFF", BackgroundColor3 = Color3.fromRGB(104, 49, 54),
        TextColor3 = Color3.new(1, 1, 1), TextSize = 12,
        Font = Enum.Font.GothamBold, BorderSizePixel = 0
    }, b)
    make("UICorner", {CornerRadius = UDim.new(0, 6)}, indicator)
    b.MouseButton1Click:Connect(function()
        enabled[key] = not enabled[key]
        indicator.Text = enabled[key] and "ON" or "OFF"
        indicator.BackgroundColor3 = enabled[key]
            and Color3.fromRGB(37, 115, 76) or Color3.fromRGB(104, 49, 54)
    end)
end

toggleRow("train", "Auto Train (anvil / prompt)", 71)
toggleRow("mine", "Auto Mine (nearby prompt)", 110)
toggleRow("cut", "Auto Cut (nearby machine)", 149)
toggleRow("sell", "Auto Sell (nearby prompt)", 188)
toggleRow("tool", "Auto Activate Equipped Tool", 227)

status = make("TextLabel", {
    Size = UDim2.new(1, -24, 0, 38), Position = UDim2.fromOffset(12, 266),
    Text = "Ready. Scan to detect interactions.",
    BackgroundTransparency = 1, TextColor3 = Color3.fromRGB(190, 206, 226),
    TextSize = 11, Font = Enum.Font.Gotham, TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left
}, frame)

local scanButton = make("TextButton", {
    Size = UDim2.new(0.5, -16, 0, 34), Position = UDim2.fromOffset(12, 309),
    Text = "SCAN", BackgroundColor3 = Color3.fromRGB(49, 79, 133),
    TextColor3 = Color3.new(1, 1, 1), TextSize = 13,
    Font = Enum.Font.GothamBold, BorderSizePixel = 0
}, frame)
local reportButton = make("TextButton", {
    Size = UDim2.new(0.5, -16, 0, 34), Position = UDim2.new(0.5, 4, 0, 309),
    Text = "COPY REPORT", BackgroundColor3 = Color3.fromRGB(57, 65, 87),
    TextColor3 = Color3.new(1, 1, 1), TextSize = 12,
    Font = Enum.Font.GothamBold, BorderSizePixel = 0
}, frame)
make("UICorner", {CornerRadius = UDim.new(0, 7)}, scanButton)
make("UICorner", {CornerRadius = UDim.new(0, 7)}, reportButton)

make("TextLabel", {
    Size = UDim2.new(1, -24, 0, 31), Position = UDim2.fromOffset(12, 349),
    Text = "Test version: may not support remote-based actions.",
    TextWrapped = true, BackgroundTransparency = 1,
    TextColor3 = Color3.fromRGB(141, 150, 170),
    TextSize = 10, Font = Enum.Font.Gotham
}, frame)

local function hasAny(s, words)
    for _, word in ipairs(words) do
        if string.find(s, word, 1, true) then return true end
    end
    return false
end

local function classify(obj)
    local parent = obj.Parent
    local text = (parent and parent.Name or "") .. " " ..
        (parent and parent.Parent and parent.Parent.Name or "") .. " " .. obj.Name
    if obj:IsA("ProximityPrompt") then
        text = text .. " " .. obj.ActionText .. " " .. obj.ObjectText
    end
    text = string.lower(text)
    if hasAny(text, {"buy", "shop", "purchase", "robux", "gamepass", "upgrade", "gift", "premium", "pack"}) then
        return nil
    end
    if hasAny(text, {"anvil", "train"}) then return "train" end
    if hasAny(text, {"sell", "market"}) then return "sell" end
    if hasAny(text, {"cutter", "cutting", "slice", "machine", "cut"}) then return "cut" end
    if hasAny(text, {"mine", "rock", "dig", "floor", "break", "ore"}) then return "mine" end
    return nil
end

local function partFor(obj)
    if obj.Parent and obj.Parent:IsA("BasePart") then return obj.Parent end
    return obj:FindFirstAncestorWhichIsA("BasePart")
end

local function scan()
    table.clear(candidates)
    local counts = {train = 0, mine = 0, cut = 0, sell = 0}
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("ProximityPrompt") or obj:IsA("ClickDetector") then
            local cat = classify(obj)
            local part = cat and partFor(obj)
            if cat and part then
                table.insert(candidates, {obj = obj, part = part, cat = cat})
                counts[cat] += 1
            end
        end
    end
    scanCount += 1
    if running then
        status.Text = ("Found: train %d | mine %d | cut %d | sell %d\nActions triggered: %d")
            :format(counts.train, counts.mine, counts.cut, counts.sell, actionsDone)
    end
end

scanButton.MouseButton1Click:Connect(scan)

local function makeReport()
    local lines = {
        "CUT A ROCK DIAGNOSTIC v0.1",
        "PlaceId=" .. tostring(game.PlaceId),
        "GameId=" .. tostring(game.GameId),
        "Scans=" .. tostring(scanCount),
        "Interactions=" .. tostring(#candidates),
        "Actions=" .. tostring(actionsDone),
        "--- DETECTED INTERACTIONS (max 60) ---"
    }
    for i, item in ipairs(candidates) do
        if i > 60 then break end
        local obj = item.obj
        local extra = obj:IsA("ProximityPrompt") and
            (" [" .. obj.ActionText .. " / " .. obj.ObjectText .. "]") or ""
        table.insert(lines, item.cat .. " | " .. obj:GetFullName() .. extra)
    end
    table.insert(lines, "--- REMOTE NAMES (max 60, not invoked) ---")
    local n = 0
    for _, obj in ipairs(RS:GetDescendants()) do
        if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
            n += 1
            if n <= 60 then table.insert(lines, obj.ClassName .. " | " .. obj:GetFullName()) end
        end
    end
    table.insert(lines, "RemoteCount=" .. tostring(n))
    table.insert(lines, "--- PLAYER GUI BUTTONS (max 35) ---")
    local count = 0
    for _, obj in ipairs(player.PlayerGui:GetDescendants()) do
        if (obj:IsA("TextButton") or obj:IsA("ImageButton")) and not obj:IsDescendantOf(gui) then
            count += 1
            if count <= 35 then
                local buttonText = obj:IsA("TextButton") and obj.Text or "[image]"
                table.insert(lines, obj:GetFullName() .. " | " .. buttonText:sub(1, 65))
            end
        end
    end
    return table.concat(lines, "\n")
end

reportButton.MouseButton1Click:Connect(function()
    scan()
    local report = makeReport()
    print(report)
    if type(setclipboard) == "function" then
        local ok = pcall(setclipboard, report)
        status.Text = ok and "Report copied. Paste it into ChatGPT."
            or "Clipboard failed. Check executor console."
    else
        status.Text = "No setclipboard(). Open executor console to copy report."
    end
end)

local function nearestEnabled()
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    local chosen, bestDist = nil, math.huge
    for _, item in ipairs(candidates) do
        local obj, part = item.obj, item.part
        if enabled[item.cat] and obj.Parent and part.Parent then
            local distance = (root.Position - part.Position).Magnitude
            local limit = 12
            if obj:IsA("ProximityPrompt") then
                limit = math.min(12, obj.MaxActivationDistance)
            elseif obj:IsA("ClickDetector") then
                limit = math.min(12, obj.MaxActivationDistance)
            end
            if distance <= limit and distance < bestDist
                and (os.clock() - (lastAction[obj] or -100)) >= 2.5 then
                if not obj:IsA("ProximityPrompt") or obj.Enabled then
                    chosen, bestDist = item, distance
                end
            end
        end
    end
    return chosen
end

task.spawn(function()
    while running do
        local item = nearestEnabled()
        if item then
            local obj = item.obj
            local ok = false
            if obj:IsA("ProximityPrompt") and type(fireproximityprompt) == "function" then
                ok = pcall(fireproximityprompt, obj)
            elseif obj:IsA("ClickDetector") and type(fireclickdetector) == "function" then
                ok = pcall(fireclickdetector, obj)
            end
            if ok then
                lastAction[obj] = os.clock()
                actionsDone += 1
            end
        end
        if enabled.tool then
            local char = player.Character
            local tool = char and char:FindFirstChildOfClass("Tool")
            if tool then pcall(function() tool:Activate() end) end
        end
        task.wait(0.7)
    end
end)

task.spawn(function()
    while running do
        pcall(scan)
        task.wait(12)
    end
end)

print("[Cut a Rock] Starter v0.1 launched. Toggle features and use COPY REPORT.")

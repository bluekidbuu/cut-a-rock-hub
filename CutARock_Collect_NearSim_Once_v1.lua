-- CUT A ROCK | NEAR SIMULATED COLLECT | DIAGNOSTIC v1.0
-- Research-only, one-shot experiment; NOT an Auto Collect solution.
-- Question: does fireproximityprompt give a REAL reward from normal prompt range?
-- No teleport, no FireServer, no InvokeServer, no auto-loop, no prompt-range edit.
-- It does not modify the Unified v1.4 Cut / Train / Speed engines.
-- WARNING: A local success, changed prompt, or notification is not proof of reward.
-- Real reward is reported by the player via YES / NO after checking the game.

if not game:IsLoaded() then game.Loaded:Wait() end
if game.PlaceId ~= 113742027864370 and game.GameId ~= 10766468833 then
    warn('[CAR Collect NearSim] This test is only for Cut a Rock.')
    return
end

local Players = game:GetService('Players')
local RS = game:GetService('ReplicatedStorage')
local PPS = game:GetService('ProximityPromptService')
local UIS = game:GetService('UserInputService')
local player = Players.LocalPlayer
local pg = player:WaitForChild('PlayerGui')
local env = (type(getgenv) == 'function' and getgenv()) or _G

-- Only close an older copy of THIS diagnostic. Do not stop Unified or other tools.
if type(env.CARCollectNearSimOnceStop) == 'function' then
    pcall(env.CARCollectNearSimOnceStop)
end

local alive = true
local startTime = os.clock()
local boundModel, boundPrompt = nil, nil
local ownershipConfirmed = false
local attempted = false
local observing = false
local observationSeconds = 13
local observationEnd = 0
local trial = nil
local statusText = 'Stand near YOUR machine showing Collect. Then BIND NEAREST.'
local logs, connections = {}, {}
local watchedRemote = {}
local subscribed = 0
local gui, panel, detailLabel

local function log(s)
    logs[#logs + 1] = string.format('T+%.2fs %s', os.clock() - startTime, tostring(s))
    if #logs > 45 then table.remove(logs, 1) end
end

local function findModel(o)
    while o and o ~= workspace do
        if o:IsA('Model') and o.Name:match('^level%d+$') then return o end
        o = o.Parent
    end
    return nil
end

local function pointOf(p)
    local o = p and p.Parent
    if o and o:IsA('Attachment') then return o.WorldPosition end
    if o and o:IsA('BasePart') then return o.Position end
    local part = o and o:FindFirstAncestorWhichIsA('BasePart')
    return part and part.Position or nil
end

local function distanceOf(p)
    local character = player.Character
    local root = character and character:FindFirstChild('HumanoidRootPart')
    local point = pointOf(p)
    if root and point then return (root.Position - point).Magnitude end
    return nil
end

local function ownerHint(model)
    local cur = model
    local keys = {'OwnerUserId', 'PlayerUserId', 'UserId', 'Owner', 'OwnerName', 'PlayerName'}
    while cur and cur ~= workspace do
        for _, key in ipairs(keys) do
            local v = cur:GetAttribute(key)
            if type(v) == 'string' or type(v) == 'number' then
                local s = tostring(v):lower()
                if s == tostring(player.UserId) or s == player.Name:lower() then
                    return 'SELF'
                end
                return 'OTHER'
            end
        end
        cur = cur.Parent
    end
    return 'UNKNOWN'
end

local function isCollect(p)
    return p and p.Parent and p:IsA('ProximityPrompt') and p.Enabled
        and string.find(string.lower(p.ActionText or ''), 'collect', 1, true) ~= nil
end

local function bindNearest()
    if not alive then return end
    if attempted or observing then
        statusText = 'This one-shot run has already been used. Copy the report.'
        return
    end
    local nearest, nearestModel, smallest = nil, nil, math.huge
    for _, p in ipairs(workspace:GetDescendants()) do
        if p:IsA('ProximityPrompt') and p.Name == 'CutMachinePrompt' and isCollect(p) then
            local model = findModel(p)
            local d = distanceOf(p)
            if model and d and d <= p.MaxActivationDistance and d < smallest
                and ownerHint(model) ~= 'OTHER' then
                nearest, nearestModel, smallest = p, model, d
            end
        end
    end
    ownershipConfirmed = false
    boundPrompt, boundModel = nearest, nearestModel
    if nearest then
        statusText = string.format('Bound %s at %.1f studs. Confirm it is YOUR machine.',
            nearestModel.Name, smallest)
        log(string.format('BIND model=%s distance=%.1f range=%.1f ownerHint=%s',
            nearestModel.Name, smallest, nearest.MaxActivationDistance, ownerHint(nearestModel)))
    else
        statusText = 'No Collect prompt in normal range. Move near YOUR ready machine.'
        log('BIND_NONE')
    end
end

local function confirmMine()
    if not alive then return end
    if attempted then statusText = 'Test already attempted; cannot rebind.'; return end
    if not boundPrompt or not boundPrompt.Parent or not boundModel or not boundModel.Parent then
        statusText = 'BIND NEAREST first.'; return
    end
    if ownerHint(boundModel) == 'OTHER' then
        ownershipConfirmed = false
        statusText = 'Owner attribute indicates a different player; blocked.'
        log('OWNER_BLOCKED')
        return
    end
    ownershipConfirmed = true
    statusText = 'Ownership confirmed by player. Use TEST ONCE while prompt is Collect.'
    log('PLAYER_CONFIRMED_OWN_MACHINE')
end

local function doTest()
    if not alive then return end
    if attempted then statusText = 'Already attempted once. No retry in this session.'; return end
    if not ownershipConfirmed then statusText = 'Press CONFIRM MY MACHINE first.'; return end
    local p = boundPrompt
    if not p or not p.Parent or not boundModel or not boundModel.Parent then
        statusText = 'Bound prompt/model disappeared. Bind again.'; return
    end
    if findModel(p) ~= boundModel then
        statusText = 'Prompt changed parent/model; blocked.'; return
    end
    if ownerHint(boundModel) == 'OTHER' then
        statusText = 'Ownership mismatch; blocked.'; return
    end
    if not isCollect(p) then
        statusText = 'Machine must show Collect and prompt must be enabled.'; return
    end
    local distance = distanceOf(p)
    if not distance then statusText = 'Character position unavailable.'; return end
    if distance > p.MaxActivationDistance then
        statusText = string.format('Too far: %.1f / %.1f studs. Walk inside prompt range.',
            distance, p.MaxActivationDistance)
        return
    end
    if type(fireproximityprompt) ~= 'function' then
        statusText = 'Executor does not support fireproximityprompt; no test performed.'
        log('METHOD_UNAVAILABLE')
        return
    end

    -- One-shot lock is set BEFORE invoking the executor function, even on error.
    attempted = true
    observing = true
    observationEnd = os.clock() + observationSeconds
    trial = {
        distance = distance,
        range = p.MaxActivationDistance,
        ownerHint = ownerHint(boundModel),
        before = p.ActionText,
        after = p.ActionText,
        promptChanged = false,
        placeRockSeen = false,
        promptTriggeredSignals = 0,
        kesim = 0,
        aura = 0,
        callOK = false,
        callError = '',
        reward = 'UNVERIFIED',
        ended = false
    }
    -- Event-based prompt observation avoids missing fast ActionText changes.
    connections[#connections + 1] = p:GetPropertyChangedSignal('ActionText'):Connect(function()
        if not alive or not observing or not trial then return end
        local action = p.ActionText
        if action ~= trial.after then
            trial.promptChanged = true
            trial.after = action
            if string.find(string.lower(action), 'place rock', 1, true) then
                trial.placeRockSeen = true
            end
            log('PROMPT_STATE_CHANGED=' .. action)
        end
    end)
    log(string.format('NEAR_SIM_ONCE_START distance=%.1f range=%.1f before=%s',
        distance, p.MaxActivationDistance, p.ActionText))
    local ok, err = pcall(function() fireproximityprompt(p) end)
    trial.callOK = ok
    if not ok then trial.callError = tostring(err):sub(1,160) end
    log('LOCAL_CALL_OK=' .. tostring(ok) .. ' (NOT server acceptance)')
    if not ok then log('LOCAL_ERROR=' .. trial.callError) end
    statusText = 'One call attempted. Observe actual reward, then tap REWARD YES or NO.'

    task.delay(observationSeconds, function()
        if not alive or not trial then return end
        observing = false
        trial.ended = true
        if boundPrompt and boundPrompt.Parent then trial.after = boundPrompt.ActionText end
        log('OBSERVATION_DONE promptChanged=' .. tostring(trial.promptChanged)
            .. ' reward=' .. trial.reward)
        statusText = 'Observation finished. Check actual reward, select YES/NO, COPY REPORT.'
    end)
end

local function rewardMark(yes)
    if not attempted or not trial then
        statusText = 'Run TEST ONCE before recording a result.'
        return
    end
    trial.reward = yes and 'YES' or 'NO'
    log('REAL_REWARD_BY_PLAYER=' .. trial.reward)
    statusText = 'Recorded real reward ' .. trial.reward .. '. Copy the report and send it.'
end

-- Only observe named inbound notifications. No outbound calls or hooks.
local function watchRemote(o)
    if not alive or not o:IsA('RemoteEvent') or watchedRemote[o] then return end
    if o.Name ~= 'KesimBildirimi' and o.Name ~= 'AuraBildirimi' then return end
    watchedRemote[o] = true
    local ok, conn = pcall(function()
        return o.OnClientEvent:Connect(function(...)
            if not alive or not observing or not trial then return end
            if o.Name == 'KesimBildirimi' then trial.kesim = trial.kesim + 1
            else trial.aura = trial.aura + 1 end
            log('INBOUND ' .. o.Name .. ' argumentCount=' .. tostring(select('#', ...)))
        end)
    end)
    if ok and conn then
        subscribed = subscribed + 1
        connections[#connections + 1] = conn
    end
end
for _, o in ipairs(RS:GetDescendants()) do watchRemote(o) end
connections[#connections + 1] = RS.DescendantAdded:Connect(watchRemote)

connections[#connections + 1] = PPS.PromptTriggered:Connect(function(p)
    if alive and observing and trial and p == boundPrompt then
        trial.promptTriggeredSignals = trial.promptTriggeredSignals + 1
        log('LOCAL_PROMPT_TRIGGERED_SIGNAL (NOT server reward proof)')
    end
end)

local report
report = function()
    local lines = {
        'CUT A ROCK | NEAR SIMULATED COLLECT ONE-SHOT v1.0',
        'PlaceId=' .. tostring(game.PlaceId),
        'MachineBound=' .. tostring(boundModel ~= nil and boundModel.Parent ~= nil),
        'MachineLevel=' .. (boundModel and boundModel.Name or 'none'),
        'OwnerHint=' .. (boundModel and ownerHint(boundModel) or 'none'),
        'OwnershipConfirmedByPlayer=' .. tostring(ownershipConfirmed),
        'FunctionAvailable=' .. tostring(type(fireproximityprompt) == 'function'),
        'Attempted=' .. tostring(attempted),
        'Observing=' .. tostring(observing),
        'ObservationSeconds=' .. tostring(observationSeconds),
        'InboundNotificationListeners=' .. tostring(subscribed)
    }
    if trial then
        lines[#lines + 1] = string.format('Distance=%.1f Range=%.1f', trial.distance, trial.range)
        lines[#lines + 1] = 'PromptBefore=' .. tostring(trial.before)
        lines[#lines + 1] = 'PromptAfter=' .. tostring(trial.after)
        lines[#lines + 1] = 'PromptChanged=' .. tostring(trial.promptChanged)
        lines[#lines + 1] = 'PlaceRockSeen=' .. tostring(trial.placeRockSeen)
        lines[#lines + 1] = 'LocalCallOK=' .. tostring(trial.callOK)
        lines[#lines + 1] = 'LocalCallError=' .. (trial.callError ~= '' and trial.callError or 'none')
        lines[#lines + 1] = 'LocalPromptTriggeredSignals=' .. tostring(trial.promptTriggeredSignals)
        lines[#lines + 1] = 'KesimBildirimi=' .. tostring(trial.kesim)
        lines[#lines + 1] = 'AuraBildirimi=' .. tostring(trial.aura)
        lines[#lines + 1] = 'RealRewardByPlayer=' .. trial.reward
        lines[#lines + 1] = 'ObservationEnded=' .. tostring(trial.ended)
    else
        lines[#lines + 1] = 'Trial=NOT_STARTED'
    end
    lines[#lines + 1] = 'NOTE: Local call, PromptTriggered and notifications are NOT real reward proof.'
    lines[#lines + 1] = 'NOTE: Reward YES means player saw actual reward increase in game.'
    lines[#lines + 1] = '--- TIMELINE ---'
    for _, line in ipairs(logs) do lines[#lines + 1] = line end
    return table.concat(lines, '\n')
end

local function copyReport()
    local data = report()
    print(data)
    local copy = (type(setclipboard) == 'function' and setclipboard)
        or (type(toclipboard) == 'function' and toclipboard) or nil
    if copy and pcall(copy, data) then
        statusText = 'Report copied to clipboard. Paste it in ChatGPT.'
    else
        statusText = 'Report printed in executor console. Copy it from there.'
    end
end

local function stop()
    if not alive then return end
    alive = false
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    if gui then gui:Destroy() end
    if env.CARCollectNearSimOnceStop == stop then env.CARCollectNearSimOnceStop = nil end
end
env.CARCollectNearSimOnceStop = stop

local function create(className, props, parent)
    local obj = Instance.new(className)
    for k, v in pairs(props) do obj[k] = v end
    obj.Parent = parent
    return obj
end

gui = create('ScreenGui', {
    Name = 'CAR_Collect_NearSim_Once_v1', ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling
}, pg)
panel = create('Frame', {
    Position = UDim2.new(0, 10, 0.12, 0), Size = UDim2.fromOffset(322, 439),
    BackgroundColor3 = Color3.fromRGB(22, 28, 40), BorderSizePixel = 0
}, gui)
create('UICorner', {CornerRadius = UDim.new(0, 10)}, panel)
create('UIStroke', {Color = Color3.fromRGB(72, 106, 140), Thickness = 1}, panel)
local title = create('TextLabel', {
    Text = 'CAR | COLLECT NEAR TEST v1',
    Position = UDim2.fromOffset(12, 5), Size = UDim2.fromOffset(261, 30),
    BackgroundTransparency = 1, TextColor3 = Color3.new(1, 1, 1),
    Font = Enum.Font.GothamBold, TextSize = 13,
    TextXAlignment = Enum.TextXAlignment.Left
}, panel)

local function button(label, x, y, width, height, action)
    local b = create('TextButton', {
        Text = label, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(width, height),
        BackgroundColor3 = Color3.fromRGB(43, 74, 105),
        TextColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
        Font = Enum.Font.GothamMedium, TextSize = 11
    }, panel)
    create('UICorner', {CornerRadius = UDim.new(0, 7)}, b)
    connections[#connections + 1] = b.Activated:Connect(action)
    return b
end

button('X', 282, 6, 29, 26, stop)
detailLabel = create('TextLabel', {
    Text = '', Position = UDim2.fromOffset(11, 42), Size = UDim2.fromOffset(300, 131),
    BackgroundTransparency = 1, TextColor3 = Color3.fromRGB(205, 221, 238),
    Font = Enum.Font.Gotham, TextSize = 11, TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top
}, panel)
button('1. BIND NEAREST COLLECT', 11, 178, 300, 33, bindNearest)
button('2. CONFIRM MY MACHINE', 11, 217, 300, 33, confirmMine)
button('3. TEST NEAR ONCE', 11, 257, 300, 37, doTest)
button('REAL REWARD YES', 11, 301, 146, 33, function() rewardMark(true) end)
button('NO REWARD', 165, 301, 146, 33, function() rewardMark(false) end)
button('COPY REPORT', 11, 344, 300, 37, copyReport)
create('TextLabel', {
    Text = 'Single prompt call only. Confirm REAL reward, not an animation.',
    Position = UDim2.fromOffset(12, 392), Size = UDim2.fromOffset(298, 32),
    BackgroundTransparency = 1, TextColor3 = Color3.fromRGB(158, 185, 213),
    Font = Enum.Font.Gotham, TextSize = 10, TextWrapped = true
}, panel)

local dragging = false
local dragStart, oldPos
connections[#connections + 1] = title.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart, oldPos = input.Position, panel.Position
        local c
        c = input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
                c:Disconnect()
            end
        end)
    end
end)
connections[#connections + 1] = UIS.InputChanged:Connect(function(input)
    if dragging and dragStart and (input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseMovement) then
        local delta = input.Position - dragStart
        panel.Position = UDim2.new(oldPos.X.Scale, oldPos.X.Offset + delta.X,
            oldPos.Y.Scale, oldPos.Y.Offset + delta.Y)
    end
end)

log('LOADED; passive listeners=' .. tostring(subscribed) .. '; no tests yet')
task.spawn(function()
    while alive do
        local ok = pcall(function()
            if trial and observing and boundPrompt and boundPrompt.Parent then
                local action = boundPrompt.ActionText
                if action ~= trial.after then
                    trial.promptChanged = true
                    trial.after = action
                    if string.find(string.lower(action), 'place rock', 1, true) then
                        trial.placeRockSeen = true
                    end
                    log('PROMPT_STATE_CHANGED=' .. action)
                end
            end
            local p = boundPrompt
            local d = p and distanceOf(p) or nil
            local positionLine = string.format('Machine: %s  |  Dist: %s / %s',
                boundModel and boundModel.Name or 'none',
                d and string.format('%.1f', d) or '?',
                p and string.format('%.1f', p.MaxActivationDistance) or '?')
            local testLine
            if trial then
                testLine = string.format('Test: %s | PromptChanged: %s | Reward: %s',
                    observing and 'OBSERVING' or 'DONE',
                    tostring(trial.promptChanged), trial.reward)
            else
                testLine = 'Test: NOT STARTED'
            end
            detailLabel.Text = positionLine .. '\nPrompt: ' .. (p and p.ActionText or 'none')
                .. '\n' .. testLine .. '\n' .. statusText
        end)
        if not ok then statusText = 'Display error; collect report from console if available.' end
        task.wait(0.20)
    end
end)
print('[CAR Collect NearSim] v1 loaded. Bind your ready machine; confirm ownership; TEST once within normal prompt range.')

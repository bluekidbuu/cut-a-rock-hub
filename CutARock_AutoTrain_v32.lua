-- Cut a Rock | Auto Train v3.2 - round-synced, change-based memory-game assistant
-- Cut a Rock PlaceId 113742027864370 / GameId 10766468833
-- Uses only local GUI observation and GUI button activation.
-- No FireServer, InvokeServer, purchases, movement, or server-side bypass.
-- Enable before pressing PLAY (ideally at the game's "PRESS PLAY TO START" screen).

if not game:IsLoaded() then game.Loaded:Wait() end
if game.PlaceId ~= 113742027864370 and game.GameId ~= 10766468833 then
    warn('[CAR Train v3] Not the expected game.')
    return
end

local Players = game:GetService('Players')
local UIS = game:GetService('UserInputService')
local player = Players.LocalPlayer
local playerGui = player:WaitForChild('PlayerGui')
local env = type(getgenv) == 'function' and getgenv() or _G
if type(env.CutARockTrainV3Stop) == 'function' then
    pcall(env.CutARockTrainV3Stop)
end

local alive = true
local on = false
local connections = {}
local lastPress = setmetatable({}, {__mode='k'})
local state = 'OFF'
local phase = 'unknown'
local previousPhase = 'unknown'
local sequence = {}
local tileList = {}
local litLatch = nil
local proposed = nil
local proposedAt = 0
local replaying = false
local synced = false
local turn = 0
local successes = 0
local retries = 0
local lastActionAt = 0
local lastListAt = 0
local lastPhaseAt = os.clock()
local pressMethod = 'none'
local debugLast = 'Ready'
local observed = 0
-- Track NEW tile changes instead of interpreting every old Image swap as a flash.
local previousVisual = setmetatable({}, {__mode='k'})
local previousStrength = setmetatable({}, {__mode='k'})
local visualAtRest = setmetatable({}, {__mode='k'})
local recentPulse = setmetatable({}, {__mode='k'})
local tileFlashActive = setmetatable({}, {__mode='k'})
local waitingForRoundResult = false
local flashesRejected = 0
local visualChanges = 0
local recentTrace = {}
local function trace(message)
    if #recentTrace >= 32 then table.remove(recentTrace, 1) end
    recentTrace[#recentTrace+1] = string.format('%.2f | %s', os.clock(), message)
end
local gui

local function path(root, name)
    local node = root
    for p in string.gmatch(name, '[^.]+') do
        node = node and node:FindFirstChild(p)
    end
    return node
end
local function isVisible(obj)
    if not obj or not obj.Parent or not obj:IsA('GuiObject') then return false end
    if obj.AbsoluteSize.X <= 1 or obj.AbsoluteSize.Y <= 1 then return false end
    local n = obj
    while n do
        if n:IsA('GuiObject') and not n.Visible then return false end
        if n:IsA('ScreenGui') and not n.Enabled then return false end
        n = n.Parent
    end
    return true
end
local function currentMenu()
    local menu = playerGui:FindFirstChild('MemoryMenu')
    if not menu then return nil end
    if menu:IsA('ScreenGui') then return menu.Enabled and menu or nil end
    return isVisible(menu) and menu or nil
end
local function phaseText(menu)
    if not menu then return 'hidden', '' end
    local texts = {}
    for _, obj in ipairs(menu:GetDescendants()) do
        if (obj:IsA('TextLabel') or obj:IsA('TextButton'))
            and isVisible(obj) and obj.Text and obj.Text ~= '' then
            local t = string.lower(obj.Text:gsub('%s+', ' '))
            texts[#texts+1] = t
        end
    end
    -- The bottom-of-window phase label is visible in the user's recording.
    local all = table.concat(texts, ' | ')
    if all:find('try again', 1, true) then return 'failed', all end
    if all:find('tap in the same order', 1, true)
        or all:find('tap the same order', 1, true) then return 'tap', all end
    if all:find('remember the pattern', 1, true) then return 'remember', all end
    if all:find('press play to start', 1, true) then return 'ready', all end
    return 'unknown', all
end
local function tiles(menu)
    if not menu then return {} end
    if os.clock() - lastListAt < 0.6 and #tileList > 0 then
        local ok = true
        for _, tile in ipairs(tileList) do
            if not tile.Parent then ok = false break end
        end
        if ok then return tileList end
    end
    lastListAt = os.clock()
    tileList = {}
    for _, o in ipairs(menu:GetDescendants()) do
        if o:IsA('GuiButton') and o.Name:match('^Tas%d+$') and isVisible(o) then
            tileList[#tileList+1] = o
        end
    end
    table.sort(tileList, function(a,b)
        return tonumber(a.Name:match('%d+')) < tonumber(b.Name:match('%d+'))
    end)
    return tileList
end

-- Return a high score for cyan-blue highlights, not gray tiles or white UI images.
local function colorDiff(a,b)
    return math.max(math.abs(a.R-b.R), math.abs(a.G-b.G), math.abs(a.B-b.B))
end
local function blueStrength(col, alpha)
    if alpha < 0.12 then return 0 end
    if col.B < 0.60 or col.G < 0.44 then return 0 end
    local d1, d2 = col.B - col.R, col.G - col.R
    if d1 < 0.21 or d2 < 0.12 then return 0 end
    return math.min(1, math.min(d1 * 1.4, d2 * 1.7) * alpha)
end
local baselineImages = setmetatable({}, {__mode='k'})
local baselineVisuals = setmetatable({}, {__mode='k'})
local function snapshotImages(menu)
    table.clear(baselineImages)
    table.clear(baselineVisuals)
    for _, tile in ipairs(tiles(menu)) do
        local all = {tile}
        for _, child in ipairs(tile:GetDescendants()) do all[#all+1] = child end
        for _, obj in ipairs(all) do
            if obj:IsA('GuiObject') then
                local base = {
                    backgroundColor=obj.BackgroundColor3,
                    backgroundAlpha=obj.BackgroundTransparency
                }
                if obj:IsA('ImageLabel') or obj:IsA('ImageButton') then
                    baselineImages[obj] = obj.Image
                    base.imageAlpha=obj.ImageTransparency
                    base.imageColor=obj.ImageColor3
                    base.rectOffset=obj.ImageRectOffset
                end
                baselineVisuals[obj] = base
            end
        end
    end
end
local function flashScore(tile)
    local best = 0
    local all = {tile}
    for _, child in ipairs(tile:GetDescendants()) do all[#all+1] = child end
    for _, obj in ipairs(all) do
        if obj:IsA('GuiObject') and isVisible(obj) then
            best = math.max(best, blueStrength(obj.BackgroundColor3, 1 - obj.BackgroundTransparency))
            local base=baselineVisuals[obj]
            if base then
                local change=colorDiff(obj.BackgroundColor3,base.backgroundColor)
                if change > 0.30 and obj.BackgroundTransparency < 0.93 then
                    best=math.max(best, 0.45)
                end
                if math.abs(obj.BackgroundTransparency-base.backgroundAlpha)>0.35 then
                    best=math.max(best, 0.45)
                end
            end
            if obj:IsA('ImageLabel') or obj:IsA('ImageButton') then
                best = math.max(best, blueStrength(obj.ImageColor3, 1 - obj.ImageTransparency))
                local original = baselineImages[obj]
                if original and original ~= '' and obj.Image ~= original then
                    best = math.max(best, 0.58)
                end
                if base then
                    if colorDiff(obj.ImageColor3,base.imageColor)>0.3 then
                        best=math.max(best,0.55)
                    end
                    if math.abs(obj.ImageTransparency-base.imageAlpha)>0.35 then
                        best=math.max(best,0.52)
                    end
                    if obj.ImageRectOffset ~= base.rectOffset then
                        best=math.max(best,0.50)
                    end
                end
            end
            for _, child in ipairs(obj:GetChildren()) do
                if child:IsA('UIStroke') then
                    best = math.max(best, blueStrength(child.Color, 1 - child.Transparency))
                end
            end
        end
    end
    return best
end

-- String signatures represent LOCAL visual properties, not game inventory IDs.
-- A static changed image is not enough: we need a new transition during REMEMBER.
local function visualSignature(tile)
    local parts = {}
    local all = {tile}
    for _, child in ipairs(tile:GetDescendants()) do all[#all+1] = child end
    local function col(c)
        return string.format('%d,%d,%d', math.floor(c.R*255+0.5),
            math.floor(c.G*255+0.5), math.floor(c.B*255+0.5))
    end
    for _, obj in ipairs(all) do
        if obj:IsA('GuiObject') then
            parts[#parts+1] = obj.ClassName .. ':' .. obj.Name
                .. ':b' .. col(obj.BackgroundColor3)
                .. ':a' .. string.format('%.2f',obj.BackgroundTransparency)
            if obj:IsA('ImageLabel') or obj:IsA('ImageButton') then
                parts[#parts+1] = ':i' .. obj.Image
                    .. ':t' .. col(obj.ImageColor3)
                    .. ':a' .. string.format('%.2f',obj.ImageTransparency)
                    .. ':r' .. tostring(obj.ImageRectOffset)
            end
            for _, child in ipairs(obj:GetChildren()) do
                if child:IsA('UIStroke') then
                    parts[#parts+1] = ':stroke' .. col(child.Color)
                        .. ':a' .. string.format('%.2f',child.Transparency)
                end
            end
        end
    end
    return table.concat(parts, '|')
end

local function sampleIdleVisuals(menu)
    for _, tile in ipairs(tiles(menu)) do
        local sig = visualSignature(tile)
        previousVisual[tile] = sig
        previousStrength[tile] = flashScore(tile)
        -- During READY we have a clean image state. At TAP/FAILED retain the
        -- last sample only; it may contain cracks or error highlights.
        if phase == 'ready' then visualAtRest[tile] = sig end
    end
end

local function press(button, minInterval)
    if not button or not button:IsA('GuiButton') or not isVisible(button) then
        return false, 'button not visible'
    end
    if button.Interactable == false then return false, 'button disabled' end
    local now = os.clock()
    if now - (lastPress[button] or -100) < (minInterval or 0.12) then
        return false, 'cooldown'
    end
    lastPress[button] = now
    -- Fire exactly ONE callback. Never invoke Activated AND MouseButton1Click together.
    if type(getconnections) == 'function' then
        for _, signal in ipairs({button.Activated, button.MouseButton1Click}) do
            local ok, list = pcall(getconnections, signal)
            if ok and type(list) == 'table' then
                for _, connection in ipairs(list) do
                    if type(connection.Fire) == 'function' then
                        local did = pcall(function() connection:Fire() end)
                        if did then pressMethod = 'connection'; return true, pressMethod end
                    end
                end
            end
        end
    end
    if type(firesignal) == 'function' then
        if pcall(firesignal, button.Activated) then
            pressMethod = 'firesignal'; return true, pressMethod
        end
        if pcall(firesignal, button.MouseButton1Click) then
            pressMethod = 'firesignal click'; return true, pressMethod
        end
    end
    local ok, vim = pcall(function() return game:GetService('VirtualInputManager') end)
    if ok and vim then
        local p = button.AbsolutePosition + (button.AbsoluteSize / 2)
        local sent = pcall(function()
            vim:SendMouseButtonEvent(p.X, p.Y, 0, true, game, 0)
            task.wait(0.06)
            vim:SendMouseButtonEvent(p.X, p.Y, 0, false, game, 0)
        end)
        if sent then
            pressMethod = 'virtual mouse (unverified)'; return true, pressMethod
        end
    end
    return false, 'executor could not activate UI'
end
local function byTileName(name)
    for _, tile in ipairs(tileList) do
        if tile.Name == name and isVisible(tile) then return tile end
    end
    return nil
end
local function restartRecording(menu)
    sequence = {}
    litLatch = nil
    proposed = nil
    proposedAt = 0
    observed = 0
    turn += 1
    synced = true
    replaying = false
    state = 'WATCH'
    -- A new round can begin automatically without reopening the menu.
    -- Remove active flags so a tile repeated in the next round can be captured.
    table.clear(tileFlashActive)
    if #tileList == 0 then tiles(menu) end
    debugLast = 'Recording new round #' .. tostring(turn)
    trace('ROUND ' .. tostring(turn) .. ' REMEMBER')
end
local function readFlashes(menu)
    local changed = {}
    local now = os.clock()
    -- All tiles may differ from the first-ever baseline after earlier rounds.
    -- The relevant event is which tile CHANGED now, not how many remain different.
    for _, tile in ipairs(tiles(menu)) do
        local sig = visualSignature(tile)
        local score = flashScore(tile)
        local oldSig = previousVisual[tile]
        local oldScore = previousStrength[tile] or 0
        local neutral = visualAtRest[tile] ~= nil and sig == visualAtRest[tile]
        -- Re-arm a tile when its flash ends, but NEVER on a changing image
        -- while it remains illuminated. This avoids duplicate entries from
        -- the same 0.5-second flash / ImageTransparency animation.
        if neutral or (oldScore > score + 0.16 and score < 0.28) then
            tileFlashActive[tile] = nil
        end
        if oldSig ~= nil and sig ~= oldSig then
            visualChanges += 1
            -- If the current state matches the last neutral appearance, it is
            -- the trailing edge of a flash, not the start of a new flash.
            local rising = score > oldScore + 0.08
            local changedImage = sig ~= oldSig and score >= 0.30
            if not neutral and not tileFlashActive[tile]
                and (rising or changedImage) and score >= 0.29 then
                changed[#changed+1] = {
                    tile=tile, score=score, delta=score-oldScore,
                    weight=(rising and 1 or 0)+score+math.max(0,score-oldScore)
                }
            end
        end
        previousVisual[tile] = sig
        previousStrength[tile] = score
    end
    if #changed == 0 then
        return
    end
    table.sort(changed, function(a,b) return a.weight > b.weight end)
    -- Do not guess when several tiles animate together. Request a clean event.
    if #changed > 1 and changed[1].weight - changed[2].weight < 0.3 then
        flashesRejected += 1
        if flashesRejected <= 12 then trace('AMBIGUOUS ' .. tostring(#changed) .. ' changing tiles') end
        return
    end
    local item = changed[1]
    local found = item.tile.Name
    local last = recentPulse[item.tile] or -100
    if now-last < 0.20 then return end
    recentPulse[item.tile] = now
    tileFlashActive[item.tile] = true
    if #sequence < 40 then
        sequence[#sequence+1] = found
        observed += 1
        debugLast = 'New visual flash #' .. #sequence .. ' = ' .. found
        trace(debugLast .. string.format(' score %.2f',item.score))
    end
end
local function findPlay(menu)
    local btn = menu and menu:FindFirstChild('PlayButonu', true)
    return btn and btn:IsA('GuiButton') and isVisible(btn) and btn or nil
end
local function beginReplay(menu)
    if not synced or #sequence == 0 then
        state = 'NEED_RESTART'
        debugLast = #sequence == 0 and 'No blue flashes detected; cannot guess.'
            or 'Joined mid-round; waiting for restart.'
        return
    end
    local planned = table.clone(sequence)
    local currentTurn = turn
    replaying = true
    waitingForRoundResult = true
    state = 'REPLAY'
    debugLast = 'Answering ' .. #planned .. ' flashes'
    task.spawn(function()
        task.wait(0.12)
        for i, name in ipairs(planned) do
            if not alive or not on or turn ~= currentTurn then break end
            if phase ~= 'tap' or not currentMenu() then break end
            local target = byTileName(name)
            if not target then debugLast = 'Missing ' .. name; break end
            local ok, why = press(target, 0.09)
            if not ok then debugLast = 'Could not tap ' .. name .. ': ' .. tostring(why); break end
            debugLast = string.format('Answer %d/%d: %s', i, #planned, name)
            task.wait(0.25)
        end
        if turn == currentTurn then
            replaying = false
            state = 'WAIT_RESULT'
            debugLast = debugLast .. ' | awaiting next round'
        end
    end)
end
local function enable()
    on = true
    previousPhase = 'unknown'
    phase = 'unknown'
    sequence = {}
    litLatch = nil
    proposed = nil
    replaying = false
    state = 'START'
    synced = false
    waitingForRoundResult = false
    lastActionAt = 0
    debugLast = 'Turn ON before pressing PLAY.'
    trace('ON; waiting for memory game')
end
local function disable()
    on = false
    turn += 1 -- cancel a running replay coroutine
    waitingForRoundResult = false
    state = 'OFF'
    debugLast = 'Auto Train OFF'
    trace('OFF; user stopped')
end

local function logic()
    if not on then return end
    local menu = currentMenu()
    local ph, raw = phaseText(menu)
    phase = ph
    if ph ~= previousPhase then
        lastPhaseAt = os.clock()
        local old = previousPhase
        previousPhase = ph
        trace('PHASE ' .. tostring(old) .. ' -> ' .. tostring(ph) .. ' / captured=' .. tostring(#sequence))
        if ph == 'remember' then
            -- There may be a brief unknown phase between TAP and REMEMBER.
            -- New REMEMBER always means new recording, even after that gap.
            if waitingForRoundResult then
                successes += 1
                trace('AUTO-ADVANCE after round answer')
            end
            waitingForRoundResult = false
            restartRecording(menu)
        elseif ph == 'tap' then
            beginReplay(menu)
        elseif ph == 'failed' then
            turn += 1
            replaying = false
            synced = false
            state = 'FAIL'
            retries += 1
            waitingForRoundResult = false
            debugLast = 'TRY AGAIN: resetting sequence'
        elseif ph == 'ready' then
            turn += 1
            replaying = false
            synced = true
            sequence = {}
            state = 'READY'
            waitingForRoundResult = false
        elseif ph == 'hidden' then
            turn += 1
            replaying = false
            sequence = {}
            state = 'OPEN_MENU'
            waitingForRoundResult = false
        else
            state = 'UNKNOWN_PHASE'
            debugLast = 'Cannot read phase text from MemoryMenu.'
        end
    end
    if ph == 'remember' then
        if synced and not replaying then
            readFlashes(menu)
        else
            state = 'NEED_RESTART'
        end
    elseif ph == 'ready' or ph == 'failed' then
        local now = os.clock()
        if now - lastActionAt > 2.3 then
            local btn = findPlay(menu)
            if btn then
                lastActionAt = now
                snapshotImages(menu)
                sampleIdleVisuals(menu)
                local ok, why = press(btn, 2)
                if ok then
                    state = 'WAIT_PATTERN'
                    debugLast = (ph == 'ready' and 'Started memory game' or 'Restarted after error')
                else
                    debugLast = 'PLAY failed: ' .. tostring(why)
                end
            else
                debugLast = 'PlayButonu not visible'
            end
        end
    elseif ph == 'hidden' then
        local intro = path(playerGui, 'MemoryPlayGui.PlayButonu')
        if intro and isVisible(intro) and os.clock() - lastActionAt > 3 then
            lastActionAt = os.clock()
            local ok, why = press(intro, 2)
            debugLast = ok and 'Opening Memory Game' or ('Cannot open game: ' .. tostring(why))
        else
            state = 'OPEN_MENU'
        end
    elseif ph == 'unknown' then
        -- Fail closed: do not blindly tap tiles when phase is unclear.
        state = 'UNKNOWN_PHASE'
        if raw ~= '' then debugLast = 'Phase unrecognized: ' .. raw:sub(1, 85) end
    end
    -- Keep the previous visual samples fresh outside REMEMBER, especially
    -- between consecutive rounds that start without pressing PLAY again.
    if ph ~= 'remember' and menu then sampleIdleVisuals(menu) end
end

local function make(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    o.Parent = parent
    return o
end

gui = make('ScreenGui', {Name='CutARock_AutoTrain_v3', ResetOnSpawn=false,
    ZIndexBehavior=Enum.ZIndexBehavior.Sibling}, playerGui)
local panel = make('Frame', {Size=UDim2.fromOffset(310,237),
    Position=UDim2.new(0,14,0.19,0), BackgroundColor3=Color3.fromRGB(23,28,40),
    BorderSizePixel=0}, gui)
make('UICorner',{CornerRadius=UDim.new(0,10)},panel)
make('UIStroke',{Color=Color3.fromRGB(78,95,123),Thickness=1},panel)
local title = make('TextLabel',{Text='CUT A ROCK | AUTO TRAIN v3.2',
    Size=UDim2.fromOffset(262,35),Position=UDim2.fromOffset(11,3),
    BackgroundTransparency=1,TextColor3=Color3.new(1,1,1),
    TextXAlignment=Enum.TextXAlignment.Left,Font=Enum.Font.GothamBold,TextSize=13},panel)
local close = make('TextButton',{Text='X',Size=UDim2.fromOffset(28,27),
    Position=UDim2.fromOffset(273,7),BackgroundColor3=Color3.fromRGB(139,50,58),
    TextColor3=Color3.new(1,1,1),BorderSizePixel=0},panel)
make('UICorner',{CornerRadius=UDim.new(0,6)},close)
local toggle = make('TextButton',{Text='AUTO TRAIN: OFF',Size=UDim2.fromOffset(284,38),
    Position=UDim2.fromOffset(12,44),BackgroundColor3=Color3.fromRGB(58,71,91),
    TextColor3=Color3.new(1,1,1),Font=Enum.Font.GothamBold,
    TextSize=14,BorderSizePixel=0},panel)
make('UICorner',{CornerRadius=UDim.new(0,7)},toggle)
local status = make('TextLabel',{Size=UDim2.fromOffset(284,91),
    Position=UDim2.fromOffset(12,88),BackgroundTransparency=1,
    TextColor3=Color3.fromRGB(202,223,243),TextSize=11,
    Font=Enum.Font.Gotham,TextWrapped=true,
    TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top},panel)
local copy = make('TextButton',{Text='COPY DEBUG',Size=UDim2.fromOffset(135,31),
    Position=UDim2.fromOffset(12,188),BackgroundColor3=Color3.fromRGB(45,77,120),
    TextColor3=Color3.new(1,1,1),Font=Enum.Font.GothamMedium,
    TextSize=12,BorderSizePixel=0},panel)
make('UICorner',{CornerRadius=UDim.new(0,6)},copy)
local hint = make('TextLabel',{Size=UDim2.fromOffset(140,35),
    Position=UDim2.fromOffset(158,184),BackgroundTransparency=1,
    Text='Enable at PRESS PLAY TO START',TextWrapped=true,
    TextColor3=Color3.fromRGB(164,182,205),TextSize=10},panel)

local function stop()
    if not alive then return end
    disable()
    alive = false
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    if gui and gui.Parent then gui:Destroy() end
    if env.CutARockTrainV3Stop == stop then env.CutARockTrainV3Stop = nil end
end
env.CutARockTrainV3Stop = stop
connections[#connections+1] = close.Activated:Connect(stop)
connections[#connections+1] = toggle.Activated:Connect(function()
    if on then disable() else enable() end
    toggle.Text = on and 'AUTO TRAIN: ON' or 'AUTO TRAIN: OFF'
    toggle.BackgroundColor3 = on and Color3.fromRGB(29,126,87)
        or Color3.fromRGB(58,71,91)
end)
connections[#connections+1] = copy.Activated:Connect(function()
    local menu = currentMenu()
    local ph, raw = phaseText(menu)
    local names = {}
    for _, name in ipairs(sequence) do names[#names+1] = name end
    local scores = {}
    for _, tile in ipairs(tiles(menu)) do
        scores[#scores+1] = tile.Name .. ':' .. string.format('%.2f', flashScore(tile))
    end
    local lines = {
        'CUT A ROCK AUTO TRAIN v3.2 REPORT',
        'Phase='..ph..' State='..state..' On='..tostring(on),
        'Rounds='..turn..' SuccessTransitions='..successes..' Failures='..retries,
        'TilesVisible='..#tiles(menu)..' FlashCount='..#sequence,
        'VisualChanges='..visualChanges..' AmbiguousEvents='..flashesRejected,
        'PendingNextRound='..tostring(waitingForRoundResult),
        'Sequence='..table.concat(names, ', '),
        'PressMethod='..pressMethod,
        'Synced='..tostring(synced)..' ReplayActive='..tostring(replaying),
        'TileScores='..table.concat(scores, ' '),
        'Status='..debugLast,
        'PhaseText='..raw:sub(1,300),
        '--- RECENT VISUAL AND PHASE EVENTS ---'
    }
    for _,line in ipairs(recentTrace) do lines[#lines+1] = line end
    local output = table.concat(lines, '\n')
    local clip = type(setclipboard) == 'function' and setclipboard
        or (type(toclipboard) == 'function' and toclipboard) or nil
    if clip and pcall(clip, output) then
        debugLast = 'Debug copied; paste in ChatGPT'
    else
        print(output)
        debugLast = 'Debug printed to executor console'
    end
end)
local dragging, startInput, startPos = false, nil, nil
connections[#connections+1] = title.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.Touch
        or i.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging, startInput, startPos = true, i.Position, panel.Position
        local c
        c = i.Changed:Connect(function()
            if i.UserInputState == Enum.UserInputState.End then
                dragging = false
                c:Disconnect()
            end
        end)
    end
end)
connections[#connections+1] = UIS.InputChanged:Connect(function(i)
    if dragging and startInput and (i.UserInputType == Enum.UserInputType.Touch
        or i.UserInputType == Enum.UserInputType.MouseMovement) then
        local d = i.Position - startInput
        panel.Position = UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,
            startPos.Y.Scale,startPos.Y.Offset+d.Y)
    end
end)

task.spawn(function()
    while alive do
        local ok, err = pcall(logic)
        if not ok then debugLast = 'Error: ' .. tostring(err):sub(1,110) end
        if status and status.Parent then
            status.Text = string.format('Phase: %s | State: %s\nRound %d | Flashes %d | OK %d | Fail %d\n%s\nTap method: %s',
                phase,state,turn,#sequence,successes,retries,debugLast,pressMethod)
        end
        task.wait(on and 0.035 or 0.3)
    end
end)
print('[CAR Train v3.2] Ready. Enable at PRESS PLAY TO START; use COPY DEBUG after a round.')

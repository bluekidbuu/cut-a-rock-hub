-- Cut a Rock | Remote Cut ONE-SHOT Test v1.0
-- Cut a Rock PlaceId 113742027864370, GameId 10766468833
-- Test goal: check whether a legitimate inventory stone can be placed
-- in the observed cutting machine remotely, with no menu or teleport.
-- Based on manual audit: PlaceStoneInMachineEvent:FireServer(levelModel, stoneUUID).
-- The server may reject this due to distance/ownership/state restrictions.
-- No automatic loops, purchases, InstantCutEvent, or hidden asset ID guessing.
-- The request is sent ONCE only when the user presses TEST ONCE.

if not game:IsLoaded() then game.Loaded:Wait() end
if game.PlaceId ~= 113742027864370 and game.GameId ~= 10766468833 then
    warn('[CAR Remote Test] This test is only for Cut a Rock.')
    return
end

local Players = game:GetService('Players')
local UIS = game:GetService('UserInputService')
local RS = game:GetService('ReplicatedStorage')
local player = Players.LocalPlayer
local guiParent = player:WaitForChild('PlayerGui')
local env = (type(getgenv) == 'function' and getgenv()) or _G
if type(env.CARRemoteCutTestStop) == 'function' then
    pcall(env.CARRemoteCutTestStop)
end

local alive = true
local busy = false
local lastAttempt = -1000
local connections = {}
local selectedLevel = 11 -- Confirmed in the user's previous manual audit.
local stones = {}
local machines = {}
local selectedMachine
local scanCount = 0
local requestCount = 0
local result = 'Not tested'
local state = 'Ready. SCAN first, then TEST ONCE far from your machine.'
local history = {}
local runningAt = os.clock()

local function isUuid(s)
    return type(s) == 'string'
        and s:match('^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$') ~= nil
end
local function record(s)
    if #history >= 18 then table.remove(history, 1) end
    history[#history+1] = string.format('T+%.1fs %s', os.clock() - runningAt, tostring(s))
end
local function getPath(obj)
    if not obj or not obj.Parent then return 'destroyed' end
    local ok, full = pcall(function() return obj:GetFullName() end)
    return ok and full or tostring(obj.Name)
end
local function attrOwner(obj)
    -- Match only clearly labeled owner attributes or values. Do not infer ownership from location.
    local id = tostring(player.UserId)
    local name = player.Name:lower()
    local keys = {'OwnerUserId','PlayerUserId','UserId','Owner','OwnerName','PlayerName'}
    local p = obj
    while p and p ~= workspace do
        for _, k in ipairs(keys) do
            local value = p:GetAttribute(k)
            if value ~= nil then
                local v = tostring(value)
                if v == id or v:lower() == name then return 'match' end
                if (k == 'OwnerUserId' or k == 'PlayerUserId' or k == 'Owner' or k == 'OwnerName')
                    and (type(value) == 'number' or type(value) == 'string') then
                    return 'other/unknown'
                end
            end
        end
        p = p.Parent
    end
    return 'unverified'
end
local function promptOf(machine)
    if not machine or not machine.Parent then return nil end
    for _,p in ipairs(machine:GetDescendants()) do
        if p:IsA('ProximityPrompt') and p.Name == 'CutMachinePrompt' then return p end
    end
    return nil
end
local function findPosition(p)
    local node = p
    while node and node ~= workspace do
        if node:IsA('Attachment') then return node.WorldPosition end
        if node:IsA('BasePart') then return node.Position end
        node = node.Parent
    end
    return nil
end
local function distanceTo(machine)
    local character = player.Character
    local root = character and character:FindFirstChild('HumanoidRootPart')
    if not root then return nil end
    local p = promptOf(machine)
    local pos = p and findPosition(p)
    if not pos then
        local ok, pivot = pcall(function() return machine:GetPivot() end)
        pos = ok and pivot.Position or nil
    end
    if pos then return (root.Position-pos).Magnitude end
end
local function promptAction(machine)
    local p = promptOf(machine)
    return p and p.ActionText or 'NO_PROMPT'
end
local function addStone(bucket, id, src, node, quality)
    if not isUuid(id) then return end
    if bucket[id] then
        if quality > bucket[id].quality then
            bucket[id].source, bucket[id].quality = src, quality
            bucket[id].node = node
        end
        return
    end
    bucket[id] = {id=id, source=src, quality=quality, node=node}
end
local function isUnder(node, ancestor)
    while node do
        if node == ancestor then return true end
        node = node.Parent
    end
    return false
end
local function excludedFromRawInventory(node)
    local excluded = {
        CurrentCut=true, FinishCard=true, CutStoneTab=true,
        KesimPaneli=true, BoostBar=true, SellMenu=true, StonePhoto=true
    }
    while node do
        if excluded[node.Name] then return true end
        node = node.Parent
    end
    return false
end
local function scanStones()
    local found = {}
    local cutting = guiParent:FindFirstChild('CuttingMenu')
    local inventory = guiParent:FindFirstChild('InventoryMenu')
    for _, node in ipairs(guiParent:GetDescendants()) do
        if (cutting and isUnder(node, cutting)) or (inventory and isUnder(node, inventory)) then
            if not excludedFromRawInventory(node) then
                local source = (inventory and isUnder(node, inventory)) and 'InventoryMenu' or 'CuttingMenu'
                local quality = source == 'CuttingMenu' and 3 or 2
                if isUuid(node.Name) then
                    if node:IsA('GuiButton') then quality += 2 end
                    addStone(found,node.Name,source..':'..node.ClassName,node,quality)
                end
                if node:IsA('StringValue') and isUuid(node.Value) then
                    addStone(found,node.Value,source..':StringValue',node,quality)
                end
            end
        end
    end
    -- Some game inventory data is replicated under the local Player, outside PlayerGui.
    for _,node in ipairs(player:GetDescendants()) do
        if not isUnder(node, guiParent) then
            local parentName = node.Parent and node.Parent.Name:lower() or ''
            local pathHint = parentName:find('stone',1,true) or parentName:find('rock',1,true)
                or parentName:find('inventory',1,true) or parentName:find('cep',1,true)
                or parentName:find('tas',1,true) or parentName:find('pocket',1,true)
                or parentName:find('bag',1,true)
            if pathHint then
                if isUuid(node.Name) then addStone(found,node.Name,'PlayerData:'..parentName,node,1) end
                if node:IsA('StringValue') and isUuid(node.Value) then
                    addStone(found,node.Value,'PlayerDataValue:'..parentName,node,1)
                end
            end
        end
    end
    local arr = {}
    for _,s in pairs(found) do arr[#arr+1] = s end
    table.sort(arr,function(a,b)
        if a.quality ~= b.quality then return a.quality > b.quality end
        return a.id < b.id
    end)
    return arr
end
local function scanMachines()
    local models={}
    for _, node in ipairs(workspace:GetDescendants()) do
        if node:IsA('Model') and node.Name:match('^level%d+$')
            and promptOf(node) ~= nil then
            local level = tonumber(node.Name:match('%d+'))
            if level == selectedLevel then
                models[#models+1] = {model=node, ownership=attrOwner(node), level=level}
            end
        end
    end
    table.sort(models,function(a,b)
        if a.ownership ~= b.ownership then return a.ownership == 'match' end
        return getPath(a.model) < getPath(b.model)
    end)
    return models
end
local function chooseMachine(list)
    local owned = {}
    for _, item in ipairs(list) do
        if item.ownership == 'match' then owned[#owned+1] = item end
    end
    if #owned == 1 then return owned[1], 'owner attribute matches' end
    if #owned > 1 then return nil, 'multiple owned machines at this level' end
    if #list == 1 and list[1].ownership == 'other/unknown' then
        return nil, 'machine owner appears to be someone else'
    end
    if #list == 1 then
        return list[1], 'unique level model; ownership unverified'
    end
    return nil, #list == 0 and 'no matching level machine' or 'multiple machines; owner ambiguous'
end
local function refresh()
    stones = scanStones()
    machines = scanMachines()
    local why
    selectedMachine, why = chooseMachine(machines)
    scanCount += 1
    record(string.format('SCAN stones=%d level%d-machines=%d selected=%s',
        #stones,selectedLevel,#machines,selectedMachine and why or 'NO: '..why))
    return why
end

local gui=Instance.new('ScreenGui')
gui.Name='CAR_RemoteCut_OneShot_v1'
gui.ResetOnSpawn=false
gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
gui.Parent=guiParent
local function create(class,props,parent)
    local o=Instance.new(class)
    for k,v in pairs(props) do o[k]=v end
    o.Parent=parent
    return o
end
local panel=create('Frame',{
    Size=UDim2.fromOffset(324,334), Position=UDim2.new(0,12,0.16,0),
    BackgroundColor3=Color3.fromRGB(22,27,39), BorderSizePixel=0
},gui)
create('UICorner',{CornerRadius=UDim.new(0,10)},panel)
create('UIStroke',{Color=Color3.fromRGB(80,95,120),Thickness=1},panel)
local title=create('TextLabel',{
    Text='CUT A ROCK | REMOTE CUT TEST', BackgroundTransparency=1,
    Size=UDim2.fromOffset(275,36), Position=UDim2.fromOffset(10,3),
    TextColor3=Color3.new(1,1,1),Font=Enum.Font.GothamBold,TextSize=13,
    TextXAlignment=Enum.TextXAlignment.Left
},panel)
local function button(caption,y,fn,x,w)
    local b=create('TextButton',{
        Text=caption, Size=UDim2.fromOffset(w or 302,34),
        Position=UDim2.fromOffset(x or 11,y),
        BackgroundColor3=Color3.fromRGB(47,69,100),
        BorderSizePixel=0,TextColor3=Color3.new(1,1,1),
        Font=Enum.Font.GothamMedium, TextSize=12
    },panel)
    create('UICorner',{CornerRadius=UDim.new(0,7)},b)
    if fn then
        connections[#connections+1]=b.Activated:Connect(function() fn(b) end)
    end
    return b
end
local function stop()
    alive=false
    for _,c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    gui:Destroy()
    if env.CARRemoteCutTestStop == stop then env.CARRemoteCutTestStop=nil end
end
env.CARRemoteCutTestStop=stop
button('X',7,function()stop()end,283,30)
local info=create('TextLabel',{
    Text='',Size=UDim2.fromOffset(302,94),Position=UDim2.fromOffset(11,47),
    BackgroundTransparency=1,TextColor3=Color3.fromRGB(196,213,236),
    TextSize=11,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,
    TextYAlignment=Enum.TextYAlignment.Top,Font=Enum.Font.Gotham
},panel)
local levelDisplay=create('TextLabel',{
    Text='',Size=UDim2.fromOffset(302,20),Position=UDim2.fromOffset(11,149),
    BackgroundTransparency=1,TextColor3=Color3.fromRGB(192,218,247),
    TextSize=11,Font=Enum.Font.GothamBold
},panel)
button('LEVEL -',171,function() if not busy then selectedLevel=math.max(1,selectedLevel-1);refresh() end end,11,91)
button('LEVEL +',171,function() if not busy then selectedLevel=math.min(99,selectedLevel+1);refresh() end end,116,91)
button('SCAN',171,function() if not busy then refresh() end end,221,92)
local trigger=button('TEST ONCE (remote)',214,nil)
button('COPY REPORT',260,function()
    local distance=selectedMachine and distanceTo(selectedMachine.model)
    local lines={
        'CUT A ROCK REMOTE CUT TEST v1',
        'PlaceId='..tostring(game.PlaceId), 'GameId='..tostring(game.GameId),
        'MachineLevel='..tostring(selectedLevel), 'MachineCandidates='..#machines,
        'SelectedMachine='..(selectedMachine and getPath(selectedMachine.model) or 'NONE'),
        'Ownership='..(selectedMachine and selectedMachine.ownership or 'NONE'),
        'DistanceStuds='..(distance and string.format('%.1f',distance) or 'unknown'),
        'PromptAction='..(selectedMachine and promptAction(selectedMachine.model) or 'none'),
        'StoneCandidates='..#stones,
        'BestStoneSource='..(stones[1] and stones[1].source or 'none'),
        'ScanCount='..scanCount,
        'RemoteCallsFromThisTest='..requestCount,
        'Result='..result,
        'Note: a local FireServer success does not prove server acceptance.',
        'Note: no UUID/string values included in report.',
        '--- TIMELINE ---'
    }
    for _,h in ipairs(history) do lines[#lines+1]=h end
    local report=table.concat(lines,'\n')
    print(report)
    local copy=type(setclipboard)=='function' and setclipboard or
        (type(toclipboard)=='function' and toclipboard or nil)
    if copy then
        local ok=pcall(copy,report)
        state=ok and 'Report copied. Paste it into ChatGPT.' or 'Clipboard failed; see console.'
    else
        state='Report printed in executor console.'
    end
end)
create('TextLabel',{
    Text='No menu / no teleport / no purchases / one-shot only',
    Size=UDim2.fromOffset(302,23),Position=UDim2.fromOffset(11,298),
    BackgroundTransparency=1,TextColor3=Color3.fromRGB(159,179,199),
    TextSize=10,Font=Enum.Font.Gotham
},panel)

-- Drag using title on mobile.
local dragging=false
local dragStart, oldPos
connections[#connections+1]=title.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
        dragging=true;dragStart=input.Position;oldPos=panel.Position
        local conn
        conn=input.Changed:Connect(function()
            if input.UserInputState==Enum.UserInputState.End then
                dragging=false;conn:Disconnect()
            end
        end)
    end
end)
connections[#connections+1]=UIS.InputChanged:Connect(function(input)
    if dragging and dragStart and (input.UserInputType==Enum.UserInputType.Touch
        or input.UserInputType==Enum.UserInputType.MouseMovement) then
        local d=input.Position-dragStart
        panel.Position=UDim2.new(oldPos.X.Scale,oldPos.X.Offset+d.X,
            oldPos.Y.Scale,oldPos.Y.Offset+d.Y)
    end
end)

local function testOnce()
    if busy or not alive then return end
    if os.clock()-lastAttempt < 20 then
        state='Cooldown: 20s between manual tests.'
        return
    end
    refresh()
    if not selectedMachine then
        result='BLOCKED: machine not uniquely identified'
        state='No unique level'..selectedLevel..' machine. Check LEVEL and SCAN.'
        return
    end
    if #stones == 0 then
        result='BLOCKED: stone ID not visible in client replicated inventory/GUI'
        state='No stone UUID. Inventory may only populate when menu opens.'
        return
    end
    local machine=selectedMachine.model
    local prompt=promptOf(machine)
    if not prompt then result='BLOCKED: machine prompt missing'; return end
    local distance=distanceTo(machine)
    if not distance then result='BLOCKED: unknown distance';return end
    local minFar=math.max(30,prompt.MaxActivationDistance+10)
    if distance < minFar then
        result='BLOCKED: need distance >= '..string.format('%.1f',minFar)
        state='Move further from machine to test REMOTE access.'
        return
    end
    local event=RS:FindFirstChild('PlaceStoneInMachineEvent')
    if not event or not event:IsA('RemoteEvent') then
        result='BLOCKED: PlaceStoneInMachineEvent missing'
        return
    end
    busy=true
    lastAttempt=os.clock()
    trigger.Text='TESTING (please wait)'
    local stone=stones[1]
    local promptBefore=promptAction(machine)
    local idBefore=stone.id
    local numBefore=#stones
    local beforeTime=os.clock()
    state='Sent one request locally; checking machine state...'
    local ok,err=pcall(function()
        event:FireServer(machine,stone.id)
    end)
    requestCount+=1
    record(string.format('REMOTE_SEND ok=%s level=%d distance=%.1f source=%s actionBefore=%s',
        tostring(ok),selectedLevel,distance,stone.source,promptBefore))
    if not ok then
        result='LOCAL ERROR: '..tostring(err):sub(1,110)
        state=result
    else
        task.wait(3)
        if alive then
            local after=scanStones()
            local stillPresent=false
            for _,v in ipairs(after) do if v.id==idBefore then stillPresent=true; break end end
            local promptAfter=promptAction(machine)
            local changed = promptAfter ~= promptBefore
            local vanished = not stillPresent and numBefore>0 and #after>0
            record(string.format('OBSERVE after=%.1fs actionAfter=%s changed=%s stoneDisappeared=%s',
                os.clock()-beforeTime,promptAfter,tostring(changed),tostring(vanished)))
            if changed and (promptAfter:lower():find('cut',1,true)
                or promptAfter:lower():find('collect',1,true)) then
                result='POSSIBLE ACCEPTED: machine action changed'
            elseif vanished then
                result='POSSIBLE ACCEPTED: one stone vanished but others remain in client list'
            else
                result='UNCONFIRMED: server response not evident; distance vs ID/state unresolved'
            end
            state=result
            stones=after
        end
    end
    if alive then
        busy=false
        trigger.Text='TEST ONCE (remote)'
    end
end
-- Bind the visible TEST button after testOnce exists.
connections[#connections+1]=trigger.Activated:Connect(testOnce)

local function updateUI()
    if not alive or not info.Parent then return end
    local selected=selectedMachine
    local distance=selected and distanceTo(selected.model)
    info.Text=string.format('Stone IDs found: %d (%s)\nLevel%d machines: %d | owner: %s\nDistance: %s studs | Prompt: %s\nStatus: %s',
        #stones,stones[1] and stones[1].source or 'none',selectedLevel,#machines,
        selected and selected.ownership or 'unverified',
        distance and string.format('%.1f',distance) or '?',
        selected and promptAction(selected.model) or '?',state)
    levelDisplay.Text='Target: level'..selectedLevel..' | Remote calls: '..requestCount
end

refresh()
updateUI()
task.spawn(function()
    while alive do
        pcall(updateUI)
        task.wait(0.6)
    end
end)
print('[CAR Remote Cut Test] Scan, move far from your machine, TEST ONCE, COPY REPORT.')

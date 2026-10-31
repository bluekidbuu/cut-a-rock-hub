-- Cut a Rock | Remote Cut Test v1.1 | single-shot, explicit manual authorization
-- The user first binds the actual machine and captures a fresh stone UUID.
-- Uses actual observed remote signature only, never invents UUIDs or teleports.
-- Does not buy upgrades, use InstantCutEvent, or auto-loop FireServer.
-- Compatibility depends on executor support and game server validation.

if not game:IsLoaded() then game.Loaded:Wait() end
if game.PlaceId ~= 113742027864370 and game.GameId ~= 10766468833 then
    warn('[CAR] Wrong place/universe; Remote Cut Test disabled.')
    return
end

local Players = game:GetService('Players')
local UIS = game:GetService('UserInputService')
local PPS = game:GetService('ProximityPromptService')
local RS = game:GetService('ReplicatedStorage')
local player = Players.LocalPlayer
local pg = player:WaitForChild('PlayerGui')
local env = type(getgenv) == 'function' and getgenv() or _G
if type(env.CARRemoteCutTestStop) == 'function' then pcall(env.CARRemoteCutTestStop) end

local alive, busy = true, false
local bound, boundVia, boundTime = nil, 'none', 0
local stones = {}
local lastCaptured = 0
local scans, sends, attempted = 0, 0, false
local rawButtons, visibleCards, inventoryData = 0, 0, 0
local result = 'Not tested'
local statusMsg = '1) Bind machine near it; 2) Open CUT menu & scan stones.'
local history, conns = {}, {}
local startTime = os.clock()
local function log(s)
    history[#history + 1] = string.format('T+%.1fs %s', os.clock() - startTime, tostring(s))
    if #history > 26 then table.remove(history, 1) end
end
local function uid(s)
    return type(s) == 'string' and
        s:match('^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$') ~= nil
end
local function ancestorLevel(o)
    local p = o
    while p and p ~= workspace do
        if p:IsA('Model') and p.Name:match('^level%d+$') then return p end
        p = p.Parent
    end
    return nil
end
local function promptOf(model)
    if not model or not model.Parent then return nil end
    for _,p in ipairs(model:GetDescendants()) do
        if p:IsA('ProximityPrompt') and p.Name == 'CutMachinePrompt' then return p end
    end
end
local function promptPos(p)
    if not p then return nil end
    local par = p.Parent
    if par and par:IsA('Attachment') then return par.WorldPosition end
    local x = par and (par:IsA('BasePart') and par or par:FindFirstAncestorWhichIsA('BasePart'))
    return x and x.Position or nil
end
local function distance(model)
    local char = player.Character
    local root = char and char:FindFirstChild('HumanoidRootPart')
    local p = promptOf(model)
    local pos = promptPos(p)
    if root and pos then return (root.Position - pos).Magnitude end
end
local function promptLabel()
    local p = bound and promptOf(bound)
    return p and p.ActionText or 'none'
end
local function machinePath()
    if not bound or not bound.Parent then return 'none' end
    local ok, p = pcall(function() return bound:GetFullName() end)
    return ok and p or bound.Name
end
local function bind(model, via)
    if not model or not model.Parent or not promptOf(model) then return false end
    bound = model
    boundVia = via
    boundTime = os.clock()
    statusMsg = 'Bound ' .. bound.Name .. ' by ' .. via .. '. Open its CUT menu.'
    log('MACHINE_BIND ' .. bound.Name .. ' source=' .. via)
    return true
end
local function findNearest()
    local ch = player.Character
    local root = ch and ch:FindFirstChild('HumanoidRootPart')
    if not root then return nil, 'character root missing' end
    local selected, nearest = nil, math.huge
    for _,desc in ipairs(workspace:GetDescendants()) do
        if desc:IsA('ProximityPrompt') and desc.Name == 'CutMachinePrompt'
            and desc.Enabled then
            local model = ancestorLevel(desc)
            local pos = promptPos(desc)
            if model and pos then
                local d = (root.Position - pos).Magnitude
                if d <= desc.MaxActivationDistance + 1 and d < nearest then
                    selected, nearest = model, d
                end
            end
        end
    end
    return selected, selected and string.format('%.1f studs', nearest)
        or 'no accessible CutMachinePrompt nearby'
end
-- One prompt manually used by the player resolves the ambiguous level models.
conns[#conns + 1] = PPS.PromptTriggered:Connect(function(p, who)
    if not alive or not p or p.Name ~= 'CutMachinePrompt' then return end
    if who ~= nil and who ~= player then return end
    local model = ancestorLevel(p)
    if model then bind(model, 'MANUAL_PROMPT') end
end)

local function visible(o)
    if not o or not o.Parent or not o:IsA('GuiObject') then return false end
    if o.AbsoluteSize.X < 5 or o.AbsoluteSize.Y < 5 then return false end
    local a = o
    while a and a ~= pg do
        if a:IsA('GuiObject') and not a.Visible then return false end
        if a:IsA('ScreenGui') and not a.Enabled then return false end
        a = a.Parent
    end
    return true
end
local function excluded(node)
    local p = node
    while p and p ~= pg do
        if p.Name == 'CurrentCut' or p.Name == 'FinishCard'
            or p.Name == 'CutStoneTab' or p.Name == 'KesimPaneli'
            or p.Name == 'StonePhoto' or p.Name == 'SellMenu' then return true end
        p = p.Parent
    end
    return false
end
local function hasAncestor(o, a)
    while o do
        if o == a then return true end
        o = o.Parent
    end
    return false
end
local function observeStones()
    scans += 1
    local menu = pg:FindFirstChild('CuttingMenu')
    local inv = pg:FindFirstChild('InventoryMenu')
    local fresh = {}
    local guiActive = false
    rawButtons, visibleCards, inventoryData = 0, 0, 0
    -- Only displayed, selectable stone cards constitute a reliable current candidate.
    for _,node in ipairs(pg:GetDescendants()) do
        if node:IsA('GuiButton') and uid(node.Name)
            and (menu and hasAncestor(node,menu) or inv and hasAncestor(node, inv))
            and not excluded(node) then
            rawButtons += 1
            if visible(node) then
                visibleCards += 1
                fresh[node.Name] = {source = menu and hasAncestor(node,menu)
                    and 'CuttingMenu' or 'InventoryMenu', captured=os.clock()}
                guiActive = true
            end
        end
    end
    -- These are diagnostic counts only, never used as proof of inventory ownership.
    for _,node in ipairs(player:GetDescendants()) do
        if node:IsA('StringValue') and uid(node.Value)
            and (node.Parent and node.Parent.Name:lower():find('stone',1,true)) then
            inventoryData += 1
        end
    end
    if guiActive then
        -- Replace rather than append so the cache reflects the latest visible inventory.
        stones = fresh
        lastCaptured = os.clock()
        log('STONES_CAPTURED visible=' .. visibleCards .. ' from active UI')
        statusMsg = 'Captured ' .. visibleCards .. ' selectable stones. Close menu; move far.'
    elseif #history == 0 then
        statusMsg = 'No visible stone cards. Open the CuttingMenu while holding raw stones.'
    end
    return visibleCards
end
local function stoneCount()
    local n=0
    for _ in pairs(stones) do n+=1 end
    return n
end
local function chooseStone()
    local keys={}
    for id in pairs(stones) do keys[#keys+1] = id end
    table.sort(keys)
    return keys[1]
end

local gui=Instance.new('ScreenGui')
gui.Name='CAR_RemoteCut_Test_v11'
gui.ResetOnSpawn=false
gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
gui.Parent=pg
local function create(class, properties, parent)
    local o=Instance.new(class)
    for k,v in pairs(properties) do o[k]=v end
    o.Parent=parent
    return o
end
local panel=create('Frame',{
    Position=UDim2.new(0,12,0.13,0),Size=UDim2.fromOffset(325,398),
    BackgroundColor3=Color3.fromRGB(23,29,40),BorderSizePixel=0},gui)
create('UICorner',{CornerRadius=UDim.new(0,10)},panel)
create('UIStroke',{Color=Color3.fromRGB(76,94,121),Thickness=1},panel)
local heading=create('TextLabel',{
    Text='CUT A ROCK | REMOTE CUT v1.1',
    TextColor3=Color3.new(1,1,1),Font=Enum.Font.GothamBold,
    TextSize=13,Size=UDim2.fromOffset(270,34),Position=UDim2.fromOffset(11,4),
    TextXAlignment=Enum.TextXAlignment.Left,BackgroundTransparency=1},panel)
local function button(text,x,y,w,h,fn)
    local b=create('TextButton',{
        Text=text,TextSize=12,Font=Enum.Font.GothamMedium,
        TextColor3=Color3.new(1,1,1),BackgroundColor3=Color3.fromRGB(44,73,107),
        Size=UDim2.fromOffset(w,h),Position=UDim2.fromOffset(x,y),BorderSizePixel=0
    },panel)
    create('UICorner',{CornerRadius=UDim.new(0,7)},b)
    if fn then conns[#conns+1]=b.Activated:Connect(function() fn(b) end) end
    return b
end
local function stop()
    if not alive then return end
    alive=false
    for _,c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    if gui and gui.Parent then gui:Destroy() end
    if env.CARRemoteCutTestStop==stop then env.CARRemoteCutTestStop=nil end
end
env.CARRemoteCutTestStop=stop
button('X',286,5,28,29,stop)
local info=create('TextLabel',{
    Text='Ready',TextColor3=Color3.fromRGB(196,221,238),
    BackgroundTransparency=1,TextWrapped=true,
    TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,
    TextSize=11,Font=Enum.Font.Gotham,
    Position=UDim2.fromOffset(12,43),Size=UDim2.fromOffset(302,137)},panel)
button('1. BIND NEAREST',11,185,145,36,function()
    local nearest, why=findNearest()
    if nearest then bind(nearest,'NEAREST_IN_RANGE')
    else statusMsg='Bind failed: '..tostring(why);log('BIND_FAILED '..tostring(why)) end
end)
button('2. SCAN STONES',168,185,145,36,function()
    local n=observeStones()
    if n==0 then
        statusMsg='No visible stone UUID cards. Open your CuttingMenu and rescan.'
        log('STONE_SCAN zero cards; raw='..rawButtons..' inventoryData='..inventoryData)
    end
end)
local testBtn=button('3. TEST FAR ONCE',11,230,302,39,nil)
local function report()
    local dist=distance(bound)
    local p=bound and promptOf(bound)
    local arr={
        'CUT A ROCK REMOTE CUT TEST v1.1',
        'PlaceId='..tostring(game.PlaceId),
        'MachineBound='..tostring(bound~=nil and bound.Parent~=nil),
        'MachinePath='..machinePath(),
        'BoundVia='..boundVia,
        'DistanceStuds='..(dist and string.format('%.1f',dist) or 'unknown'),
        'Prompt='..promptLabel(),
        'PromptRange='..(p and tostring(p.MaxActivationDistance) or 'unknown'),
        'RawUUIDButtons='..rawButtons,
        'VisibleStoneCards='..visibleCards,
        'ReplicatedStoneStringValues='..inventoryData,
        'CachedStoneIds='..stoneCount(),
        'CacheAgeSeconds='..(lastCaptured>0 and string.format('%.1f',os.clock()-lastCaptured) or 'none'),
        'Scans='..scans, 'RemoteSent='..sends,
        'Result='..result,
        'Note: local FireServer return is NOT confirmation of server acceptance.',
        'Note: UUID values are not exported.',
        '--- TIMELINE ---'
    }
    for _,msg in ipairs(history) do arr[#arr+1]=msg end
    return table.concat(arr,'\n')
end
button('COPY REPORT',11,278,302,37,function()
    local txt=report()
    print(txt)
    local cb=type(setclipboard)=='function' and setclipboard
        or type(toclipboard)=='function' and toclipboard or nil
    if cb and pcall(cb,txt) then
        statusMsg='Copied report. Paste into ChatGPT.'
    else statusMsg='Report printed in executor console.' end
end)
create('TextLabel',{
    Text='No teleport • no purchase • one explicit remote attempt',
    Size=UDim2.fromOffset(303,25),Position=UDim2.fromOffset(11,323),
    TextSize=10,TextColor3=Color3.fromRGB(166,184,204),
    BackgroundTransparency=1,Font=Enum.Font.Gotham},panel)
create('TextLabel',{
    Text='For testing, bind/capture once near machine, then move far away.',
    Size=UDim2.fromOffset(302,34),Position=UDim2.fromOffset(11,352),
    TextWrapped=true,TextSize=10,TextColor3=Color3.fromRGB(166,184,204),
    BackgroundTransparency=1,Font=Enum.Font.Gotham},panel)
-- Mobile panel dragging.
local drag, start, old = false, nil, nil
conns[#conns+1]=heading.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
        drag=true;start=input.Position;old=panel.Position
        local c; c=input.Changed:Connect(function()
            if input.UserInputState==Enum.UserInputState.End then drag=false;c:Disconnect() end
        end)
    end
end)
conns[#conns+1]=UIS.InputChanged:Connect(function(input)
    if drag and start and (input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseMovement) then
        local delta=input.Position-start
        panel.Position=UDim2.new(old.X.Scale,old.X.Offset+delta.X,old.Y.Scale,old.Y.Offset+delta.Y)
    end
end)

local function testOnce()
    if busy or attempted then
        statusMsg=attempted and 'Already tested this session; restart script to test again.' or 'Busy.'
        return
    end
    if not bound or not bound.Parent or not promptOf(bound) then
        statusMsg='No bound machine. BIND NEAREST while standing next to your machine.'
        result='BLOCKED: no bound machine'
        return
    end
    local stone=chooseStone()
    if not stone then
        statusMsg='No cached stone. Open CUT menu, SCAN STONES, then close menu.'
        result='BLOCKED: no selected stone UUID'
        return
    end
    local age=os.clock()-lastCaptured
    if age>120 then
        statusMsg='Cached stone list is older than 120s. Recapture before testing.'
        result='BLOCKED: stale stone list'
        return
    end
    local p=promptOf(bound)
    local dist=distance(bound)
    if not dist then result='BLOCKED: distance unavailable';return end
    if dist<math.max(30,p.MaxActivationDistance+10) then
        result='BLOCKED: not far enough'
        statusMsg='Move at least 30 studs away and press TEST FAR ONCE.'
        return
    end
    local action=p.ActionText:lower()
    if action:find('collect',1,true) or action:find('cutting',1,true) then
        result='BLOCKED: machine busy or ready to collect'
        statusMsg='Machine is cutting/collecting, not ready for a fresh stone.'
        return
    end
    local remote=RS:FindFirstChild('PlaceStoneInMachineEvent')
    if not remote or not remote:IsA('RemoteEvent') then
        result='BLOCKED: PlaceStoneInMachineEvent not found'
        return
    end
    busy=true
    attempted=true
    testBtn.Text='TESTING ...'
    local beforeAction=p.ActionText
    local nBefore=stoneCount()
    log(string.format('TEST_START machine=%s range=%.1f distance=%.1f cacheAge=%.1f stones=%d',
        bound.Name,p.MaxActivationDistance,dist,age,nBefore))
    local ok,err=pcall(function() remote:FireServer(bound,stone) end)
    sends+=1
    if not ok then
        result='LOCAL ERROR: '..tostring(err):sub(1,130)
        log('SEND_ERROR '..result)
    else
        result='SENT: awaiting visible effect'
        log('SEND_OK: one remote request (no evidence of acceptance yet)')
        task.wait(4)
        if alive then
            local afterAction=p.ActionText
            log('OBSERVED promptBefore='..beforeAction..' promptAfter='..afterAction)
            if afterAction~=beforeAction then
                result='POSSIBLE ACCEPTED: machine prompt action changed'
            else
                result='UNCONFIRMED: prompt unchanged; server acceptance unknown'
            end
        end
    end
    statusMsg=result
    busy=false
    testBtn.Text='TESTED - COPY REPORT'
end
conns[#conns+1]=testBtn.Activated:Connect(testOnce)

task.spawn(function()
    while alive do
        local dist=distance(bound)
        info.Text='Machine: '..(bound and bound.Name or 'NONE')..' ['..boundVia..']\n'
            ..'Distance: '..(dist and string.format('%.1f studs',dist) or '?')
            ..' | Prompt: '..promptLabel()..'\n'
            ..'Stone cards visible: '..visibleCards..' | Cached: '..stoneCount()..'\n'
            ..'Cache: '..(lastCaptured>0 and string.format('%.0fs old',os.clock()-lastCaptured) or 'none')..'\n'
            ..'Status: '..statusMsg
        task.wait(0.5)
    end
end)
log('START: no remotes dispatched automatically')
print('[CAR v1.1] Bind machine, open CUT menu and SCAN STONES, move far, TEST FAR ONCE.')

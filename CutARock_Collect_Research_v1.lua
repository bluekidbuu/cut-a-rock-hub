-- Cut a Rock | Collect Research v1.0 | ONE-SHOT remote prompt test
-- PlaceId 113742027864370 / GameId 10766468833
-- Purpose: verify whether a known, user-owned CutMachinePrompt can collect
-- an already-finished stone from FAR AWAY with the executor's prompt API.
-- Does NOT send guessed remote calls, loop, teleport, buy, or alter Auto Cut.
-- IMPORTANT: fireproximityprompt is executor-specific. A successful call alone
-- does not prove server-side acceptance. Only an observed machine transition does.

if not game:IsLoaded() then game.Loaded:Wait() end
if game.PlaceId ~= 113742027864370 and game.GameId ~= 10766468833 then
    warn('[CAR Collect Research] Incorrect game. Stopping.')
    return
end
local Players=game:GetService('Players')
local PPS=game:GetService('ProximityPromptService')
local UIS=game:GetService('UserInputService')
local player=Players.LocalPlayer
local pg=player:WaitForChild('PlayerGui')
local env=(type(getgenv)=='function' and getgenv()) or _G
if type(env.CARCollectResearchStop)=='function' then
    pcall(env.CARCollectResearchStop)
end

local alive=true
local busy=false
local started=os.clock()
local bound=nil
local via='none'
local manualArmed=false
local manualVerified=false
local manualStarts=0
local manualChanges=0
local manualTriggers=0
local testAttempted=false
local testCalls=0
local testMethod='not-used'
local testObserved='none'
local testResult='NOT_TESTED'
local logs={}
local conns={}
local status='Stand near YOUR cutting machine and BIND NEAREST.'
local manualBefore=nil
local manualStart=0
local observedPrompt=nil
local observedAction=nil
local nowAction=nil
local nowPrompt=nil
local lastPromptSample=0
local localFireSupported=(type(fireproximityprompt)=='function')

local function log(x)
    logs[#logs+1]=string.format('T+%.1fs %s',os.clock()-started,tostring(x))
    if #logs>38 then table.remove(logs,1) end
end
local function path(x)
    if not x or not x.Parent then return 'MISSING' end
    local ok,out=pcall(function()return x:GetFullName()end)
    return ok and out or x.Name
end
local function ancestorMachine(x)
    local p=x
    while p and p~=workspace do
        if p:IsA('Model') and p.Name:match('^level%d+$') then return p end
        p=p.Parent
    end
    return nil
end
local function promptOf(model)
    if not model or not model.Parent then return nil end
    for _,node in ipairs(model:GetDescendants()) do
        if node:IsA('ProximityPrompt') and node.Name=='CutMachinePrompt' then
            return node
        end
    end
    return nil
end
local function promptPos(p)
    if not p then return nil end
    local q=p.Parent
    if q and q:IsA('Attachment') then return q.WorldPosition end
    if q and q:IsA('BasePart') then return q.Position end
    local part=q and q:FindFirstAncestorWhichIsA('BasePart')
    return part and part.Position or nil
end
local function root()
    return player.Character and player.Character:FindFirstChild('HumanoidRootPart')
end
local function distance(p)
    local r=root()
    local pos=promptPos(p)
    if not r or not pos then return nil end
    return (r.Position-pos).Magnitude
end
local function state(p)
    if not p then return 'MISSING' end
    return tostring(p.ActionText)
end
local function isCollect(p)
    return p and p.Enabled and p.ActionText:lower():find('collect',1,true)~=nil
end
local function isReady(p)
    return p and p.ActionText:lower():find('place',1,true)~=nil
end
local function safeOwner(model)
    if not model then return 'unverified' end
    local id=tostring(player.UserId)
    local username=player.Name:lower()
    for _,key in ipairs({'OwnerUserId','PlayerUserId','UserId','Owner','OwnerName','PlayerName'}) do
        local value=model:GetAttribute(key)
        if value~=nil then
            local v=tostring(value)
            return (v==id or v:lower()==username) and 'match' or 'other'
        end
    end
    return 'unverified'
end
local function bindMachine(model,method)
    if not model or not model.Parent then
        status='No valid machine.'
        return false
    end
    local p=promptOf(model)
    if not p then
        status='No CutMachinePrompt under model.'
        return false
    end
    if safeOwner(model)=='other' then
        status='Machine has owner attribute for someone else; not bound.'
        log('BIND_REJECT owner mismatch')
        return false
    end
    if bound~=model then
        manualArmed=false
        manualVerified=false
        manualBefore=nil
    end
    bound=model
    via=method
    observedPrompt=p
    observedAction=p.ActionText
    nowPrompt=p
    nowAction=p.ActionText
    status='Machine bound. Wait until its prompt says Collect.'
    log('BIND '..model.Name..' via='..method..' currentAction='..p.ActionText)
    return true
end
local function bindNearest()
    local r=root()
    if not r then status='Character root not found.';return end
    local best,distBest=nil,math.huge
    for _,p in ipairs(workspace:GetDescendants()) do
        if p:IsA('ProximityPrompt') and p.Name=='CutMachinePrompt' then
            local m=ancestorMachine(p)
            local d=distance(p)
            if m and d and d<=p.MaxActivationDistance+1 and d<distBest
                and safeOwner(m)~='other' then
                best=m
                distBest=d
            end
        end
    end
    if best then bindMachine(best,'NEAREST_IN_RANGE')
    else status='Stand within prompt range of YOUR machine, then retry.' end
end
-- Listen for the player's own NORMAL prompt interactions. No RemoteEvent is sent.
conns[#conns+1]=PPS.PromptTriggered:Connect(function(p,who)
    if not alive or not p or p.Name~='CutMachinePrompt' then return end
    if who and who~=player then return end
    if bound and ancestorMachine(p)==bound then
        manualTriggers+=1
        log('MANUAL_PROMPT_TRIGGER action='..state(p))
    end
end)

local gui=Instance.new('ScreenGui')
gui.Name='CAR_Collect_Research_v1'
gui.ResetOnSpawn=false
gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
gui.Parent=pg
local function create(kind,props,parent)
    local o=Instance.new(kind)
    for k,v in pairs(props) do o[k]=v end
    o.Parent=parent
    return o
end
local panel=create('Frame',{
    Size=UDim2.fromOffset(336,415),
    Position=UDim2.new(0,12,0.12,0),
    BackgroundColor3=Color3.fromRGB(24,30,43),BorderSizePixel=0
},gui)
create('UICorner',{CornerRadius=UDim.new(0,10)},panel)
create('UIStroke',{Color=Color3.fromRGB(90,110,138),Thickness=1},panel)
local title=create('TextLabel',{
    Text='CUT A ROCK | COLLECT RESEARCH v1',
    Size=UDim2.fromOffset(290,34),Position=UDim2.fromOffset(10,3),
    BackgroundTransparency=1,TextColor3=Color3.new(1,1,1),
    TextSize=13,TextXAlignment=Enum.TextXAlignment.Left,Font=Enum.Font.GothamBold
},panel)
local function button(caption,x,y,w,h,fn)
    local b=create('TextButton',{
        Text=caption,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),
        BackgroundColor3=Color3.fromRGB(53,78,107),BorderSizePixel=0,
        TextSize=12,TextColor3=Color3.new(1,1,1),Font=Enum.Font.GothamMedium
    },panel)
    create('UICorner',{CornerRadius=UDim.new(0,6)},b)
    if fn then conns[#conns+1]=b.Activated:Connect(fn) end
    return b
end
local function stop()
    alive=false
    for _,c in ipairs(conns) do pcall(function()c:Disconnect()end) end
    if gui and gui.Parent then gui:Destroy() end
    if env.CARCollectResearchStop==stop then env.CARCollectResearchStop=nil end
end
env.CARCollectResearchStop=stop
button('X',299,5,26,27,stop)

local info=create('TextLabel',{
    Text='Initializing...',Position=UDim2.fromOffset(12,46),
    Size=UDim2.fromOffset(310,105),BackgroundTransparency=1,
    TextColor3=Color3.fromRGB(195,216,236),TextSize=11,
    TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,
    TextWrapped=true,Font=Enum.Font.Gotham
},panel)
button('1. BIND NEAREST',12,158,310,35,bindNearest)
button('2. ARM MANUAL WATCH',12,199,310,35,function()
    if not bound or not bound.Parent then
        status='BIND NEAREST first.'
        return
    end
    local p=promptOf(bound)
    if not isCollect(p) then
        status='Wait for this machine to show Collect, then ARM.'
        return
    end
    local d=distance(p)
    if not d or d>p.MaxActivationDistance+1 then
        status='Stand near this machine before arming the manual test.'
        return
    end
    manualArmed=true
    manualBefore=p.ActionText
    manualStart=os.clock()
    manualStarts+=1
    status='WATCH ON: Collect once MANUALLY while near the machine.'
    log('MANUAL_ARM prompt='..manualBefore)
end)
local testBtn
local function testFar()
    if busy or testAttempted then
        status=testAttempted and 'Only one far test per script run. Relaunch after checking results.' or 'Busy.'
        return
    end
    if not bound or not bound.Parent then status='BIND a machine first.';return end
    if not manualVerified then
        status='First verify normal Collect: ARM MANUAL WATCH, collect once nearby.'
        return
    end
    local p=promptOf(bound)
    if not isCollect(p) then
        status='This machine is not in Collect state yet. Wait for finish.'
        return
    end
    if not localFireSupported then
        testResult='BLOCKED_NO_FIREPROXIMITYPROMPT'
        status='Executor does not offer fireproximityprompt; no request sent.'
        log('FAR_BLOCKED fireproximityprompt unavailable')
        return
    end
    local d=distance(p)
    if not d then status='Distance unknown. Make sure character is spawned.';return end
    local threshold=math.max(30,p.MaxActivationDistance+10)
    if d<threshold then
        status=string.format('Move farther away (need >= %.1f studs; current %.1f).',threshold,d)
        return
    end
    local cut=pg:FindFirstChild('CuttingMenu')
    if cut and cut:IsA('ScreenGui') and cut.Enabled then
        status='Close CuttingMenu before far test to prevent confusion.'
        return
    end
    testAttempted=true
    busy=true
    testBtn.Text='OBSERVING ...'
    local before=p.ActionText
    local from=d
    log(string.format('FAR_ATTEMPT distance=%.1f maxPromptRange=%.1f before=%s',d,p.MaxActivationDistance,before))
    -- This executor-specific API requests one prompt activation. Never loop or retry.
    local ok,err=pcall(function()
        fireproximityprompt(p)
    end)
    testMethod='fireproximityprompt'
    testCalls+=1
    if not ok then
        testResult='LOCAL_ERROR'
        testObserved='none'
        status='Prompt API local error. See report.'
        log('FAR_LOCAL_ERROR '..tostring(err):sub(1,110))
    else
        testResult='SENT_UNCONFIRMED'
        status='One prompt activation attempted; observing server-visible state.'
        local seen='none'
        local changed=false
        local untilAt=os.clock()+9
        repeat
            if not alive then break end
            task.wait(0.1)
            local current=promptOf(bound)
            if current and current.ActionText~=before then
                changed=true
                seen=current.ActionText
                break
            end
        until os.clock()>=untilAt
        testObserved=seen
        if changed and isReady(promptOf(bound)) then
            testResult='POSSIBLE_ACCEPTED_COLLECT_TO_PLACE_ROCK'
            status='Prompt changed to Place Rock. Check collected item/reward in game.'
        elseif changed then
            testResult='CHANGED_BUT_NOT_PLACE_ROCK'
            status='Prompt changed, but Collect success is not established.'
        else
            testResult='UNCONFIRMED_NO_PROMPT_CHANGE'
            status='No prompt transition observed. Do not assume server accepted.'
        end
        log('FAR_RESULT before='..before..' after='..testObserved..' result='..testResult)
    end
    busy=false
    if alive then testBtn.Text='3. TEST FAR ONCE (used)' end
end
testBtn=button('3. TEST FAR ONCE',12,240,310,41,testFar)
local function report()
    local p=bound and promptOf(bound)
    local dist=distance(p)
    local out={
        'CUT A ROCK COLLECT RESEARCH v1',
        'PlaceId='..tostring(game.PlaceId),
        'MachineBound='..tostring(bound~=nil and bound.Parent~=nil),
        'BoundMachine='..(bound and bound.Name or 'none'),
        'BoundVia='..via,
        'MachinePath='..path(bound),
        'OwnerHint='..safeOwner(bound),
        'Prompt='..state(p),
        'PromptEnabled='..tostring(p and p.Enabled or false),
        'PromptRange='..tostring(p and p.MaxActivationDistance or 'unknown'),
        'DistanceStuds='..(dist and string.format('%.1f',dist) or 'unknown'),
        'PromptMethodAvailable='..tostring(localFireSupported),
        'ManualArms='..manualStarts,
        'ManualTriggers='..manualTriggers,
        'ManualPromptChanges='..manualChanges,
        'ManualVerified='..tostring(manualVerified),
        'FarAttempted='..tostring(testAttempted),
        'FarMethod='..testMethod,
        'FarCalls='..testCalls,
        'FarObserved='..testObserved,
        'Result='..testResult,
        'NOTE: Script never loops collect, teleports, or guesses a RemoteEvent.',
        'NOTE: fireproximityprompt call success alone is not server confirmation.',
        'NOTE: Check manually whether an actual cut stone was collected.',
        '--- TIMELINE ---'
    }
    for _,entry in ipairs(logs) do out[#out+1]=entry end
    return table.concat(out,'\n')
end
button('COPY REPORT',12,290,310,39,function()
    local result=report()
    print(result)
    local copy=(type(setclipboard)=='function' and setclipboard) or
        (type(toclipboard)=='function' and toclipboard) or nil
    if copy and pcall(copy,result) then
        status='Report copied. Paste it into ChatGPT.'
    else
        status='Report printed in executor console.'
    end
end)
create('TextLabel',{
    Text='Passive manual watch + ONE explicit far test; no Auto Cut changes',
    Position=UDim2.fromOffset(11,346),Size=UDim2.fromOffset(313,32),
    BackgroundTransparency=1,TextColor3=Color3.fromRGB(164,184,207),
    TextSize=10,TextWrapped=true,Font=Enum.Font.Gotham
},panel)

-- Mobile drag support (title only).
local dragging=false
local begin=nil
local old=nil
conns[#conns+1]=title.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.Touch
        or input.UserInputType==Enum.UserInputType.MouseButton1 then
        dragging=true
        begin=input.Position
        old=panel.Position
        local conn
        conn=input.Changed:Connect(function()
            if input.UserInputState==Enum.UserInputState.End then
                dragging=false
                conn:Disconnect()
            end
        end)
    end
end)
conns[#conns+1]=UIS.InputChanged:Connect(function(input)
    if dragging and begin and (input.UserInputType==Enum.UserInputType.Touch
        or input.UserInputType==Enum.UserInputType.MouseMovement) then
        local delta=input.Position-begin
        panel.Position=UDim2.new(old.X.Scale,old.X.Offset+delta.X,
            old.Y.Scale,old.Y.Offset+delta.Y)
    end
end)

local function sample()
    local p=bound and promptOf(bound)
    if p then
        -- Monitor transitions even if the game replaces the ProximityPrompt instance.
        if p~=observedPrompt then
            log('PROMPT_REPLACED old='..tostring(observedAction)..' new='..p.ActionText)
            observedPrompt=p
            observedAction=p.ActionText
        elseif observedAction~=p.ActionText then
            log('STATE_CHANGED '..tostring(observedAction)..' -> '..p.ActionText)
            observedAction=p.ActionText
        end
        nowPrompt=p
        nowAction=p.ActionText
        if manualArmed and p.ActionText~=manualBefore then
            manualArmed=false
            manualChanges+=1
            if isReady(p) then
                manualVerified=true
                log('MANUAL_CONFIRMED Collect -> '..p.ActionText)
                status='Manual Collect verified. Fill machine again; wait until Collect; then test FAR.'
            else
                log('MANUAL_CHANGED Collect -> '..p.ActionText..' (unverified)')
                status='Manual prompt changed but not to Place Rock; inspect machine.'
            end
        end
    end
    local dist=distance(p)
    info.Text=string.format('Bound: %s | via %s\nPrompt: %s | distance: %s | range: %s\nManual verified: %s | far API: %s\nFar result: %s\n%s',
        bound and bound.Name or 'NONE',via,state(p),
        dist and string.format('%.1f studs',dist) or '?',
        p and tostring(p.MaxActivationDistance) or '?',
        tostring(manualVerified),tostring(localFireSupported),testResult,status)
end
log('LOADED: passive; no automatic requests')
task.spawn(function()
    while alive do
        local ok,err=pcall(sample)
        if not ok then log('SAMPLE_ERROR '..tostring(err):sub(1,75)) end
        task.wait(0.13)
    end
end)
print('[CAR Collect Research v1] Bind own machine, ARM MANUAL, collect once near, wait for next Collect, move far, TEST FAR ONCE, COPY REPORT.')

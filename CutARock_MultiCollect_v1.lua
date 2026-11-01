-- CUT A ROCK | MULTI COLLECT v1.0 (separate from Auto Cut v1.8)
-- PlaceId=113742027864370, GameId=10766468833
-- Grounding: player verified a successful collection from 149.6 studs with
-- fireproximityprompt in the one-shot Collect Research v1 test.
-- The old observer incorrectly reported UNCONFIRMED when ActionText did not change.
-- This script never interprets a successful local call as proof of a reward.
-- Safe experiment: register owned machines, try COLLECT ALL ONCE, confirm by eye.
-- OPTIONAL AUTO WATCH requires Collect state and only one attempt per observed cycle.
-- No remotes guessed, no teleport, no purchases, no modifications to Auto Cut.

if not game:IsLoaded() then game.Loaded:Wait() end
if game.PlaceId ~= 113742027864370 and game.GameId ~= 10766468833 then
    warn('[CAR MultiCollect] Wrong game. Stopping.')
    return
end

local Players=game:GetService('Players')
local UIS=game:GetService('UserInputService')
local player=Players.LocalPlayer
local pg=player:WaitForChild('PlayerGui')
local env=type(getgenv)=='function' and getgenv() or _G
if type(env.CARMultiCollectStop)=='function' then
    pcall(env.CARMultiCollectStop)
end

local alive=true
local auto=false
local busy=false
local machines={}
local machineIndex={}
local preview={}
local anchor=nil
local nextIndex=1
local conns={}
local logLines={}
local started=os.clock()
local supported=type(fireproximityprompt)=='function'
local sends=0
local localOk=0
local localErrors=0
local batchRuns=0
local promptTransitions=0
local noVisibleChange=0
local manualConfirmedBatches=0
local maxCalls=36 -- bounded pilot; explicit relaunch required after this
local minimumGap=2.0
local lastSendAt=-1000
local lastBatchCount=0
local lastBatchConfirmed=false
local message='Bind your machine(s), then test COLLECT ALL ONCE.'

local function log(msg)
    logLines[#logLines+1]=string.format('T+%.1fs %s',os.clock()-started,tostring(msg))
    if #logLines>48 then table.remove(logLines,1) end
end
local function path(obj)
    if not obj or not obj.Parent then return 'MISSING' end
    local ok,p=pcall(function() return obj:GetFullName() end)
    return ok and p or obj.Name
end
local function ancestorMachine(obj)
    local p=obj
    while p and p~=workspace do
        if p:IsA('Model') and p.Name:match('^level%d+$') then return p end
        p=p.Parent
    end
    return nil
end
local function promptOf(model)
    if not model or not model.Parent then return nil end
    for _,p in ipairs(model:GetDescendants()) do
        if p:IsA('ProximityPrompt') and p.Name=='CutMachinePrompt' then return p end
    end
    return nil
end
local function promptPosition(p)
    local q=p and p.Parent
    if q and q:IsA('Attachment') then return q.WorldPosition end
    if q and q:IsA('BasePart') then return q.Position end
    local par=q and q:FindFirstAncestorWhichIsA('BasePart')
    return par and par.Position or nil
end
local function distance(p)
    local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
    local pos=promptPosition(p)
    return root and pos and (root.Position-pos).Magnitude or nil
end
local function ownerHint(model)
    if not model then return 'unknown' end
    local id=tostring(player.UserId)
    local name=player.Name:lower()
    for _,key in ipairs({'OwnerUserId','PlayerUserId','UserId','Owner','OwnerName','PlayerName'}) do
        local v=model:GetAttribute(key)
        if v~=nil then
            local s=tostring(v)
            return (s==id or s:lower()==name) and 'match' or 'other'
        end
    end
    return 'unknown'
end
local function state(p)
    if not p then return 'MISSING' end
    return tostring(p.ActionText)
end
local function isCollect(p)
    return p and p.Enabled and p.ActionText:lower():find('collect',1,true)~=nil
end
local function isNonCollectCycle(action)
    action=tostring(action or ''):lower()
    return action:find('cutting',1,true)~=nil or action:find('place rock',1,true)~=nil
end
local function bindMachine(model,via)
    if not model or not model.Parent then return false end
    local p=promptOf(model)
    if not p or ownerHint(model)=='other' then return false end
    if machineIndex[model] then return false end
    local item={model=model,via=via,lastState=state(p),armed=isCollect(p),
        attempts=0,localOk=0,lastAttempt=-1000,observed=0,lastResult='NOT_ATTEMPTED',
        lastAttemptState='none',postAttemptObserved=false}
    machines[#machines+1]=item
    machineIndex[model]=item
    anchor=model
    message='Bound machines: '..#machines
    log('BIND slot='..#machines..' '..path(model)..' via='..via..' state='..item.lastState)
    return true
end
local function nearest()
    local closest=math.huge
    local chosen=nil
    for _,p in ipairs(workspace:GetDescendants()) do
        if p:IsA('ProximityPrompt') and p.Name=='CutMachinePrompt' then
            local m=ancestorMachine(p)
            local d=distance(p)
            if m and d and d<=p.MaxActivationDistance+1 and d<closest
                and ownerHint(m)~='other' then
                chosen=m
                closest=d
            end
        end
    end
    if chosen then
        if not bindMachine(chosen,'NEAREST_IN_RANGE') then message='Machine already bound or rejected.' end
    else
        message='Move within prompt range of YOUR machine, then BIND NEAREST.'
    end
end
local function previewBase()
    preview={}
    if not anchor or not anchor.Parent then
        message='BIND NEAREST once first.'
        return
    end
    for _,m in ipairs(anchor.Parent:GetChildren()) do
        if m:IsA('Model') and m.Name:match('^level%d+$') and promptOf(m)
            and ownerHint(m)~='other' then
            preview[#preview+1]=m
        end
    end
    table.sort(preview,function(a,b)
        local x=tonumber(a.Name:match('%d+')) or 0
        local y=tonumber(b.Name:match('%d+')) or 0
        if x~=y then return x<y end
        return path(a)<path(b)
    end)
    log('PREVIEW siblings='..#preview..' parent='..path(anchor.Parent))
    message='Preview='..#preview..'. ADD PREVIEW ONLY if all candidates belong to you.'
end
local function addPreview()
    local n=0
    for _,m in ipairs(preview) do
        if m.Parent and ownerHint(m)~='other' and bindMachine(m,'CONFIRMED_SAME_BASE') then
            n+=1
        end
    end
    preview={}
    message='Added '..n..' machines; total '..#machines
    log('CONFIRM_BASE added='..n)
end
local function sampleStates()
    for i,item in ipairs(machines) do
        local p=promptOf(item.model)
        local action=state(p)
        local old=item.lastState
        if action~=old then
            -- Missing prompt is not an observed completion; avoid rearming from it.
            if isNonCollectCycle(action) then
                item.armed=true
            end
            if item.attempts>0 and old=='Collect' and isNonCollectCycle(action)
                and os.clock()-item.lastAttempt<20 then
                item.postAttemptObserved=true
                promptTransitions+=1
                item.observed+=1
                log('PROMPT_TRANSITION slot='..i..' from='..old..' to='..action)
            end
            item.lastState=action
        end
    end
end
local function attempt(item,idx,origin)
    if not alive or not supported then return false,'NO_PROMPT_API' end
    if sends>=maxCalls then
        auto=false
        message='Session cap reached ('..maxCalls..'); re-run after review.'
        log('SESSION_CAP reached')
        return false,'CAP_REACHED'
    end
    local p=promptOf(item.model)
    if not isCollect(p) then return false,'NOT_COLLECT' end
    if ownerHint(item.model)=='other' then return false,'OTHER_OWNER' end
    if not item.armed then return false,'ALREADY_ATTEMPTED_THIS_STATE' end
    if os.clock()-item.lastAttempt<25 then return false,'PER_MACHINE_COOLDOWN' end
    local d=distance(p)
    if not d then return false,'DISTANCE_UNAVAILABLE' end
    local gap=os.clock()-lastSendAt
    if gap<minimumGap then task.wait(minimumGap-gap) end
    if not alive then return false,'STOPPED' end
    p=promptOf(item.model)
    if not isCollect(p) then return false,'PROMPT_CHANGED_BEFORE_SEND' end
    -- One attempt per observed Collect cycle, even if client prompt remains stale.
    -- Do NOT rearm merely because the prompt was replaced/streamed back in.
    item.armed=false
    item.attempts+=1
    item.lastAttempt=os.clock()
    item.lastAttemptState=state(p)
    item.postAttemptObserved=false
    lastSendAt=os.clock()
    sends+=1
    local ok,err=pcall(function() fireproximityprompt(p) end)
    if ok then
        item.localOk+=1
        localOk+=1
        item.lastResult='SENT_UNVERIFIED'
        log(string.format('COLLECT_ATTEMPT slot=%d origin=%s distance=%.1f localOk=true',idx,origin,d))
        return true,'SENT_UNVERIFIED'
    end
    localErrors+=1
    item.lastResult='LOCAL_ERROR'
    log('COLLECT_LOCAL_ERROR slot='..idx..' '..tostring(err):sub(1,80))
    return false,'LOCAL_ERROR'
end
local function currentReadyCount()
    local n=0
    for _,item in ipairs(machines) do
        if item.armed and isCollect(promptOf(item.model)) then n+=1 end
    end
    return n
end
local function collectBatch()
    if busy then message='A collection pass is already running.';return end
    if #machines==0 then message='BIND machines first.';return end
    if not supported then message='fireproximityprompt unavailable on this executor.';return end
    busy=true
    batchRuns+=1
    lastBatchCount=0
    lastBatchConfirmed=false
    message='Collecting eligible machines ONCE; check rewards manually.'
    log('BATCH_START bound='..#machines..' ready='..currentReadyCount())
    task.spawn(function()
        for i,item in ipairs(machines) do
            if not alive then break end
            sampleStates()
            local ok=attempt(item,i,'BATCH_ONCE')
            if ok then lastBatchCount+=1 end
            task.wait(0.35)
        end
        busy=false
        log('BATCH_END attempts='..lastBatchCount..' visuallyConfirmed=unknown')
        if alive then message='Batch sent '..lastBatchCount..' prompt activations. VERIFY your collected rewards.' end
    end)
end
local function autoTick()
    if not auto or busy or #machines==0 then return end
    if not supported then auto=false;message='Prompt API unavailable';return end
    if sends>=maxCalls then auto=false;message='Session cap reached';return end
    local n=#machines
    for offset=0,n-1 do
        local idx=((nextIndex+offset-1)%n)+1
        local item=machines[idx]
        if item.armed and isCollect(promptOf(item.model)) then
            busy=true
            nextIndex=(idx%n)+1
            local ok=attempt(item,idx,'AUTO_WATCH')
            busy=false
            if ok then
                message='Auto Watch attempted Collect slot #'..idx..'; observe rewards.'
            end
            return
        end
    end
end

local gui=Instance.new('ScreenGui')
gui.Name='CAR_MultiCollect_v1'
gui.ResetOnSpawn=false
gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
gui.Parent=pg
local function make(cls,props,parent)
    local obj=Instance.new(cls)
    for k,v in pairs(props) do obj[k]=v end
    obj.Parent=parent
    return obj
end
local panel=make('Frame',{
    Size=UDim2.fromOffset(336,444),Position=UDim2.new(0,12,0.10,0),
    BackgroundColor3=Color3.fromRGB(22,29,42),BorderSizePixel=0
},gui)
make('UICorner',{CornerRadius=UDim.new(0,10)},panel)
make('UIStroke',{Color=Color3.fromRGB(85,106,130),Thickness=1},panel)
local title=make('TextLabel',{
    Text='CUT A ROCK | MULTI COLLECT v1',
    Size=UDim2.fromOffset(285,35),Position=UDim2.fromOffset(11,2),
    BackgroundTransparency=1,Font=Enum.Font.GothamBold,TextSize=13,
    TextColor3=Color3.new(1,1,1),TextXAlignment=Enum.TextXAlignment.Left
},panel)
local function button(text,x,y,w,h,fn)
    local b=make('TextButton',{
        Text=text,Size=UDim2.fromOffset(w,h),Position=UDim2.fromOffset(x,y),
        BackgroundColor3=Color3.fromRGB(49,78,109),BorderSizePixel=0,
        Font=Enum.Font.GothamMedium,TextSize=12,TextColor3=Color3.new(1,1,1)
    },panel)
    make('UICorner',{CornerRadius=UDim.new(0,7)},b)
    if fn then conns[#conns+1]=b.Activated:Connect(function()fn(b)end) end
    return b
end
local function stop()
    if not alive then return end
    alive=false;auto=false
    for _,c in ipairs(conns) do pcall(function()c:Disconnect()end) end
    if gui and gui.Parent then gui:Destroy() end
    if env.CARMultiCollectStop==stop then env.CARMultiCollectStop=nil end
end
env.CARMultiCollectStop=stop
button('X',296,5,28,27,stop)
local info=make('TextLabel',{
    Text='Starting...',Size=UDim2.fromOffset(312,104),Position=UDim2.fromOffset(12,40),
    BackgroundTransparency=1,Font=Enum.Font.Gotham,TextSize=11,TextWrapped=true,
    TextColor3=Color3.fromRGB(188,213,236),TextXAlignment=Enum.TextXAlignment.Left,
    TextYAlignment=Enum.TextYAlignment.Top
},panel)
button('BIND NEAREST',11,154,154,35,function()nearest()end)
button('PREVIEW SAME BASE',172,154,153,35,function()previewBase()end)
button('ADD PREVIEW',11,197,154,35,function()addPreview()end)
local batchButton=button('COLLECT ALL ONCE',172,197,153,35,function()collectBatch()end)
local autoBtn=button('AUTO WATCH: OFF',11,240,314,37,function(b)
    if #machines==0 then message='Bind machines first.';return end
    if not supported then message='Prompt function unavailable.';return end
    auto=not auto
    b.Text='AUTO WATCH: '..(auto and 'ON' or 'OFF')
    b.BackgroundColor3=auto and Color3.fromRGB(37,114,86) or Color3.fromRGB(49,78,109)
    log('AUTO_WATCH '..(auto and 'ON' or 'OFF'))
    message=auto and 'Watching Collect transitions. Only one attempt per observed cycle.'
        or 'Auto Watch paused.'
end)
button('CONFIRM LAST BATCH',11,285,314,34,function()
    if lastBatchCount>0 and not lastBatchConfirmed and not busy then
        lastBatchConfirmed=true
        manualConfirmedBatches+=1
        log('USER_CONFIRMED_BATCH attempts='..lastBatchCount..' (human report, not server proof)')
        message='Marked last batch as verified by player. Thank you.'
    else
        message='Run COLLECT ALL ONCE and check actual rewards first.'
    end
end)
local function report()
    local out={
        'CUT A ROCK MULTI COLLECT v1',
        'PlaceId='..tostring(game.PlaceId),
        'BoundMachines='..#machines,
        'PreviewCandidates='..#preview,
        'PromptMethodAvailable='..tostring(supported),
        'AutoWatch='..tostring(auto)..' Busy='..tostring(busy),
        'BatchRuns='..batchRuns,
        'PromptCalls='..sends,
        'LocalCallOK='..localOk,
        'LocalErrors='..localErrors,
        'PromptTransitionsObserved='..promptTransitions,
        'PlayerVerifiedBatches='..manualConfirmedBatches,
        'ReadyUnattemptedMachines='..currentReadyCount(),
        'SessionCap='..maxCalls,
        'NOTE: Successful local call does not prove server accepted collection.',
        'NOTE: User personally verified a far one-shot Collect from 149.6 studs in prior test.',
        'NOTE: If prompt stays Collect after success, no repeat is attempted until a real non-Collect state is seen.',
        '--- MACHINES ---'
    }
    for i,item in ipairs(machines) do
        local p=promptOf(item.model)
        local d=distance(p)
        out[#out+1]=string.format('#%d %s | via=%s | state=%s | armed=%s | attempts=%d | localOk=%d | observed=%d | distance=%s',
            i,path(item.model),item.via,state(p),tostring(item.armed),item.attempts,item.localOk,
            item.observed,d and string.format('%.1f',d) or '?')
    end
    out[#out+1]='--- PREVIEW ---'
    for i,m in ipairs(preview) do out[#out+1]=i..'. '..path(m)..' ownerHint='..ownerHint(m) end
    out[#out+1]='--- TIMELINE ---'
    for _,s in ipairs(logLines) do out[#out+1]=s end
    return table.concat(out,'\n')
end
button('COPY REPORT',11,327,314,37,function()
    local r=report()
    print(r)
    local copy=type(setclipboard)=='function' and setclipboard
        or type(toclipboard)=='function' and toclipboard or nil
    if copy and pcall(copy,r) then message='Report copied; paste into ChatGPT.'
    else message='Report printed in executor console.' end
end)
make('TextLabel',{
    Text='Start with COLLECT ALL ONCE. AUTO WATCH is optional after you confirm results.',
    Size=UDim2.fromOffset(312,31),Position=UDim2.fromOffset(12,377),
    BackgroundTransparency=1,Font=Enum.Font.Gotham,TextSize=10,TextWrapped=true,
    TextColor3=Color3.fromRGB(162,185,208)
},panel)
local dragging=false
local dragPos=nil
local startPos=nil
conns[#conns+1]=title.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.Touch
        or input.UserInputType==Enum.UserInputType.MouseButton1 then
        dragging=true;dragPos=input.Position;startPos=panel.Position
        local conn
        conn=input.Changed:Connect(function()
            if input.UserInputState==Enum.UserInputState.End then
                dragging=false;conn:Disconnect()
            end
        end)
    end
end)
conns[#conns+1]=UIS.InputChanged:Connect(function(input)
    if dragging and dragPos and (input.UserInputType==Enum.UserInputType.Touch
        or input.UserInputType==Enum.UserInputType.MouseMovement) then
        local delta=input.Position-dragPos
        panel.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+delta.X,
            startPos.Y.Scale,startPos.Y.Offset+delta.Y)
    end
end)
log('LOADED. No automatic prompt activations. One previous far Collect verified by user.')
task.spawn(function()
    while alive do
        local ok,err=pcall(function()
            sampleStates()
            if auto then autoTick() end
            if info and info.Parent then
                info.Text=string.format('Bound machines: %d | Ready: %d | Preview: %d\nPrompt API: %s | Auto: %s | Calls: %d/%d\nLast batch: %d attempts | Player-confirmed batches: %d\n%s',
                    #machines,currentReadyCount(),#preview,tostring(supported),
                    auto and 'ON' or 'OFF',sends,maxCalls,lastBatchCount,manualConfirmedBatches,message)
            end
        end)
        if not ok then log('LOOP_ERROR '..tostring(err):sub(1,100)) end
        task.wait(0.25)
    end
end)
print('[CAR MultiCollect v1] Bind owned machines, preview/confirm group, COLLECT ALL ONCE, verify actual rewards, COPY REPORT. AUTO WATCH optional.')

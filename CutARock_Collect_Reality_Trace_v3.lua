-- CUT A ROCK | Collect Reality Trace v3.0 (PASSIVE MANUAL COLLECT STUDY)
-- v3 adds client inventory snapshots and explicit user-verified real reward flag.
-- PlaceId: 113742027864370 | GameId: 10766468833
-- Captures prompt status changes and inbound RemoteEvent names while the user
-- collects ONE finished stone normally from close range.
-- OPTIONAL: if user taps ENABLE OUTBOUND TRACE and executor supports
-- hookmetamethod + getnamecallmethod, logs outgoing RemoteEvent/RemoteFunction
-- NAME, METHOD, and ARGUMENT TYPES ONLY. No payload values or identifiers.
-- This script NEVER calls FireServer, InvokeServer, or fireproximityprompt;
-- it does not teleport, auto collect, manipulate server state, or buy things.
-- A global namecall hook may stay installed (in pass-through mode) until rejoin.

if not game:IsLoaded() then game.Loaded:Wait() end
if game.PlaceId ~= 113742027864370 and game.GameId ~= 10766468833 then
    warn('[CAR Collect Trace v3] Wrong Roblox game. Not running.')
    return
end

local Players=game:GetService('Players')
local PPS=game:GetService('ProximityPromptService')
local RS=game:GetService('ReplicatedStorage')
local UIS=game:GetService('UserInputService')
local player=Players.LocalPlayer
local pg=player:WaitForChild('PlayerGui')
local env=(type(getgenv)=='function' and getgenv()) or _G
if type(env.CARCollectTraceStop)=='function' then pcall(env.CARCollectTraceStop) end

local alive=true
local bound=nil
local armed=false
local windowEnds=0
local windowStart=0
local windowSeconds=18
local boundVia='none'
local started=os.clock()
local hookStatus='NOT_ENABLED'
local hookSupported=type(hookmetamethod)=='function' and type(getnamecallmethod)=='function'
local manualVerified=false
local beforeAction='none'
local lastAction='none'
local manualTriggers=0
local inboundCount=0
local outboundCount=0
local observedPromptTransitions=0
local subscribed=0
local subscriptionErrors=0
local stream={}
local outbound={}
local inbound={}
local status='Stand near YOUR machine showing Collect; BIND NEAREST.'
local conns={}
local listeners={}
local listening={}
local rootGui
local startButton
local rewardVerifiedByUser=false
local inventoryBaseline=nil
local inventoryAfter=nil
local inventoryChanges={}
local inventoryChangesSeen={}
local inventorySamples=0
local nextInventorySample=1
local inventorySampleSchedule={1,3,7,16}
local inventoryCap=12000
local inventoryTruncated=false

local function push(msg)
    stream[#stream+1]=string.format('T+%.1fs %s',os.clock()-started,tostring(msg))
    if #stream>55 then table.remove(stream,1) end
end
local function safeName(o)
    if not o or not o.Parent then return 'MISSING' end
    local ok,result=pcall(function() return o:GetFullName() end)
    return ok and result or o.Name
end
local function parentLevel(o)
    local p=o
    while p and p~=workspace do
        if p:IsA('Model') and p.Name:match('^level%d+$') then return p end
        p=p.Parent
    end
end
local function promptOf(model)
    if not model or not model.Parent then return nil end
    for _,o in ipairs(model:GetDescendants()) do
        if o:IsA('ProximityPrompt') and o.Name=='CutMachinePrompt' then return o end
    end
end
local function promptPos(p)
    local q=p and p.Parent
    if q and q:IsA('Attachment') then return q.WorldPosition end
    if q and q:IsA('BasePart') then return q.Position end
    local part=q and q:FindFirstAncestorWhichIsA('BasePart')
    return part and part.Position
end
local function distance(p)
    local character=player.Character
    local root=character and character:FindFirstChild('HumanoidRootPart')
    local pos=promptPos(p)
    return (root and pos) and (root.Position-pos).Magnitude or nil
end
local function ownedElsewhere(model)
    if not model then return false end
    local keys={'OwnerUserId','PlayerUserId','UserId','Owner','OwnerName','PlayerName'}
    for _,k in ipairs(keys) do
        local v=model:GetAttribute(k)
        if v~=nil then
            local s=tostring(v)
            return s~=tostring(player.UserId) and s:lower()~=player.Name:lower()
        end
    end
    return false
end
local function bindNearest()
    if armed then status='Finish current trace before binding again.';return end
    local best,closest=nil,math.huge
    for _,p in ipairs(workspace:GetDescendants()) do
        if p:IsA('ProximityPrompt') and p.Name=='CutMachinePrompt' then
            local model=parentLevel(p)
            local dist=distance(p)
            if model and not ownedElsewhere(model) and dist
                and dist<=p.MaxActivationDistance+1 and dist<closest then
                best,closest=model,dist
            end
        end
    end
    if best then
        bound=best
        boundVia='NEAREST_IN_RANGE'
        local p=promptOf(best)
        lastAction=p and p.ActionText or 'none'
        status='Bound '..best.Name..'. Wait until Collect, then ARM.'
        push('BIND '..safeName(best)..' distance='..string.format('%.1f',closest)..' action='..lastAction)
    else
        status='No own machine prompt in range. Move closer.'
    end
end

-- Snapshot only client-visible inventory-related instances and numeric values.
-- This is supporting evidence, NOT authoritative proof of a server grant.
local function isUUID(s)
    return type(s)=='string' and s:match('^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x$')~=nil
end
local function inventoryRelated(o)
    local node=o
    for _=1,7 do
        if not node or node==player or node==pg then break end
        local name=node.Name:lower()
        if name=='cep' or name:find('inventory',1,true) or name:find('stone',1,true)
            or name:find('rock',1,true) or name:find('bag',1,true)
            or name:find('pocket',1,true) or name:find('storage',1,true)
            or name:find('collect',1,true) or name:find('material',1,true)
            or name:find('item',1,true) or name:find('cut',1,true)
            or name:find('tas',1,true) then return true end
        node=node.Parent
    end
    return false
end
local function safePath(o,root)
    local segments={}
    while o and o~=root and #segments<7 do
        local name=o.Name
        if isUUID(name) then name='<uuid>' end
        if #name>42 then name=name:sub(1,42)..'...' end
        table.insert(segments,1,name)
        o=o.Parent
    end
    return table.concat(segments,'/')
end
local function snapshotInventory()
    local snap={cep=0,cutCards=0,candidates=0,numeric={},total=0}
    local function visit(root,section)
        local nodes=root:GetDescendants()
        for _,obj in ipairs(nodes) do
            snap.total+=1
            if snap.total>inventoryCap then inventoryTruncated=true;break end
            if obj.Parent and isUUID(obj.Name) and obj.Parent.Name=='Cep' then snap.cep+=1 end
            if obj:IsA('GuiButton') and isUUID(obj.Name) then
                local parent=obj.Parent
                local inCutting=false
                while parent and parent~=pg do
                    if parent.Name=='CuttingMenu' then inCutting=true;break end
                    parent=parent.Parent
                end
                if inCutting then snap.cutCards+=1 end
            end
            if inventoryRelated(obj) then
                snap.candidates+=1
                if obj:IsA('IntValue') or obj:IsA('NumberValue') then
                    local key=section..'/'..safePath(obj,root)
                    snap.numeric[key]=obj.Value
                end
            end
        end
    end
    -- Player:GetDescendants includes PlayerGui, so avoid double counting it.
    visit(player,'Player')
    return snap
end
local function summarizeChange(a,b)
    local changes={}
    if not a or not b then return changes end
    for k,v in pairs(b.numeric) do
        if a.numeric[k]~=nil and v~=a.numeric[k] then
            changes[#changes+1]=string.format('%s %.4g -> %.4g',k,a.numeric[k],v)
        elseif a.numeric[k]==nil then
            changes[#changes+1]=string.format('%s <new numeric>',k)
        end
    end
    table.sort(changes)
    return changes
end
local function recordInventory(stage)
    local sn=snapshotInventory()
    inventorySamples+=1
    inventoryAfter=sn
    inventoryChanges=summarizeChange(inventoryBaseline,sn)
    for _,entry in ipairs(inventoryChanges) do inventoryChangesSeen[entry]=true end
    push(string.format('INVENTORY_SAMPLE stage=%s cep=%d cutCards=%d related=%d numericChanges=%d',
        stage,sn.cep,sn.cutCards,sn.candidates,#inventoryChanges))
end

-- Inbound observation: the script never opens remotes or sends calls.
local function watchRemote(o)
    if not alive or not o or not o:IsA('RemoteEvent') or listening[o] or subscribed>=240 then return end
    listening[o]=true
    local ok,c=pcall(function()
        return o.OnClientEvent:Connect(function(...)
            if alive and armed and os.clock()<=windowEnds then
                inboundCount+=1
                local name=o.Name
                local argc=select('#',...)
                local msg=string.format('INBOUND name=%s args=%d',name,argc)
                inbound[#inbound+1]=msg
                if #inbound>16 then table.remove(inbound,1) end
                push(msg)
            end
        end)
    end)
    if ok and c then
        subscribed+=1
        listeners[#listeners+1]=c
    else
        subscriptionErrors+=1
    end
end
for _,o in ipairs(RS:GetDescendants()) do watchRemote(o) end
conns[#conns+1]=RS.DescendantAdded:Connect(function(o) watchRemote(o) end)

-- The optional global hook is passive and passes the ORIGINAL method call
-- with unchanged arguments. It stays as an inert pass-through after closing UI.
local hook=env.CARCollectTraceHookV2
if type(hook)~='table' then
    hook={installed=false,sink=nil}
    env.CARCollectTraceHookV2=hook
end
local function enableOutboundHook()
    if not hookSupported then
        hookStatus='UNAVAILABLE'
        status='Outbound trace unavailable on this executor; inbound and prompts still work.'
        push('HOOK_UNAVAILABLE')
        return
    end
    if hook.installed then
        hookStatus='ENABLED_REUSED'
        status='Outbound trace enabled (existing pass-through hook).'
        push('HOOK_REUSED')
        return
    end
    local ok,err=pcall(function()
        local old
        local wrapper=function(self,...)
            local method=getnamecallmethod()
            if hook.sink and (method=='FireServer' or method=='InvokeServer') then
                local valid=(typeof(self)=='Instance')
                    and (self:IsA('RemoteEvent') or self:IsA('RemoteFunction'))
                if valid then
                    local n=select('#',...)
                    local args={...}
                    local types={}
                    for i=1,math.min(n,6) do types[#types+1]=typeof(args[i]) end
                    if n>6 then types[#types+1]='+'..tostring(n-6) end
                    pcall(hook.sink,self.Name,self.ClassName,method,table.concat(types,','))
                end
            end
            return old(self,...)
        end
        if type(newcclosure)=='function' then wrapper=newcclosure(wrapper) end
        old=hookmetamethod(game,'__namecall',wrapper)
        if type(old)~='function' then error('hookmetamethod did not return old method') end
        hook.installed=true
    end)
    if ok then
        hookStatus='ENABLED'
        status='Outbound trace enabled. Collect normally while armed.'
        push('HOOK_ENABLED_PASS_THROUGH')
    else
        hookStatus='HOOK_ERROR'
        status='Outbound trace failed to install; prompt monitoring still available.'
        push('HOOK_ERROR '..tostring(err):sub(1,70))
    end
end

local function arm()
    if armed then status='Trace already armed. Collect normally now.';return end
    if not bound or not bound.Parent then status='First BIND NEAREST.';return end
    local p=promptOf(bound)
    if not p or p.ActionText:lower():find('collect',1,true)==nil then
        status='Wait until your machine shows Collect before arming.';return
    end
    local d=distance(p)
    if not d or d>p.MaxActivationDistance+1 then
        status='Stand within normal prompt range to perform a manual Collect.';return
    end
    inboundCount=0;outboundCount=0;manualTriggers=0;observedPromptTransitions=0
    inbound={};outbound={};manualVerified=false
    rewardVerifiedByUser=false
    inventorySamples=0
    nextInventorySample=1
    inventoryTruncated=false
    inventoryBaseline=snapshotInventory()
    inventoryAfter=inventoryBaseline
    inventoryChanges={}
    inventoryChangesSeen={}
    push(string.format('INVENTORY_BASELINE cep=%d cutCards=%d related=%d',inventoryBaseline.cep,inventoryBaseline.cutCards,inventoryBaseline.candidates))
    beforeAction=p.ActionText
    lastAction=beforeAction
    windowStart=os.clock()
    windowEnds=windowStart+windowSeconds
    armed=true
    if hookStatus=='ENABLED' or hookStatus=='ENABLED_REUSED' then
        hook.sink=function(name,cls,method,signature)
            if not alive or not armed or os.clock()>windowEnds then return end
            outboundCount+=1
            local msg=string.format('OUTBOUND name=%s class=%s method=%s argTypes=(%s)',name,cls,method,signature)
            outbound[#outbound+1]=msg
            if #outbound>16 then table.remove(outbound,1) end
            push(msg)
        end
    end
    status='Trace active for 18s. Collect this stone MANUALLY now.'
    push('TRACE_ARM before='..beforeAction..' dist='..string.format('%.1f',d)
        ..' hook='..hookStatus)
end

conns[#conns+1]=PPS.PromptTriggered:Connect(function(p,who)
    if not alive or not armed or not bound or not p or p.Name~='CutMachinePrompt' then return end
    if who and who~=player then return end
    if parentLevel(p)==bound then
        manualTriggers+=1
        push('PROMPT_TRIGGER action='..tostring(p.ActionText))
    end
end)

local function stop()
    alive=false
    armed=false
    if hook.sink then hook.sink=nil end
    for _,c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    for _,c in ipairs(listeners) do pcall(function() c:Disconnect() end) end
    if rootGui then rootGui:Destroy() end
    if env.CARCollectTraceStop==stop then env.CARCollectTraceStop=nil end
end
env.CARCollectTraceStop=stop

local function create(cls,props,parent)
    local o=Instance.new(cls)
    for k,v in pairs(props) do o[k]=v end
    o.Parent=parent
    return o
end
rootGui=create('ScreenGui',{Name='CAR_Collect_Trace_v3',ResetOnSpawn=false,
    ZIndexBehavior=Enum.ZIndexBehavior.Sibling},pg)
local panel=create('Frame',{
    Size=UDim2.fromOffset(334,469),Position=UDim2.new(0,10,0.12,0),
    BackgroundColor3=Color3.fromRGB(22,28,40),BorderSizePixel=0
},rootGui)
create('UICorner',{CornerRadius=UDim.new(0,10)},panel)
create('UIStroke',{Color=Color3.fromRGB(82,105,135),Thickness=1},panel)
local title=create('TextLabel',{
    Text='CUT A ROCK | COLLECT TRACE v3',
    Position=UDim2.fromOffset(11,4),Size=UDim2.fromOffset(278,34),
    TextColor3=Color3.new(1,1,1),Font=Enum.Font.GothamBold,TextSize=13,
    TextXAlignment=Enum.TextXAlignment.Left,BackgroundTransparency=1
},panel)
local function button(text,x,y,w,h,fn)
    local b=create('TextButton',{
        Text=text,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),
        TextColor3=Color3.new(1,1,1),BackgroundColor3=Color3.fromRGB(47,77,109),
        BorderSizePixel=0,Font=Enum.Font.GothamMedium,TextSize=12
    },panel)
    create('UICorner',{CornerRadius=UDim.new(0,7)},b)
    conns[#conns+1]=b.Activated:Connect(fn)
    return b
end
button('X',294,7,29,28,stop)
local info=create('TextLabel',{
    Text='Loading...',Position=UDim2.fromOffset(12,45),Size=UDim2.fromOffset(311,117),
    BackgroundTransparency=1,TextWrapped=true,TextColor3=Color3.fromRGB(190,211,235),
    TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,
    Font=Enum.Font.Gotham,TextSize=11
},panel)
button('1. BIND NEAREST',12,169,310,36,bindNearest)
button('2. ENABLE OUTBOUND TRACE (optional)',12,211,310,36,enableOutboundHook)
startButton=button('3. ARM 18s, THEN MANUAL COLLECT',12,253,310,39,arm)
local function report()
    local p=bound and promptOf(bound)
    local d=distance(p)
    local state=p and p.ActionText or 'MISSING'
    local lines={
        'CUT A ROCK COLLECT REALITY TRACE v3',
        'PlaceId='..tostring(game.PlaceId),
        'MachineBound='..tostring(bound~=nil and bound.Parent~=nil),
        'BoundMachine='..(bound and bound.Name or 'NONE'),
        'BoundVia='..boundVia,
        'DistanceStuds='..(d and string.format('%.1f',d) or 'unknown'),
        'PromptRange='..(p and tostring(p.MaxActivationDistance) or 'unknown'),
        'PromptNow='..state,
        'HookSupported='..tostring(hookSupported),
        'HookStatus='..hookStatus,
        'TraceArmed='..tostring(armed),
        'PromptTransitionToPlaceRock='..tostring(manualVerified),
        'ActualRewardVerifiedByUser='..tostring(rewardVerifiedByUser),
        'InventorySamples='..inventorySamples,
        'InventoryTruncated='..tostring(inventoryTruncated),
        'BaselineCepUUIDObjects='..(inventoryBaseline and inventoryBaseline.cep or 'none'),
        'AfterCepUUIDObjects='..(inventoryAfter and inventoryAfter.cep or 'none'),
        'BaselineCutCards='..(inventoryBaseline and inventoryBaseline.cutCards or 'none'),
        'AfterCutCards='..(inventoryAfter and inventoryAfter.cutCards or 'none'),
        'NumericChangesLastSnapshot='..#inventoryChanges,
        'NumericChangeObservations='..(function()local n=0 for _ in pairs(inventoryChangesSeen) do n+=1 end return n end)(),
        'ManualTriggers='..manualTriggers,
        'PromptTransitions='..observedPromptTransitions,
        'OutboundCalls='..outboundCount,
        'InboundEvents='..inboundCount,
        'ObservedRemotes='..subscribed,
        'SubscriptionErrors='..subscriptionErrors,
        'NOTE: captures remote names, method, argument types only; never payload values.',
        'NOTE: no remotes, teleports or prompts dispatched by this script.',
        'NOTE: outbound hook may stay installed inert until game rejoin.',
        'NOTE: no outbound calls does NOT prove absence of server-side Prompt processing.',
        'NOTE: numeric changes are client observations, not proof of reward.',
        '--- CLIENT INVENTORY NUMERIC CHANGES (max 20) ---'
    }
    local recordedChanges={}
    for entry in pairs(inventoryChangesSeen) do recordedChanges[#recordedChanges+1]=entry end
    table.sort(recordedChanges)
    for i=1,math.min(20,#recordedChanges) do lines[#lines+1]=recordedChanges[i] end
    lines[#lines+1]='--- OUTBOUND ---'
    for _,s in ipairs(outbound) do lines[#lines+1]=s end
    lines[#lines+1]='--- INBOUND ---'
    for _,s in ipairs(inbound) do lines[#lines+1]=s end
    lines[#lines+1]='--- TIMELINE ---'
    for _,s in ipairs(stream) do lines[#lines+1]=s end
    return table.concat(lines,'\n')
end
button('I VERIFIED REAL REWARD',12,300,310,34,function()
    if not inventoryBaseline then
        status='ARM trace and perform a real manual collect first.'
        return
    end
    rewardVerifiedByUser=true
    status='Marked: player personally verified ACTUAL reward in game; not just a notification.'
    push('USER_VERIFIED_ACTUAL_REWARD (not inferred from prompt)')
end)
button('COPY REPORT',12,342,310,38,function()
    local s=report()
    print(s)
    local copy=(type(setclipboard)=='function' and setclipboard) or
        (type(toclipboard)=='function' and toclipboard) or nil
    if copy and pcall(copy,s) then
        status='Report copied. Paste it to ChatGPT.'
    else status='Report printed in executor console.' end
end)
create('TextLabel',{
    Text='Collect manually near machine. Press VERIFY only if the real reward is in inventory, not if a notification appears.',
    Position=UDim2.fromOffset(12,394),Size=UDim2.fromOffset(310,50),
    TextWrapped=true,TextColor3=Color3.fromRGB(158,180,204),
    TextSize=10,BackgroundTransparency=1,Font=Enum.Font.Gotham
},panel)
-- Mobile dragging with title.
local dragging=false
local dragFrom=nil
local panelFrom=nil
conns[#conns+1]=title.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
        dragging=true
        dragFrom=input.Position
        panelFrom=panel.Position
        local con
        con=input.Changed:Connect(function()
            if input.UserInputState==Enum.UserInputState.End then
                dragging=false
                con:Disconnect()
            end
        end)
    end
end)
conns[#conns+1]=UIS.InputChanged:Connect(function(input)
    if dragging and dragFrom and
        (input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseMovement) then
        local delta=input.Position-dragFrom
        panel.Position=UDim2.new(panelFrom.X.Scale,panelFrom.X.Offset+delta.X,
            panelFrom.Y.Scale,panelFrom.Y.Offset+delta.Y)
    end
end)

push('LOADED passive; inbound listeners='..subscribed..'; no outgoing requests')
task.spawn(function()
    while alive do
        local ok,err=pcall(function()
            local p=bound and promptOf(bound)
            if p and lastAction~=p.ActionText then
                observedPromptTransitions+=armed and 1 or 0
                push('PROMPT_STATE '..tostring(lastAction)..' -> '..p.ActionText)
                lastAction=p.ActionText
                if armed and beforeAction:lower():find('collect',1,true)
                    and p.ActionText:lower():find('place',1,true) then
                    manualVerified=true
                    push('PROMPT_CHANGED_TO_PLACE_ROCK (NOT alone proof of reward)')
                end
            end
            if armed and nextInventorySample<=#inventorySampleSchedule
                and os.clock()-windowStart>=inventorySampleSchedule[nextInventorySample] then
                recordInventory('T+'..inventorySampleSchedule[nextInventorySample]..'s')
                nextInventorySample+=1
            end
            if armed and os.clock()>windowEnds then
                armed=false
                hook.sink=nil
                push('TRACE_DONE manualVerified='..tostring(manualVerified)..
                    ' outgoing='..outboundCount..' incoming='..inboundCount)
                status='Trace finished. COPY REPORT now.'
            end
            local d=distance(p)
            info.Text=string.format('Bound: %s | Prompt: %s\nDistance: %s | Range: %s\nOutbound hook: %s | Inbound monitors: %d\nTrace: %s | verified: %s\nOut: %d | In: %d\n%s',
                bound and bound.Name or 'NONE',p and p.ActionText or 'none',
                d and string.format('%.1f',d) or '?',p and tostring(p.MaxActivationDistance) or '?',
                hookStatus,subscribed,armed and 'ARMED' or 'OFF',tostring(manualVerified),
                outboundCount,inboundCount,status)
        end)
        if not ok then push('MONITOR_ERROR '..tostring(err):sub(1,70)) end
        task.wait(0.09)
    end
end)
print('[CAR Collect Trace v3] One SCRIPT: BIND NEAREST, optionally outbound hook, ARM 18s, manual Collect nearby, verify actual reward, COPY REPORT.')

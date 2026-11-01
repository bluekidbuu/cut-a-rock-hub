-- CUT A ROCK | Collect Near-vs-Far Reality Check v4
-- User-controlled A/B test to distinguish accepted collection from local prompt effects.
-- Does not guess or call any RemoteEvent, purchase, teleport, or auto-loop.
-- Manual near collection is the control. One far fireproximityprompt attempt is optional.
-- A local call or notification is NEVER labeled as real reward proof.
-- PlaceId 113742027864370 | GameId 10766468833

if not game:IsLoaded() then game.Loaded:Wait() end
if game.PlaceId ~= 113742027864370 and game.GameId ~= 10766468833 then
    warn('[CAR Collect v4] Wrong game; disabled.')
    return
end

local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local UIS=game:GetService('UserInputService')
local player=Players.LocalPlayer
local pg=player:WaitForChild('PlayerGui')
local env=type(getgenv)=='function' and getgenv() or _G
if type(env.CARCollectCompareV4Stop)=='function' then pcall(env.CARCollectCompareV4Stop) end
if type(env.CARCollectTraceStop)=='function' then pcall(env.CARCollectTraceStop) end

local alive=true
local started=os.clock()
local bound=nil
local active=nil
local windowLength=13
local windowUntil=0
local trials={near=nil,far=nil}
local conns={}
local eventConns={}
local watched={}
local timeline={}
local watchedCount=0
local status='BIND NEAREST while close to a machine showing Collect.'
local isFarMethodAvailable=type(fireproximityprompt)=='function'
local farUsed=false
local gui
local panel
local label

local function log(line)
    timeline[#timeline+1]=string.format('T+%.1fs %s',os.clock()-started,tostring(line))
    if #timeline>60 then table.remove(timeline,1) end
end
local function ancestryMachine(obj)
    while obj and obj~=workspace do
        if obj:IsA('Model') and obj.Name:match('^level%d+$') then return obj end
        obj=obj.Parent
    end
end
local function promptOf(model)
    if not model or not model.Parent then return nil end
    for _,obj in ipairs(model:GetDescendants()) do
        if obj:IsA('ProximityPrompt') and obj.Name=='CutMachinePrompt' then return obj end
    end
end
local function positionOf(p)
    local obj=p and p.Parent
    if obj and obj:IsA('Attachment') then return obj.WorldPosition end
    if obj and obj:IsA('BasePart') then return obj.Position end
    local part=obj and obj:FindFirstAncestorWhichIsA('BasePart')
    return part and part.Position
end
local function distance(p)
    local char=player.Character
    local root=char and char:FindFirstChild('HumanoidRootPart')
    local pos=positionOf(p)
    if root and pos then return (root.Position-pos).Magnitude end
end
local function ownerOther(model)
    local cur=model
    local keys={'OwnerUserId','PlayerUserId','UserId','Owner','OwnerName','PlayerName'}
    while cur and cur~=workspace do
        for _,key in ipairs(keys) do
            local val=cur:GetAttribute(key)
            if val~=nil then
                local s=tostring(val)
                return s~=tostring(player.UserId) and s:lower()~=player.Name:lower()
            end
        end
        cur=cur.Parent
    end
    return false
end
local function nearestBind()
    if active then status='Finish current 13s observation first.';return end
    local best,small=nil,math.huge
    for _,o in ipairs(workspace:GetDescendants()) do
        if o:IsA('ProximityPrompt') and o.Name=='CutMachinePrompt' then
            local m=ancestryMachine(o)
            local d=distance(o)
            if m and d and d<=o.MaxActivationDistance+1 and d<small and not ownerOther(m) then
                best=m;small=d
            end
        end
    end
    if best then
        bound=best
        status='Bound '..best.Name..' at '..string.format('%.1f',small)..' studs.'
        log('BIND '..best.Name..' distance='..string.format('%.1f',small))
    else
        status='No CutMachinePrompt in normal range; stand beside YOUR machine.'
    end
end
local function newTrial(mode,p,d)
    local trial={mode=mode,at=os.clock(),distance=d,range=p.MaxActivationDistance,
        before=p.ActionText,after=p.ActionText,changed=false,placeSeen=false,
        kesim=0,aura=0,other={},real='UNKNOWN',localCalled=false,
        localOK=false,error='',promptSignals=0,eventTotal=0}
    trials[mode]=trial
    active=mode
    windowUntil=os.clock()+windowLength
    log(string.format('ARM_%s distance=%.1f promptRange=%.1f before=%s',mode:upper(),d,p.MaxActivationDistance,p.ActionText))
    return trial
end
local function armNear()
    if active then status='Observation still running.';return end
    if not bound then status='BIND NEAREST first.';return end
    local p=promptOf(bound)
    if not p or not p.ActionText:lower():find('collect',1,true) then
        status='Machine must show Collect for near control.';return
    end
    local d=distance(p)
    if not d or d>p.MaxActivationDistance then status='Move into normal prompt range first.';return end
    newTrial('near',p,d)
    status='NEAR armed: collect MANUALLY, then verify actual reward in inventory.'
end
local function armFar()
    if active then status='Observation still running.';return end
    if farUsed then status='Far test can only be sent ONCE this session.';return end
    if not trials.near or trials.near.real~='YES' then
        status='First complete NEAR control and mark NEAR REWARD YES.';return
    end
    if not bound then status='BIND NEAREST first.';return end
    if not isFarMethodAvailable then status='fireproximityprompt unavailable.';return end
    local p=promptOf(bound)
    if not p or not p.ActionText:lower():find('collect',1,true) then
        status='Refill same machine normally; wait until Collect before far test.';return
    end
    local d=distance(p)
    local needed=math.max(30,p.MaxActivationDistance+10)
    if not d or d<needed then
        status='Move at least '..string.format('%.1f',needed)..' studs away first.';return
    end
    local trial=newTrial('far',p,d)
    farUsed=true
    local ok,err=pcall(function() fireproximityprompt(p) end)
    trial.localCalled=true
    trial.localOK=ok
    if not ok then trial.error=tostring(err):sub(1,90) end
    log('FAR_LOCAL_CALL ok='..tostring(ok)..' (NOT server acceptance)')
    status=ok and 'Far call made; inspect REAL inventory/reward, not notification.'
        or 'Local far-call error; review report.'
end
local function markReal(mode,yes)
    local trial=trials[mode]
    if not trial then status='No '..mode..' trial yet.';return end
    trial.real=yes and 'YES' or 'NO'
    log(mode:upper()..'_ACTUAL_REWARD_PLAYER_VERIFIED='..trial.real)
    status=(mode=='near' and 'Near' or 'Far')..' genuine reward marked '..trial.real..'.'
end

-- Monitor all replicated incoming notifications; omit payload values.
local function watch(o)
    if not alive or not o:IsA('RemoteEvent') or watched[o] or watchedCount>=240 then return end
    watched[o]=true
    local ok,conn=pcall(function()
        return o.OnClientEvent:Connect(function(...)
            if not alive or not active or os.clock()>windowUntil then return end
            local trial=trials[active]
            if not trial then return end
            local name=o.Name
            trial.eventTotal+=1
            if name=='KesimBildirimi' then
                trial.kesim+=1
                log(active:upper()..' INBOUND KesimBildirimi')
            elseif name=='AuraBildirimi' then
                trial.aura+=1
                log(active:upper()..' INBOUND AuraBildirimi')
            elseif name~='KapiVurusu' then
                trial.other[name]=(trial.other[name] or 0)+1
                log(active:upper()..' INBOUND '..name..' argCount='..select('#',...))
            end
        end)
    end)
    if ok and conn then
        watchedCount+=1
        eventConns[#eventConns+1]=conn
    end
end
for _,o in ipairs(RS:GetDescendants()) do watch(o) end
conns[#conns+1]=RS.DescendantAdded:Connect(watch)

local function stop()
    alive=false
    for _,c in ipairs(conns) do pcall(function()c:Disconnect()end) end
    for _,c in ipairs(eventConns) do pcall(function()c:Disconnect()end) end
    if gui then gui:Destroy() end
    if env.CARCollectCompareV4Stop==stop then env.CARCollectCompareV4Stop=nil end
end
env.CARCollectCompareV4Stop=stop

local function report()
    local arr={
        'CUT A ROCK COLLECT NEAR-FAR REALITY CHECK v4',
        'PlaceId='..tostring(game.PlaceId),
        'MachineBound='..tostring(bound~=nil and bound.Parent~=nil),
        'Machine='..(bound and bound.Name or 'NONE'),
        'RemoteEventListeners='..watchedCount,
        'FarMethodAvailable='..tostring(isFarMethodAvailable),
        'FarAttempted='..tostring(farUsed),
        'NOTE: RealReward=YES/NO is manually reported by player, not inferred from notification.',
        'NOTE: PromptTriggered, local calls and notifications are not proof of reward.',
        'NOTE: This study does not infer that a remote can bypass server distance validation.'
    }
    for _,mode in ipairs({'near','far'}) do
        local t=trials[mode]
        arr[#arr+1]='--- '..mode:upper()..' ---'
        if not t then
            arr[#arr+1]='NOT_TESTED'
        else
            arr[#arr+1]=string.format('Distance=%.1f Range=%.1f Before=%s After=%s',t.distance,t.range,t.before,t.after)
            arr[#arr+1]='LocalMethodCalled='..tostring(t.localCalled)..' LocalOK='..tostring(t.localOK)
            arr[#arr+1]='PromptChanged='..tostring(t.changed)..' PlaceRockSeen='..tostring(t.placeSeen)
            arr[#arr+1]='KesimBildirimi='..t.kesim..' AuraBildirimi='..t.aura..' InboundAll='..t.eventTotal
            arr[#arr+1]='ActualRewardByPlayer='..t.real..' LocalError='..(t.error~='' and t.error or 'none')
            local named={}
            for name,n in pairs(t.other) do named[#named+1]=name..':'..n end
            table.sort(named)
            arr[#arr+1]='OtherInbound='..(#named>0 and table.concat(named,',') or 'none')
        end
    end
    arr[#arr+1]='--- TIMELINE ---'
    for _,s in ipairs(timeline) do arr[#arr+1]=s end
    return table.concat(arr,'\n')
end
local function copyReport()
    local s=report()
    print(s)
    local c=type(setclipboard)=='function' and setclipboard
        or type(toclipboard)=='function' and toclipboard or nil
    if c and pcall(c,s) then status='Report copied. Paste it to ChatGPT.'
    else status='Report printed in executor console.' end
end

local function create(class,props,parent)
    local obj=Instance.new(class)
    for k,v in pairs(props) do obj[k]=v end
    obj.Parent=parent
    return obj
end
gui=create('ScreenGui',{Name='CAR_Collect_Compare_v4',ResetOnSpawn=false,
    ZIndexBehavior=Enum.ZIndexBehavior.Sibling},pg)
panel=create('Frame',{Size=UDim2.fromOffset(338,452),Position=UDim2.new(0,12,0.10,0),
    BackgroundColor3=Color3.fromRGB(22,28,40),BorderSizePixel=0},gui)
create('UICorner',{CornerRadius=UDim.new(0,10)},panel)
create('UIStroke',{Color=Color3.fromRGB(74,101,130),Thickness=1},panel)
local title=create('TextLabel',{Text='CUT A ROCK | COLLECT REALITY v4',
    Size=UDim2.fromOffset(295,34),Position=UDim2.fromOffset(10,4),
    BackgroundTransparency=1,Font=Enum.Font.GothamBold,TextSize=13,
    TextXAlignment=Enum.TextXAlignment.Left,TextColor3=Color3.new(1,1,1)},panel)
local function button(s,x,y,w,h,action)
    local b=create('TextButton',{Text=s,Size=UDim2.fromOffset(w,h),Position=UDim2.fromOffset(x,y),
        BackgroundColor3=Color3.fromRGB(44,73,103),TextColor3=Color3.new(1,1,1),
        BorderSizePixel=0,Font=Enum.Font.GothamMedium,TextSize=11},panel)
    create('UICorner',{CornerRadius=UDim.new(0,7)},b)
    conns[#conns+1]=b.Activated:Connect(action)
    return b
end
button('X',296,6,31,27,stop)
label=create('TextLabel',{Text='',Size=UDim2.fromOffset(316,115),Position=UDim2.fromOffset(11,42),
    BackgroundTransparency=1,TextColor3=Color3.fromRGB(203,219,238),Font=Enum.Font.Gotham,
    TextSize=11,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top},panel)
button('1. BIND NEAREST',11,164,316,32,nearestBind)
button('2. ARM NEAR / MANUAL COLLECT',11,203,316,36,armNear)
button('NEAR REWARD YES',11,246,151,32,function()markReal('near',true)end)
button('NEAR REWARD NO',176,246,151,32,function()markReal('near',false)end)
button('3. FAR TEST ONCE (after refill)',11,284,316,37,armFar)
button('FAR REAL REWARD YES',11,329,151,32,function()markReal('far',true)end)
button('FAR NO REWARD',176,329,151,32,function()markReal('far',false)end)
button('COPY REPORT',11,371,316,37,copyReport)
create('TextLabel',{Text='Observe actual inventory. Never mark YES for notification alone.',
    Position=UDim2.fromOffset(12,413),Size=UDim2.fromOffset(313,26),
    BackgroundTransparency=1,TextColor3=Color3.fromRGB(166,184,208),Font=Enum.Font.Gotham,
    TextSize=10,TextWrapped=true},panel)

local dragging=false
local dragStart,oldPosition
conns[#conns+1]=title.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
        dragging=true;dragStart=input.Position;oldPosition=panel.Position
        local conn
        conn=input.Changed:Connect(function()
            if input.UserInputState==Enum.UserInputState.End then dragging=false;conn:Disconnect() end
        end)
    end
end)
conns[#conns+1]=UIS.InputChanged:Connect(function(input)
    if dragging and dragStart and (input.UserInputType==Enum.UserInputType.Touch
        or input.UserInputType==Enum.UserInputType.MouseMovement) then
        local delta=input.Position-dragStart
        panel.Position=UDim2.new(oldPosition.X.Scale,oldPosition.X.Offset+delta.X,
            oldPosition.Y.Scale,oldPosition.Y.Offset+delta.Y)
    end
end)
log('LOADED passive; incoming event listeners='..watchedCount..'; no prompt calls until far test')
task.spawn(function()
    while alive do
        pcall(function()
            local p=bound and promptOf(bound)
            local d=distance(p)
            if active and trials[active] then
                local t=trials[active]
                if p then
                    local s=p.ActionText
                    if s~=t.after then
                        t.changed=true
                        t.after=s
                        if s:lower():find('place rock',1,true) then t.placeSeen=true end
                        log(active:upper()..' PROMPT_STATE '..s)
                    end
                end
                if os.clock()>windowUntil then
                    log(active:upper()..' WINDOW_DONE actualReward='..t.real)
                    active=nil
                end
            end
            local near=trials.near
            local far=trials.far
            label.Text=string.format('Machine: %s | Prompt: %s | Dist: %s studs\nNear: %s | Kesim:%d Aura:%d | Reward:%s\nFar: %s | Kesim:%d Aura:%d | Reward:%s\n%s',
                bound and bound.Name or 'none',p and p.ActionText or 'none',
                d and string.format('%.1f',d) or '?',
                near and (near.placeSeen and 'Place Rock seen' or 'observed') or 'not tested',
                near and near.kesim or 0,near and near.aura or 0,near and near.real or '?',
                far and (far.placeSeen and 'Place Rock seen' or 'observed') or 'not tested',
                far and far.kesim or 0,far and far.aura or 0,far and far.real or '?',status)
        end)
        task.wait(0.12)
    end
end)
print('[CAR Collect v4] BIND NEAREST > ARM NEAR > manual Collect > NEAR REWARD YES > refill > move far > FAR TEST ONCE > mark reward > COPY REPORT')

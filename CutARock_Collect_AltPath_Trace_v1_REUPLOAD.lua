-- CUT A ROCK | COLLECT ALTERNATE-PATH TRACE v1.0
-- One MANUAL Collect. Watches every replicated RemoteEvent inbound, not only named candidates.
-- Optional outbound metadata observer (hookmetamethod): records only remote name, class,
-- method and time. No argument values, caller data, UUIDs, source inspection or network sends.
-- The optional hook is pass-through and stays installed but inert after closing until rejoin.
-- NEVER calls FireServer, InvokeServer, fireproximityprompt or teleports the character.
-- Purpose: look for alternative CLIENT-side Collect paths; cannot reveal server handlers.

if not game:IsLoaded() then game.Loaded:Wait() end
if game.PlaceId~=113742027864370 and game.GameId~=10766468833 then
    warn('[CAR AltPath] Wrong game. Disabled.'); return
end

local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local PPS=game:GetService('ProximityPromptService')
local UIS=game:GetService('UserInputService')
local me=Players.LocalPlayer
local pg=me:WaitForChild('PlayerGui')
local env=(type(getgenv)=='function' and getgenv()) or _G
if type(env.CARAltPathStop)=='function' then pcall(env.CARAltPathStop) end

local observationSeconds=20
local MAX_EVENTS=80
local MAX_REMOTES=180
local alive,active,used,ended=true,false,false,false
local ownerConfirmed=false
local bound,boundPrompt=nil,nil
local started=os.clock()
local endingAt=0
local inboundWatched=0
local inboundCapped=false
local observed={}
local connections={}
local logRows={}
local scriptNames={}
local remoteNames={}
local scanCounts={objects=0,locals=0,modules=0,events=0,functions=0}
local scanDone=false
local hookStatus='OFF'
local outboundEnabled=false
local hook={}
local trial=nil
local panel,label,gui
local status='SCAN first; then BIND your machine showing Collect.'

local function now() return os.clock()-started end
local function stamp() return string.format('T+%.2f',now()) end
local function redact(s)
    s=tostring(s or 'UNKNOWN')
    s=s:gsub('[%da-fA-F][%da-fA-F][%da-fA-F][%da-fA-F][%da-fA-F][%da-fA-F][%da-fA-F][%da-fA-F]%-[%da-fA-F%-]+','<id>')
    if me.Name~='' then s=s:gsub(me.Name,'<player>') end
    if me.DisplayName~='' then
        local safePattern=me.DisplayName:gsub('(%W)','%%%1')
        s=s:gsub(safePattern,'<player>')
    end
    return s:sub(1,105)
end
local function log(msg)
    logRows[#logRows+1]=stamp()..' '..redact(msg)
    if #logRows>110 then table.remove(logRows,1) end
end
local function ancestorsLevel(o)
    while o and o~=workspace do
        if o:IsA('Model') and o.Name:match('^level%d+$') then return o end
        o=o.Parent
    end
end
local function promptPosition(p)
    local obj=p and p.Parent
    if obj and obj:IsA('Attachment') then return obj.WorldPosition end
    if obj and obj:IsA('BasePart') then return obj.Position end
    local part=obj and obj:FindFirstAncestorWhichIsA('BasePart')
    return part and part.Position or nil
end
local function distance(p)
    local c=me.Character
    local root=c and c:FindFirstChild('HumanoidRootPart')
    local pos=promptPosition(p)
    if root and pos then return (root.Position-pos).Magnitude end
end
local ownerKeys={'OwnerUserId','PlayerUserId','UserId','Owner','OwnerName','PlayerName'}
local function ownerHint(m)
    while m and m~=workspace do
        for _,key in ipairs(ownerKeys) do
            local v=m:GetAttribute(key)
            if v~=nil then
                local t=tostring(v)
                return (t==tostring(me.UserId) or t:lower()==me.Name:lower()) and 'SELF' or 'OTHER'
            end
        end
        m=m.Parent
    end
    return 'UNKNOWN'
end
local function validCollect(p)
    return p and p.Parent and p.Enabled and type(p.ActionText)=='string'
        and p.ActionText:lower():find('collect',1,true)~=nil
end
local function addEvent(kind,name)
    if not active or not trial or os.clock()>endingAt then return end
    if trial.events>=MAX_EVENTS then trial.dropped=trial.dropped+1;return end
    trial.events=trial.events+1
    trial.entries[#trial.entries+1]=stamp()..' '..kind..' '..redact(name)
    trial.totals[kind]=(trial.totals[kind] or 0)+1
end
local function watchIncoming(o)
    if not alive or not o:IsA('RemoteEvent') or observed[o] then return end
    if inboundWatched>=MAX_REMOTES then inboundCapped=true;return end
    observed[o]=true
    local ok,conn=pcall(function()
        return o.OnClientEvent:Connect(function(...)
            if active and trial and os.clock()<=endingAt then
                -- Arg count only, NEVER argument payload.
                addEvent('INBOUND',o.Name..' args='..select('#',...))
            end
        end)
    end)
    if ok and conn then
        inboundWatched=inboundWatched+1
        connections[#connections+1]=conn
    end
end
for _,o in ipairs(RS:GetDescendants()) do watchIncoming(o) end
connections[#connections+1]=RS.DescendantAdded:Connect(watchIncoming)

local function scan()
    if active then status='Finish observation first.';return end
    scanCounts={objects=0,locals=0,modules=0,events=0,functions=0}
    scriptNames={};remoteNames={}
    local roots={RS,pg,game:GetService('ReplicatedFirst')}
    local ps=me:FindFirstChild('PlayerScripts')
    if ps then roots[#roots+1]=ps end
    local models=workspace:FindFirstChild('Models')
    local bases=models and models:FindFirstChild('Bases')
    if bases then roots[#roots+1]=bases end
    for _,r in ipairs(roots) do
        if r then
            for _,obj in ipairs(r:GetDescendants()) do
                scanCounts.objects=scanCounts.objects+1
                if scanCounts.objects>30000 then break end
                local cls=obj.ClassName
                if cls=='ModuleScript' or cls=='LocalScript' then
                    if cls=='LocalScript' then scanCounts.locals=scanCounts.locals+1
                    else scanCounts.modules=scanCounts.modules+1 end
                    local n=obj.Name:lower()
                    if n:find('collect',1,true) or n:find('prompt',1,true)
                      or n:find('machine',1,true) or n:find('cut',1,true)
                      or n:find('stone',1,true) then
                        if #scriptNames<45 then scriptNames[#scriptNames+1]=cls..' '..redact(obj.Name) end
                    end
                elseif cls=='RemoteEvent' or cls=='RemoteFunction' then
                    if cls=='RemoteEvent' then scanCounts.events=scanCounts.events+1
                    else scanCounts.functions=scanCounts.functions+1 end
                    if #remoteNames<90 then remoteNames[#remoteNames+1]=cls..' '..redact(obj.Name) end
                end
            end
        end
        if scanCounts.objects>30000 then break end
    end
    table.sort(scriptNames);table.sort(remoteNames)
    scanDone=true
    status='Scan complete. Bind one Collect-ready machine.'
    log('SCAN remotes='..scanCounts.events..' functions='..scanCounts.functions..' scripts='..(scanCounts.locals+scanCounts.modules))
end

local function bindNearest()
    if used or active then status='One-shot used; rerun for another trial.';return end
    local models=workspace:FindFirstChild('Models')
    local bases=models and models:FindFirstChild('Bases')
    if not bases then status='Bases not visible.';return end
    local candidate,best,bestD=nil,nil,math.huge
    for _,o in ipairs(bases:GetDescendants()) do
        if o:IsA('ProximityPrompt') and o.Name=='CutMachinePrompt' and validCollect(o) then
            local m=ancestorsLevel(o)
            local d=distance(o)
            if m and d and d<=o.MaxActivationDistance and d<bestD and ownerHint(m)~='OTHER' then
                candidate,best,bestD=m,o,d
            end
        end
    end
    if not best then status='Stand near YOUR machine showing Collect.';return end
    bound,boundPrompt=candidate,best
    ownerConfirmed=false
    log(string.format('BIND machine=%s dist=%.1f range=%.1f ownerHint=%s',bound.Name,bestD,best.MaxActivationDistance,ownerHint(bound)))
    status='Bound '..bound.Name..'; confirm ownership.'
end
local function confirmOwn()
    if not bound or not bound.Parent or not boundPrompt or not boundPrompt.Parent then
        status='Bind a ready machine first.';return
    end
    if ownerHint(bound)=='OTHER' then status='Owner mismatch; test denied.';return end
    ownerConfirmed=true
    log('OWNER_CONFIRMED_BY_PLAYER')
    status='Ownership confirmed. Enable outbound observer if wanted, then ARM.'
end

-- Optional passive metadata observer. The global hook remains installed in pass-through
-- mode until rejoining Roblox; it does NOT alter arguments or produce remote calls.
local function noteOutbound(name,class,method)
    if not outboundEnabled or not active then return end
    addEvent('OUTBOUND_LUA',class..'/'..name..'/'..method)
end
local function enableOutbound()
    if active then status='Cannot enable during observation.';return end
    if type(hookmetamethod)~='function' or type(getnamecallmethod)~='function' then
        hookStatus='UNSUPPORTED';status='Executor has no optional outbound observer.';return
    end
    local slot=env.CARAltPathHookV1
    if type(slot)~='table' then
        slot={installed=false,sink=nil}
        env.CARAltPathHookV1=slot
    end
    hook=slot
    if not slot.installed then
        local ok,err=pcall(function()
            local old
            local wrapper=function(self,...)
                local method=getnamecallmethod()
                if slot.sink and (method=='FireServer' or method=='InvokeServer')
                   and typeof(self)=='Instance'
                   and (self:IsA('RemoteEvent') or self:IsA('RemoteFunction')) then
                    pcall(slot.sink,self.Name,self.ClassName,method)
                end
                return old(self,...)
            end
            if type(newcclosure)=='function' then wrapper=newcclosure(wrapper) end
            old=hookmetamethod(game,'__namecall',wrapper)
            if type(old)~='function' then error('No original namecall returned') end
            slot.installed=true
        end)
        if not ok then
            hookStatus='ERROR';status='Hook installation failed: '..redact(err);return
        end
    end
    outboundEnabled=true
    slot.sink=noteOutbound
    hookStatus='ON_METADATA_ONLY'
    log('OPTIONAL_OUTBOUND_HOOK_ENABLED (pass-through, metadata only)')
    status='Outbound observer ON. ARM, then manually collect ONE reward.'
end

local function arm()
    if used then status='Already attempted one observation.';return end
    if not ownerConfirmed or not bound or not boundPrompt or not boundPrompt.Parent then
        status='BIND and confirm your own machine first.';return
    end
    if not validCollect(boundPrompt) then status='Machine must show Collect now.';return end
    local d=distance(boundPrompt)
    if not d or d>boundPrompt.MaxActivationDistance then
        status='Stand inside normal prompt range for manual control.';return
    end
    used=true;active=true;ended=false
    endingAt=os.clock()+observationSeconds
    trial={events=0,dropped=0,entries={},totals={},before=boundPrompt.ActionText,
        after=boundPrompt.ActionText,changed=false,placeSeen=false,reward='UNKNOWN',
        startDistance=d,range=boundPrompt.MaxActivationDistance}
    log(string.format('ARM_MANUAL_20S dist=%.1f range=%.1f hook=%s',d,boundPrompt.MaxActivationDistance,hookStatus))
    status='ARMED! Manually collect within 2-4s. Do not press other buttons.'
end
local function markReward(v)
    if not trial then status='ARM observation first.';return end
    trial.reward=v
    log('REAL_REWARD_BY_PLAYER='..v)
    status='Reward '..v..'. COPY REPORT and paste into chat.'
end
local function stop()
    alive=false;active=false
    if type(hook)=='table' then hook.sink=nil end
    for _,c in ipairs(connections) do pcall(function()c:Disconnect()end) end
    if gui then gui:Destroy() end
    if env.CARAltPathStop==stop then env.CARAltPathStop=nil end
end
env.CARAltPathStop=stop

-- No remote requests are sent by this script. Listen to all proximity prompt triggers
-- and distinguish the machine being studied from other prompts.
connections[#connections+1]=PPS.PromptTriggered:Connect(function(p,who)
    if active and (who==me or who==nil) then
        local loc=(p==boundPrompt) and 'BOUND' or 'OTHER'
        addEvent('PROMPT_TRIGGERED',loc..' '..redact(p and p.Name))
    end
end)
connections[#connections+1]=PPS.PromptTriggerEnded:Connect(function(p,who)
    if active and (who==me or who==nil) then
        addEvent('PROMPT_TRIGGER_ENDED',(p==boundPrompt and 'BOUND' or 'OTHER'))
    end
end)

local function report()
    local lines={
        'CUT A ROCK | COLLECT ALTERNATE-PATH TRACE v1.0',
        'PlaceId='..game.PlaceId,
        'ResearchOnly=true NoPromptCalls=true NoDirectFireServer=true NoDirectInvokeServer=true',
        'SourceReadable=false ServerHandlersReadable=false',
        'ScanComplete='..tostring(scanDone)..' ScannedObjects='..scanCounts.objects,
        'ScannedLocalScripts='..scanCounts.locals..' ScannedModuleScripts='..scanCounts.modules,
        'ScannedRemoteEvents='..scanCounts.events..' ScannedRemoteFunctions='..scanCounts.functions,
        'InboundWatchers='..inboundWatched..' WatcherCap='..tostring(inboundCapped),
        'OptionalOutboundHook='..hookStatus,
        'MachineBound='..tostring(bound~=nil and bound.Parent~=nil),
        'Machine='..(bound and redact(bound.Name) or 'none'),
        'OwnerHint='..(bound and ownerHint(bound) or 'none'),
        'OwnerConfirmed='..tostring(ownerConfirmed),
        'Attempted='..tostring(used)..' ObservationEnded='..tostring(ended),
        'ObservationSeconds='..observationSeconds,
        'NOTE: inbound events and observed outbound method names are correlations, NOT verified Collect APIs',
        'NOTE: engine-native PromptTriggered is not necessarily visible to Lua __namecall hooks.',
        'NOTE: metadata observer hook remains pass-through until rejoin if enabled.',
        'NOTE: no game remote is sent or prompt fired; manual Collect only.',
    }
    if trial then
        lines[#lines+1]=string.format('StartDistance=%.1f PromptRange=%.1f',trial.startDistance,trial.range)
        lines[#lines+1]='PromptBefore='..redact(trial.before)
        lines[#lines+1]='PromptAfter='..redact(trial.after)
        lines[#lines+1]='PromptChanged='..tostring(trial.changed)
        lines[#lines+1]='PlaceRockSeen='..tostring(trial.placeSeen)
        lines[#lines+1]='RealRewardByPlayer='..trial.reward
        lines[#lines+1]='CapturedEvents='..trial.events..' DroppedEvents='..trial.dropped
        local kinds={}
        for k in pairs(trial.totals) do kinds[#kinds+1]=k end
        table.sort(kinds)
        for _,kind in ipairs(kinds) do lines[#lines+1]='TOTAL_'..kind..'='..trial.totals[kind] end
        lines[#lines+1]='--- EVENT TIMELINE ---'
        for _,v in ipairs(trial.entries) do lines[#lines+1]=v end
    end
    lines[#lines+1]='--- ALL REPLICATED REMOTE NAMES (NO PAYLOAD) ---'
    for _,v in ipairs(remoteNames) do lines[#lines+1]=v end
    lines[#lines+1]='--- SCRIPT NAME CANDIDATES (NO SOURCE) ---'
    for _,v in ipairs(scriptNames) do lines[#lines+1]=v end
    lines[#lines+1]='--- DIAGNOSTIC TIMELINE ---'
    for _,v in ipairs(logRows) do lines[#lines+1]=v end
    return table.concat(lines,'\n')
end
local function copyReport()
    local s=report()
    print(s)
    local cb=(type(setclipboard)=='function' and setclipboard)
        or (type(toclipboard)=='function' and toclipboard)
    if cb then
        local ok=pcall(cb,s)
        status=ok and 'Report copied; paste in chat.' or 'Copy failed; use executor console.'
    else status='Report printed to console; copy it from there.' end
end
local function mk(class,props,parent)
    local x=Instance.new(class)
    for k,v in pairs(props) do x[k]=v end
    x.Parent=parent
    return x
end
gui=mk('ScreenGui',{Name='CAR_Collect_AltPath_Trace_v1',ResetOnSpawn=false},pg)
panel=mk('Frame',{Size=UDim2.fromOffset(330,534),Position=UDim2.new(0,10,0.09,0),
    BackgroundColor3=Color3.fromRGB(23,29,42),BorderSizePixel=0,Active=true},gui)
mk('UICorner',{CornerRadius=UDim.new(0,11)},panel)
mk('UIStroke',{Color=Color3.fromRGB(74,109,139),Thickness=1},panel)
local title=mk('TextLabel',{Text='CAR | COLLECT ALT-PATH TRACE v1',Size=UDim2.fromOffset(280,38),
    Position=UDim2.fromOffset(10,5),BackgroundTransparency=1,
    TextColor3=Color3.fromRGB(240,245,251),Font=Enum.Font.GothamBold,TextSize=12,
    TextXAlignment=Enum.TextXAlignment.Left},panel)
label=mk('TextLabel',{Text='',Position=UDim2.fromOffset(11,44),Size=UDim2.fromOffset(306,114),
    BackgroundTransparency=1,TextColor3=Color3.fromRGB(207,220,236),TextWrapped=true,
    Font=Enum.Font.Gotham,TextSize=11,TextXAlignment=Enum.TextXAlignment.Left,
    TextYAlignment=Enum.TextYAlignment.Top},panel)
local function button(t,x,y,w,h,fn)
    local b=mk('TextButton',{Text=t,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),
        BackgroundColor3=Color3.fromRGB(47,79,110),TextColor3=Color3.new(1,1,1),
        BorderSizePixel=0,Font=Enum.Font.GothamMedium,TextSize=11},panel)
    mk('UICorner',{CornerRadius=UDim.new(0,7)},b)
    connections[#connections+1]=b.Activated:Connect(fn)
    return b
end
button('X',289,8,30,29,stop)
button('1. SCAN ALL REMOTES',11,166,308,33,scan)
button('2. BIND NEAREST COLLECT',11,205,308,33,bindNearest)
button('3. CONFIRM MY MACHINE',11,244,308,33,confirmOwn)
button('OPTIONAL: ENABLE OUTBOUND TRACE',11,283,308,33,enableOutbound)
button('4. ARM MANUAL COLLECT 20s',11,322,308,38,arm)
button('REAL REWARD YES',11,367,148,33,function()markReward('YES')end)
button('NO REWARD',171,367,148,33,function()markReward('NO')end)
button('5. COPY REPORT',11,407,308,41,copyReport)
mk('TextLabel',{Text='One manual Collect only. No auto action. Outbound hook is OPTIONAL.',
    Position=UDim2.fromOffset(12,455),Size=UDim2.fromOffset(306,44),
    BackgroundTransparency=1,TextColor3=Color3.fromRGB(166,181,203),
    TextSize=10,TextWrapped=true,Font=Enum.Font.Gotham},panel)

local dragging=false
local firstTouch,oldPosition
connections[#connections+1]=title.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
        dragging=true;firstTouch=input.Position;oldPosition=panel.Position
        local cc
        cc=input.Changed:Connect(function()
            if input.UserInputState==Enum.UserInputState.End then
                dragging=false;cc:Disconnect()
            end
        end)
    end
end)
connections[#connections+1]=UIS.InputChanged:Connect(function(input)
    if dragging and firstTouch and
       (input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseMovement) then
        local d=input.Position-firstTouch
        panel.Position=UDim2.new(oldPosition.X.Scale,oldPosition.X.Offset+d.X,
            oldPosition.Y.Scale,oldPosition.Y.Offset+d.Y)
    end
end)
log('LOADED inbound watchers='..inboundWatched..' optional outbound OFF')
task.spawn(function()
    while alive do
        pcall(function()
            if active and trial then
                if boundPrompt and boundPrompt.Parent then
                    local a=boundPrompt.ActionText
                    if a~=trial.after then
                        trial.changed=true
                        trial.after=a
                        if a:lower():find('place rock',1,true) then trial.placeSeen=true end
                        addEvent('PROMPT_STATE',a)
                    end
                end
                if os.clock()>=endingAt then
                    active=false;ended=true
                    if type(hook)=='table' then hook.sink=nil end
                    log('WINDOW_DONE reward='..trial.reward)
                    status='Observation finished. Mark reward, then copy report.'
                end
            end
            local d=distance(boundPrompt)
            label.Text=string.format(
                'Remotes watched: %d | Remote objects: %d\nBound: %s | Distance: %s / %s\nOutbound: %s | Events: %s\nTrial: %s | Reward: %s\n%s',
                inboundWatched,scanCounts.events+scanCounts.functions,
                bound and bound.Name or 'none',d and string.format('%.1f',d) or '?',
                boundPrompt and string.format('%.1f',boundPrompt.MaxActivationDistance) or '?',
                hookStatus,trial and trial.events or 0,
                active and 'OBSERVING' or ended and 'DONE' or used and 'USED' or 'NONE',
                trial and trial.reward or '?',status)
        end)
        task.wait(0.10)
    end
end)
print('[CAR AltPath] Ready. Scan, bind, confirm, optional outbound observer, ARM 20s, manually Collect, verify reward, copy report.')

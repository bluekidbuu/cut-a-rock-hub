-- CUT A ROCK | PASSIVE COLLECT INSPECTOR v1.0
-- One-shot, read-only client observation of ONE normal manual Collect.
-- Does NOT fire prompts, send remotes, hook metamethods, teleport, or read script Source.
-- Source code is NOT readable in a live published Roblox experience by normal client APIs.
-- Only replicated script/remote instance metadata can be observed; server code is unavailable.
-- PlaceId=113742027864370, GameId=10766468833.
if not game:IsLoaded() then game.Loaded:Wait() end
if game.PlaceId ~= 113742027864370 and game.GameId ~= 10766468833 then
    warn('[CAR Passive Collect] Wrong Roblox game; not running.')
    return
end
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local PPS=game:GetService('ProximityPromptService')
local UIS=game:GetService('UserInputService')
local player=Players.LocalPlayer
local pg=player:WaitForChild('PlayerGui')
local env=(type(getgenv)=='function' and getgenv()) or _G
if type(env.CARPassiveCollectInspectorStop)=='function' then
    pcall(env.CARPassiveCollectInspectorStop)
end

local alive=true
local watched={}
local conns={}
local logLines={}
local scanned=false
local scanResult={scripts=0,localScripts=0,modules=0,remotes=0,functions=0,prompts=0,visited=0,limited=false}
local clientCandidates={}
local remoteCandidates={}
local inboundWatched=0
local inboundNames={}
local started=os.clock()
local bound=nil
local boundPrompt=nil
local ownershipConfirmed=false
local attempted=false
local active=false
local ended=false
local endingAt=0
local observationSeconds=12
local trial=nil
local status='Step 1: SCAN CLIENT (read-only), then BIND NEAREST.'
local gui,panel,statusLabel
local function stamp()return string.format('T+%.2fs',os.clock()-started)end
local function addLog(msg)
    logLines[#logLines+1]=stamp()..' '..tostring(msg)
    if #logLines>65 then table.remove(logLines,1)end
end
local function redact(s)
    s=tostring(s or '?')
    -- Redact player names, long number IDs and UUID-like strings from any output.
    local function literalPattern(v) return (v:gsub('([^%w])','%%%1')) end
    s=s:gsub(literalPattern(player.Name),'<player>')
    if player.DisplayName and player.DisplayName~='' then
        s=s:gsub(literalPattern(player.DisplayName),'<player>')
    end
    s=s:gsub('[%x]+%-%x+%-%x+%-%x+%-%x+','<uuid>')
    s=s:gsub('%d%d%d%d%d%d%d%d+','<id>')
    return s:sub(1,135)
end
local function create(class,props,parent)
    local obj=Instance.new(class)
    for k,v in pairs(props)do obj[k]=v end
    obj.Parent=parent
    return obj
end
local function ancestorLevel(obj)
    while obj and obj~=workspace do
        if obj:IsA('Model') and obj.Name:match('^level%d+$') then return obj end
        obj=obj.Parent
    end
end
local function promptOf(model)
    if not model or not model.Parent then return nil end
    for _,obj in ipairs(model:GetDescendants())do
        if obj:IsA('ProximityPrompt') and obj.Name=='CutMachinePrompt' then return obj end
    end
end
local function promptPosition(p)
    local q=p and p.Parent
    if q and q:IsA('Attachment') then return q.WorldPosition end
    if q and q:IsA('BasePart') then return q.Position end
    local part=q and q:FindFirstAncestorWhichIsA('BasePart')
    return part and part.Position or nil
end
local function distance(p)
    local ch=player.Character
    local root=ch and ch:FindFirstChild('HumanoidRootPart')
    local pos=promptPosition(p)
    if root and pos then return (root.Position-pos).Magnitude end
end
local ownerKeys={'OwnerUserId','PlayerUserId','UserId','Owner','OwnerName','PlayerName'}
local function ownerHint(model)
    local node=model
    while node and node~=workspace do
        for _,key in ipairs(ownerKeys)do
            local ok,v=pcall(function()return node:GetAttribute(key)end)
            if ok and v~=nil then
                local str=tostring(v)
                if str==tostring(player.UserId) or str:lower()==player.Name:lower() then return 'SELF' end
                return 'OTHER'
            end
        end
        node=node.Parent
    end
    return 'UNKNOWN'
end
local function isCollect(p)
    return p and p.Parent and p.Enabled and p.ActionText:lower():find('collect',1,true)~=nil
end
local function safePath(obj,root)
    local xs={}
    local cur=obj
    while cur and cur~=root and #xs<5 do
        table.insert(xs,1,redact(cur.Name))
        cur=cur.Parent
    end
    return redact(root.Name)..'/'..table.concat(xs,'/')
end
local interesting='collect|cut|machine|rock|stone|reward|result|kesim|aura|item|material|prompt|base'
local function relevant(name)
    local n=name:lower()
    for part in interesting:gmatch('[^|]+')do
        if n:find(part,1,true)then return true end
    end
    return false
end
local function pushLimited(arr,val,max)
    if #arr<max then arr[#arr+1]=val end
end
local function scanClient()
    if active then status='Finish manual Collect observation first.';return end
    local roots={RS,pg,game:GetService('ReplicatedFirst')}
    local playerScripts=player:FindFirstChild('PlayerScripts')
    if playerScripts then roots[#roots+1]=playerScripts end
    local models=workspace:FindFirstChild('Models')
    local bases=models and models:FindFirstChild('Bases')
    if bases then roots[#roots+1]=bases end
    local counts={scripts=0,localScripts=0,modules=0,remotes=0,functions=0,prompts=0,visited=0,limited=false}
    local scripts,remotes={},{}
    for _,root in ipairs(roots)do
        if root then
            local ok,items=pcall(function()return root:GetDescendants()end)
            if ok then
                for _,obj in ipairs(items)do
                    counts.visited=counts.visited+1
                    if counts.visited>30000 then counts.limited=true;break end
                    local typ=obj.ClassName
                    local name=obj.Name
                    local where=safePath(obj,root)
                    if typ=='LocalScript' or typ=='ModuleScript' then
                        counts.scripts=counts.scripts+1
                        if typ=='LocalScript' then counts.localScripts=counts.localScripts+1
                        else counts.modules=counts.modules+1 end
                        if relevant(name) or relevant(where) then
                            pushLimited(scripts,typ..' '..where,45)
                        end
                    elseif typ=='RemoteEvent' or typ=='RemoteFunction' then
                        counts.remotes=counts.remotes+1
                        if typ=='RemoteFunction' then counts.functions=counts.functions+1 end
                        if relevant(name) or relevant(where) then
                            pushLimited(remotes,typ..' '..where,60)
                        end
                    elseif typ=='ProximityPrompt' and name=='CutMachinePrompt' then
                        counts.prompts=counts.prompts+1
                    end
                end
            else addLog('SCAN_ERROR root='..redact(root.Name)) end
        end
        if counts.limited then break end
    end
    table.sort(scripts)
    table.sort(remotes)
    scanResult,clientCandidates,remoteCandidates=counts,scripts,remotes
    scanned=true
    status='Scan completed (metadata ONLY). Bind one ready machine.'
    addLog(string.format('SCAN scripts=%d remotes=%d candidateScripts=%d candidateRemotes=%d limited=%s',
        counts.scripts,counts.remotes,#scripts,#remotes,tostring(counts.limited)))
end
local function bindNearest()
    if attempted or active then status='One-shot observer already used; rerun script for another test.';return end
    local best,bestPrompt,bestDistance=nil,nil,math.huge
    local root=workspace:FindFirstChild('Models')
    local bases=root and root:FindFirstChild('Bases')
    if not bases then status='Workspace.Models.Bases not replicated/visible.';return end
    for _,obj in ipairs(bases:GetDescendants())do
        if obj:IsA('ProximityPrompt') and obj.Name=='CutMachinePrompt' and isCollect(obj)then
            local model=ancestorLevel(obj)
            local d=distance(obj)
            if model and ownerHint(model)~='OTHER' and d and d<=obj.MaxActivationDistance
                and d<bestDistance then
                best,bestPrompt,bestDistance=model,obj,d
            end
        end
    end
    if not best then
        status='No eligible ready machine nearby. Approach YOUR machine showing Collect.'
        return
    end
    bound,boundPrompt=best,bestPrompt
    ownershipConfirmed=false
    status=string.format('Bound %s at %.1f studs. CONFIRM YOUR MACHINE.',redact(best.Name),bestDistance)
    addLog(string.format('BIND model=%s dist=%.1f range=%.1f ownerHint=%s',
        redact(best.Name),bestDistance,bestPrompt.MaxActivationDistance,ownerHint(best)))
end
local function confirmOwnership()
    if not bound or not bound.Parent or not boundPrompt or not boundPrompt.Parent then
        status='Bind a ready machine first.';return
    end
    if ownerHint(bound)=='OTHER' then status='Owner mismatch. Cannot continue.';return end
    ownershipConfirmed=true
    status='Ownership confirmed. ARM then collect normally by hand.'
    addLog('OWNER_CONFIRMED_BY_PLAYER ownerHint='..ownerHint(bound))
end
local function noteEvent(kind,p)
    if not alive or not active or not trial or p~=boundPrompt then return end
    trial.events[kind]=(trial.events[kind] or 0)+1
    addLog('PROMPT_EVENT '..kind..' distance='..string.format('%.1f',distance(p) or -1))
end
local function arm()
    if attempted then status='One-shot used; rerun this diagnostic for another observation.';return end
    if not ownershipConfirmed or not bound or not boundPrompt then
        status='BIND and CONFIRM YOUR MACHINE first.';return
    end
    local p=boundPrompt
    local d=distance(p)
    if not isCollect(p) then status='Machine must currently show Collect.';return end
    if not d or d>p.MaxActivationDistance then status='Stand inside normal prompt range.';return end
    attempted=true
    active=true
    ended=false
    endingAt=os.clock()+observationSeconds
    trial={before=p.ActionText,after=p.ActionText,dist=d,range=p.MaxActivationDistance,
        promptChanged=false,placeRock=false,events={},inbound={},reward='UNKNOWN',
        hold=p.HoldDuration,enabled=p.Enabled,start=os.clock()}
    addLog(string.format('ARM_MANUAL_ONE_SHOT distance=%.1f range=%.1f hold=%.2f before=%s',
        d,p.MaxActivationDistance,p.HoldDuration,redact(p.ActionText)))
    status='ARMED 12s. Perform ONE NORMAL MANUAL Collect. Verify real reward.'
end
local function markReward(answer)
    if not trial then status='ARM first; then collect manually.';return end
    trial.reward=answer
    addLog('PLAYER_VERIFIED_REAL_REWARD='..answer)
    status='Reward='..answer..'. COPY REPORT and paste into ChatGPT.'
end
local function stop()
    if not alive then return end
    alive=false
    active=false
    for _,c in ipairs(conns)do pcall(function()c:Disconnect()end)end
    if gui then gui:Destroy()end
    if env.CARPassiveCollectInspectorStop==stop then env.CARPassiveCollectInspectorStop=nil end
end
env.CARPassiveCollectInspectorStop=stop

local function buildReport()
    local out={
        'CUT A ROCK | PASSIVE COLLECT INSPECTOR v1.0',
        'PlaceId='..tostring(game.PlaceId),
        'ReadOnly=true NoPromptCalls=true NoFireServer=true NoInvokeServer=true NoHooks=true',
        'SourceReadable=false ServerScriptsReadable=false',
        'ScanCompleted='..tostring(scanned),
        'ScannedInstances='..scanResult.visited..' ScanTruncated='..tostring(scanResult.limited),
        'LocalScripts='..scanResult.localScripts..' ModuleScripts='..scanResult.modules,
        'RemoteEvents='..(scanResult.remotes-scanResult.functions)..' RemoteFunctions='..scanResult.functions,
        'CutMachinePrompts='..scanResult.prompts,
        'MatchingScriptCandidates='..#clientCandidates,
        'MatchingRemoteCandidates='..#remoteCandidates,
        'InboundWatchers='..inboundWatched,
        'Bound='..tostring(bound~=nil and bound.Parent~=nil),
        'Machine='..(bound and redact(bound.Name) or 'NONE'),
        'OwnerHint='..(bound and ownerHint(bound) or 'NONE'),
        'OwnershipConfirmed='..tostring(ownershipConfirmed),
        'Armed='..tostring(attempted)..' ObservationEnded='..tostring(ended)
    }
    if trial then
        out[#out+1]=string.format('Distance=%.1f PromptRange=%.1f HoldDuration=%.2f PromptEnabled=%s',
            trial.dist,trial.range,trial.hold,tostring(trial.enabled))
        out[#out+1]='PromptBefore='..redact(trial.before)
        out[#out+1]='PromptAfter='..redact(trial.after)
        out[#out+1]='PromptChanged='..tostring(trial.promptChanged)..' PlaceRockSeen='..tostring(trial.placeRock)
        out[#out+1]='RealRewardByPlayer='..trial.reward
        for _,k in ipairs({'TRIGGERED','HOLD_BEGAN','HOLD_ENDED','TRIGGER_ENDED','SHOWN','HIDDEN'})do
            out[#out+1]='Prompt_'..k..'='..(trial.events[k] or 0)
        end
        local keys={}
        for k in pairs(trial.inbound)do keys[#keys+1]=k end
        table.sort(keys)
        for _,k in ipairs(keys)do out[#out+1]='INBOUND_'..redact(k)..'='..trial.inbound[k] end
    else out[#out+1]='Trial=NOT_ARMED' end
    -- 'Place Rock' observed after a successful Collect is a client state indicator only.
    out[#out+1]='--- REPLICATED SCRIPT CANDIDATES (NAMES ONLY) ---'
    for _,v in ipairs(clientCandidates)do out[#out+1]=v end
    out[#out+1]='--- REPLICATED REMOTE CANDIDATES (NAMES ONLY) ---'
    for _,v in ipairs(remoteCandidates)do out[#out+1]=v end
    out[#out+1]='--- TIMELINE ---'
    for _,v in ipairs(logLines)do out[#out+1]=v end
    out[#out+1]='NOTE: This cannot reveal server handlers, read script Source, or prove remote request causality.'
    out[#out+1]='NOTE: OnClientEvent messages are inbound notifications, not a demonstrated collect API.'
    out[#out+1]='NOTE: Player-confirmed reward is separate from prompt and notification signals.'
    return table.concat(out,'\n')
end
local function copyReport()
    local r=buildReport()
    print(r)
    local clip=type(setclipboard)=='function' and setclipboard
        or type(toclipboard)=='function' and toclipboard or nil
    if clip and pcall(clip,r) then status='Report copied. Paste into ChatGPT.'
    else status='Report printed to executor console. Copy from there.' end
end

-- Passive watchers: only existing replicated events with relevant names.
local function watchInbound(obj)
    if not alive or not obj:IsA('RemoteEvent') or watched[obj] or inboundWatched>=90 then return end
    if not relevant(obj.Name) then return end
    watched[obj]=true
    local ok,c=pcall(function()
        return obj.OnClientEvent:Connect(function(...)
            if not alive or not active or not trial or os.clock()>endingAt then return end
            local name=redact(obj.Name)
            trial.inbound[name]=(trial.inbound[name] or 0)+1
            addLog('INBOUND '..name..' argCount='..select('#',...))
        end)
    end)
    if ok and c then
        inboundWatched=inboundWatched+1
        conns[#conns+1]=c
    end
end
for _,obj in ipairs(RS:GetDescendants())do watchInbound(obj)end
conns[#conns+1]=RS.DescendantAdded:Connect(watchInbound)
-- Service events are observed but never fired by this diagnostic.
conns[#conns+1]=PPS.PromptTriggered:Connect(function(p,who) if who==player or who==nil then noteEvent('TRIGGERED',p)end end)
conns[#conns+1]=PPS.PromptButtonHoldBegan:Connect(function(p,who) if who==player or who==nil then noteEvent('HOLD_BEGAN',p)end end)
conns[#conns+1]=PPS.PromptButtonHoldEnded:Connect(function(p,who) if who==player or who==nil then noteEvent('HOLD_ENDED',p)end end)
conns[#conns+1]=PPS.PromptTriggerEnded:Connect(function(p,who) if who==player or who==nil then noteEvent('TRIGGER_ENDED',p)end end)
conns[#conns+1]=PPS.PromptShown:Connect(function(p)noteEvent('SHOWN',p)end)
conns[#conns+1]=PPS.PromptHidden:Connect(function(p)noteEvent('HIDDEN',p)end)
addLog('LOADED passive; subscribed relevant inbound events='..inboundWatched)

-- Compact, draggable Android GUI; no changes to any game objects beyond own ScreenGui.
gui=create('ScreenGui',{Name='CAR_PassiveCollectInspector_v1',ResetOnSpawn=false,
    ZIndexBehavior=Enum.ZIndexBehavior.Sibling},pg)
panel=create('Frame',{Size=UDim2.fromOffset(318,417),Position=UDim2.new(0,10,0.14,0),
    BackgroundColor3=Color3.fromRGB(23,29,41),BorderSizePixel=0,Active=true},gui)
create('UICorner',{CornerRadius=UDim.new(0,10)},panel)
create('UIStroke',{Color=Color3.fromRGB(85,108,139),Thickness=1},panel)
local title=create('TextLabel',{Text='CAR | PASSIVE COLLECT INSPECTOR v1',Size=UDim2.fromOffset(272,30),
    Position=UDim2.fromOffset(10,5),BackgroundTransparency=1,Font=Enum.Font.GothamBold,
    TextSize=12,TextXAlignment=Enum.TextXAlignment.Left,TextColor3=Color3.new(1,1,1)},panel)
local function button(txt,x,y,w,h,fn)
    local b=create('TextButton',{Text=txt,Size=UDim2.fromOffset(w,h),Position=UDim2.fromOffset(x,y),
        BackgroundColor3=Color3.fromRGB(47,80,112),BorderSizePixel=0,Font=Enum.Font.GothamMedium,
        TextColor3=Color3.new(1,1,1),TextSize=11},panel)
    create('UICorner',{CornerRadius=UDim.new(0,6)},b)
    conns[#conns+1]=b.Activated:Connect(fn)
end
button('X',279,5,29,28,stop)
button('1. SCAN CLIENT (READ ONLY)',10,43,298,35,scanClient)
button('2. BIND NEAREST COLLECT',10,86,298,35,bindNearest)
button('3. CONFIRM MY MACHINE',10,129,298,35,confirmOwnership)
button('4. ARM MANUAL COLLECT (12s)',10,172,298,35,arm)
button('REWARD YES',10,216,143,32,function()markReward('YES')end)
button('REWARD NO',165,216,143,32,function()markReward('NO')end)
button('5. COPY REPORT',10,257,298,36,copyReport)
statusLabel=create('TextLabel',{Text='',Position=UDim2.fromOffset(11,305),Size=UDim2.fromOffset(296,103),
    BackgroundTransparency=1,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,
    TextWrapped=true,Font=Enum.Font.Gotham,TextSize=11,TextColor3=Color3.fromRGB(201,221,240)},panel)
local dragging,startPos,oldPos=false,nil,nil
conns[#conns+1]=title.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
        dragging=true;startPos=input.Position;oldPos=panel.Position
        local c
        c=input.Changed:Connect(function()
            if input.UserInputState==Enum.UserInputState.End then dragging=false;c:Disconnect()end
        end)
    end
end)
conns[#conns+1]=UIS.InputChanged:Connect(function(input)
    if dragging and startPos and (input.UserInputType==Enum.UserInputType.Touch
        or input.UserInputType==Enum.UserInputType.MouseMovement)then
        local delta=input.Position-startPos
        panel.Position=UDim2.new(oldPos.X.Scale,oldPos.X.Offset+delta.X,
            oldPos.Y.Scale,oldPos.Y.Offset+delta.Y)
    end
end)
task.spawn(function()
    while alive do
        pcall(function()
            if active and trial then
                local p=boundPrompt
                if p and p.Parent then
                    local a=p.ActionText
                    if a~=trial.after then
                        trial.after=a
                        trial.promptChanged=true
                        if a:lower():find('place rock',1,true)then trial.placeRock=true end
                        addLog('PROMPT_STATE_CHANGED='..redact(a))
                    end
                end
                if os.clock()>=endingAt then
                    active=false;ended=true
                    addLog('OBSERVATION_FINISHED reward='..trial.reward)
                    status='Observation ended. Mark actual reward and COPY REPORT.'
                end
            end
            local d=distance(boundPrompt)
            statusLabel.Text=string.format('Scripts: %d  Remotes: %d  Listeners: %d\nMachine: %s  Distance: %s\nTrial: %s  Reward: %s\n%s',
                scanResult.scripts,scanResult.remotes,inboundWatched,
                bound and redact(bound.Name) or 'NONE',d and string.format('%.1f',d) or '?',
                active and 'OBSERVING' or (ended and 'DONE' or attempted and 'ARMED' or 'NOT STARTED'),
                trial and trial.reward or 'UNKNOWN',status)
        end)
        task.wait(0.20)
    end
end)
print('[CAR Passive Collect Inspector] Ready: SCAN, BIND, CONFIRM, ARM, manual Collect, verify REAL reward, COPY REPORT. No remote calls or prompt simulation.')

-- Cut A Rock | Combined Auto Cut v1.8 + Multi Collect v1.0 | COMBINED v1.0
-- One executor script, one machine list, one mobile UI.
-- Auto Cut retains the user-verified 20-second Cep age gate and round-robin.
-- Auto Collect uses the user-verified fireproximityprompt method.
-- WARNING: distant Collect can leave a stale local prompt; do not retry blindly.
-- Neither module purchases, teleports, guesses UUIDs, or calls InstantCutEvent.
-- Only bind/confirm machines in your own base. Session limits: 60 Cut / 36 Collect.

if not game:IsLoaded() then game.Loaded:Wait() end
if game.PlaceId ~= 113742027864370 and game.GameId ~= 10766468833 then
    warn('[CAR MultiCut] This script is only for Cut a Rock.')
    return
end

local Players=game:GetService('Players')
local PPS=game:GetService('ProximityPromptService')
local UIS=game:GetService('UserInputService')
local RS=game:GetService('ReplicatedStorage')
local player=Players.LocalPlayer
local pg=player:WaitForChild('PlayerGui')
local remote=RS:FindFirstChild('PlaceStoneInMachineEvent')
local env=type(getgenv)=='function' and getgenv() or _G
for _, key in ipairs({'CARCombinedStop','CARMultiCutStop','CARMultiCollectStop'}) do
    if type(env[key])=='function' then pcall(env[key]) end
end

local alive,auto,busy=true,false,false
local collectAuto,collectBusy=false,false
local collectSupported=(type(fireproximityprompt)=='function')
local collectCalls,collectOK,collectErrors,collectTransitions=0,0,0,0
local collectBatches,collectUserConfirmed=0,0
local collectCap,collectMinimumGap=36,2.0
local collectLastSendAt=-1000
local collectNextIndex=1
local collectLastBatch=0
local collectLastBatchVerified=false
local machines={} -- explicit bound machine instances (not all nearby models)
local machineIndex={}
local preview={}
local anchor=nil
local stones={} -- captured from Player.Cep events or optional UI, UUID -> {seen,source,order}
local spent={} -- never reuse a stone UUID within this script session
local connections={}
local logs={}
local capturedAt=0
local captures,sends,confirmed,unconfirmed,localErrors=0,0,0,0,0
local lateConfirmed,holdReleased,hardHolds=0,0,0
local consecutiveUnconfirmed=0
local nextMachineIndex=1
local cepCaptured,uiCaptured,duplicateIds,expiredIds,cepEvents=0,0,0,0,0
local nextOrder=0
local witnessedCepInstances=setmetatable({}, {__mode="k"}) -- ignore repeat polling of same Folder
local lastMessage='Bind your machines, enable AUTO FILL, then collect new rocks.'
local maxSends=60 -- explicit bounded safety limit; restart manually after cap
local maxQueue=160
local stoneTTL=900 -- discard UUIDs older than 15 minutes without attempting
local minStoneAge=20 -- EXPERIMENT: allow longer inventory/server synchronization, not proof
local sendEvidence={} -- anonymized per-send diagnostics, never stores UUIDs
local started=os.clock()

local function record(msg)
    logs[#logs+1]=string.format('T+%.1fs %s',os.clock()-started,tostring(msg))
    if #logs>80 then table.remove(logs,1) end
end
local function uuid(v)
    return type(v)=='string' and v:match('^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$')~=nil
end
local function safePath(o)
    if not o or not o.Parent then return 'removed' end
    local ok,result=pcall(function()return o:GetFullName()end)
    return ok and result or o.Name
end
local function isUnder(obj,parent)
    while obj do if obj==parent then return true end; obj=obj.Parent end
    return false
end
local function ancestorLevel(o)
    local p=o
    while p and p~=workspace do
        if p:IsA('Model') and p.Name:match('^level%d+$') then return p end
        p=p.Parent
    end
end
local function promptOf(m)
    if not m or not m.Parent then return nil end
    for _,v in ipairs(m:GetDescendants()) do
        if v:IsA('ProximityPrompt') and v.Name=='CutMachinePrompt' then return v end
    end
end
local function promptPosition(p)
    local par=p and p.Parent
    if par and par:IsA('Attachment') then return par.WorldPosition end
    if par and par:IsA('BasePart') then return par.Position end
    local q=par and par:FindFirstAncestorWhichIsA('BasePart')
    return q and q.Position
end
local function playerRoot()
    return player.Character and player.Character:FindFirstChild('HumanoidRootPart')
end
local function distanceTo(model)
    local p=promptOf(model)
    local pos=promptPosition(p)
    local root=playerRoot()
    return pos and root and (pos-root.Position).Magnitude or nil
end
local function ownerHint(model)
    -- A mismatched explicit ID/name on the model itself prevents a mass bind.
    -- The absence of an owner attribute is NOT proof of ownership.
    for _,key in ipairs({'OwnerUserId','PlayerUserId','Owner','OwnerName','PlayerName','UserId'}) do
        local value=model:GetAttribute(key)
        if value~=nil then
            local v=tostring(value)
            if v==tostring(player.UserId) or v:lower()==player.Name:lower() then return 'match' end
            return 'other'
        end
    end
    return 'unknown'
end
local function bindMachine(model,via)
    if not model or not model.Parent or not promptOf(model) or ownerHint(model)=='other' then return false end
    if machineIndex[model] then return true end
    machineIndex[model]=true
    local p=promptOf(model)
    local collectAtBind=p and p.Enabled and p.ActionText:lower():find('collect',1,true)~=nil
    machines[#machines+1]={model=model,via=via,last=0,filled=0,
        holdUntil=0,misses=0,locked=false,uncertain=nil,
        collectArmed=collectAtBind or false,collectLastState=p and p.ActionText or 'MISSING',
        collectAttempts=0,collectOK=0,collectObserved=0,
        collectLastAttempt=-1000,collectLastDistance=nil,collectLastResult='NONE'}
    anchor=model
    lastMessage='Bound '..model.Name..'. Total machines: '..#machines
    record('BIND '..safePath(model)..' via='..via)
    return true
end
local function findNearest()
    local root=playerRoot()
    if not root then return nil end
    local best,dBest=nil,math.huge
    for _,p in ipairs(workspace:GetDescendants()) do
        if p:IsA('ProximityPrompt') and p.Name=='CutMachinePrompt' then
            local model=ancestorLevel(p)
            local pos=promptPosition(p)
            if model and pos and ownerHint(model)~='other' then
                local d=(root.Position-pos).Magnitude
                if d<=p.MaxActivationDistance+1 and d<dBest then
                    best,dBest=model,d
                end
            end
        end
    end
    return best
end
connections[#connections+1]=PPS.PromptTriggered:Connect(function(p,who)
    if not alive or not p or p.Name~='CutMachinePrompt' then return end
    if who and who~=player then return end
    local model=ancestorLevel(p)
    if model then bindMachine(model,'MANUAL_PROMPT') end
end)
local function visible(o)
    if not o or not o.Parent or not o:IsA('GuiObject') then return false end
    if o.AbsoluteSize.X<5 or o.AbsoluteSize.Y<5 then return false end
    local p=o
    while p and p~=pg do
        if p:IsA('GuiObject') and not p.Visible then return false end
        if p:IsA('ScreenGui') and not p.Enabled then return false end
        p=p.Parent
    end
    return true
end
local function excludedFromStoneCards(o)
    local p=o
    while p and p~=pg do
        if p.Name=='CurrentCut' or p.Name=='FinishCard'
            or p.Name=='KesimPaneli' or p.Name=='CutStoneTab'
            or p.Name=='StonePhoto' or p.Name=='SellMenu' then
            return true
        end
        p=p.Parent
    end
    return false
end
local function countCaptured()
    local n=0
    for _ in pairs(stones) do n+=1 end
    return n
end
local function countAvailable()
    local n=0
    for id in pairs(stones) do if not spent[id] then n+=1 end end
    return n
end
local function pruneQueue()
    local now=os.clock()
    for id,entry in pairs(stones) do
        if (now-entry.seen)>stoneTTL then
            if not spent[id] then expiredIds+=1 end
            stones[id]=nil
        end
    end
end
local function ingestStone(id,source)
    if not uuid(id) then return false end
    if spent[id] or stones[id] then duplicateIds+=1;return false end
    pruneQueue()
    if countCaptured()>=maxQueue then
        lastMessage='Stone queue full; AUTO remains paused for new IDs until queue clears.'
        record('QUEUE_LIMIT reached, ignored one candidate')
        return false
    end
    nextOrder+=1
    stones[id]={seen=os.clock(),source=source,order=nextOrder}
    capturedAt=os.clock()
    if source=='Cep' then cepCaptured+=1 else uiCaptured+=1 end
    record('STONE_NEW source='..source..' available='..countAvailable())
    return true
end
-- Trace v1.4 showed exact matching UUID-named Folders under Player.Cep.
-- Restrict to that proven structure; not all arbitrary UUIDs on the client.
local function ingestCepFolder(node)
    if not alive or not node or not node:IsA('Folder') or not uuid(node.Name) then return end
    local parent=node.Parent
    if not parent or parent.Name~='Cep' or not isUnder(parent,player) or isUnder(parent,pg) then return end
    if witnessedCepInstances[node] then return end
    witnessedCepInstances[node]=true
    ingestStone(node.Name,'Cep')
end
local function scanCep()
    local cep=player:FindFirstChild('Cep')
    if not cep then return end
    for _,node in ipairs(cep:GetChildren()) do ingestCepFolder(node) end
end
connections[#connections+1]=player.DescendantAdded:Connect(function(node)
    if not alive then return end
    if node:IsA('Folder') and uuid(node.Name) then
        local parent=node.Parent
        if parent and parent.Name=='Cep' and isUnder(parent,player) then
            cepEvents+=1
            ingestCepFolder(node)
        end
    end
end)
local function scanStones()
    local cutting=pg:FindFirstChild('CuttingMenu')
    local inventory=pg:FindFirstChild('InventoryMenu')
    local observed,added=0,0
    for _,obj in ipairs(pg:GetDescendants()) do
        if obj:IsA('GuiButton') and uuid(obj.Name) and visible(obj)
            and not excludedFromStoneCards(obj)
            and ((cutting and isUnder(obj,cutting)) or (inventory and isUnder(obj,inventory))) then
            observed+=1
            if ingestStone(obj.Name,'Menu') then added+=1 end
        end
    end
    captures+=1
    record('MENU_IMPORT visible='..observed..' new='..added..' available='..countAvailable())
    if observed==0 then
        lastMessage='No visible stone cards; new Cep stones will still be captured automatically.'
    else
        lastMessage='Imported '..added..' new stone IDs from '..observed..' visible cards.'
    end
    return observed
end
local function previewBase()
    preview={}
    if not anchor or not anchor.Parent then
        lastMessage='Bind a machine by prompt first.'
        return
    end
    local parent=anchor.Parent
    for _,m in ipairs(parent:GetChildren()) do
        if m:IsA('Model') and m.Name:match('^level%d+$') and promptOf(m) then
            if ownerHint(m)~='other' then
                preview[#preview+1]=m
            end
        end
    end
    table.sort(preview,function(a,b)
        local la=tonumber(a.Name:match('%d+')) or 0
        local lb=tonumber(b.Name:match('%d+')) or 0
        if la~=lb then return la<lb end
        return a.Name<b.Name
    end)
    lastMessage='Preview '..#preview..' sibling machines. Confirm ONLY if this base is yours.'
    record('PREVIEW parent='..safePath(parent)..' eligible='..#preview)
end
local function commitPreview()
    if #preview==0 then lastMessage='Preview first; nothing added.';return end
    local n=0
    for _,m in ipairs(preview) do
        if m.Parent and ownerHint(m)~='other' and not machineIndex[m] then
            if bindMachine(m,'CONFIRMED_SAME_BASE') then n+=1 end
        end
    end
    preview={}
    lastMessage='Added '..n..' machines. Bound total '..#machines
    record('CONFIRM_BASE added='..n)
end
local function nextStone()
    local chosenId,chosenEntry
    local now=os.clock()
    for id,entry in pairs(stones) do
        if not spent[id] and now-entry.seen>=minStoneAge
          and (not chosenEntry or entry.order<chosenEntry.order) then
            chosenId,chosenEntry=id,entry
        end
    end
    return chosenId,chosenEntry
end
local function machineNumber(model)
    for i,item in ipairs(machines) do
        if item.model==model then return i end
    end
    return 0
end
local function evidenceAdd(probe, age, source, machineNo)
    local e={number=sends,machine=machineNo,age=age,source=source,
        status='SENT',sentAt=os.clock()}
    sendEvidence[#sendEvidence+1]=e
    if #sendEvidence>30 then table.remove(sendEvidence,1) end
    probe.evidence=e
end
local function evidenceResult(probe,status)
    if probe and probe.evidence then probe.evidence.status=status end
end
local function readyMachine()
    -- Fair round-robin. v1.5 always chose the earliest idle machine and
    -- could starve machines #4-#6 even when all were ready.
    local n=#machines
    if n==0 then return nil end
    for offset=0,n-1 do
        local idx=((nextMachineIndex+offset-1)%n)+1
        local item=machines[idx]
        local model=item.model
        local p=promptOf(model)
        if model.Parent and p and p.Enabled and not item.uncertain
            and not item.locked and os.clock()>=item.holdUntil then
            local action=p.ActionText:lower()
            if action:find('place rock',1,true) and os.clock()-item.last>8 then
                nextMachineIndex=(idx%n)+1
                return item,p
            end
        end
    end
end
local function stopAuto(why)
    auto=false
    lastMessage=why
    record('AUTO_PAUSED '..why)
end
local function countHolds()
    local unknown,locked=0,0
    for _,item in ipairs(machines) do
        if item.uncertain then unknown+=1 end
        if item.locked then locked+=1 end
    end
    return unknown,locked
end
local function disconnectProbe(probe)
    if probe and probe.connection then
        pcall(function()probe.connection:Disconnect()end)
        probe.connection=nil
    end
end
local function reconcileHolds()
    for _,item in ipairs(machines) do
        local probe=item.uncertain
        if probe then
            local p=promptOf(item.model)
            local now=os.clock()
            local current=p and p.ActionText or 'MISSING'
            if probe.changedTo or (p and current~=probe.before) then
                item.filled+=1
                lateConfirmed+=1
                evidenceResult(probe,'LATE_CHANGED')
                item.misses=0
                consecutiveUnconfirmed=0
                item.holdUntil=now+8
                record('LATE_PROMPT_CHANGED slot='..machineNumber(item.model)..' '..item.model.Name
                    ..' after='..string.format('%.1fs',now-probe.sentAt))
                disconnectProbe(probe)
                item.uncertain=nil
                lastMessage='A delayed machine response was confirmed; continuing.'
            elseif now-probe.since>=22 then
                -- No definitive change. Never recycle the same stone ID.
                -- Cool down this machine, then allow a different ID only
                -- unless it has failed twice in this session.
                evidenceResult(probe,'UNCONFIRMED_FINAL')
                disconnectProbe(probe)
                item.uncertain=nil
                item.misses+=1
                if item.misses>=2 then
                    item.locked=true
                    hardHolds+=1
                    record('MACHINE_LOCKED slot='..machineNumber(item.model)..' '..item.model.Name
                        ..' two unconfirmed sends; inspect before RESET LOCKS')
                else
                    item.holdUntil=now+12
                    holdReleased+=1
                    record('MACHINE_RECHECK slot='..machineNumber(item.model)..' '..item.model.Name
                        ..' no change; held for 12 more seconds')
                end
            end
        end
    end
end
local function attemptOne()
    if not auto or busy or collectBusy or not alive then return end
    if not remote or not remote:IsA('RemoteEvent') then
        stopAuto('PlaceStoneInMachineEvent missing')
        return
    end
    if #machines==0 then stopAuto('Bind your machines first');return end
    if sends>=maxSends then stopAuto('Session cap '..maxSends..' reached; restart manually to continue.');return end
    pruneQueue()
    if countAvailable()==0 then return end -- await fresh Cep events
    -- Avoid racing against the player's manual actions in a visible menu.
    local cutMenu=pg:FindFirstChild('CuttingMenu')
    if cutMenu and cutMenu:IsA('ScreenGui') and cutMenu.Enabled then return end
    local item,p=readyMachine()
    if not item then return end
    local id,entry=nextStone()
    if not id then return end -- wait minStoneAge seconds to test inventory/server settling
    busy=true
    item.last=os.clock()
    spent[id]=true -- NEVER retry an uncertain UUID
    local before=p.ActionText
    local probe={before=before,changedTo=nil,sentAt=os.clock(),since=nil,connection=nil}
    local ageAtSend=os.clock()-entry.seen
    local slot=machineNumber(item.model)
    local connected,signalOrError=pcall(function()
        return p:GetPropertyChangedSignal('ActionText'):Connect(function()
            local action=p.ActionText
            if action~=before then probe.changedTo=action end
        end)
    end)
    if connected then probe.connection=signalOrError end
    local ok,err=pcall(function()
        remote:FireServer(item.model,id)
    end)
    sends+=1
    evidenceAdd(probe,ageAtSend,entry.source,slot)
    record('SEND slot='..slot..' level='..item.model.Name..' source='..entry.source
        ..' stoneAge='..string.format('%.1f',ageAtSend)..'s'
        ..' localOk='..tostring(ok)..' queued='..countAvailable())
    if not ok then
        disconnectProbe(probe)
        localErrors+=1
        evidenceResult(probe,'LOCAL_ERROR')
        busy=false
        stopAuto('Local error: '..tostring(err):sub(1,90))
        return
    end
    lastMessage='Sent to '..item.model.Name..'; observing prompt state...'
    local changed=false
    local observed='none'
    local endedAt=os.clock()+7
    repeat
        task.wait(0.10)
        if not alive then break end
        local now=promptOf(item.model)
        if probe.changedTo then
            observed=probe.changedTo
            changed=true
            break
        end
        if now and now.ActionText~=before then
            observed=now.ActionText
            changed=true
            break
        end
    until os.clock()>=endedAt
    if not alive then
        disconnectProbe(probe)
        busy=false
        return
    end
    if changed then
        disconnectProbe(probe)
        item.filled+=1
        item.misses=0
        item.holdUntil=os.clock()+8
        confirmed+=1
        evidenceResult(probe,'PROMPT_CHANGED')
        consecutiveUnconfirmed=0
        lastMessage='Confirmed '..item.model.Name..'; next machine in round-robin.'
        record('PROMPT_CHANGED slot='..slot..' '..item.model.Name..' from='..before..' to='..observed)
    else
        unconfirmed+=1
        consecutiveUnconfirmed+=1
        probe.since=os.clock()
        evidenceResult(probe,'UNCERTAIN_HOLD')
        item.uncertain=probe -- event listener stays live for late response
        lastMessage='One machine unconfirmed; holding that machine while checking others.'
        record('UNCONFIRMED_HOLD slot='..slot..' '..item.model.Name..' stoneAge='
            ..string.format('%.1f',ageAtSend)..'s after=7s; other machines may continue')
        if consecutiveUnconfirmed>=3 then
            stopAuto('3 consecutive unconfirmed responses: inspect machines/inventory before resuming.')
        end
    end
    busy=false
end


-- --------------------------- COLLECT CORE ---------------------------
-- Reuses the same bound machine Instances and the same CutMachinePrompt.
-- A Collect activation is attempted at most once per observed Collect cycle.
-- If a far call succeeds but the prompt remains stale, the machine stays disarmed.
local function isCollect(p)
    return p and p.Enabled and p.ActionText:lower():find('collect',1,true)~=nil
end
local function isNonCollectCycle(action)
    local a=tostring(action or ''):lower()
    return a:find('place rock',1,true)~=nil or a:find('cutting',1,true)~=nil
end
local function sampleCollectStates()
    for i,item in ipairs(machines) do
        local p=promptOf(item.model)
        local current=p and p.ActionText or 'MISSING'
        local old=item.collectLastState
        if current~=old then
            if isNonCollectCycle(current) then item.collectArmed=true end
            if item.collectAttempts>0 and old=='Collect' and isNonCollectCycle(current)
                and os.clock()-item.collectLastAttempt<20 then
                item.collectObserved+=1
                item.collectLastResult='PROMPT_TRANSITION'
                collectTransitions+=1
                record('COLLECT_TRANSITION slot='..i..' '..old..' -> '..current)
            end
            item.collectLastState=current
        end
    end
end
local function collectReadyCount()
    local count=0
    for _,item in ipairs(machines) do
        if item.collectArmed and isCollect(promptOf(item.model)) then count+=1 end
    end
    return count
end
local function attemptCollect(item,slot,origin)
    if not alive or not collectSupported then return false,'PROMPT_API_UNAVAILABLE' end
    if collectCalls>=collectCap then
        collectAuto=false
        lastMessage='Collect session cap reached; restart after review.'
        record('COLLECT_CAP_REACHED')
        return false,'CAP'
    end
    if ownerHint(item.model)=='other' then return false,'OTHER_OWNER' end
    local p=promptOf(item.model)
    if not isCollect(p) then return false,'NOT_COLLECT' end
    if not item.collectArmed then return false,'ALREADY_ATTEMPTED_THIS_CYCLE' end
    if os.clock()-item.collectLastAttempt<25 then return false,'PER_MACHINE_COOLDOWN' end
    local d=distanceTo(item.model)
    if not d then return false,'NO_DISTANCE' end
    local gap=os.clock()-collectLastSendAt
    if gap<collectMinimumGap then task.wait(collectMinimumGap-gap) end
    if not alive or busy then return false,'STOPPED_OR_CUT_BUSY' end
    p=promptOf(item.model)
    if not isCollect(p) then return false,'STATE_CHANGED_BEFORE_COLLECT' end
    item.collectArmed=false
    item.collectAttempts+=1
    item.collectLastAttempt=os.clock()
    item.collectLastDistance=d
    item.collectLastResult='SENT_UNVERIFIED'
    collectLastSendAt=os.clock()
    collectCalls+=1
    local ok,err=pcall(function() fireproximityprompt(p) end)
    if ok then
        collectOK+=1
        item.collectOK+=1
        record(string.format('COLLECT_SEND slot=%d origin=%s distance=%.1f localOk=true',slot,origin,d))
        lastMessage='Collect attempted at slot #'..slot..'; verify rewards. Prompt may lag when far.'
        return true,'SENT_UNVERIFIED'
    end
    collectErrors+=1
    item.collectLastResult='LOCAL_ERROR'
    record('COLLECT_LOCAL_ERROR slot='..slot..' '..tostring(err):sub(1,90))
    return false,'LOCAL_ERROR'
end
local function collectAutoTick()
    if not collectAuto or collectBusy or busy or not alive or #machines==0 then return end
    if not collectSupported then collectAuto=false;lastMessage='No fireproximityprompt in executor';return end
    if collectCalls>=collectCap then collectAuto=false;return end
    local n=#machines
    for offset=0,n-1 do
        local idx=((collectNextIndex+offset-1)%n)+1
        local item=machines[idx]
        if item.collectArmed and isCollect(promptOf(item.model)) then
            collectBusy=true
            collectNextIndex=(idx%n)+1
            local ok,why=attemptCollect(item,idx,'AUTO_WATCH')
            collectBusy=false
            if not ok and why=='LOCAL_ERROR' then
                lastMessage='Collect local error; inspect report before continuing.'
                collectAuto=false
            end
            return
        end
    end
end
local function collectBatch()
    if collectBusy or busy then lastMessage='Another Cut/Collect operation is busy.';return end
    if #machines==0 then lastMessage='Bind your machines first.';return end
    if not collectSupported then lastMessage='fireproximityprompt is unavailable.';return end
    collectBusy=true
    collectBatches+=1
    collectLastBatch=0
    collectLastBatchVerified=false
    record('COLLECT_BATCH_START ready='..collectReadyCount()..' machines='..#machines)
    task.spawn(function()
        for i,item in ipairs(machines) do
            if not alive then break end
            sampleCollectStates()
            local ok=attemptCollect(item,i,'BATCH_ONCE')
            if ok then collectLastBatch+=1 end
            task.wait(0.35)
        end
        collectBusy=false
        record('COLLECT_BATCH_END attempted='..collectLastBatch..' verified=unknown')
        if alive then lastMessage='Collect batch: '..collectLastBatch..' attempted. Verify actual rewards.' end
    end)
end

-- --------------------------- ONE PANEL UI ---------------------------
local gui=Instance.new('ScreenGui')
gui.Name='CAR_CutCollect_Combined_v1'
gui.ResetOnSpawn=false
gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
gui.Parent=pg
local function create(class,props,parent)
    local obj=Instance.new(class)
    for k,v in pairs(props) do obj[k]=v end
    obj.Parent=parent
    return obj
end
local panel=create('Frame',{
    Size=UDim2.fromOffset(336,514),Position=UDim2.new(0,12,0.055,0),
    BackgroundColor3=Color3.fromRGB(22,28,40),BorderSizePixel=0
},gui)
create('UICorner',{CornerRadius=UDim.new(0,11)},panel)
create('UIStroke',{Color=Color3.fromRGB(81,98,120),Thickness=1},panel)
local title=create('TextLabel',{
    Text='CUT A ROCK | CUT + COLLECT v1',TextSize=13,
    Font=Enum.Font.GothamBold,TextXAlignment=Enum.TextXAlignment.Left,
    Size=UDim2.fromOffset(264,33),Position=UDim2.fromOffset(10,2),
    BackgroundTransparency=1,TextColor3=Color3.new(1,1,1)
},panel)
local function button(text,x,y,w,h,callback)
    local b=create('TextButton',{
        Text=text,TextSize=11,Font=Enum.Font.GothamMedium,
        TextColor3=Color3.new(1,1,1),BackgroundColor3=Color3.fromRGB(50,76,108),
        Size=UDim2.fromOffset(w,h),Position=UDim2.fromOffset(x,y),
        BorderSizePixel=0
    },panel)
    create('UICorner',{CornerRadius=UDim.new(0,7)},b)
    if callback then connections[#connections+1]=b.Activated:Connect(function() callback(b) end) end
    return b
end
local info=create('TextLabel',{
    Position=UDim2.fromOffset(11,36),Size=UDim2.fromOffset(314,82),
    Text='Loading...',BackgroundTransparency=1,TextColor3=Color3.fromRGB(192,214,236),
    TextSize=11,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,
    TextYAlignment=Enum.TextYAlignment.Top,Font=Enum.Font.Gotham
},panel)
local function stop()
    if not alive then return end
    alive=false;auto=false;collectAuto=false
    for _,item in ipairs(machines) do disconnectProbe(item.uncertain) end
    for _,connection in ipairs(connections) do
        pcall(function()connection:Disconnect()end)
    end
    if gui and gui.Parent then gui:Destroy() end
    for _,key in ipairs({'CARCombinedStop','CARMultiCutStop','CARMultiCollectStop'}) do
        if env[key]==stop then env[key]=nil end
    end
end
env.CARCombinedStop=stop
env.CARMultiCutStop=stop
env.CARMultiCollectStop=stop
button('X',296,4,29,27,stop)
local minimized=false
local miniButton=button('-',268,4,25,27,function(b)
    minimized=not minimized
    panel.Size=UDim2.fromOffset(336,minimized and 34 or 514)
    for _,child in ipairs(panel:GetChildren()) do
        if child:IsA('GuiObject') and child~=title and child~=b then
            -- Keep close control visible too.
            if child:IsA('TextButton') and child.Text=='X' then
                child.Visible=true
            else
                child.Visible=not minimized
            end
        end
    end
    b.Text=minimized and '+' or '-'
end)
button('BIND NEAREST',11,122,153,34,function()
    local m=findNearest()
    if m then bindMachine(m,'NEAREST_IN_RANGE')
    else lastMessage='Move close to an owned machine to bind it.' end
end)
button('IMPORT MENU (opt.)',172,122,153,34,function()scanStones()end)
button('PREVIEW SAME BASE',11,164,153,34,previewBase)
button('ADD PREVIEW*',172,164,153,34,commitPreview)
local cutButton=button('AUTO FILL: OFF',11,206,314,42,function()
    if auto then
        stopAuto('Paused by user')
    else
        if busy then lastMessage='Wait for current Cut request.';return end
        if #machines==0 then lastMessage='Bind your machine(s) first.';return end
        auto=true
        record('AUTO_FILL_ON machines='..#machines..' queued='..countAvailable())
        lastMessage='Auto Fill active: new Cep IDs wait 20s; ready machines only.'
    end
end)
local collectButton=button('AUTO COLLECT: OFF',11,255,314,42,function()
    if collectAuto then
        collectAuto=false
        record('AUTO_COLLECT_OFF by user')
        lastMessage='Auto Collect paused.'
    else
        if #machines==0 then lastMessage='Bind your machine(s) first.';return end
        if not collectSupported then lastMessage='Executor has no fireproximityprompt.';return end
        if collectCalls>=collectCap then lastMessage='Collect cap reached; restart after checking.';return end
        collectAuto=true
        record('AUTO_COLLECT_ON machines='..#machines..' ready='..collectReadyCount())
        lastMessage='Auto Collect ON: one attempt per observed Collect cycle.'
    end
end)
button('COLLECT READY ONCE',11,306,153,35,collectBatch)
button('RESET CUT LOCKS',172,306,153,35,function()
    local count=0
    for _,item in ipairs(machines) do
        local p=promptOf(item.model)
        if item.locked and not item.uncertain and p and p.Enabled
            and p.ActionText:lower():find('place rock',1,true) then
            item.locked=false
            item.misses=0
            item.holdUntil=os.clock()+4
            count+=1
        end
    end
    record('RESET_CUT_LOCKS unlocked='..count)
    lastMessage='Reset '..count..' Cut-locked machines (only Place Rock state).'
end)
local function report()
    local unknown,locked=countHolds()
    local output={
        'CUT A ROCK COMBINED CUT + COLLECT v1',
        'PlaceId='..tostring(game.PlaceId),
        'BoundMachines='..#machines..' PreviewCandidates='..#preview,
        'AutoFill='..tostring(auto)..' CutBusy='..tostring(busy),
        'AutoCollect='..tostring(collectAuto)..' CollectBusy='..tostring(collectBusy),
        'PromptMethodAvailable='..tostring(collectSupported),
        'CepCaptured='..cepCaptured..' CepEvents='..cepEvents
           ..' MenuImported='..uiCaptured..' CapturedStoneIds='..countCaptured(),
        'AvailableStoneIds='..countAvailable()..' DuplicateIgnored='..duplicateIds
           ..' Expired='..expiredIds,
        'StoneReadyDelaySeconds='..minStoneAge..' StoneTTLSeconds='..stoneTTL,
        'CutRemoteSent='..sends..' PromptChanged='..confirmed
           ..' LateConfirmed='..lateConfirmed..' UnconfirmedTimeouts='..unconfirmed,
        'CutConsecutiveUnconfirmed='..consecutiveUnconfirmed
           ..' ActiveHolds='..unknown..' LockedMachines='..locked,
        'CutLocalErrors='..localErrors..' CutCap='..maxSends,
        'CollectPromptCalls='..collectCalls..' CollectLocalOK='..collectOK
           ..' CollectLocalErrors='..collectErrors..' CollectCap='..collectCap,
        'CollectPromptTransitions='..collectTransitions..' CollectReadyUnattempted='..collectReadyCount(),
        'CollectBatchRuns='..collectBatches..' UserVerifiedBatches='..collectUserConfirmed,
        'NOTE: Cut PROMPT_CHANGED suggests server accepted placement; no direct response was exposed.',
        'NOTE: A local Collect call is NOT proof of reward; distant prompts may remain stale.',
        'NOTE: A machine is NEVER automatically Collect-retried without a non-Collect transition.',
        'NOTE: Each stone UUID is spent on first Cut send and never auto-reused.',
        'NOTE: UUID strings and player identifiers are not exported.',
        '--- MACHINES ---'
    }
    for i,item in ipairs(machines) do
        local p=promptOf(item.model)
        local cutHold=item.uncertain and 'UNCERTAIN'
           or item.locked and 'LOCKED'
           or os.clock()<item.holdUntil and 'COOLDOWN' or 'none'
        output[#output+1]=string.format(
            '#%d %s | via=%s | state=%s | cutFilled=%d | cutHold=%s | cutMisses=%d',
            i,safePath(item.model),item.via,p and p.ActionText or 'MISSING',
            item.filled,cutHold,item.misses)
        output[#output+1]=string.format(
            '   collectArmed=%s collectAttempts=%d collectLocalOK=%d collectTransitions=%d lastDistance=%s lastResult=%s',
            tostring(item.collectArmed),item.collectAttempts,item.collectOK,item.collectObserved,
            item.collectLastDistance and string.format('%.1f',item.collectLastDistance) or '?',
            item.collectLastResult)
    end
    output[#output+1]='--- CUT SEND EVIDENCE ---'
    for _,entry in ipairs(sendEvidence) do
        output[#output+1]=string.format('Send#%d machine#%d source=%s age=%.1fs status=%s',
            entry.number,entry.machine,entry.source,entry.age,entry.status)
    end
    output[#output+1]='--- PREVIEW ---'
    for _,candidate in ipairs(preview) do
        output[#output+1]=safePath(candidate)..' ownerHint='..ownerHint(candidate)
    end
    output[#output+1]='--- TIMELINE ---'
    for _,line in ipairs(logs) do output[#output+1]=line end
    return table.concat(output,'\n')
end
button('COPY REPORT',11,348,153,35,function()
    local txt=report()
    print(txt)
    local clipboard=type(setclipboard)=='function' and setclipboard
        or type(toclipboard)=='function' and toclipboard or nil
    if clipboard and pcall(clipboard,txt) then
        lastMessage='Report copied; paste into ChatGPT.'
    else
        lastMessage='Clipboard unsupported; report printed to executor console.'
    end
end)
button('CONFIRM BATCH',172,348,153,35,function()
    if collectLastBatch>0 and not collectLastBatchVerified and not collectBusy then
        collectLastBatchVerified=true
        collectUserConfirmed+=1
        record('USER_CONFIRMED_COLLECT_BATCH attempts='..collectLastBatch)
        lastMessage='Marked last batch player-verified. Only use if rewards were received.'
    else
        lastMessage='First run COLLECT READY ONCE and verify actual rewards.'
    end
end)
create('TextLabel',{
    Text='*ADD PREVIEW only if the whole base is yours. One UI controls both modules.\nIf far Collect leaves prompt stale, it will not blindly retry.',
    Position=UDim2.fromOffset(11,392),Size=UDim2.fromOffset(314,42),
    BackgroundTransparency=1,TextSize=10,TextWrapped=true,
    TextColor3=Color3.fromRGB(166,187,209),Font=Enum.Font.Gotham
},panel)
local machineText=create('TextLabel',{
    Text='No machines bound.',Position=UDim2.fromOffset(11,444),
    Size=UDim2.fromOffset(314,60),BackgroundTransparency=1,
    TextSize=10,TextWrapped=true,TextColor3=Color3.fromRGB(178,200,219),
    TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,
    Font=Enum.Font.Gotham
},panel)
-- Mobile drag by title.
local dragging=false
local dragStart,dragOrigin
connections[#connections+1]=title.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.Touch
        or input.UserInputType==Enum.UserInputType.MouseButton1 then
        dragging=true
        dragStart=input.Position
        dragOrigin=panel.Position
        local con
        con=input.Changed:Connect(function()
            if input.UserInputState==Enum.UserInputState.End then
                dragging=false
                con:Disconnect()
            end
        end)
    end
end)
connections[#connections+1]=UIS.InputChanged:Connect(function(input)
    if dragging and dragStart
        and (input.UserInputType==Enum.UserInputType.Touch
          or input.UserInputType==Enum.UserInputType.MouseMovement) then
        local d=input.Position-dragStart
        panel.Position=UDim2.new(dragOrigin.X.Scale,dragOrigin.X.Offset+d.X,
            dragOrigin.Y.Scale,dragOrigin.Y.Offset+d.Y)
    end
end)

-- --------------------------- SHARED SCHEDULER ---------------------------
-- Cut has its verified 20s Cep age delay; Collect is independently toggled.
-- Both operate on the exact same machine Instances and never send concurrently.
task.spawn(function()
    while alive do
        local ok,err=pcall(attemptOne)
        if not ok then
            busy=false
            stopAuto('Cut unexpected error: '..tostring(err):sub(1,100))
        end
        task.wait(0.85)
    end
end)
task.spawn(function()
    while alive do
        pcall(scanCep)
        pcall(reconcileHolds)
        task.wait(0.5)
    end
end)
task.spawn(function()
    while alive do
        local ok,err=pcall(function()
            sampleCollectStates()
            if collectAuto then collectAutoTick() end
        end)
        if not ok then
            collectBusy=false
            collectAuto=false
            lastMessage='Collect loop error: '..tostring(err):sub(1,90)
            record('COLLECT_LOOP_ERROR '..tostring(err):sub(1,100))
        end
        task.wait(0.25)
    end
end)
task.spawn(function()
    while alive do
        pcall(function()
            cutButton.Text=auto and 'AUTO FILL: ON' or 'AUTO FILL: OFF'
            cutButton.BackgroundColor3=auto and Color3.fromRGB(32,122,86) or Color3.fromRGB(50,76,108)
            collectButton.Text=collectAuto and 'AUTO COLLECT: ON' or 'AUTO COLLECT: OFF'
            collectButton.BackgroundColor3=collectAuto and Color3.fromRGB(32,122,86) or Color3.fromRGB(50,76,108)
            info.Text=string.format(
                'Machines: %d | Cep: %d | Queued: %d\nCut: %d sent / %d changed / %d unknown\nCollect: %d calls / %d changed / %d ready\n%s',
                #machines,cepCaptured,countAvailable(),sends,confirmed+lateConfirmed,unconfirmed,
                collectCalls,collectTransitions,collectReadyCount(),lastMessage)
            local summary={}
            for i,item in ipairs(machines) do
                local p=promptOf(item.model)
                local state=p and p.ActionText or 'MISSING'
                local compact=state:find('Collect',1,true) and 'Collect'
                    or state:find('Place Rock',1,true) and 'Place'
                    or state:find('Cutting',1,true) and 'Cutting' or state
                summary[#summary+1]='#'..i..':'..compact
            end
            machineText.Text='Machines: '..(#summary>0 and table.concat(summary,' | ') or 'none')
                ..'\nPreview: '..#preview..' | Fill '..(auto and 'ON' or 'OFF')
                ..' | Collect '..(collectAuto and 'ON' or 'OFF')
                ..'\nStale Collect prompt may need client state refresh (no automatic retry).'
        end)
        task.wait(0.3)
    end
end)
scanCep()
record('COMBINED_LOADED passive; bind machines and enable Auto Fill/Auto Collect independently')
print('[CAR Combined] One script for Cut v1.8 + Multi Collect v1. Both modes OFF by default. Confirm your own base, enable both, COPY REPORT for audit.')

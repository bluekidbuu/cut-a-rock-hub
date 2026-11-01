-- CUT A ROCK | AUTO CUT + AUTO TRAIN | UNIFIED v1.3
-- Auto Cut v1.9: Player.Envanter (MAIN BACKPACK) is the sole stone readiness gate.
-- Audit v1 evidence: SHOP +1 in Envanter; MINING Cep-only; RETURN +1 in
-- Envanter; 3/3 CuttingMenu cards matched Player.Envanter IDs.
-- Cep is monitored for diagnostics ONLY, never sent to Cutting Machine.
-- Existing main inventory stones are scanned at startup; menus are optional.
-- Auto Train v3.2 replay logic is retained byte-for-byte from Unified v1.1.
-- Collect disabled; does not buy, mine, teleport, or use InstantCutEvent.

if not game:IsLoaded() then game.Loaded:Wait() end
if game.PlaceId~=113742027864370 and game.GameId~=10766468833 then
    warn('[CAR Unified] Wrong Roblox game')
    return
end
local player=game:GetService('Players').LocalPlayer
local pg=player:WaitForChild('PlayerGui')
local UIS=game:GetService('UserInputService')
local env=(type(getgenv)=='function' and getgenv()) or _G
for _,key in ipairs({'CARUnifiedCutTrainStop','CARCombinedStop','CARMultiCutStop',
    'CARMultiCollectStop','CutARockTrainV3Stop'}) do
    if type(env[key])=='function' then pcall(env[key]) end
end
-- Same engine code, isolated scopes to prevent event/state collisions.
local function initCut()
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
-- Existing versions are stopped once by the unified loader.

local alive,auto,busy=true,false,false
local machines={} -- explicit bound machine instances (not all nearby models)
local machineIndex={}
local preview={}
local anchor=nil
local stones={} -- ONLY IDs currently present in Player.Envanter (main backpack)
local spent={} -- never reuse a stone UUID within this script session
local connections={}
local logs={}
local capturedAt=0
local captures,sends,confirmed,unconfirmed,localErrors=0,0,0,0,0
local lateConfirmed,holdReleased,hardHolds=0,0,0
local consecutiveUnconfirmed=0
local nextMachineIndex=1
local cepObserved,uiCaptured,duplicateIds,expiredIds,cepEvents=0,0,0,0,0
local mainCaptured,mainAddEvents,mainRemoveEvents,mainScans,mainMissingDrops=0,0,0,0,0
local mainSourceObserved=false
local seenMainInstances=setmetatable({}, {__mode='k'})
-- Menu diagnostics distinguish a closed menu from already-known Cep IDs.
local menuScanCount,menuOpenEvents,menuVisibleLast,menuVisiblePeak=0,0,0,0
local menuKnownLast,menuSpentLast,menuNewLast=0,0,0
local menuWasOpen,menuHasEverShownCards=false,false
local manualImportAttempts,lastManualVisible,lastManualAdded=0,0,0
local nextOrder=0
local witnessedCepInstances=setmetatable({}, {__mode="k"}) -- diagnostic ONLY
local lastMessage='Bind your machines, enable AUTO FILL, then collect new rocks.'
local maxSends=60 -- explicit bounded safety limit; restart manually after cap
local maxQueue=160
local stoneTTL=0 -- disabled: availability is checked against live Player.Envanter
local minStoneAge=0 -- no age gate; Envanter membership is required before every send
local sendEvidence={} -- anonymized per-send diagnostics, never stores UUIDs
local started=os.clock()

local function record(msg)
    logs[#logs+1]=string.format('T+%.1fs %s',os.clock()-started,tostring(msg))
    if #logs>40 then table.remove(logs,1) end
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
    if not model or not model.Parent or not promptOf(model) then return false end
    if machineIndex[model] then return true end
    machineIndex[model]=true
    machines[#machines+1]={model=model,via=via,last=0,filled=0,
        holdUntil=0,misses=0,locked=false,uncertain=nil}
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
            if model and pos then
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
-- Audited: direct UUID-named children of Players.LocalPlayer.Envanter.
-- Unlike Cep, this source remained absent in Mining and gained the item
-- only after return to base. An ID in Envanter is a candidate, not a server ACK.
local function mainInventory()
    local n=player:FindFirstChild('Envanter')
    return n and (n:IsA('Folder') or n:IsA('Model')) and n or nil
end
local function inMain(id)
    local folder=mainInventory()
    return folder~=nil and folder:FindFirstChild(id)~=nil
end
local function currentMainCount()
    local folder=mainInventory()
    local n=0
    if folder then
        for _,obj in ipairs(folder:GetChildren()) do
            if uuid(obj.Name) then n+=1 end
        end
    end
    return n
end
local function countCaptured()
    local n=0
    for _ in pairs(stones) do n+=1 end
    return n
end
local function countAvailable()
    local n=0
    for id in pairs(stones) do
        if not spent[id] and inMain(id) then n+=1 end
    end
    return n
end
local function pruneQueue()
    -- Never retain an unspent stone that has left the actual main backpack.
    -- Do not expire inventory stones merely for waiting a long time.
    for id in pairs(stones) do
        if not spent[id] and not inMain(id) then
            stones[id]=nil
            mainMissingDrops+=1
        end
    end
end
local function ingestStone(id,source)
    if not uuid(id) or not inMain(id) then return false end
    if spent[id] or stones[id] then duplicateIds+=1;return false end
    pruneQueue()
    if countCaptured()>=maxQueue then
        lastMessage='Inventory queue full; cannot track more unique IDs in this session.'
        record('QUEUE_LIMIT reached, ignored one main-inventory ID')
        return false
    end
    nextOrder+=1
    stones[id]={seen=os.clock(),source=source,order=nextOrder}
    capturedAt=os.clock()
    if source=='OldMenuValidated' then uiCaptured+=1 else mainCaptured+=1 end
    record('STONE_IN_MAIN source='..source..' available='..countAvailable())
    return true
end
local function scanMain()
    mainScans+=1
    local folder=mainInventory()
    if not folder then return 0 end
    mainSourceObserved=true
    local added=0
    for _,node in ipairs(folder:GetChildren()) do
        if uuid(node.Name) and not spent[node.Name] and not stones[node.Name] then
            if ingestStone(node.Name,'MainInventory') then added+=1 end
        end
    end
    return added
end
local function ingestCepFolder(node)
    -- Cep is Mining staging in our audit, so NEVER send its UUID to a machine.
    if not alive or not node or not node:IsA('Folder') or not uuid(node.Name) then return end
    local parent=node.Parent
    if not parent or parent.Name~='Cep' or not isUnder(parent,player) or isUnder(parent,pg) then return end
    if witnessedCepInstances[node] then return end
    witnessedCepInstances[node]=true
    cepObserved+=1
    record('CEP_STAGING_OBSERVED (NOT QUEUED) seen='..cepObserved)
end
local function scanCep()
    local cep=player:FindFirstChild('Cep')
    if not cep then return end
    for _,node in ipairs(cep:GetChildren()) do ingestCepFolder(node) end
end
connections[#connections+1]=player.DescendantAdded:Connect(function(node)
    if not alive then return end
    local parent=node.Parent
    if parent and parent==mainInventory() and uuid(node.Name) then
        mainAddEvents+=1
        if not seenMainInstances[node] then
            seenMainInstances[node]=true
            ingestStone(node.Name,'MainInventory')
        end
    elseif node:IsA('Folder') and uuid(node.Name) and parent
        and parent.Name=='Cep' and isUnder(parent,player) then
        cepEvents+=1
        ingestCepFolder(node)
    end
end)
connections[#connections+1]=player.DescendantRemoving:Connect(function(node)
    if not alive then return end
    if uuid(node.Name) and node.Parent==mainInventory() then
        mainRemoveEvents+=1
        record('MAIN_ID_REMOVED mainNow='..math.max(0,currentMainCount()-1))
    end
end)
local function scanStones(silent)
    local cutting=pg:FindFirstChild('CuttingMenu')
    local inventory=pg:FindFirstChild('InventoryMenu')
    local observed,added,alreadyKnown,alreadySpent,notInMain=0,0,0,0,0
    menuScanCount+=1
    if not silent then manualImportAttempts+=1 end
    -- Count only *visible and selectable* UUID game cards. A card that was
    -- already recorded from Cep is not a NEW menu import, but is still seen.
    for _,obj in ipairs(pg:GetDescendants()) do
        if obj:IsA('GuiButton') and uuid(obj.Name) and visible(obj)
            and not excludedFromStoneCards(obj)
            and ((cutting and isUnder(obj,cutting)) or (inventory and isUnder(obj,inventory))) then
            observed+=1
            if not inMain(obj.Name) then
                notInMain+=1
            elseif spent[obj.Name] then
                alreadySpent+=1
            elseif stones[obj.Name] then
                alreadyKnown+=1
            elseif ingestStone(obj.Name,'OldMenuValidated') then
                added+=1
            end
        end
    end
    menuVisibleLast,menuKnownLast,menuSpentLast,menuNewLast=observed,alreadyKnown,alreadySpent,added
    menuVisiblePeak=math.max(menuVisiblePeak,observed)
    if observed>0 then menuHasEverShownCards=true end
    if not silent then
        lastManualVisible,lastManualAdded=observed,added
    end
    if not silent or added>0 or (observed>0 and menuVisiblePeak==observed and menuScanCount<=2) then
        captures+=1
        record('OLD_MENU_SCAN visible='..observed..' added='..added..' known='..alreadyKnown
            ..' spent='..alreadySpent..' notInMain='..notInMain..' available='..countAvailable())
        if observed==0 and not silent then
            lastMessage='Menu cards not visible; main inventory works without opening menu.'
        elseif added>0 then
            lastMessage='Validated '..added..' menu IDs against main inventory.'
        elseif not silent and observed>0 then
            lastMessage='Menu cards scanned; only IDs present in Envanter can be sent.'
        end
    end
    return observed,added
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
    for id,entry in pairs(stones) do
        if not spent[id] and inMain(id)
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
    if not auto or busy or not alive then return end
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
    if not id then return end -- wait for actual Player.Envanter membership
    if not inMain(id) then
        mainMissingDrops+=1
        stones[id]=nil
        return
    end
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

local function report()
    local lines={
        'CUT A ROCK CUT ENGINE v1.9 (UNIFIED; ENVANTER INTAKE)',
        'PlaceId='..game.PlaceId,
        'BoundMachines='..#machines,
        'PreviewCandidates='..#preview,
        'CapturedStoneIds='..countCaptured(),
        'AvailableIds='..countAvailable(),
        'MainInventoryPath=Players.LocalPlayer.Envanter (direct UUID children)',
        'MainInventoryPresent='..tostring(mainInventory()~=nil)
            ..' MainInventorySeen='..tostring(mainSourceObserved)
            ..' MainInventoryCurrent='..currentMainCount(),
        'MainCaptured='..mainCaptured..' MainAddEvents='..mainAddEvents
            ..' MainRemoveEvents='..mainRemoveEvents..' MainScans='..mainScans,
        'MainMissingDrops='..mainMissingDrops,
        'CepStagingObserved='..cepObserved..' CepEvents='..cepEvents
            ..' MenuValidatedImports='..uiCaptured,
        'MenuScans='..menuScanCount..' MenuOpenEvents='..menuOpenEvents
            ..' MenuCardsVisibleLast='..menuVisibleLast..' MenuCardsVisiblePeak='..menuVisiblePeak,
        'MenuLastKnownFromCache='..menuKnownLast..' MenuLastAlreadySent='..menuSpentLast
            ..' MenuLastNew='..menuNewLast,
        'ManualImports='..manualImportAttempts..' LastManualVisible='..lastManualVisible
            ..' LastManualAdded='..lastManualAdded,
        'MenuEverHadCards='..tostring(menuHasEverShownCards),
        'DuplicateIgnored='..duplicateIds..' Expired='..expiredIds,
        'SessionCap='..maxSends..' StoneTTLSeconds='..stoneTTL,
        'StoneReadyDelaySeconds='..minStoneAge..' Readiness=LIVE_ENVANTER_MEMBERSHIP',
        'CacheAge='..(capturedAt>0 and string.format('%.1f',os.clock()-capturedAt) or 'none'),
        'Auto='..tostring(auto)..' Busy='..tostring(busy),
        'RemoteSent='..sends..' PromptChanged='..confirmed..' LateConfirmed='..lateConfirmed
            ..' UnconfirmedTimeouts='..unconfirmed,
        'ConsecutiveUnconfirmed='..consecutiveUnconfirmed,
        'NextMachineIndex='..nextMachineIndex,
        'ActiveHolds='..countHolds()..' LockedMachines='..select(2,countHolds()),
        'HoldReleased='..holdReleased..' HardHolds='..hardHolds,
        'LocalErrors='..localErrors,
        'NOTE: Changed prompt suggests acceptance; server-side details are not exposed.',
        'NOTE: UUID strings redacted and never included.',
        'NOTE: Cep is Mining staging. Cep IDs are observed for audit only, never queued.',
        'NOTE: Server acceptance after Envanter replication remains experimental.',
        'NOTE: Unconfirmed UUIDs are not retried automatically.',
        'OldStoneImport=LIVE_MAIN_INVENTORY; no Cutting Menu needed',
        '--- MACHINES ---'
    }
    for i,item in ipairs(machines) do
        local p=promptOf(item.model)
        lines[#lines+1]=string.format('%d. %s | via=%s | state=%s | filled=%d',
            i,safePath(item.model),item.via,p and p.ActionText or 'missing',item.filled)
        lines[#lines+1]='   hold='..(item.uncertain and 'UNCERTAIN' or item.locked and 'LOCKED'
            or os.clock()<item.holdUntil and 'COOLDOWN' or 'none')..' misses='..item.misses
    end
    lines[#lines+1]='--- ANONYMOUS SEND EVIDENCE (last 30) ---'
    for _,e in ipairs(sendEvidence) do
        lines[#lines+1]=string.format('Send#%d machine#%d source=%s age=%.1fs status=%s',
            e.number,e.machine,e.source,e.age,e.status)
    end
    lines[#lines+1]='--- PREVIEW (NOT YET BOUND) ---'
    for _,candidate in ipairs(preview) do
        lines[#lines+1]=safePath(candidate)..' ownerHint='..ownerHint(candidate)
    end
    lines[#lines+1]='--- TIMELINE ---'
    for _,line in ipairs(logs) do lines[#lines+1]=line end
    return table.concat(lines,'\n')
end

local function setAuto(value)
    if not alive then return false end
    if value then
        if #machines==0 then lastMessage='Bind machines before AUTO CUT.'; return false end
        if sends>=maxSends then lastMessage='Cut session cap reached.'; return false end
        if not mainInventory() then
            lastMessage='Main Inventory (Envanter) not replicated yet; CUT stays OFF.'
            return false
        end
        scanMain()
        auto=true
        record('AUTO_ON machines='..#machines..' queued='..countAvailable()..' MAIN INVENTORY ONLY')
        lastMessage='Auto Cut ON; reads Envanter, does not send Cep staging IDs.'
        return true
    end
    if auto then stopAuto('Paused by user') end
    auto=false
    return false
end
local function resetLocks()
    local n=0
    for _,item in ipairs(machines) do
        local p=promptOf(item.model)
        if item.locked and not item.uncertain and p and p.Enabled
            and p.ActionText:lower():find('place rock',1,true) then
            item.locked=false
            item.misses=0
            item.holdUntil=os.clock()+4
            n+=1
        end
    end
    lastMessage='Reset '..n..' locks that showed Place Rock.'
    record('MANUAL_RESET_LOCKS unlocked='..n)
end
local function stopCut()
    alive=false
    auto=false
    for _,item in ipairs(machines) do disconnectProbe(item.uncertain) end
    for _,c in ipairs(connections) do pcall(function() c:Disconnect() end) end
end
local function visibleCutMenu()
    local c=pg:FindFirstChild('CuttingMenu')
    local inv=pg:FindFirstChild('InventoryMenu')
    return (c and ((not c:IsA('ScreenGui')) or c.Enabled))
        or (inv and ((not inv:IsA('ScreenGui')) or inv.Enabled))
end
-- Existing stones are read directly from the replicated main inventory.
-- Cep events are tracked only to verify the Mining staging hypothesis.
scanMain()
scanCep()
record('CUT_LOADED Envanter watcher ON; main='..tostring(mainInventory()~=nil)
    ..' available='..countAvailable()..' Cep is diagnostic only')
task.spawn(function()
    while alive do
        local ok,err=pcall(attemptOne)
        if not ok then busy=false;stopAuto('Cut error: '..tostring(err):sub(1,100)) end
        task.wait(0.85)
    end
end)
task.spawn(function()
    while alive do
        pcall(scanMain)
        pcall(scanCep)
        pcall(reconcileHolds)
        task.wait(0.5)
    end
end)
task.spawn(function()
    while alive do
        local open=visibleCutMenu() and true or false
        if open and not menuWasOpen then
            menuOpenEvents+=1
            record('CUT_MENU_OPEN_DETECTED; scanning visible stone cards')
        end
        menuWasOpen=open
        if open then pcall(scanStones,true) end
        task.wait(0.5)
    end
end)
return {
    bindNearest=function()
        local m=findNearest()
        if m then bindMachine(m,'NEAREST_IN_RANGE')
        else lastMessage='Stand near YOUR machine, then BIND.' end
    end,
    preview=previewBase,
    addPreview=commitPreview,
    importOld=function()
        local n=scanMain()
        local observed,menuAdded=scanStones(false)
        lastMessage='Main inventory scan: +'..n..' IDs; menu matches observed='..observed
        record('MANUAL_MAIN_SCAN new='..n..' menuAdded='..menuAdded)
        return n,menuAdded
    end,
    resetLocks=resetLocks,
    setAuto=setAuto,
    isAuto=function() return auto end,
    report=report,
    getStatus=function() return {
        bound=#machines, queued=countAvailable(), newMain=mainCaptured,
        mainCurrent=currentMainCount(),mainPresent=mainInventory()~=nil,
        oldMenu=uiCaptured, menuVisible=menuVisiblePeak,
        menuOpen=menuOpenEvents, sent=sends, confirmed=confirmed+lateConfirmed,
        unconfirmed=unconfirmed, holds=select(1,countHolds()), message=lastMessage,
        auto=auto, busy=busy
    } end,
    stop=stopCut
}

end

local function initTrain()
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
-- Existing versions are stopped once by the unified loader.

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


local function report()
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
    return output
end
local function stopTrain()
    if not alive then return end
    disable()
    alive=false
    for _,c in ipairs(connections) do pcall(function() c:Disconnect() end) end
end
task.spawn(function()
    while alive do
        local ok,err=pcall(logic)
        if not ok then debugLast='Error: '..tostring(err):sub(1,110) end
        task.wait(on and 0.035 or 0.3)
    end
end)
return {
    enable=enable,disable=disable,
    isOn=function()return on end,
    report=report,
    status=function()return {
        on=on, phase=phase, state=state, round=turn,
        flashes=#sequence, successes=successes, failures=retries,
        message=debugLast
    }end,
    stop=stopTrain
}

end

-- ----------------------- COMPACT SHARED UI -----------------------
local cut=initCut()
local train=initTrain()
local alive=true
local allConnections={}
local function make(class,props,parent)
    local o=Instance.new(class)
    for k,v in pairs(props) do o[k]=v end
    o.Parent=parent
    return o
end
local gui=make('ScreenGui',{Name='CAR_CutTrain_Unified_v13',ResetOnSpawn=false,
    ZIndexBehavior=Enum.ZIndexBehavior.Sibling,DisplayOrder=99},pg)
local panel=make('Frame',{Size=UDim2.fromOffset(296,307),
    Position=UDim2.new(0,12,0.12,0),BackgroundColor3=Color3.fromRGB(21,27,38),
    BorderSizePixel=0,ClipsDescendants=true},gui)
make('UICorner',{CornerRadius=UDim.new(0,9)},panel)
make('UIStroke',{Color=Color3.fromRGB(76,94,117),Thickness=1},panel)
local title=make('TextLabel',{Text='CAR | CUT + TRAIN 1.3',Position=UDim2.fromOffset(10,3),
    Size=UDim2.fromOffset(220,30),TextSize=12,Font=Enum.Font.GothamBold,
    TextXAlignment=Enum.TextXAlignment.Left,TextColor3=Color3.new(1,1,1),
    BackgroundTransparency=1},panel)
local function button(label,x,y,w,h)
    local b=make('TextButton',{Text=label,Position=UDim2.fromOffset(x,y),
        Size=UDim2.fromOffset(w,h),BackgroundColor3=Color3.fromRGB(47,70,99),
        TextColor3=Color3.new(1,1,1),Font=Enum.Font.GothamMedium,
        TextSize=11,BorderSizePixel=0},panel)
    make('UICorner',{CornerRadius=UDim.new(0,6)},b)
    return b
end
local function onClick(btn,callback)
    allConnections[#allConnections+1]=btn.Activated:Connect(callback)
end
local minButton=button('_',239,5,24,26)
local closeButton=button('X',268,5,20,26)
closeButton.BackgroundColor3=Color3.fromRGB(126,54,64)
local body=make('Frame',{Position=UDim2.fromOffset(0,35),Size=UDim2.fromOffset(296,271),
    BackgroundTransparency=1},panel)
-- Buttons are parented to body to disappear on minimize.
local function bodyButton(label,x,y,w,h)
    local b=button(label,x,y+35,w,h)
    b.Parent=body
    b.Position=UDim2.fromOffset(x,y)
    return b
end
local trainToggle=bodyButton('TRAIN: OFF',9,5,135,35)
local cutToggle=bodyButton('CUT: OFF',152,5,135,35)
local bindBtn=bodyButton('1  BIND',9,46,135,31)
local prevBtn=bodyButton('2  PREVIEW',152,46,135,31)
local addBtn=bodyButton('3  ADD BASE',9,82,135,31)
local importBtn=bodyButton('SCAN BACKPACK',152,82,135,31)
local resetBtn=bodyButton('RESET LOCKS',9,118,135,31)
local copyBtn=bodyButton('COPY REPORT',152,118,135,31)
local status=make('TextLabel',{Position=UDim2.fromOffset(10,156),Size=UDim2.fromOffset(276,76),
    Text='Starting...',BackgroundTransparency=1,TextColor3=Color3.fromRGB(198,217,237),
    TextSize=10,Font=Enum.Font.Gotham,TextWrapped=true,
    TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top},body)
local hint=make('TextLabel',{Position=UDim2.fromOffset(10,232),Size=UDim2.fromOffset(276,32),
    Text='Stones: watch Player.Envanter, not Mining Cep.\nCollect disabled; CUT & TRAIN run independently.',
    BackgroundTransparency=1,TextColor3=Color3.fromRGB(148,171,195),
    TextSize=9,Font=Enum.Font.Gotham,TextWrapped=true,
    TextXAlignment=Enum.TextXAlignment.Left},body)
local minimized=false
local expandedHeight=307
onClick(minButton,function()
    minimized=not minimized
    body.Visible=not minimized
    panel.Size=UDim2.fromOffset(296,minimized and 35 or expandedHeight)
    minButton.Text=minimized and '+' or '_'
end)
local function stopAll()
    if not alive then return end
    alive=false
    train.stop()
    cut.stop()
    for _,c in ipairs(allConnections) do pcall(function()c:Disconnect()end) end
    if gui and gui.Parent then gui:Destroy() end
    if env.CARUnifiedCutTrainStop==stopAll then env.CARUnifiedCutTrainStop=nil end
end
env.CARUnifiedCutTrainStop=stopAll
onClick(closeButton,stopAll)
onClick(trainToggle,function()
    if train.isOn() then train.disable() else train.enable() end
end)
onClick(cutToggle,function()
    cut.setAuto(not cut.isAuto())
end)
onClick(bindBtn,cut.bindNearest)
onClick(prevBtn,cut.preview)
onClick(addBtn,cut.addPreview)
onClick(importBtn,function()
    -- Optional manual scan; normally Envanter is watched automatically.
    cut.importOld()
end)
onClick(resetBtn,cut.resetLocks)
local function report()
    local lines={
        'CUT A ROCK UNIFIED v1.3 | AUTO CUT v1.9 + AUTO TRAIN v3.2',
        'AutoCollect=false (DISABLED; far calls did not yield real stone)',
        'StoneSource=Player.Envanter (Shop + returned Mining + old stones); Cep DIAGNOSTICS ONLY',
        '--- AUTO CUT REPORT ---',cut.report(),
        '--- AUTO TRAIN REPORT ---',train.report()
    }
    return table.concat(lines,'\n')
end
onClick(copyBtn,function()
    local output=report()
    print(output)
    local clipboard=(type(setclipboard)=='function' and setclipboard)
        or (type(toclipboard)=='function' and toclipboard) or nil
    if clipboard and pcall(clipboard,output) then
        hint.Text='Report copied; paste into ChatGPT. All stones: Player.Envanter.'
    else
        hint.Text='Report printed in executor console.'
    end
end)
-- Mobile drag from title; unmodified game buttons are never intercepted.
local dragging,startPos,oldPos=false,nil,nil
allConnections[#allConnections+1]=title.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.Touch
        or input.UserInputType==Enum.UserInputType.MouseButton1 then
        dragging=true;startPos=input.Position;oldPos=panel.Position
        local c
        c=input.Changed:Connect(function()
            if input.UserInputState==Enum.UserInputState.End then
                dragging=false;c:Disconnect()
            end
        end)
    end
end)
allConnections[#allConnections+1]=UIS.InputChanged:Connect(function(input)
    if dragging and startPos and (input.UserInputType==Enum.UserInputType.Touch
        or input.UserInputType==Enum.UserInputType.MouseMovement) then
        local delta=input.Position-startPos
        panel.Position=UDim2.new(oldPos.X.Scale,oldPos.X.Offset+delta.X,
            oldPos.Y.Scale,oldPos.Y.Offset+delta.Y)
    end
end)
task.spawn(function()
    while alive do
        local c=cut.getStatus()
        local t=train.status()
        local onCol=Color3.fromRGB(28,124,87)
        local offCol=Color3.fromRGB(47,70,99)
        trainToggle.Text=t.on and 'TRAIN: ON' or 'TRAIN: OFF'
        trainToggle.BackgroundColor3=t.on and onCol or offCol
        cutToggle.Text=c.auto and 'CUT: ON' or 'CUT: OFF'
        cutToggle.BackgroundColor3=c.auto and onCol or offCol
        status.Text=string.format(
            'Machines: %d | Ready IDs: %d | Main: %d | Seen: %d\n'
            ..'Menu cards seen: %d | Cut %d/%d | uncertain %d\n'
            ..'Train: %s | round %d | OK %d | fail %d\n'
            ..'%s',c.bound,c.queued,c.mainCurrent,c.newMain,c.menuVisible,
            c.confirmed,c.sent,c.unconfirmed,(t.on and t.phase or 'OFF'),
            t.round,t.successes,t.failures,
            tostring(c.message):sub(1,105))
        task.wait(0.32)
    end
end)
print('[CAR Unified] v1.3: Cut v1.9 from Player.Envanter + unmodified Train v3.2. Cep mining staging NOT sent. Collect disabled. BIND/PREVIEW/ADD, enable TRAIN and CUT. Minimize with _.')

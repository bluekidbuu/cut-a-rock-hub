-- Cut a Rock | Multi-Machine Auto Cut + Cep Monitor v1.5
-- PlaceId 113742027864370 / GameId 10766468833
-- Built from a user-verified one-shot PlaceStoneInMachineEvent test.
-- Binds machines explicitly, monitors actual UUID-named Folder objects in Player.Cep
-- (5/5 exact matches against cut cards in user trace v1.4), optionally imports
-- GUI stone cards, then fills idle machines sequentially without menus/teleports.
-- Remote collect is not implemented: finished stones must still be collected separately.
-- Does not use InstantCutEvent, buy upgrades, or guess UUIDs.

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
if type(env.CARMultiCutStop)=='function' then pcall(env.CARMultiCutStop) end

local alive,auto,busy=true,false,false
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
local cepCaptured,uiCaptured,duplicateIds,expiredIds,cepEvents=0,0,0,0,0
local nextOrder=0
local witnessedCepInstances=setmetatable({}, {__mode="k"}) -- ignore repeat polling of same Folder
local lastMessage='Bind your machines, enable AUTO FILL, then collect new rocks.'
local maxSends=60 -- explicit bounded safety limit; restart manually after cap
local maxQueue=160
local stoneTTL=900 -- discard UUIDs older than 15 minutes without attempting
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
    machines[#machines+1]={model=model,via=via,last=0,filled=0}
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
        if not spent[id] and now-entry.seen>=2.5
          and (not chosenEntry or entry.order<chosenEntry.order) then
            chosenId,chosenEntry=id,entry
        end
    end
    return chosenId,chosenEntry
end
local function readyMachine()
    for _,item in ipairs(machines) do
        local model=item.model
        local p=promptOf(model)
        if model.Parent and p and p.Enabled then
            local action=p.ActionText:lower()
            if action:find('place rock',1,true) and os.clock()-item.last>8 then
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
local function attemptOne()
    if not auto or busy or not alive then return end
    if not remote or not remote:IsA('RemoteEvent') then
        stopAuto('PlaceStoneInMachineEvent missing')
        return
    end
    if #machines==0 then stopAuto('Bind your machines first');return end
    if sends>=maxSends then stopAuto('Session cap '..maxSends..' reached; restart manually to continue.');return end
    pruneQueue()
    if countAvailable()==0 then return end -- stay armed: await fresh Cep events
    -- Avoid racing against the player's manual actions in a visible menu.
    local cutMenu=pg:FindFirstChild('CuttingMenu')
    if cutMenu and cutMenu:IsA('ScreenGui') and cutMenu.Enabled then return end
    local item,p=readyMachine()
    if not item then return end -- cutting/collectable machines are never overwritten
    local id,entry=nextStone()
    if not id then return end -- wait 2.5 seconds for inventory replication
    busy=true
    item.last=os.clock()
    spent[id]=true -- never resend same ID within this session
    local before=p.ActionText
    local ok,err=pcall(function()
        remote:FireServer(item.model,id)
    end)
    sends+=1
    record('SEND machine='..safePath(item.model)..' source='..entry.source..' localOk='..tostring(ok)..' queued='..countAvailable())
    if not ok then
        localErrors+=1
        busy=false
        stopAuto('Local error: '..tostring(err):sub(1,90))
        return
    end
    lastMessage='Sent to '..item.model.Name..'; observing prompt state...'
    local changed=false
    local endedAt=os.clock()+5
    repeat
        task.wait(0.25)
        if not alive then break end
        local now=promptOf(item.model)
        if now then
            local action=now.ActionText
            if action~=before then changed=true; break end
        end
    until os.clock()>=endedAt
    if changed then
        item.filled+=1
        confirmed+=1
        lastMessage='Machine '..item.model.Name..' changed state. Continue next idle machine.'
        record('PROMPT_CHANGED '..item.model.Name..' from='..before)
    else
        unconfirmed+=1
        stopAuto('Unconfirmed machine response; paused to prevent repeated sends.')
    end
    busy=false
end

-- UI (mobile-friendly). Use separate buttons to explicitly confirm the base group.
local gui=Instance.new('ScreenGui')
gui.Name='CAR_MultiCut_v15'
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
    Size=UDim2.fromOffset(336,461),Position=UDim2.new(0,12,0.1,0),
    BackgroundColor3=Color3.fromRGB(22,28,40),BorderSizePixel=0
},gui)
create('UICorner',{CornerRadius=UDim.new(0,11)},panel)
create('UIStroke',{Color=Color3.fromRGB(81,98,120),Thickness=1},panel)
local title=create('TextLabel',{
    Text='CUT A ROCK | AUTO CUT v1.5',TextSize=14,
    TextXAlignment=Enum.TextXAlignment.Left,Font=Enum.Font.GothamBold,
    Size=UDim2.fromOffset(285,34),Position=UDim2.fromOffset(11,3),
    BackgroundTransparency=1,TextColor3=Color3.new(1,1,1)
},panel)
local function button(text,x,y,w,h,fn)
    local b=create('TextButton',{
        Text=text,TextSize=12,Font=Enum.Font.GothamMedium,
        TextColor3=Color3.new(1,1,1),
        BackgroundColor3=Color3.fromRGB(50,76,108),
        Size=UDim2.fromOffset(w,h),Position=UDim2.fromOffset(x,y),
        BorderSizePixel=0
    },panel)
    create('UICorner',{CornerRadius=UDim.new(0,7)},b)
    if fn then connections[#connections+1]=b.Activated:Connect(function() fn(b) end) end
    return b
end
local function stop()
    if not alive then return end
    auto=false;alive=false
    for _,conn in ipairs(connections) do pcall(function()conn:Disconnect()end) end
    if gui and gui.Parent then gui:Destroy() end
    if env.CARMultiCutStop==stop then env.CARMultiCutStop=nil end
end
env.CARMultiCutStop=stop
button('X',298,5,27,27,stop)
local info=create('TextLabel',{
    Position=UDim2.fromOffset(12,41),Size=UDim2.fromOffset(312,93),
    Text='Starting...',BackgroundTransparency=1,TextColor3=Color3.fromRGB(190,216,235),
    TextSize=11,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,
    TextYAlignment=Enum.TextYAlignment.Top,Font=Enum.Font.Gotham
},panel)
button('BIND NEAREST',11,140,154,38,function()
    local m=findNearest()
    if m then bindMachine(m,'NEAREST_IN_RANGE')
    else lastMessage='Stand near an owned machine and retry.' end
end)
button('IMPORT MENU (opt.)',172,140,153,38,function()scanStones()end)
button('PREVIEW SAME BASE',11,184,154,38,previewBase)
button('ADD PREVIEW*',172,184,153,38,commitPreview)
local activeButton=button('AUTO FILL: OFF',11,230,314,45,nil)
connections[#connections+1]=activeButton.Activated:Connect(function()
    if auto then
        stopAuto('Paused by user')
    else
        if busy then lastMessage='Wait for current request';return end
        if #machines==0 then
            lastMessage='Bind machine(s) first. Cep watcher is already active.'
            return
        end
        auto=true
        record('AUTO_ON machines='..#machines..' available='..countAvailable()..' watching Cep')
        lastMessage='Auto ON: watching Cep for new stones; idle machines only.'
    end
end)
local function report()
    local lines={
        'CUT A ROCK AUTO CUT v1.5 CEP WATCH',
        'PlaceId='..game.PlaceId,
        'BoundMachines='..#machines,
        'PreviewCandidates='..#preview,
        'CapturedStoneIds='..countCaptured(),
        'AvailableIds='..countAvailable(),
        'CepCaptured='..cepCaptured..' CepEvents='..cepEvents..' MenuImported='..uiCaptured,
        'DuplicateIgnored='..duplicateIds..' Expired='..expiredIds,
        'SessionCap='..maxSends..' StoneTTLSeconds='..stoneTTL,
        'CacheAge='..(capturedAt>0 and string.format('%.1f',os.clock()-capturedAt) or 'none'),
        'Auto='..tostring(auto)..' Busy='..tostring(busy),
        'RemoteSent='..sends..' PromptChanged='..confirmed..' Unconfirmed='..unconfirmed,
        'LocalErrors='..localErrors,
        'NOTE: Changed prompt suggests acceptance; server-side details are not exposed.',
        'NOTE: UUID strings redacted and never included.',
        'NOTE: Cep IDs matched 5/5 cut cards in previous trace; individual new sends still require validation.',
        '--- MACHINES ---'
    }
    for i,item in ipairs(machines) do
        local p=promptOf(item.model)
        lines[#lines+1]=string.format('%d. %s | via=%s | state=%s | filled=%d',
            i,safePath(item.model),item.via,p and p.ActionText or 'missing',item.filled)
    end
    lines[#lines+1]='--- PREVIEW (NOT YET BOUND) ---'
    for _,candidate in ipairs(preview) do
        lines[#lines+1]=safePath(candidate)..' ownerHint='..ownerHint(candidate)
    end
    lines[#lines+1]='--- TIMELINE ---'
    for _,line in ipairs(logs) do lines[#lines+1]=line end
    return table.concat(lines,'\n')
end
button('COPY REPORT',11,287,314,37,function()
    local reportText=report()
    print(reportText)
    local copy=type(setclipboard)=='function' and setclipboard
        or type(toclipboard)=='function' and toclipboard or nil
    if copy and pcall(copy,reportText) then
        lastMessage='Report copied.'
    else
        lastMessage='Report printed in executor console.'
    end
end)
create('TextLabel',{
    Text='*Confirm only your own base. Detects NEW Cep stones with menus closed.\nNo remote collect. A fresh session may not know existing older stones.',
    Position=UDim2.fromOffset(12,334),Size=UDim2.fromOffset(312,47),
    BackgroundTransparency=1,TextSize=10,TextWrapped=true,
    TextColor3=Color3.fromRGB(164,185,205),Font=Enum.Font.Gotham
},panel)
local scrollInfo=create('TextLabel',{
    Text='Machine list will appear here after binding.',
    Position=UDim2.fromOffset(12,390),Size=UDim2.fromOffset(312,61),
    BackgroundTransparency=1,TextSize=10,TextWrapped=true,
    TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,
    TextColor3=Color3.fromRGB(183,198,218),Font=Enum.Font.Gotham
},panel)
local dragging=false
local dragStart,dragPos
connections[#connections+1]=title.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
        dragging=true
        dragStart=input.Position
        dragPos=panel.Position
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
    if dragging and dragStart and (input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseMovement) then
        local delta=input.Position-dragStart
        panel.Position=UDim2.new(dragPos.X.Scale,dragPos.X.Offset+delta.X,dragPos.Y.Scale,dragPos.Y.Offset+delta.Y)
    end
end)

task.spawn(function()
    while alive do
        local ok,err=pcall(attemptOne)
        if not ok then
            busy=false
            stopAuto('Unexpected error: '..tostring(err):sub(1,100))
        end
        task.wait(0.85)
    end
end)
task.spawn(function()
    while alive do
        pcall(scanCep)
        task.wait(1)
    end
end)
task.spawn(function()
    while alive do
        activeButton.Text=auto and 'AUTO FILL: ON' or 'AUTO FILL: OFF'
        activeButton.BackgroundColor3=auto and Color3.fromRGB(32,122,86) or Color3.fromRGB(50,76,108)
        info.Text=string.format('Machines: %d | Cep new: %d | Menu: %d\nQueued: %d | Sent: %d | Changed: %d\n%s',
            #machines,cepCaptured,uiCaptured,countAvailable(),sends,confirmed,lastMessage)
        local names={}
        for i=1,math.min(#machines,5) do
            local item=machines[i]
            local p=promptOf(item.model)
            names[#names+1]=item.model.Name..' ['..(p and p.ActionText or 'missing')..']'
        end
        local previewNames={}
        for i=1,math.min(#preview,8) do
            previewNames[#previewNames+1]=preview[i].Name
        end
        local previewText=#preview>0 and ('\nPreview: '..table.concat(previewNames,', ')
            ..(#preview>8 and (' + '..(#preview-8)..' more') or '')) or ''
        scrollInfo.Text='Bound: '..(#names>0 and table.concat(names,', ') or 'none')
            ..(#machines>5 and (' + '..(#machines-5)..' more') or '')..previewText
        task.wait(0.3)
    end
end)
scanCep() -- Only an initial snapshot: the primary source is the event above.
record('LOADED Cep watcher active; no remotes until AUTO FILL enabled')
print('[CAR MultiCut v1.5] Bind machines, enable AUTO FILL (even with empty queue), collect stones; Cep events feed cutting automatically. Optional IMPORT MENU for existing stones.')

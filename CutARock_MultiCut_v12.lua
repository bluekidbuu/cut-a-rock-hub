-- Cut a Rock | Multi-Machine Remote Cut v1.2
-- PlaceId 113742027864370 / GameId 10766468833
-- Built from a user-verified one-shot PlaceStoneInMachineEvent test.
-- Binds machines explicitly, caches real UUIDs seen in the game UI,
-- then fills idle bound machines sequentially, without menus/teleports.
-- NOT a remote collect bypass. Collect remains a separate action.
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
local stones={} -- captured in live UI, UUID -> record
local spent={} -- never reuse a stone UUID within this script session
local connections={}
local logs={}
local capturedAt=0
local captures,sends,confirmed,unconfirmed,localErrors=0,0,0,0,0
local lastMessage='Bind your machine, then scan visible stone cards.'
local maxSends=24
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
local function scanStones()
    local cutting=pg:FindFirstChild('CuttingMenu')
    local inventory=pg:FindFirstChild('InventoryMenu')
    local nextStones={}
    for _,obj in ipairs(pg:GetDescendants()) do
        if obj:IsA('GuiButton') and uuid(obj.Name) and visible(obj)
            and not excludedFromStoneCards(obj)
            and ((cutting and isUnder(obj,cutting)) or (inventory and isUnder(obj,inventory))) then
            nextStones[obj.Name]={seen=os.clock(),source=isUnder(obj,cutting) and 'CuttingMenu' or 'InventoryMenu'}
        end
    end
    local n=0
    for _ in pairs(nextStones) do n+=1 end
    if n>0 then
        -- Do not resurrect UUIDs previously sent to a machine this session.
        stones=nextStones
        capturedAt=os.clock()
        captures+=1
        lastMessage='Captured '..n..' stone cards ('..countAvailable()..' unsent).'
        record('CAPTURE visible='..n..' available='..countAvailable())
    else
        lastMessage='No selectable UUID cards. Open CuttingMenu, then SCAN STONES.'
        record('CAPTURE empty; cache preserved')
    end
    return n
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
    local ids={}
    for id in pairs(stones) do if not spent[id] then ids[#ids+1]=id end end
    table.sort(ids)
    return ids[1]
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
    if countAvailable()==0 then stopAuto('Stone cache empty; SCAN STONES with menu open');return end
    if os.clock()-capturedAt>300 then
        stopAuto('Cache is over 5 minutes old. Refresh visible inventory.')
        return
    end
    if sends>=maxSends then stopAuto('Session safety cap reached ('..maxSends..')');return end
    local item,p=readyMachine()
    if not item then return end -- all machines cutting, collectable, or otherwise not ready
    local id=nextStone()
    if not id then stopAuto('No unused stone IDs');return end
    busy=true
    item.last=os.clock()
    spent[id]=true -- no reuse, even if the server rejects this one
    local before=p.ActionText
    local ok,err=pcall(function()
        remote:FireServer(item.model,id)
    end)
    sends+=1
    record('SEND machine='..safePath(item.model)..' localOk='..tostring(ok)..' stonesLeft='..countAvailable())
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
gui.Name='CAR_MultiCut_v12'
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
    Text='CUT A ROCK | MULTI CUT v1.2',TextSize=14,
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
button('SCAN STONES',172,140,153,38,function()scanStones()end)
button('PREVIEW SAME BASE',11,184,154,38,previewBase)
button('ADD PREVIEW*',172,184,153,38,commitPreview)
local activeButton=button('AUTO FILL: OFF',11,230,314,45,nil)
connections[#connections+1]=activeButton.Activated:Connect(function()
    if auto then
        stopAuto('Paused by user')
    else
        if busy then lastMessage='Wait for current request';return end
        if #machines==0 or countAvailable()==0 then
            lastMessage='Bind machine(s) and capture selectable stone UUIDs first.'
            return
        end
        auto=true
        record('AUTO_ON machines='..#machines..' available='..countAvailable())
        lastMessage='Sequential auto fill ON; idle machines only.'
    end
end)
local function report()
    local lines={
        'CUT A ROCK MULTI CUT v1.2',
        'PlaceId='..game.PlaceId,
        'BoundMachines='..#machines,
        'PreviewCandidates='..#preview,
        'CapturedStoneIds='..countCaptured(),
        'AvailableIds='..countAvailable(),
        'CacheAge='..(capturedAt>0 and string.format('%.1f',os.clock()-capturedAt) or 'none'),
        'Auto='..tostring(auto)..' Busy='..tostring(busy),
        'RemoteSent='..sends..' PromptChanged='..confirmed..' Unconfirmed='..unconfirmed,
        'LocalErrors='..localErrors,
        'NOTE: Changed prompt suggests acceptance; server-side details are not exposed.',
        'NOTE: UUID strings redacted and never included.',
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
    Text='*ADD PREVIEW only if all sibling machines belong to you.\nCollect from afar is NOT implemented; recapture fresh inventory as needed.',
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
        activeButton.Text=auto and 'AUTO FILL: ON' or 'AUTO FILL: OFF'
        activeButton.BackgroundColor3=auto and Color3.fromRGB(32,122,86) or Color3.fromRGB(50,76,108)
        info.Text=string.format('Bound machines: %d | Base preview: %d\nStone IDs available: %d | Sent: %d | Changed: %d\n%s',
            #machines,#preview,countAvailable(),sends,confirmed,lastMessage)
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
record('LOADED; no remote requests until AUTO FILL is enabled')
print('[CAR MultiCut] Bind at least one machine, preview/confirm same base if owned, scan visible stone cards, AUTO FILL.')

-- CUT A ROCK | MAIN BACKPACK SOURCE AUDIT v1.0
-- Read-only diagnostic: compare main inventory sources across SHOP,
-- MINING STORAGE, RETURN TO BASE and CUTTING MENU.
-- Never sends remotes, buys, cuts, collects, teleports, or fires prompts.
-- Roblox PlaceId=113742027864370 | GameId=10766468833
-- Values/UUIDs remain in local memory; reports use session-local S# labels.

if not game:IsLoaded() then game.Loaded:Wait() end
if game.PlaceId ~= 113742027864370 and game.GameId ~= 10766468833 then
    warn('[CAR Backpack Audit] Wrong Roblox game.')
    return
end

local Players=game:GetService('Players')
local UIS=game:GetService('UserInputService')
local RS=game:GetService('ReplicatedStorage')
local player=Players.LocalPlayer
local pg=player:WaitForChild('PlayerGui')
local env=type(getgenv)=='function' and getgenv() or _G
if type(env.CARMainBackpackAuditStop)=='function' then
    pcall(env.CARMainBackpackAuditStop)
end

local alive=true
local started=os.clock()
local conns={}
local recent={}
local phase='BEFORE_BASELINE'
local snapshots={}
local seen={}  -- id -> {label, sources={source={first,last,eventCount,stage,path,how}}, first}
local labels=0
local maxTracked=1800
local scanLimit=25000
local scanErrors=0
local eventAdds=0
local eventRemoves=0
local maxTimeline=60
local lastStatus='Close inventory menus, then press BASELINE.'
local lastScan=nil
local pollCount=0
local pollCapped=0
local machineMenuOpened=0
local lastCutOpen=false
local lastGuiSummary=''
local windowEvents={} -- short-lived UUIDs captured between stage snapshots
local ROOTS={'RobloxBackpack','Cep','OtherPlayerData','CuttingMenu','InventoryMenu','MiningStorageUI','OtherInventoryUI','OtherGui','RSInventory','RSOther'}
local uuidPat='^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$'
local function isUUID(v)
    return type(v)=='string' and #v==36 and v:match(uuidPat)~=nil
end
local function log(x)
    recent[#recent+1]=string.format('T+%.1fs %s',os.clock()-started,tostring(x))
    if #recent>maxTimeline then table.remove(recent,1) end
end
local function isUnder(node,root)
    while node do if node==root then return true end; node=node.Parent end
    return false
end
local function contains(x,w)
    return string.find(string.lower(tostring(x or '')),w,1,true)~=nil
end
local function inventoryHint(node)
    local n=node
    for _=1,7 do
        if not n then break end
        local s=n.Name:lower()
        for _,word in ipairs({'invent','backpack','stone','rock','cep','tas','bag','pocket','item','storage','mining','mine','sirt','canta','envanter','depo','izgara','tepsi'}) do
            if s:find(word,1,true) then return true end
        end
        n=n.Parent
    end
    return false
end
local function mineHint(node)
    local n=node
    for _=1,8 do
        if not n then break end
        local s=n.Name:lower()
        if s:find('mining',1,true) or s:find('mine',1,true)
            or s:find('storage',1,true) or s:find('depo',1,true) then return true end
        n=n.Parent
    end
    return false
end
local function backpack()
    return player:FindFirstChildOfClass('Backpack') or player:FindFirstChild('Backpack')
end
local function menuVisible(name)
    local m=pg:FindFirstChild(name)
    if not m then return false end
    if m:IsA('ScreenGui') and not m.Enabled then return false end
    local frame=m:FindFirstChild('MainFrame')
    if frame and frame:IsA('GuiObject') and not frame.Visible then return false end
    return true
end
local function guiVisible(o)
    if not o or not o.Parent or not o:IsA('GuiObject') or o.AbsoluteSize.X<4 or o.AbsoluteSize.Y<4 then return false end
    local p=o
    while p and p~=pg do
        if p:IsA('GuiObject') and not p.Visible then return false end
        if p:IsA('ScreenGui') and not p.Enabled then return false end
        p=p.Parent
    end
    return true
end
local function classify(obj)
    local cb=pg:FindFirstChild('CuttingMenu')
    local inv=pg:FindFirstChild('InventoryMenu')
    if cb and isUnder(obj,cb) then return 'CuttingMenu' end
    if inv and isUnder(obj,inv) then return 'InventoryMenu' end
    if isUnder(obj,pg) then
        if mineHint(obj) then return 'MiningStorageUI' end
        if inventoryHint(obj) then return 'OtherInventoryUI' end
        return 'OtherGui'
    end
    local bp=backpack()
    if bp and isUnder(obj,bp) then return 'RobloxBackpack' end
    if isUnder(obj,player) then
        local n=obj
        while n and n~=player do
            if n.Name=='Cep' then return 'Cep' end
            n=n.Parent
        end
        return 'OtherPlayerData'
    end
    if isUnder(obj,RS) then
        return inventoryHint(obj) and 'RSInventory' or 'RSOther'
    end
    return nil
end
local knownNames={
    Cep=true,Backpack=true,InventoryMenu=true,CuttingMenu=true,MainFrame=true,
    Panel=true,Tepsi=true,Izgara=true,Storage=true,Mining=true,MiningMenu=true,
    Mine=true,Inventory=true,Items=true,Item=true,Stones=true,Stone=true,
    Rock=true,Rocks=true,Data=true,PlayerData=true,Tool=true,Slot=true,
    Slots=true,Bag=true,BackpackGui=true,BackpackMenu=true,MiningStorage=true,
    Tas=true,Canta=true,Envanter=true,Depo=true
}
local function safePath(obj,source)
    local root=(source=='RSInventory' or source=='RSOther') and RS
        or ((source=='CuttingMenu' or source=='InventoryMenu' or source=='MiningStorageUI'
             or source=='OtherInventoryUI' or source=='OtherGui') and pg or player)
    local parts={}
    local p=obj
    while p and p~=root and #parts<8 do
        local name=p.Name
        if isUUID(name) then
            name='<stone-id>'
        elseif not knownNames[name] then
            if name:match('^level%d+$') then name='level#'
            elseif name:match('^Tas%d+$') then name='Tas#'
            else name='<node:'..p.ClassName..'>' end
        end
        parts[#parts+1]=name
        p=p.Parent
    end
    local result={}
    for i=#parts,1,-1 do result[#result+1]=parts[i] end
    return source..'/'..table.concat(result,'/')
end
local function excludedCut(obj)
    local p=obj
    while p and p~=pg do
        if p.Name=='CurrentCut' or p.Name=='FinishCard' or p.Name=='KesimPaneli'
            or p.Name=='CutStoneTab' or p.Name=='StonePhoto' or p.Name=='SellMenu' then return true end
        p=p.Parent
    end
    return false
end
local function track(id,src,obj,how,event)
    if not isUUID(id) or not src then return end
    if src=='CuttingMenu' and (not obj:IsA('GuiButton') or excludedCut(obj) or not guiVisible(obj)) then return end
    if src=='InventoryMenu' and not menuVisible('InventoryMenu') then return end
    -- Avoid arbitrary UUIDs elsewhere in UI/RS unless under a likely inventory path.
    if (src=='OtherGui' or src=='RSOther') and not inventoryHint(obj) then return end
    local r=seen[id]
    if not r then
        if labels>=maxTracked then return end
        labels+=1
        r={label='S'..labels,first=os.clock(),sources={}}
        seen[id]=r
    end
    local now=os.clock()
    local s=r.sources[src]
    if not s then
        s={first=now,last=now,events=0,phase=phase,how=how,path=safePath(obj,src)}
        r.sources[src]=s
        if event then log('NEW_ID '..r.label..' source='..src..' stage='..phase) end
    else s.last=now end
    if event then s.events+=1 end
end
local function captureNode(obj,event,target)
    local src=classify(obj)
    if not src then return end
    if src=='CuttingMenu' and not menuVisible('CuttingMenu') then return end
    if src=='InventoryMenu' and not menuVisible('InventoryMenu') then return end
    local found={}
    if isUUID(obj.Name) then found[#found+1]={obj.Name,'Name'} end
    if obj:IsA('StringValue') and isUUID(obj.Value) then found[#found+1]={obj.Value,'StringValue'} end
    -- Attribute UUIDs sometimes hold the canonical item identifier.
    if (src=='RobloxBackpack' or src=='Cep' or src=='OtherPlayerData' or src=='OtherInventoryUI' or src=='MiningStorageUI')
        and inventoryHint(obj) then
        local ok,attrs=pcall(function()return obj:GetAttributes()end)
        if ok then
            for k,v in pairs(attrs) do
                if isUUID(v) then found[#found+1]={v,'Attribute'} end
            end
        end
    end
    for _,item in ipairs(found) do
        local id,how=item[1],item[2]
        track(id,src,obj,how,event)
        if event then
            local w=windowEvents[phase]
            if not w then w={};windowEvents[phase]=w end
            local sourceSet=w[src]
            if not sourceSet then sourceSet={};w[src]=sourceSet end
            sourceSet[id]=true
        end
        if target and seen[id] and seen[id].sources[src] then
            local e=target.ids[id]
            if not e then e={};target.ids[id]=e end
            e[src]=true
            target.sourceSets[src][id]=true
        end
    end
end
local function blankSnapshot(stage)
    local x={stage=stage,at=os.clock(),ids={},sourceSets={},scanned=0,truncated=false,
        bpTools=0,bpChildren=0,menuCut=menuVisible('CuttingMenu'),menuInv=menuVisible('InventoryMenu')}
    for _,s in ipairs(ROOTS) do x.sourceSets[s]={} end
    return x
end
local function scanFull(stage)
    local x=blankSnapshot(stage)
    local bp=backpack()
    if bp then
        x.bpChildren=#bp:GetChildren()
        for _,obj in ipairs(bp:GetChildren()) do if obj:IsA('Tool') then x.bpTools+=1 end end
    end
    -- Scoped recursion, with PlayerGui scanned once (not again via Player).
    for _,root in ipairs({player,pg,RS}) do
        if x.scanned>=scanLimit then x.truncated=true;break end
        captureNode(root,false,x)
        for _,obj in ipairs(root:GetDescendants()) do
            if root~=player or not isUnder(obj,pg) then
                x.scanned+=1
                captureNode(obj,false,x)
                if x.scanned>=scanLimit then x.truncated=true;break end
            end
        end
    end
    if x.truncated then pollCapped+=1 end
    lastScan=x
    return x
end
local function size(set)
    local n=0
    for _ in pairs(set or {}) do n+=1 end
    return n
end
local function intersection(a,b)
    local n=0
    for id in pairs(a or {}) do if b and b[id] then n+=1 end end
    return n
end
local function difference(a,b)
    local n=0
    for id in pairs(a or {}) do if not b or not b[id] then n+=1 end end
    return n
end
local function unionSet(x,srcs)
    local u={}
    if not x then return u end
    for _,src in ipairs(srcs) do
        for id in pairs(x.sourceSets[src] or {}) do u[id]=true end
    end
    return u
end
local function store(stage)
    local ok,x=pcall(scanFull,stage)
    if not ok then
        scanErrors+=1
        lastStatus='Snapshot error; see report.'
        log('SNAPSHOT_ERROR '..tostring(x):sub(1,90))
        return
    end
    snapshots[stage]=x
    local main=unionSet(x,{'RobloxBackpack','OtherPlayerData','InventoryMenu','OtherInventoryUI'})
    log(stage..' total='..size(x.ids)..' backpack='..size(x.sourceSets.RobloxBackpack)
        ..' otherPlayer='..size(x.sourceSets.OtherPlayerData)
        ..' cep='..size(x.sourceSets.Cep)..' cut='..size(x.sourceSets.CuttingMenu)
        ..' otherInv='..size(x.sourceSets.OtherInventoryUI)..' candidateMain='..size(main)
        ..(x.truncated and ' TRUNCATED' or ''))
    lastStatus=stage..' snapshot saved. Continue to next step.'
end
local function stageAction(stage,nextPhase)
    if stage=='BASELINE' and (menuVisible('CuttingMenu') or menuVisible('InventoryMenu')) then
        lastStatus='Close CuttingMenu and InventoryMenu before BASELINE.'
        return
    end
    if stage=='CUT_MENU' and not menuVisible('CuttingMenu') then
        lastStatus='Open CuttingMenu and wait for stone cards before CUT MENU.'
        return
    end
    store(stage)
    if snapshots[stage] then phase=nextPhase end
end
local function sourcesText(x)
    local arr={}
    for _,s in ipairs(ROOTS) do
        local n=size(x and x.sourceSets[s] or nil)
        if n>0 then arr[#arr+1]=s..'='..n end
    end
    return #arr>0 and table.concat(arr,' ') or 'none'
end
local function report()
    local baseline=snapshots.BASELINE
    local shop=snapshots.SHOP
    local mine=snapshots.MINING_INSIDE
    local returned=snapshots.RETURNED_BASE
    local cut=snapshots.CUT_MENU
    local cutIDs=cut and cut.sourceSets.CuttingMenu or {}
    local lines={
        'CUT A ROCK MAIN BACKPACK SOURCE AUDIT v1',
        'PlaceId='..tostring(game.PlaceId),
        'Stages=BASELINE:'..tostring(baseline~=nil)..' SHOP:'..tostring(shop~=nil)
            ..' MINING_INSIDE:'..tostring(mine~=nil)..' RETURNED_BASE:'..tostring(returned~=nil)
            ..' CUT_MENU:'..tostring(cut~=nil),
        'TrackedUniqueUUIDs='..labels..' Limit='..maxTracked,
        'BackpackSource=UNVERIFIED (until exact matches and stage deltas establish it)',
        'EventAdds='..eventAdds..' EventRemoves='..eventRemoves
            ..' ScanErrors='..scanErrors..' TruncatedSnapshots='..pollCapped,
        'NOTE: Roblox Backpack may hold Tools, while the game may use custom main inventory.',
        'NOTE: Cep is a candidate source, not automatically proof of main backpack availability.',
        'NOTE: UUID values and player identifiers redacted. No game state modifications.',
        '--- SNAPSHOT SOURCES ---'
    }
    for _,name in ipairs({'BASELINE','SHOP','MINING_INSIDE','RETURNED_BASE','CUT_MENU'}) do
        local x=snapshots[name]
        if x then
            lines[#lines+1]=name..' totalUnique='..size(x.ids)
                ..' scanned='..x.scanned..' truncated='..tostring(x.truncated)
                ..' backpackChildren='..x.bpChildren..' backpackTools='..x.bpTools
                ..' cuttingMenuOpen='..tostring(x.menuCut)
            lines[#lines+1]='  '..sourcesText(x)
        else lines[#lines+1]=name..'=NOT_CAPTURED' end
    end
    lines[#lines+1]='--- EXACT ID MATCH TO CUTTING MENU ---'
    for _,src in ipairs(ROOTS) do
        -- Most useful validation is exact item ID equality, not nearby timestamps.
        local inCut=cut and cut.sourceSets[src] or {}
        local ever={}
        for id,r in pairs(seen) do if r.sources[src] then ever[id]=true end end
        lines[#lines+1]=src..' snapshot='..intersection(inCut,cutIDs)
            ..' everSeen='..intersection(ever,cutIDs)
    end
    lines[#lines+1]='--- STAGE DELTAS (ID level) ---'
    local function delta(a,b,key)
        if not a then return key..'=NOT_CAPTURED' end
        local as=unionSet(a,{'RobloxBackpack','OtherPlayerData','InventoryMenu','OtherInventoryUI'})
        local bs=unionSet(b,{'RobloxBackpack','OtherPlayerData','InventoryMenu','OtherInventoryUI'})
        local newMain={}
        for id in pairs(as) do if not bs[id] then newMain[id]=true end end
        return key..' newCandidateMain='..difference(as,bs)
            ..' newCep='..difference(a.sourceSets.Cep,b and b.sourceSets.Cep)
            ..' newMiningUI='..difference(a.sourceSets.MiningStorageUI,b and b.sourceSets.MiningStorageUI)
            ..' newAll='..difference(a.ids,b and b.ids)
            ..' newMainMatchedCut='..intersection(newMain,cutIDs)
    end
    lines[#lines+1]=delta(shop,baseline,'SHOP_AFTER_BASELINE')
    lines[#lines+1]=delta(mine,shop or baseline,'MINING_INSIDE_AFTER_PREVIOUS')
    lines[#lines+1]=delta(returned,mine,'RETURNED_BASE_AFTER_MINING')
    lines[#lines+1]='--- SHORT-LIVED UUID EVENTS BETWEEN STAGES ---'
    for _,wname in ipairs({'WAIT_SHOP','WAIT_MINING','WAIT_RETURN','WAIT_CUT_MENU'}) do
        local w=windowEvents[wname] or {}
        local parts={}
        for _,src in ipairs(ROOTS) do
            local sets=w[src] or {}
            if size(sets)>0 then
                parts[#parts+1]=src..'='..size(sets)..'(cutMatch='..intersection(sets,cutIDs)..')'
            end
        end
        lines[#lines+1]=wname..' '..(#parts>0 and table.concat(parts,' ') or 'none')
    end
    lines[#lines+1]='--- CANDIDATE PATHS EXACT-MATCHED TO CUT MENU (max 24) ---'
    local out={}
    for id in pairs(cutIDs) do
        local r=seen[id]
        if r then
            for _,src in ipairs(ROOTS) do
                if src~='CuttingMenu' and r.sources[src] then
                    local s=r.sources[src]
                    out[#out+1]={first=r.first,line=r.label..' | '..src
                        ..' | firstStage='..s.phase..' | method='..s.how..' | '..s.path}
                end
            end
        end
    end
    table.sort(out,function(a,b)
        if a.first~=b.first then return a.first<b.first end
        return a.line<b.line
    end)
    if #out==0 then lines[#lines+1]='none yet' end
    for i=1,math.min(24,#out) do lines[#lines+1]=out[i].line end
    lines[#lines+1]='--- NOTABLE INVENTORY SOURCES (up to 16) ---'
    local candidates={}
    for id,r in pairs(seen) do
        if r.sources.RobloxBackpack or r.sources.OtherPlayerData
          or r.sources.OtherInventoryUI or r.sources.MiningStorageUI then
            local c=r.sources.RobloxBackpack or r.sources.OtherPlayerData
                or r.sources.OtherInventoryUI or r.sources.MiningStorageUI
            candidates[#candidates+1]={first=r.first,line=r.label..' | '
                ..(r.sources.RobloxBackpack and 'RobloxBackpack' or
                    r.sources.OtherPlayerData and 'OtherPlayerData' or
                    r.sources.OtherInventoryUI and 'OtherInventoryUI' or 'MiningStorageUI')
                ..' | cutMatched='..tostring(cutIDs[id]~=nil)
                ..' | '..c.path}
        end
    end
    table.sort(candidates,function(a,b)return a.first<b.first end)
    if #candidates==0 then lines[#lines+1]='none; main inventory may be maintained in client Lua tables or server-only data' end
    for i=1,math.min(16,#candidates) do lines[#lines+1]=candidates[i].line end
    lines[#lines+1]='--- TIMELINE ---'
    for _,line in ipairs(recent) do lines[#lines+1]=line end
    return table.concat(lines,'\n')
end

local gui=Instance.new('ScreenGui')
gui.Name='CAR_MainBackpackAudit_v1'
gui.ResetOnSpawn=false
gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
gui.Parent=pg
local function mk(class,props,parent)
    local o=Instance.new(class)
    for k,v in pairs(props) do o[k]=v end
    o.Parent=parent
    return o
end
local panel=mk('Frame',{Size=UDim2.fromOffset(300,354),
    Position=UDim2.new(0,13,0.13,0),BackgroundColor3=Color3.fromRGB(23,29,40),
    BorderSizePixel=0},gui)
mk('UICorner',{CornerRadius=UDim.new(0,10)},panel)
mk('UIStroke',{Color=Color3.fromRGB(80,103,128),Thickness=1},panel)
local title=mk('TextLabel',{Text='CAR | MAIN BACKPACK AUDIT v1',
    Size=UDim2.fromOffset(232,34),Position=UDim2.fromOffset(10,4),
    BackgroundTransparency=1,TextColor3=Color3.new(1,1,1),
    Font=Enum.Font.GothamBold,TextSize=12,TextXAlignment=Enum.TextXAlignment.Left},panel)
local function button(text,x,y,w,h,fn)
    local b=mk('TextButton',{Text=text,Size=UDim2.fromOffset(w,h),
        Position=UDim2.fromOffset(x,y),TextColor3=Color3.new(1,1,1),
        TextSize=11,Font=Enum.Font.GothamMedium,BorderSizePixel=0,
        BackgroundColor3=Color3.fromRGB(48,78,110)},panel)
    mk('UICorner',{CornerRadius=UDim.new(0,6)},b)
    if fn then conns[#conns+1]=b.Activated:Connect(fn) end
    return b
end
local small=false
local status=mk('TextLabel',{Text='',Size=UDim2.fromOffset(278,73),
    Position=UDim2.fromOffset(11,46),BackgroundTransparency=1,
    TextColor3=Color3.fromRGB(194,215,235),Font=Enum.Font.Gotham,
    TextSize=11,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,
    TextYAlignment=Enum.TextYAlignment.Top},panel)
button('_',240,6,23,26,function()
    small=not small
    panel.Size=UDim2.fromOffset(300,small and 37 or 354)
    for _,child in ipairs(panel:GetChildren()) do
        if child:IsA('GuiObject') and child~=title then
            -- Minimize button and close button must remain visible.
            if child.Name~='Minimizer' and child.Name~='CloseButton' then child.Visible=not small end
        end
    end
end).Name='Minimizer'
local function stop()
    alive=false
    for _,conn in ipairs(conns) do pcall(function()conn:Disconnect()end) end
    if gui.Parent then gui:Destroy() end
    if env.CARMainBackpackAuditStop==stop then env.CARMainBackpackAuditStop=nil end
end
env.CARMainBackpackAuditStop=stop
button('X',266,6,23,26,stop).Name='CloseButton'
button('1 BASELINE',11,133,134,35,function()stageAction('BASELINE','WAIT_SHOP')end)
button('2 AFTER SHOP',155,133,134,35,function()stageAction('SHOP','WAIT_MINING')end)
button('3 IN MINING',11,176,134,35,function()stageAction('MINING_INSIDE','WAIT_RETURN')end)
button('4 BACK AT BASE',155,176,134,35,function()stageAction('RETURNED_BASE','WAIT_CUT_MENU')end)
button('5 CUT MENU',11,219,134,35,function()stageAction('CUT_MENU','DONE')end)
button('COPY REPORT',155,219,134,35,function()
    local r=report()
    print(r)
    local clipboard=type(setclipboard)=='function' and setclipboard or
        (type(toclipboard)=='function' and toclipboard or nil)
    if clipboard then
        local ok=pcall(clipboard,r)
        lastStatus=ok and 'Report copied. Send to ChatGPT.' or 'Copy failed; report in console.'
    else lastStatus='Report printed to executor console.' end
end)
mk('TextLabel',{Text='Passive only. Shop purchase is MANUAL.\nNo cut/collect/teleport; only snapshot IDs.',
    Size=UDim2.fromOffset(278,42),Position=UDim2.fromOffset(11,264),
    BackgroundTransparency=1,Font=Enum.Font.Gotham,TextSize=10,
    TextColor3=Color3.fromRGB(164,183,200),TextWrapped=true},panel)
local footer=mk('TextLabel',{Text='',Size=UDim2.fromOffset(278,35),
    Position=UDim2.fromOffset(11,310),BackgroundTransparency=1,
    Font=Enum.Font.Gotham,TextSize=10,TextWrapped=true,
    TextColor3=Color3.fromRGB(151,176,205)},panel)
local dragging=false
local dragStart,fromPos
conns[#conns+1]=title.InputBegan:Connect(function(inp)
    if inp.UserInputType==Enum.UserInputType.Touch or inp.UserInputType==Enum.UserInputType.MouseButton1 then
        dragging=true;dragStart=inp.Position;fromPos=panel.Position
        local change
        change=inp.Changed:Connect(function()
            if inp.UserInputState==Enum.UserInputState.End then dragging=false;change:Disconnect() end
        end)
    end
end)
conns[#conns+1]=UIS.InputChanged:Connect(function(inp)
    if dragging and dragStart and (inp.UserInputType==Enum.UserInputType.Touch
        or inp.UserInputType==Enum.UserInputType.MouseMovement) then
        local d=inp.Position-dragStart
        panel.Position=UDim2.new(fromPos.X.Scale,fromPos.X.Offset+d.X,
            fromPos.Y.Scale,fromPos.Y.Offset+d.Y)
    end
end)
-- Event capture: records transient UUID instances in Cep and UI when they appear.
-- These observations are candidate provenance, not server inventory confirmations.
local function onAdded(obj)
    if not alive or (not isUUID(obj.Name) and not (obj:IsA('StringValue') and isUUID(obj.Value))) then return end
    eventAdds+=1
    captureNode(obj,true,nil)
end
conns[#conns+1]=player.DescendantAdded:Connect(function(obj)
    if not isUnder(obj,pg) then onAdded(obj) end
end)
conns[#conns+1]=pg.DescendantAdded:Connect(onAdded)
conns[#conns+1]=RS.DescendantAdded:Connect(onAdded)
conns[#conns+1]=player.DescendantRemoving:Connect(function(obj)
    if alive and isUUID(obj.Name) then eventRemoves+=1 end
end)
log('AUDIT_LOADED; no game actions; baseline menus closed recommended')
task.spawn(function()
    while alive do
        local ok,err=pcall(function()
            local cut=menuVisible('CuttingMenu')
            if cut and not lastCutOpen then machineMenuOpened+=1;log('CUTTING_MENU_OPEN') end
            lastCutOpen=cut
            if cut then
                -- Visible card matches may be missed by creation events while hidden.
                local m=pg:FindFirstChild('CuttingMenu')
                if m then
                    for _,node in ipairs(m:GetDescendants()) do
                        if node:IsA('GuiButton') and isUUID(node.Name) then captureNode(node,false,nil) end
                    end
                end
            end
            local cep=player:FindFirstChild('Cep')
            if cep then
                for _,node in ipairs(cep:GetChildren()) do
                    if isUUID(node.Name) then captureNode(node,false,nil) end
                end
            end
            pollCount+=1
            status.Text='Stage: '..phase..' | Tracked IDs: '..labels
                ..'\nShop, mining, return and cut menu snapshots are manual.'
                ..'\n'..lastStatus
            footer.Text='Snapshots: '..(snapshots.BASELINE and 'B' or '-')
                ..(snapshots.SHOP and 'S' or '-')..(snapshots.MINING_INSIDE and 'M' or '-')
                ..(snapshots.RETURNED_BASE and 'R' or '-')..(snapshots.CUT_MENU and 'C' or '-')
                ..' | Cut menu opens: '..machineMenuOpened
        end)
        if not ok then scanErrors+=1;log('POLL_ERROR '..tostring(err):sub(1,85)) end
        task.wait(0.65)
    end
end)
print('[CAR Main Backpack Audit] BASELINE -> manual Shop buy -> AFTER SHOP -> mine and stay -> IN MINING -> return to base -> BACK AT BASE -> open CuttingMenu -> CUT MENU -> COPY REPORT.')

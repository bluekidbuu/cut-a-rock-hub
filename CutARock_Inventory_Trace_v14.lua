-- Cut a Rock | Inventory UUID Provenance Trace v1.4 (read-only)
-- PlaceId 113742027864370 / UniverseId 10766468833
-- Question: are UUID-named objects under Player.Cep or ReplicatedStorage
-- the SAME IDs that later appear as raw-stone cards in CuttingMenu?
-- No remote dispatch, teleport, UI auto-click, game-state modification or purchases.
-- Report anonymizes UUIDs (session-local S1, S2...).

if not game:IsLoaded() then game.Loaded:Wait() end
if game.PlaceId ~= 113742027864370 and game.GameId ~= 10766468833 then
    warn('[CAR Inventory Trace v1.4] Wrong game; disabled')
    return
end

local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local UIS=game:GetService('UserInputService')
local player=Players.LocalPlayer
local pg=player:WaitForChild('PlayerGui')
local env=type(getgenv)=='function' and getgenv() or _G
if type(env.CARInventoryTraceStop)=='function' then pcall(env.CARInventoryTraceStop) end

local alive=true
local started=os.clock()
local conns={}
local history={}
local records={}
local instanceRefs=setmetatable({}, {__mode='k'})
local baselineIds={}
local baselineCepIds={}
local baselineSet=false
local watch=true
local everCut={}
local menuSnapshots=0
local closedSnapshots=0
local eventAdds=0
local eventRemoves=0
local scanErrors=0
local latestCep=0
local latestCut=0
local latestRS=0
local seenCount=0
local nextLabel=0
local status='MARK BEFORE with both menus CLOSED. Obtain 2-3 stones.'
local CAP=1500
local uuidPat='^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$'
local function isUUID(s)
    return type(s)=='string' and #s==36 and s:match(uuidPat)~=nil
end
local function log(s)
    history[#history+1]=string.format('T+%.1f %s',os.clock()-started,tostring(s))
    if #history>64 then table.remove(history,1) end
end
local function under(node,anc)
    while node do if node==anc then return true end;node=node.Parent end
    return false
end
local function menuOpen(name)
    local m=pg:FindFirstChild(name)
    if not m then return false end
    if m:IsA('ScreenGui') and not m.Enabled then return false end
    local frame=m:FindFirstChild('MainFrame')
    if frame and frame:IsA('GuiObject') and not frame.Visible then return false end
    return true
end
local function menusClosed()
    return not menuOpen('CuttingMenu') and not menuOpen('InventoryMenu')
end
local function cepOf(node)
    local p=node
    while p and p~=player and p~=pg do
        if p.Name=='Cep' and under(p,player) and not under(p,pg) then return p end
        p=p.Parent
    end
    return nil
end
local function source(node)
    local cutting=pg:FindFirstChild('CuttingMenu')
    if cutting and under(node,cutting) then return 'CuttingMenu' end
    local cep=cepOf(node)
    if cep then return 'Cep' end
    if under(node,RS) then return 'ReplicatedStorage' end
    if under(node,pg) then return 'OtherGui' end
    if under(node,player) then return 'OtherPlayer' end
    return 'Other'
end
local function safePath(obj,root)
    local names={}
    local p=obj
    while p and p~=root and #names<7 do
        local name=isUUID(p.Name) and '<stone-id>' or p.Name:gsub('[\r\n\t]',' '):sub(1,36)
        names[#names+1]=name
        p=p.Parent
    end
    local out={}
    for i=#names,1,-1 do out[#out+1]=names[i] end
    return table.concat(out,'/')
end
local function makeRecord(id)
    local r=records[id]
    if not r then
        if seenCount>=CAP then return nil end
        nextLabel+=1
        seenCount+=1
        r={id=id,label='S'..nextLabel,src={},closed=false,closedFirst=false,
           newSinceBaseline=false,cut=false,created=os.clock(),firstCep=nil,
           firstRS=nil,firstCut=nil}
        records[id]=r
    end
    return r
end
local function observeID(id,obj,how,via)
    if not alive or not isUUID(id) then return end
    local src=source(obj)
    if src~='Cep' and src~='ReplicatedStorage' and src~='CuttingMenu' then return end
    if src=='CuttingMenu' then
        -- Only candidate stone cards, not the current cut/result panel.
        if not obj:IsA('GuiButton') then return end
        local p=obj
        while p and p~=pg do
            if p.Name=='CurrentCut' or p.Name=='FinishCard' or p.Name=='KesimPaneli'
              or p.Name=='CutStoneTab' or p.Name=='StonePhoto' then return end
            p=p.Parent
        end
    end
    local r=makeRecord(id)
    if not r then return end
    local now=os.clock()
    local entry=r.src[src]
    if not entry then
        local root=(src=='ReplicatedStorage' and RS)
            or (src=='CuttingMenu' and pg) or player
        entry={first=now,last=now,events=0,method=how,path=safePath(obj,root),class=obj.ClassName}
        r.src[src]=entry
        if src=='Cep' then r.firstCep=now end
        if src=='ReplicatedStorage' then r.firstRS=now end
        if src=='CuttingMenu' then r.firstCut=now end
        local tag=baselineSet and not baselineIds[id] and 'NEW' or 'EXISTING'
        if baselineSet and not baselineIds[id] then r.newSinceBaseline=true end
        if src=='Cep' or (src=='CuttingMenu' and baselineSet) then
            log(tag..' '..src..' '..r.label..' '..entry.path..' ('..how..'/'..via..')')
        end
    else
        entry.last=now
    end
    entry.events+=1
    if src=='Cep' and menusClosed() then
        if not r.closed then r.closedFirst=true end
        r.closed=true
    end
    if src=='ReplicatedStorage' and r.src.CuttingMenu and not r.rsLogged then
        r.rsLogged=true
        log('CROSS_MATCH '..r.label..' ReplicatedStorage => CuttingMenu')
    end
    if src=='CuttingMenu' then
        r.cut=true
        everCut[id]=true
        if r.closed and not r.cutLogged then
            r.cutLogged=true
            log('CROSS_MATCH '..r.label..' Cep-when-closed => CuttingMenu')
        end
        if r.src.ReplicatedStorage and not r.rsLogged then
            r.rsLogged=true
            log('CROSS_MATCH '..r.label..' ReplicatedStorage => CuttingMenu')
        end
    end
    if src=='Cep' and r.closed and r.src.CuttingMenu and not r.cutLogged then
        r.cutLogged=true
        log('CROSS_MATCH '..r.label..' Cep-when-closed => CuttingMenu')
    end
    -- Capture event lifecycles for original UUID-named instances.
    if id==obj.Name then instanceRefs[obj]={id=id,src=src,first=now} end
end
local function inspectNode(o,via)
    if isUUID(o.Name) then observeID(o.Name,o,'Name',via) end
    if o:IsA('StringValue') and isUUID(o.Value) then
        observeID(o.Value,o,'StringValue',via)
    end
end
local function relevant(node)
    local s=source(node)
    return s=='Cep' or s=='ReplicatedStorage' or s=='CuttingMenu'
end
local function snapshotCep()
    local n=0
    -- Scan only the pocket subtree; do not traverse every ScreenGui every 0.45s.
    local folder=player:FindFirstChild('Cep') or player:FindFirstChild('Cep',true)
    if folder and under(folder,pg) then folder=nil end
    if folder then
        for _,obj in ipairs(folder:GetDescendants()) do
            inspectNode(obj,'cep-poll')
            if isUUID(obj.Name) then n+=1 end
        end
    end
    latestCep=n
    return n
end
local function snapshotCut()
    local m=pg:FindFirstChild('CuttingMenu')
    local n=0
    if m and menuOpen('CuttingMenu') then
        for _,obj in ipairs(m:GetDescendants()) do
            if obj:IsA('GuiButton') and isUUID(obj.Name) then
                inspectNode(obj,'cut-poll')
                if records[obj.Name] and records[obj.Name].src.CuttingMenu then n+=1 end
            end
        end
    end
    latestCut=n
    return n
end
local function snapshotRS()
    local n=0
    for _,obj in ipairs(RS:GetDescendants()) do
        if isUUID(obj.Name) or (obj:IsA('StringValue') and isUUID(obj.Value)) then
            inspectNode(obj,'rs-snapshot')
            n+=1
        end
    end
    latestRS=n
    return n
end
local function countRecords(filter)
    local n=0
    for _,r in pairs(records) do if filter(r) then n+=1 end end
    return n
end
local function snapshotAll()
    local ok,err=pcall(function()
        snapshotCep();snapshotCut();snapshotRS()
    end)
    if not ok then scanErrors+=1;log('SCAN_ERROR '..tostring(err):sub(1,85)) end
end
local function baselineMark()
    if not menusClosed() then
        status='Close CuttingMenu and InventoryMenu before MARK BEFORE.'
        log('BASELINE_REFUSED menu open')
        return
    end
    snapshotAll()
    baselineIds={}
    baselineCepIds={}
    for id,r in pairs(records) do
        baselineIds[id]=true
        if r.src.Cep then baselineCepIds[id]=true end
    end
    -- Keep historical records so an ID can be correlated across sources.
    baselineSet=true
    for _,r in pairs(records) do
        r.closed=false;r.closedFirst=false;r.newSinceBaseline=false;r.cut=false
        r.cutLogged=nil;r.rsLogged=nil
        r.firstCep=nil;r.firstCut=nil;r.firstRS=nil
        -- Retain Cep/RS provenance known before baseline for later exact-ID comparison.
        -- Clear old menu evidence, because we only want cards observed AFTER baseline.
        r.src.CuttingMenu=nil
    end
    log('BASELINE set knownIDs='..seenCount..' Cep='..latestCep..' RS='..latestRS)
    status='Baseline set. Get 2-3 NEW stones without opening either menu.'
end
local function snapshotClosed()
    if not menusClosed() then
        status='Close both menus for SNAPSHOT CLOSED.'
        return
    end
    local before=countRecords(function(r) return r.src.Cep~=nil end)
    snapshotCep()
    closedSnapshots+=1
    local after=countRecords(function(r) return r.src.Cep~=nil end)
    log('SNAPSHOT_CLOSED Cep objects='..latestCep..' trackedCepIDs='..after..' delta='..(after-before))
    status='Closed snapshot complete. Open a cutting machine and SNAPSHOT CUT.'
end
local function snapshotCutNow()
    if not menuOpen('CuttingMenu') then
        status='Open CuttingMenu until raw stone cards are displayed.'
        return
    end
    snapshotCut()
    -- RS can already contain inventory-related UUIDs before the test started.
    -- Re-read it here so we do not lose a potential exact match.
    snapshotRS()
    menuSnapshots+=1
    local matched=countRecords(function(r) return r.src.Cep and r.src.CuttingMenu and r.closed end)
    local rsMatch=countRecords(function(r) return r.src.ReplicatedStorage and r.src.CuttingMenu end)
    log('SNAPSHOT_CUT cards='..latestCut..' CepClosedMatches='..matched..' RSMatches='..rsMatch)
    status='Cut menu snapshot complete. COPY REPORT for source correlation.'
end
local function buildReport()
    local newCep=countRecords(function(r) return r.src.Cep and r.closed and not baselineCepIds[r.id] end)
    local newRS=countRecords(function(r) return r.src.ReplicatedStorage and not baselineIds[r.id] end)
    local cutIDs=countRecords(function(r) return r.src.CuttingMenu end)
    local cepMatch=countRecords(function(r) return r.src.Cep and r.src.CuttingMenu and r.closed end)
    local rsMatch=countRecords(function(r) return r.src.ReplicatedStorage and r.src.CuttingMenu end)
    local lines={
        'CUT A ROCK INVENTORY PROVENANCE TRACE v1.4',
        'PlaceId='..tostring(game.PlaceId),
        'BaselineSet='..tostring(baselineSet),
        'MenusNowClosed='..tostring(menusClosed()),
        'SnapshotsClosed='..closedSnapshots..' SnapshotsCut='..menuSnapshots,
        'CurrentCepUUIDObjects='..latestCep..' CurrentCutCards='..latestCut..' RSUUIDCandidates='..latestRS,
        'TrackedUniqueIDs='..seenCount..' RecordsCap='..CAP,
        'NewCepIDsWhileClosed='..newCep,
        'NewReplicatedStorageIDs='..newRS,
        'CuttingMenuIDs='..cutIDs,
        'ExactCepToCutMatches='..cepMatch,
        'ExactRSToCutMatches='..rsMatch,
        'EventAdds='..eventAdds..' EventRemoves='..eventRemoves..' ScanErrors='..scanErrors,
        'NOTE: UUIDs and player identifiers are not exported.',
        'NOTE: A Cep/RS UUID is NOT proven to be a raw inventory stone unless it exactly matches a CuttingMenu stone card.',
        'NOTE: This trace never sends remotes or changes game state.',
        '--- CANDIDATE SOURCE PATHS / MATCHES (max 25) ---',
    }
    local arr={}
    for _,r in pairs(records) do
        if (r.src.Cep and r.closed and not baselineCepIds[r.id])
            or (r.src.CuttingMenu and r.src.Cep and r.closed)
            or (r.src.CuttingMenu and r.src.ReplicatedStorage)
            or r.newSinceBaseline then
            arr[#arr+1]=r
        end
    end
    table.sort(arr,function(a,b) return a.created<b.created end)
    local limit=math.min(#arr,25)
    for i=1,limit do
        local r=arr[i]
        local parts={r.label,
            r.src.Cep and 'Cep' or '-',
            r.src.ReplicatedStorage and 'RS' or '-',
            r.src.CuttingMenu and 'CUT' or '-',
            'closedCep='..tostring(r.closed),
            'exactMatch='..tostring(r.src.Cep~=nil and r.src.CuttingMenu~=nil),
        }
        local e=r.src.Cep or r.src.ReplicatedStorage or r.src.CuttingMenu
        if e then parts[#parts+1]='class='..e.class..' path='..e.path end
        lines[#lines+1]=table.concat(parts,' | ')
    end
    if #arr==0 then lines[#lines+1]='none' end
    lines[#lines+1]='--- TIMELINE (last 64 events) ---'
    for _,h in ipairs(history) do lines[#lines+1]=h end
    return table.concat(lines,'\n')
end

local gui=Instance.new('ScreenGui')
gui.Name='CAR_InventoryTrace_v14'
gui.ResetOnSpawn=false
gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
gui.Parent=pg
local function create(cl,props,parent)
    local o=Instance.new(cl)
    for k,v in pairs(props) do o[k]=v end
    o.Parent=parent
    return o
end
local panel=create('Frame',{
    Size=UDim2.fromOffset(332,362),Position=UDim2.new(0,12,0.12,0),
    BackgroundColor3=Color3.fromRGB(23,28,39),BorderSizePixel=0
},gui)
create('UICorner',{CornerRadius=UDim.new(0,11)},panel)
create('UIStroke',{Color=Color3.fromRGB(78,99,124),Thickness=1},panel)
local title=create('TextLabel',{
    Text='CUT A ROCK | INVENTORY TRACE v1.4',
    TextSize=13,Font=Enum.Font.GothamBold,TextXAlignment=Enum.TextXAlignment.Left,
    BackgroundTransparency=1,TextColor3=Color3.new(1,1,1),
    Size=UDim2.fromOffset(281,36),Position=UDim2.fromOffset(10,3)
},panel)
local info=create('TextLabel',{
    Text='',TextSize=11,Font=Enum.Font.Gotham,TextWrapped=true,
    TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,
    BackgroundTransparency=1,TextColor3=Color3.fromRGB(191,213,235),
    Size=UDim2.fromOffset(312,111),Position=UDim2.fromOffset(11,45)
},panel)
local function button(txt,x,y,w,fn)
    local b=create('TextButton',{
        Text=txt,TextSize=12,Font=Enum.Font.GothamMedium,
        TextColor3=Color3.new(1,1,1),BackgroundColor3=Color3.fromRGB(48,76,107),
        Size=UDim2.fromOffset(w,38),Position=UDim2.fromOffset(x,y),BorderSizePixel=0
    },panel)
    create('UICorner',{CornerRadius=UDim.new(0,7)},b)
    if fn then conns[#conns+1]=b.Activated:Connect(fn) end
    return b
end
button('MARK BEFORE',11,165,151,baselineMark)
button('SNAPSHOT CLOSED',171,165,150,snapshotClosed)
button('SNAPSHOT CUT',11,212,151,snapshotCutNow)
button('COPY REPORT',171,212,150,function()
    local txt=buildReport()
    print(txt)
    local cb=type(setclipboard)=='function' and setclipboard or
        (type(toclipboard)=='function' and toclipboard or nil)
    status=cb and pcall(cb,txt) and 'Report copied to clipboard.'
        or 'Report printed to executor console.'
end)
create('TextLabel',{
    Text='Read-only. Keep both menus closed while collecting.\nThen open Cut menu ONCE and snapshot its stone cards.',
    TextSize=10,Font=Enum.Font.Gotham,TextWrapped=true,
    TextColor3=Color3.fromRGB(166,187,207),BackgroundTransparency=1,
    Size=UDim2.fromOffset(310,43),Position=UDim2.fromOffset(11,269)
},panel)
local function stop()
    alive=false
    for _,c in ipairs(conns) do pcall(function()c:Disconnect()end) end
    gui:Destroy()
    if env.CARInventoryTraceStop==stop then env.CARInventoryTraceStop=nil end
end
env.CARInventoryTraceStop=stop
button('CLOSE',11,317,310,35,stop)
local dragging,startPos,framePos=false,nil,nil
conns[#conns+1]=title.InputBegan:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
        dragging=true;startPos=i.Position;framePos=panel.Position
        local localConn
        localConn=i.Changed:Connect(function()
            if i.UserInputState==Enum.UserInputState.End then
                dragging=false;localConn:Disconnect()
            end
        end)
    end
end)
conns[#conns+1]=UIS.InputChanged:Connect(function(i)
    if dragging and startPos and
      (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
        local delta=i.Position-startPos
        panel.Position=UDim2.new(framePos.X.Scale,framePos.X.Offset+delta.X,
            framePos.Y.Scale,framePos.Y.Offset+delta.Y)
    end
end)

-- Event-driven capture keeps ephemeral Player.Cep objects even if they last <1s.
conns[#conns+1]=player.DescendantAdded:Connect(function(obj)
    if alive and baselineSet and not under(obj,pg) and cepOf(obj) then
        eventAdds+=1
        inspectNode(obj,'player-added')
    end
end)
conns[#conns+1]=player.DescendantRemoving:Connect(function(obj)
    if not alive or not baselineSet then return end
    local ref=instanceRefs[obj]
    if ref and ref.src=='Cep' then
        eventRemoves+=1
        local r=records[ref.id]
        if r and r.src.Cep then
            r.src.Cep.removedAt=os.clock()
            log('CEp_REMOVED '..r.label)
        end
    end
end)
conns[#conns+1]=RS.DescendantAdded:Connect(function(obj)
    if alive and baselineSet and
        (isUUID(obj.Name) or (obj:IsA('StringValue') and isUUID(obj.Value))) then
        eventAdds+=1
        inspectNode(obj,'rs-added')
    end
end)
conns[#conns+1]=pg.DescendantAdded:Connect(function(obj)
    if alive and baselineSet and isUUID(obj.Name) then
        local cut=pg:FindFirstChild('CuttingMenu')
        if cut and under(obj,cut) then
            eventAdds+=1
            inspectNode(obj,'ui-added')
        end
    end
end)

snapshotAll()
log('TRACE_LOADED Cep='..latestCep..' RS='..latestRS..' Cut='..latestCut)
task.spawn(function()
    while alive do
        if watch then
            local ok,err=pcall(function() snapshotCep(); snapshotCut() end)
            if not ok then
                scanErrors+=1
                log('POLL_ERROR '..tostring(err):sub(1,80))
            end
        end
        local cc=countRecords(function(r) return r.src.Cep and r.closed and not baselineCepIds[r.id] end)
        local mx=countRecords(function(r) return r.src.Cep and r.src.CuttingMenu and r.closed end)
        info.Text=string.format('Baseline: %s | Menus closed: %s\nNew Cep IDs while closed: %d | Exact match in Cut: %d\nCurrent Cep objects: %d | Cut cards: %d\n%s',
            baselineSet and 'YES' or 'NO',tostring(menusClosed()),cc,mx,
            latestCep,latestCut,status)
        task.wait(0.45)
    end
end)
print('[CAR Inventory Trace v1.4] MARK BEFORE (menus closed), obtain 2-3 stones, SNAPSHOT CLOSED, open CuttingMenu, SNAPSHOT CUT, COPY REPORT.')

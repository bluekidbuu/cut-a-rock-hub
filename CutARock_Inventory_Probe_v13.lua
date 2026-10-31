-- Cut a Rock | Passive Inventory Source Probe v1.3
-- PlaceId 113742027864370 | GameId 10766468833
-- PURPOSE: find where fresh raw-stone identifiers become visible in the client
-- when CuttingMenu is CLOSED. No FireServer, InvokeServer, teleport, cut or collect.
-- Reports anonymised IDs and structural paths, never raw UUIDs.

if not game:IsLoaded() then game.Loaded:Wait() end
if game.PlaceId ~= 113742027864370 and game.GameId ~= 10766468833 then
    warn('[CAR Inventory Probe] Wrong game; stopped.')
    return
end

local Players = game:GetService('Players')
local RS = game:GetService('ReplicatedStorage')
local UIS = game:GetService('UserInputService')
local player = Players.LocalPlayer
local pg = player:WaitForChild('PlayerGui')
local env = type(getgenv) == 'function' and getgenv() or _G
if type(env.CARInventoryProbeStop) == 'function' then
    pcall(env.CARInventoryProbeStop)
end

local active, monitoring, baseline = true, true, nil
local connections, history = {}, {}
local started = os.clock()
local samples, cappedSamples = 0, 0
local scanLimit = 24000 -- limits work during live play on Android
local uuidLabels, nextUuidLabel = {}, 0
local latest = nil
local baselineAt = nil
local seenAfterBaseline, firstSeen = {}, {}
local peakBySource = {}
local remoteCount = {}
local changedNumeric = {}
local lastMessage = 'Stand away from Cutting Machine; MARK BEFORE, then collect a rock.'
local updateStatus

local uuidPattern = '^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$'
local function isUUID(v)
    return type(v) == 'string' and #v == 36 and v:match(uuidPattern) ~= nil
end
local function idLabel(v)
    local label = uuidLabels[v]
    if not label then
        nextUuidLabel += 1
        label = 'S' .. nextUuidLabel
        uuidLabels[v] = label
    end
    return label
end
local function log(line)
    history[#history + 1] = ('T+%.1fs '):format(os.clock() - started) .. tostring(line)
    if #history > 54 then table.remove(history, 1) end
end
local function menuOpen(name)
    local m = pg:FindFirstChild(name)
    if not m then return false end
    if m:IsA('ScreenGui') and not m.Enabled then return false end
    local panel = m:FindFirstChild('MainFrame')
    if panel and panel:IsA('GuiObject') and not panel.Visible then return false end
    return true
end
local function anyMenuOpen()
    return menuOpen('CuttingMenu') or menuOpen('InventoryMenu')
end
local function relativePath(obj, scope)
    local parts = {}
    local node = obj
    while node and node ~= scope and #parts < 9 do
        local name = node.Name
        if isUUID(name) then name = '<stone-id>' end
        -- Keep only structural names; do not expose arbitrary user text.
        name = name:gsub('[\r\n\t]', ' ')
        parts[#parts + 1] = name:sub(1, 44)
        node = node.Parent
    end
    local reversed = {}
    for i = #parts, 1, -1 do reversed[#reversed + 1] = parts[i] end
    return table.concat(reversed, '/')
end
local function isIn(node, parent)
    while node do
        if node == parent then return true end
        node = node.Parent
    end
    return false
end
local function sourceName(node)
    local cutting = pg:FindFirstChild('CuttingMenu')
    local invent = pg:FindFirstChild('InventoryMenu')
    if cutting and isIn(node, cutting) then return 'CuttingMenu' end
    if invent and isIn(node, invent) then return 'InventoryMenu' end
    if isIn(node, pg) then return 'PlayerGuiOther' end
    if isIn(node, player) then return 'PlayerData' end
    if isIn(node, RS) then return 'ReplicatedStorage' end
    return 'Other'
end
local function restrictedRoot(node)
    local src = sourceName(node)
    if src == 'ReplicatedStorage' then return RS end
    if src == 'PlayerData' then return player end
    return pg
end
local function excluded(node)
    local p = node
    while p and p ~= pg and p ~= player and p ~= RS do
        if p.Name == 'CurrentCut' or p.Name == 'FinishCard'
            or p.Name == 'KesimPaneli' or p.Name == 'StonePhoto'
            or p.Name == 'SellMenu' or p.Name == 'CutStoneTab' then
            return true
        end
        p = p.Parent
    end
    return false
end
local function inventoryHint(obj)
    local node = obj
    for _ = 1, 5 do
        if not node then break end
        local lower = node.Name:lower()
        if lower:find('invent', 1, true) or lower:find('stone', 1, true)
            or lower:find('rock', 1, true) or lower:find('pocket', 1, true)
            or lower:find('cep', 1, true) or lower:find('bag', 1, true)
            or lower:find('tas', 1, true) or lower:find('cuttingmenu', 1, true) then
            return true
        end
        node = node.Parent
    end
    return false
end
local function sourcePriority(src)
    if src == 'PlayerData' then return 6 end
    if src == 'ReplicatedStorage' then return 5 end
    if src == 'InventoryMenu' then return 4 end
    if src == 'CuttingMenu' then return 3 end
    return 1
end
local function recordId(target, id, node, how)
    if not isUUID(id) or excluded(node) then return end
    local src = sourceName(node)
    if src == 'PlayerGuiOther' and not inventoryHint(node) then return end
    if src == 'ReplicatedStorage' and not inventoryHint(node) then return end
    if src == 'PlayerData' and not inventoryHint(node) then return end
    local old = target.ids[id]
    local entry = {
        id = id, label = idLabel(id), source = src, method = how,
        path = relativePath(node, restrictedRoot(node))
    }
    if not old or sourcePriority(src) > sourcePriority(old.source) then
        target.ids[id] = entry
    end
    target.countBySource[src] = (target.countBySource[src] or 0) + 1
end
local function captureNode(target, obj)
    if isUUID(obj.Name) and (obj:IsA('GuiObject') or obj:IsA('ValueBase')
        or obj:IsA('Folder') or obj:IsA('Model')) then
        recordId(target, obj.Name, obj, 'Name')
    end
    if obj:IsA('StringValue') and isUUID(obj.Value) then
        recordId(target, obj.Value, obj, 'StringValue')
    end
    -- Attributes may contain stone IDs without a UUID-named child.
    if inventoryHint(obj) then
        local ok, attrs = pcall(function() return obj:GetAttributes() end)
        if ok then
            for k, v in pairs(attrs) do
                if isUUID(v) then recordId(target, v, obj, 'Attribute:' .. tostring(k):sub(1, 28)) end
            end
        end
        if obj:IsA('IntValue') or obj:IsA('NumberValue') then
            local nm = obj.Name:lower()
            if nm:find('count',1,true) or nm:find('total',1,true)
                or nm:find('bag',1,true) or nm:find('stone',1,true)
                or nm:find('rock',1,true) or nm:find('cep',1,true) then
                local src = sourceName(obj)
                local key = src .. ':' .. relativePath(obj, restrictedRoot(obj))
                target.numbers[key] = obj.Value
            end
        end
    end
end
local function snapshot()
    local state = {
        ids = {}, numbers = {}, countBySource = {}, capped = false,
        cuttingOpen = menuOpen('CuttingMenu'), inventoryOpen = menuOpen('InventoryMenu'),
        scanned = 0, when = os.clock()
    }
    local roots = {pg, player, RS}
    for _, root in ipairs(roots) do
        if state.scanned >= scanLimit then state.capped = true; break end
        captureNode(state, root)
        for _, obj in ipairs(root:GetDescendants()) do
            -- Do not rescan PlayerGui as a child of Player.
            if root ~= player or not isIn(obj, pg) then
                state.scanned += 1
                captureNode(state, obj)
                if state.scanned >= scanLimit then
                    state.capped = true
                    break
                end
            end
        end
    end
    return state
end
local function countMap(map)
    local n = 0
    for _ in pairs(map) do n += 1 end
    return n
end
local function countsString(state)
    if not state then return 'none' end
    return ('total=%d CuttingMenu=%d InventoryMenu=%d PlayerData=%d ReplicatedStorage=%d Other=%d')
        :format(countMap(state.ids),state.countBySource.CuttingMenu or 0,
            state.countBySource.InventoryMenu or 0,state.countBySource.PlayerData or 0,
            state.countBySource.ReplicatedStorage or 0,state.countBySource.PlayerGuiOther or 0)
end
local function observe(current, reason)
    local previous = latest
    latest = current
    samples += 1
    if current.capped then cappedSamples += 1 end
    for src, n in pairs(current.countBySource) do
        peakBySource[src] = math.max(peakBySource[src] or 0, n)
    end
    if baseline then
        for id, entry in pairs(current.ids) do
            if not baseline.ids[id] and not firstSeen[id] then
                firstSeen[id] = {
                    source = entry.source, method = entry.method, path = entry.path,
                    menuOpen = current.cuttingOpen or current.inventoryOpen,
                    at = os.clock(), label = entry.label
                }
                log('NEW_CANDIDATE ' .. entry.label .. ' source=' .. entry.source
                    .. ' menuOpen=' .. tostring(firstSeen[id].menuOpen))
            end
        end
        if previous then
            local appeared, disappeared = 0, 0
            for id in pairs(current.ids) do if not previous.ids[id] then appeared += 1 end end
            for id in pairs(previous.ids) do if not current.ids[id] then disappeared += 1 end end
            if appeared > 0 or disappeared > 0 then
                log(('CHANGE reason=%s +%d -%d %s'):format(reason,appeared,disappeared,
                    current.cuttingOpen and 'CUT_MENU_OPEN'
                        or current.inventoryOpen and 'INV_MENU_OPEN' or 'MENUS_CLOSED'))
            end
        end
        for k,v in pairs(current.numbers) do
            local old = baseline.numbers[k]
            if old ~= nil and old ~= v and changedNumeric[k] == nil then
                changedNumeric[k] = {before=old, after=v}
                log('COUNT_CHANGED ' .. k:sub(1, 70))
            end
        end
    end
    if updateStatus then updateStatus() end
end

local gui = Instance.new('ScreenGui')
gui.Name = 'CAR_InventoryProbe_v13'
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = pg
local function make(class, props, parent)
    local o = Instance.new(class)
    for k,v in pairs(props) do o[k] = v end
    o.Parent = parent
    return o
end
local panel = make('Frame', {
    Size = UDim2.fromOffset(330, 385), Position = UDim2.fromOffset(12,105),
    BackgroundColor3 = Color3.fromRGB(22,27,37), BorderSizePixel = 0
},gui)
make('UICorner',{CornerRadius=UDim.new(0,12)},panel)
make('UIStroke',{Color=Color3.fromRGB(72,93,117),Thickness=1},panel)
local title = make('TextLabel', {
    Text='CUT A ROCK | INVENTORY PROBE v1.3', Font=Enum.Font.GothamBold,
    TextSize=13,TextXAlignment=Enum.TextXAlignment.Left,
    BackgroundTransparency=1,TextColor3=Color3.new(1,1,1),
    Size=UDim2.fromOffset(290,36),Position=UDim2.fromOffset(11,1)
}, panel)
local function button(caption,x,y,w,fn)
    local b=make('TextButton',{
        Text=caption,Size=UDim2.fromOffset(w,36),Position=UDim2.fromOffset(x,y),
        BackgroundColor3=Color3.fromRGB(47,69,99),BorderSizePixel=0,
        TextColor3=Color3.new(1,1,1),TextSize=12,Font=Enum.Font.GothamMedium
    },panel)
    make('UICorner',{CornerRadius=UDim.new(0,7)},b)
    if fn then connections[#connections+1]=b.Activated:Connect(fn) end
    return b
end
local status = make('TextLabel',{
    Text=lastMessage, Position=UDim2.fromOffset(11,46),Size=UDim2.fromOffset(307,89),
    BackgroundTransparency=1,TextColor3=Color3.fromRGB(187,211,237),
    TextSize=11,Font=Enum.Font.Gotham,TextWrapped=true,
    TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top
},panel)
updateStatus = function()
    if not active or not status.Parent then return end
    local state=latest
    local ids=state and countMap(state.ids) or 0
    local cutting=state and state.cuttingOpen or false
    local inv=state and state.inventoryOpen or false
    status.Text=('IDs now: %d | Found since baseline: %d\nCuttingMenu: %s | InventoryMenu: %s\nMonitor: %s | Samples: %d\n%s')
        :format(ids,countMap(firstSeen),tostring(cutting),tostring(inv),
            monitoring and 'ON' or 'OFF',samples,lastMessage)
end
button('MARK BEFORE',11,150,147,function()
    local s = snapshot()
    baseline = s
    baselineAt = os.clock()
    firstSeen, changedNumeric = {}, {}
    observe(s,'baseline')
    lastMessage = 'Baseline saved. Keep menu closed; collect a NEW rock.'
    log('BASELINE ' .. countsString(s) .. ' menusOpen=' .. tostring(anyMenuOpen()))
    updateStatus()
end)
button('COMPARE NOW',170,150,147,function()
    observe(snapshot(),'manual')
    lastMessage='Compared against baseline. Open menu only after closed-menu test.'
    log('COMPARE ' .. countsString(latest))
    updateStatus()
end)
button('SNAPSHOT MENU',11,193,147,function()
    observe(snapshot(),'menu-snapshot')
    lastMessage='Menu snapshot captured. Useful to compare IDs with closed-menu data.'
    log('MENU_SNAPSHOT ' .. countsString(latest))
    updateStatus()
end)
local monitorBtn
monitorBtn=button('MONITOR: ON',170,193,147,function()
    monitoring=not monitoring
    monitorBtn.Text='MONITOR: '..(monitoring and 'ON' or 'OFF')
    lastMessage='Monitoring '..(monitoring and 'enabled' or 'paused')
    log('MONITOR '..tostring(monitoring))
    updateStatus()
end)

local function buildReport()
    if not latest then observe(snapshot(),'report') end
    local current=latest
    local baselineIds=baseline and countMap(baseline.ids) or 0
    local lines={
        'CUT A ROCK INVENTORY SOURCE PROBE v1.3',
        'PlaceId='..game.PlaceId,
        'BaselineSet='..tostring(baseline~=nil),
        'BaselineMenusOpen='..tostring(baseline and (baseline.cuttingOpen or baseline.inventoryOpen) or false),
        'BaselineIDs='..baselineIds,
        'Current='..countsString(current),
        'MenusNow Cutting='..tostring(current.cuttingOpen)..' Inventory='..tostring(current.inventoryOpen),
        'Samples='..samples..' Capped='..cappedSamples..' Limit='..scanLimit,
        'NewCandidateIDsSinceBaseline='..countMap(firstSeen),
        'NOTE: IDs seen after baseline do not necessarily mean newly earned stones.',
        'NOTE: UUIDs are anonymised; no raw identifiers or personal data are exported.',
        'NOTE: Passive observation only; no FireServer/InvokeServer/teleport/clicks.',
        '--- SOURCE PEAKS ---'
    }
    for _,src in ipairs({'CuttingMenu','InventoryMenu','PlayerData','ReplicatedStorage','PlayerGuiOther'}) do
        lines[#lines+1] = src .. ': ' .. (peakBySource[src] or 0)
    end
    local n=0
    lines[#lines+1]='--- NEW CANDIDATE SOURCES (up to 24, anonymised) ---'
    local names={}
    for _,event in pairs(firstSeen) do names[#names+1]=event end
    table.sort(names,function(a,b) return a.at<b.at end)
    for _,event in ipairs(names) do
        n+=1; if n>24 then break end
        lines[#lines+1] = event.label .. ' | '..event.source ..' | '.. event.method
            ..' | menuOpen='..tostring(event.menuOpen)..' | path='..event.path
    end
    if n == 0 then lines[#lines+1]='none' end
    lines[#lines+1]='--- NUMERIC INVENTORY COUNT CHANGES (up to 12) ---'
    n=0
    for path,pair in pairs(changedNumeric) do
        n+=1; if n>12 then break end
        lines[#lines+1]=path:sub(1,110)..' '..tostring(pair.before)..' -> '..tostring(pair.after)
    end
    if n==0 then lines[#lines+1]='none' end
    lines[#lines+1]='--- PASSIVE SERVER EVENTS ---'
    local rkeys={}
    for name in pairs(remoteCount) do rkeys[#rkeys+1]=name end
    table.sort(rkeys)
    for _,name in ipairs(rkeys) do lines[#lines+1]=name..' x'..remoteCount[name] end
    if #rkeys==0 then lines[#lines+1]='none from watched remotes' end
    lines[#lines+1]='--- TIMELINE ---'
    for _,event in ipairs(history) do lines[#lines+1]=event end
    return table.concat(lines,'\n')
end
button('COPY REPORT',11,236,306,function()
    local report = buildReport()
    local copy = type(setclipboard)=='function' and setclipboard
        or (type(toclipboard)=='function' and toclipboard) or nil
    if copy and pcall(copy,report) then
        lastMessage='Report copied. Paste into ChatGPT.'
    else
        print(report)
        lastMessage='Report printed to executor console.'
    end
    updateStatus()
end)
make('TextLabel',{
    Text='Passive audit only. Do not open CUT menu until after obtaining a rock.',
    Position=UDim2.fromOffset(11,284), Size=UDim2.fromOffset(306,34),
    TextSize=10,TextWrapped=true,Font=Enum.Font.Gotham,
    TextColor3=Color3.fromRGB(163,184,204),BackgroundTransparency=1
},panel)
local function stop()
    if not active then return end
    active=false
    for _,c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    gui:Destroy()
    if env.CARInventoryProbeStop==stop then env.CARInventoryProbeStop=nil end
end
env.CARInventoryProbeStop=stop
button('CLOSE',11,329,306,stop)

-- Drag using title on mobile.
local dragging,start,oldPos=false,nil,nil
connections[#connections+1]=title.InputBegan:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
        dragging=true;start=i.Position;oldPos=panel.Position
        local c;c=i.Changed:Connect(function()
            if i.UserInputState==Enum.UserInputState.End then dragging=false;c:Disconnect() end
        end)
    end
end)
connections[#connections+1]=UIS.InputChanged:Connect(function(i)
    if dragging and start and (i.UserInputType==Enum.UserInputType.MouseMovement
        or i.UserInputType==Enum.UserInputType.Touch) then
        local delta=i.Position-start
        panel.Position=UDim2.new(oldPos.X.Scale,oldPos.X.Offset+delta.X,
            oldPos.Y.Scale,oldPos.Y.Offset+delta.Y)
    end
end)

-- Passive server -> client notices. Does not hook or send any remote.
local passiveRemotes={
    'CepTasSil','CepDoluEvent','BagFullEvent','KesimBildirimi',
    'OpenCuttingMachineMenu','BlockBrokenEvent','SyncBrokenBlocksEvent'
}
for _,name in ipairs(passiveRemotes) do
    local remote = RS:FindFirstChild(name)
    if remote and remote:IsA('RemoteEvent') then
        connections[#connections+1] = remote.OnClientEvent:Connect(function(...)
            if not active then return end
            remoteCount[name]=(remoteCount[name] or 0)+1
            local types={}
            local argc=select('#',...)
            for i=1,math.min(argc,3) do
                local x=select(i,...)
                types[#types+1]=typeof(x)
            end
            log('SERVER_EVENT '..name..' args='..argc..' ['..table.concat(types,',')..']')
        end)
    end
end

task.spawn(function()
    while active do
        if monitoring then
            local ok, s = pcall(snapshot)
            if ok then observe(s,'auto')
            else lastMessage='Snapshot error (see executor console).' end
        end
        task.wait(1.7)
    end
end)
log('PROBE_LOADED passive observation; MARK BEFORE with menus closed')
print('[CAR Inventory Probe v1.3] MARK BEFORE, collect a rock with menus closed, COMPARE NOW, then optionally open CUT menu for SNAPSHOT MENU.')

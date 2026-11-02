-- CUT A ROCK | UNIFIED MOBILE v2.0 | CUT + TRAIN + SPEED + NEAR COLLECT + TELEPORT
-- Upload this single Lua file to github.com/bluekidbuu/cut-a-rock-hub (branch: main).
-- Loads the existing v1.4 engine source and applies verified v1.5 engine patches,
-- then installs ONE compact mobile tabbed UI including Room 0-39 Direct Teleport.
-- Features: Cut v1.9 (no session cap), Train v3.2, Speed v1,
-- Near Collect v1.5, Direct Teleport v4.0, and Report/Return.
-- Requires the existing CutARock_CutTrain_Speed_Unified_v14.lua in the same repo.
-- Does not modify original GitHub files, game files, or game RemoteEvents for teleport.

if not game:IsLoaded() then game.Loaded:Wait() end
if game.PlaceId ~= 113742027864370 and game.GameId ~= 10766468833 then
    warn('[CAR Unified v1.5] Wrong game'); return
end

local url = 'https://raw.githubusercontent.com/bluekidbuu/cut-a-rock-hub/main/CutARock_CutTrain_Speed_Unified_v14.lua'
local okDownload, source = pcall(function() return game:HttpGet(url) end)
if not okDownload or type(source) ~= 'string' or #source < 60000 then
    warn('[CAR Unified v1.5] Cannot download verified v1.4 baseline. Nothing changed: '..tostring(source))
    return
end

local function replaceOnce(before, after, label)
    local a, b = source:find(before, 1, true)
    if not a or source:find(before, b+1, true) then
        error('[CAR Unified v1.5] BASELINE MISMATCH at '..label..'; cancelled without running anything')
    end
    source = source:sub(1, a-1) .. after .. source:sub(b+1)
end

local collectEngine = [=[
-- -------- AUTO COLLECT NEAR v1.1 FAST | INTEGRATED v1.5 --------
-- No remote sends; verified near-range fireproximityprompt ONLY.
local function initNearCollect()
    local RS = game:GetService('ReplicatedStorage')
    local Players = game:GetService('Players')
    local pl = Players.LocalPlayer
    local collected, transitions, notifications, errors = 0, 0, 0, 0
    local enabled, running = true, true
    local maxDistance, rangeMargin = 13.5, 1.5
    local globalGap, cycleGap = 0.65, 1.2
    local lastCall, lastScan = -1e9, -1e9
    local states = setmetatable({}, {__mode='k'})
    local machineIds = setmetatable({}, {__mode='k'})
    local idCount = 0
    local conns, rows = {}, {}
    local info = 'Near Collect ON. Walk near YOUR ready machine.'
    local function rec(s)
        rows[#rows+1] = string.format('T+%.1f %s', os.clock(), tostring(s))
        if #rows > 32 then table.remove(rows,1) end
    end
    local function machineOf(o)
        while o and o~=workspace do
            if o:IsA('Model') and o.Name:match('^level%d+$') then return o end
            o=o.Parent
        end
    end
    local function slot(m)
        if not machineIds[m] then idCount+=1;machineIds[m]=idCount end
        return machineIds[m]
    end
    local function positionOf(p)
        local par=p.Parent
        if par and par:IsA('Attachment') then return par.WorldPosition end
        if par and par:IsA('BasePart') then return par.Position end
        local part=par and par:FindFirstAncestorWhichIsA('BasePart')
        return part and part.Position or nil
    end
    local function distanceOf(p)
        local ch=pl.Character
        local root=ch and ch:FindFirstChild('HumanoidRootPart')
        local hum=ch and ch:FindFirstChildOfClass('Humanoid')
        local pos=p.Parent and positionOf(p)
        if root and hum and hum.Health>0 and pos then return (root.Position-pos).Magnitude end
    end
    local function belongsToPlayer(p,m)
        local own=p:GetAttribute('SahipUserId')
        if own~=nil then return tostring(own)==tostring(pl.UserId) end
        local keys={'OwnerUserId','PlayerUserId','UserId','Owner','OwnerName','PlayerName'}
        while m and m~=workspace do
            for _,key in ipairs(keys) do
                local v=m:GetAttribute(key)
                if type(v)=='string' or type(v)=='number' then
                    local s=tostring(v):lower()
                    return s==tostring(pl.UserId) or s==pl.Name:lower()
                end
            end
            m=m.Parent
        end
        return false -- UNKNOWN ownership never triggers
    end
    local function isReady(p)
        if not p or not p.Parent or not p.Enabled or p.Name~='CutMachinePrompt' then return false end
        if not (p.ActionText or ''):lower():find('collect',1,true) then return false end
        local state=p:GetAttribute('Durum')
        return state==nil or state=='Hazir'
    end
    local function track(p)
        if not running or states[p] or not p:IsA('ProximityPrompt') or p.Name~='CutMachinePrompt' then return end
        if not machineOf(p) then return end
        local d={spent=false,departed=false,last=-1e9,nearAt=nil,changed=false}
        states[p]=d
        local function onChange()
            if not running or not p.Parent then return end
            if d.spent and not isReady(p) then
                d.departed=true
                if not d.changed then
                    d.changed=true;transitions+=1
                    local m=machineOf(p)
                    rec('LEFT_READY slot='..(m and slot(m) or '?'))
                end
            end
        end
        conns[#conns+1]=p:GetPropertyChangedSignal('ActionText'):Connect(onChange)
        conns[#conns+1]=p:GetAttributeChangedSignal('Durum'):Connect(onChange)
    end
    local function scan()
        local models=workspace:FindFirstChild('Models')
        local bases=models and models:FindFirstChild('Bases')
        if bases then
            for _,p in ipairs(bases:GetDescendants()) do
                if p:IsA('ProximityPrompt') and p.Name=='CutMachinePrompt' then track(p) end
            end
        end
    end
    conns[#conns+1]=workspace.DescendantAdded:Connect(function(o)
        if running and o:IsA('ProximityPrompt') and o.Name=='CutMachinePrompt' then
            task.defer(function() if running then track(o) end end)
        end
    end)
    local event=RS:FindFirstChild('KesimBildirimi')
    if event and event:IsA('RemoteEvent') then
        conns[#conns+1]=event.OnClientEvent:Connect(function(kind)
            if running and kind=='Toplandi' and os.clock()-lastCall<=5 then
                notifications+=1
                rec(string.format('TOPLANDI after=%.2fs (correlation)',os.clock()-lastCall))
            end
        end)
    end
    local function findReady()
        local now=os.clock()
        local best,bestModel,bestD=nil,nil,math.huge
        for p,d in pairs(states) do
            if p.Parent and isReady(p) then
                local m=machineOf(p)
                if m and belongsToPlayer(p,m) then
                    if d.spent and d.departed and now-d.last>=cycleGap then
                        d.spent=false;d.departed=false;d.changed=false;d.nearAt=nil
                    end
                    if not d.spent then
                        local dist=distanceOf(p)
                        local limit=math.min(maxDistance,math.max(0,p.MaxActivationDistance-rangeMargin))
                        if dist and dist<=limit then
                            if not d.nearAt then d.nearAt=now end
                            if dist<bestD then best,bestModel,bestD=p,m,dist end
                        else d.nearAt=nil end
                    end
                end
            else
                d.nearAt=nil
            end
        end
        return best,bestModel,bestD
    end
    local function attempt(p,m,dist)
        if type(fireproximityprompt)~='function' then
            enabled=false;info='Collect OFF: fireproximityprompt unsupported'
            rec(info)
            return
        end
        local d=states[p]
        if not d or d.spent or not isReady(p) or not belongsToPlayer(p,m) then return end
        local fresh=distanceOf(p)
        local limit=math.min(maxDistance,math.max(0,p.MaxActivationDistance-rangeMargin))
        if not fresh or fresh>limit then return end
        local now=os.clock()
        local nearWait=now-(d.nearAt or now)
        d.spent=true;d.departed=false;d.changed=false;d.last=now
        lastCall=now;collected+=1
        local ok,err=pcall(function() fireproximityprompt(p) end)
        rec(string.format('TRY #%d slot=%d level=%s dist=%.1f nearWait=%.2fs ok=%s',
            collected,slot(m),m.Name,fresh,nearWait,tostring(ok)))
        if not ok then
            errors+=1
            info='Collect local error; no retry for this ready cycle'
            rec(tostring(err):sub(1,90))
            if errors>=3 then enabled=false;info='Collect OFF after 3 local errors' end
        else info='Collect attempted at '..string.format('%.1f',fresh)..' studs' end
    end
    scan();lastScan=os.clock()
    task.spawn(function()
        while running do
            local ok,err=pcall(function()
                local now=os.clock()
                if now-lastScan>=8 then scan();lastScan=now end
                if enabled then
                    local p,m,dist=findReady()
                    if p and now-lastCall>=globalGap then attempt(p,m,dist) end
                end
            end)
            if not ok then enabled=false;info='Collect engine paused: '..tostring(err):sub(1,90);rec(info) end
            task.wait(0.12)
        end
    end)
    rec('NEAR_COLLECT_READY ON maxDistance=13.5 gap=0.65')
    return {
        setAuto=function(v) enabled=v and true or false;info=enabled and 'Near Collect ON' or 'Near Collect OFF' end,
        isAuto=function() return enabled end,
        status=function() return {enabled=enabled, attempts=collected, transitions=transitions,
            toplandi=notifications, errors=errors, message=info} end,
        report=function()
            local a={'CUT A ROCK | NEAR COLLECT INTEGRATED v1.5',
                'Auto='..tostring(enabled),'Attempts='..collected,'PromptLeftReady='..transitions,
                'InboundToplandi='..notifications,'LocalErrors='..errors,
                'RangeMax=13.5 RangeMargin=1.5 GlobalGap=0.65 NewCycleGap=1.2',
                'NoSessionCountCap=true OwnMachinesOnly=true NoTeleport=true',
                'NOTE: Toplandi is a correlation; verify actual inventory for reward.',
                '--- RECENT COLLECT EVENTS ---'}
            for _,r in ipairs(rows) do a[#a+1]=r end
            return table.concat(a,'\n')
        end,
        stop=function()
            running=false;enabled=false
            for _,c in ipairs(conns) do pcall(function()c:Disconnect()end) end
        end
    }
end
-- -------- END AUTO COLLECT ENGINE --------
]=]

local okPatch, patchError = pcall(function()
    replaceOnce('-- CUT A ROCK | AUTO CUT + AUTO TRAIN + SPEED SLIDER | UNIFIED v1.4',
        '-- CUT A ROCK | AUTO CUT + AUTO TRAIN + SPEED + NEAR COLLECT | UNIFIED v1.5', 'header')
    replaceOnce('-- Collect disabled; does not buy, mine, teleport, or use InstantCutEvent.',
        '-- Near Collect enabled, own ready machines, no teleport or speculative Collect remotes.', 'description')
    replaceOnce("'CARMultiCollectStop','CutARockTrainV3Stop','CARSpeedSliderStop'", 
        "'CARMultiCollectStop','CutARockTrainV3Stop','CARSpeedSliderStop','CARAutoCollectNearStop'",'old standalone collector shutdown')
    replaceOnce('local maxSends=60 -- explicit bounded safety limit; restart manually after cap',
        '-- v1.5: no fixed Auto Cut send cap (all existing response/UUID/hold guards remain)', 'cap declaration')
    replaceOnce("    if sends>=maxSends then stopAuto('Session cap '..maxSends..' reached; restart manually to continue.');return end\n",
        "    -- No fixed session count cap. Existing readiness, cooldown, and failure guards apply.\n", 'cap check')
    replaceOnce("        if sends>=maxSends then lastMessage='Cut session cap reached.'; return false end\n",
        "        -- Unlimited session; enabling CUT is not limited by number of previous sends.\n", 'cap toggle')
    replaceOnce("'SessionCap='..maxSends..' StoneTTLSeconds='..stoneTTL,",
        "'SessionCap=UNLIMITED StoneTTLSeconds='..stoneTTL,",'cap report')
    replaceOnce('-- ----------------------- COMPACT SHARED UI -----------------------',
        collectEngine..'\n-- ----------------------- COMPACT SHARED UI -----------------------','collect module')
    replaceOnce('local speed=initSpeed()\nlocal alive=true',
        'local speed=initSpeed()\nlocal collect=initNearCollect()\nlocal alive=true','collector startup')
    replaceOnce("Name='CAR_CutTrain_Speed_Unified_v14'", 
        "Name='CAR_CutTrain_Speed_Collect_Unified_v15'",'UI name')
    replaceOnce("Size=UDim2.fromOffset(296,406)",
        "Size=UDim2.fromOffset(296,445)",'panel size')
    replaceOnce("Text='CAR | CUT + TRAIN + SPEED 1.4'",
        "Text='CAR | UNIFIED 1.5 + COLLECT'",'title')
    replaceOnce("Size=UDim2.fromOffset(296,371)",
        "Size=UDim2.fromOffset(296,410)",'body size')
    replaceOnce("local copyBtn=bodyButton('COPY REPORT',152,118,135,31)",
        "local copyBtn=bodyButton('COPY REPORT',152,118,135,31)\nlocal collectToggle=bodyButton('COLLECT: ON',9,369,278,31)", 'collect button')
    replaceOnce("local expandedHeight=406", "local expandedHeight=445",'expanded height')
    replaceOnce("    speed.stop()\n    train.stop()\n    cut.stop()", 
        "    collect.stop()\n    speed.stop()\n    train.stop()\n    cut.stop()", 'shutdown')
    replaceOnce("onClick(cutToggle,function()\n    cut.setAuto(not cut.isAuto())\nend)",
        "onClick(cutToggle,function()\n    cut.setAuto(not cut.isAuto())\nend)\nonClick(collectToggle,function() collect.setAuto(not collect.isAuto()) end)", 'collect toggle')
    replaceOnce("'CUT A ROCK UNIFIED v1.4 | AUTO CUT v1.9 + AUTO TRAIN v3.2 + SPEED v1',\n        'AutoCollect=false (DISABLED; far calls did not yield real stone)',",
        "'CUT A ROCK UNIFIED v1.5 | AUTO CUT v1.9 NO COUNT CAP + AUTO TRAIN v3.2 + SPEED v1 + NEAR COLLECT',\n        'AutoCutSessionLimit=UNLIMITED',",'report title')
    replaceOnce("        '--- AUTO CUT REPORT ---',cut.report(),", 
        "        '--- AUTO CUT REPORT ---',cut.report(),\n        '--- AUTO COLLECT REPORT ---',collect.report(),",'report collect')
    replaceOnce("Text='Stones: watch Player.Envanter, not Mining Cep.\\nCollect disabled; CUT & TRAIN run independently.'",
        "Text='Cut: Player.Envanter, never Mining Cep.\\nCollect: near own ready machines, no teleport.'",'hint')
    replaceOnce("        cutToggle.Text=c.auto and 'CUT: ON' or 'CUT: OFF'",
        "        cutToggle.Text=c.auto and 'CUT: ON' or 'CUT: OFF'\n        collectToggle.Text=collect.isAuto() and 'COLLECT: ON (NEAR)' or 'COLLECT: OFF'\n        collectToggle.BackgroundColor3=collect.isAuto() and onCol or offCol", 'live toggle')
    replaceOnce("print('[CAR Unified] v1.4: Cut v1.9 Envanter + unchanged Train v3.2 + Speed Slider v1 1.0x-3.0x, reset/respawn. Collect disabled. Minimize with _.')",
        "print('[CAR Unified] v1.5: unlimited Auto Cut count, Train v3.2, Speed v1, near Auto Collect ON. No teleport. Minimize with _.')", 'ready log')
end)
if not okPatch then
    warn('[CAR Unified v1.5] Patch cancelled: '..tostring(patchError))
    return
end
-- Replace only the integrated v1.5 UI; preserve all original engines.
local mobileUI = [==[
-- ---------------- CAR UNIFIED 2.0 | MOBILE TABBED UI ----------------
-- Existing engine implementations above remain unchanged:
-- initCut v1.9 unlimited; initTrain v3.2; initSpeed v1; initNearCollect v1.5.
if type(env.CARMiningFloorTeleportStop)=='function' then
    pcall(env.CARMiningFloorTeleportStop) -- closes any older standalone teleport window
end
local cut=initCut()
local train=initTrain()
local speed=initSpeed()
local collect=initNearCollect()
local alive=true
local allConnections={}
local playerRoot=player:WaitForChild('PlayerGui')

local function connect(signal,callback)
    local c=signal:Connect(callback)
    allConnections[#allConnections+1]=c
    return c
end
local function make(kind,props,parent)
    local o=Instance.new(kind)
    for key,value in pairs(props) do o[key]=value end
    o.Parent=parent
    return o
end
local C={
    bg=Color3.fromRGB(20,30,45),
    top=Color3.fromRGB(29,47,67),
    surface=Color3.fromRGB(33,52,73),
    button=Color3.fromRGB(45,78,107),
    active=Color3.fromRGB(39,112,107),
    accent=Color3.fromRGB(49,132,121),
    white=Color3.fromRGB(237,245,252),
    muted=Color3.fromRGB(166,191,213),
    red=Color3.fromRGB(144,63,68)
}
local gui=make('ScreenGui',{
    Name='CAR_Unified_Mobile_v20',ResetOnSpawn=false,
    ZIndexBehavior=Enum.ZIndexBehavior.Sibling,DisplayOrder=180
},playerRoot)
pcall(function() gui.ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets end)
local panel=make('Frame',{
    Size=UDim2.fromOffset(320,300),Position=UDim2.fromOffset(12,36),
    BackgroundColor3=C.bg,BorderSizePixel=0,Active=true
},gui)
make('UICorner',{CornerRadius=UDim.new(0,11)},panel)
make('UIStroke',{Color=Color3.fromRGB(73,102,127),Thickness=1},panel)
local scale=make('UIScale',{Scale=1},panel)

local function button(label,x,y,w,h,parent,color)
    local b=make('TextButton',{
        Text=label,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),
        BackgroundColor3=color or C.button,TextColor3=C.white,
        Font=Enum.Font.GothamBold,TextSize=12,BorderSizePixel=0,
        AutoButtonColor=true
    },parent)
    make('UICorner',{CornerRadius=UDim.new(0,7)},b)
    return b
end
local header=make('Frame',{
    Size=UDim2.fromOffset(320,39),BackgroundColor3=C.top,
    BorderSizePixel=0,Active=true
},panel)
make('UICorner',{CornerRadius=UDim.new(0,10)},header)
local dragArea=make('TextLabel',{
    Text='  CAR HUB  |  MOBILE 2.0',TextColor3=C.white,
    Font=Enum.Font.GothamBold,TextSize=13,TextXAlignment=Enum.TextXAlignment.Left,
    BackgroundTransparency=1,Size=UDim2.fromOffset(240,39),Active=true
},header)
local minimizeBtn=button('_',249,4,31,31,header)
local exitBtn=button('X',284,4,31,31,header,C.red)
local opener=button('CAR',12,35,64,44,gui,C.accent)
opener.Visible=false

local nav=make('Frame',{
    Position=UDim2.fromOffset(7,46),Size=UDim2.fromOffset(306,39),
    BackgroundTransparency=1
},panel)
local content=make('Frame',{
    Position=UDim2.fromOffset(7,90),Size=UDim2.fromOffset(306,202),
    BackgroundColor3=C.surface,BorderSizePixel=0
},panel)
make('UICorner',{CornerRadius=UDim.new(0,8)},content)
local tabButtons={}
local pages={}
local tabs={'FARM','SPEED','TELEPORT','STATUS'}
for i,name in ipairs(tabs) do
    tabButtons[name]=button(name,(i-1)*77,0,73,38,nav)
    pages[name]=make('Frame',{
        Name=name,Size=UDim2.fromScale(1,1),
        BackgroundTransparency=1,Visible=false
    },content)
end
local tab='FARM'
local function switch(name)
    tab=name
    for _,name2 in ipairs(tabs) do
        pages[name2].Visible=(name==name2)
        tabButtons[name2].BackgroundColor3=(name==name2) and C.active or C.button
    end
end
for _,name in ipairs(tabs) do
    local n=name
    connect(tabButtons[name].Activated,function()switch(n)end)
end
switch('FARM')

-- Farm page: all existing v1.5 actions available, no engine changes.
local farm=pages.FARM
local trainToggle=button('TRAIN: OFF',6,6,144,42,farm)
local cutToggle=button('CUT: OFF',156,6,144,42,farm)
local collectToggle=button('COLLECT: ON',6,55,144,42,farm)
local bindBtn=button('BIND NEAREST',156,55,144,42,farm)
local previewBtn=button('PREVIEW',6,104,144,42,farm)
local addBtn=button('ADD BASE',156,104,144,42,farm)
local importBtn=button('SCAN BACKPACK',6,153,144,42,farm)
local resetBtn=button('RESET LOCKS',156,153,144,42,farm)

connect(trainToggle.Activated,function()
    if train.isOn() then train.disable() else train.enable() end
end)
connect(cutToggle.Activated,function()cut.setAuto(not cut.isAuto())end)
connect(collectToggle.Activated,function()collect.setAuto(not collect.isAuto())end)
connect(bindBtn.Activated,cut.bindNearest)
connect(previewBtn.Activated,cut.preview)
connect(addBtn.Activated,cut.addPreview)
connect(importBtn.Activated,cut.importOld)
connect(resetBtn.Activated,cut.resetLocks)

-- Speed page: original v1 slider engine, new touch surface.
local speedPage=pages.SPEED
local speedLabel=make('TextLabel',{
    Text='WalkSpeed 1.0x',Size=UDim2.fromOffset(290,32),
    Position=UDim2.fromOffset(9,12),TextColor3=C.white,
    Font=Enum.Font.GothamBold,TextSize=15,
    BackgroundTransparency=1,TextXAlignment=Enum.TextXAlignment.Left
},speedPage)
local speedZone=make('Frame',{
    Position=UDim2.fromOffset(17,54),Size=UDim2.fromOffset(272,50),
    BackgroundTransparency=1,Active=true
},speedPage)
local track=make('Frame',{
    Position=UDim2.fromOffset(0,20),Size=UDim2.fromOffset(272,11),
    BackgroundColor3=Color3.fromRGB(80,99,117),BorderSizePixel=0
},speedZone)
make('UICorner',{CornerRadius=UDim.new(1,0)},track)
local fill=make('Frame',{
    Size=UDim2.new(0,0,1,0),BackgroundColor3=C.accent,BorderSizePixel=0
},track)
make('UICorner',{CornerRadius=UDim.new(1,0)},fill)
local knob=make('Frame',{
    Size=UDim2.fromOffset(26,26),AnchorPoint=Vector2.new(.5,.5),
    Position=UDim2.new(0,0,.5,0),BackgroundColor3=C.white,BorderSizePixel=0
},track)
make('UICorner',{CornerRadius=UDim.new(1,0)},knob)
local speedReset=button('RESET SPEED 1.0x',9,115,288,39,speedPage)
local speedNote=make('TextLabel',{
    Text='',Size=UDim2.fromOffset(289,36),Position=UDim2.fromOffset(9,161),
    TextColor3=C.muted,Font=Enum.Font.Gotham,TextSize=10,
    TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,
    BackgroundTransparency=1
},speedPage)
local function updateSpeed()
    if not alive then return end
    local s=speed.status()
    local a=(s.multiplier-1)/2
    fill.Size=UDim2.new(a,0,1,0)
    knob.Position=UDim2.new(a,0,.5,0)
    speedLabel.Text=string.format('WalkSpeed  %.1fx',s.multiplier)
    speedNote.Text=s.status
end
speed.onChanged(updateSpeed)
local speedDragging=false
local speedTouch=nil
local function setSpeedFromInput(x)
    local w=track.AbsoluteSize.X
    if w>0 then
        speed.set(1+2*math.clamp((x-track.AbsolutePosition.X)/w,0,1))
    end
end
connect(speedZone.InputBegan,function(i)
    if i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseButton1 then
        speedDragging=true;speedTouch=i;setSpeedFromInput(i.Position.X)
    end
end)
connect(UIS.InputChanged,function(i)
    if not speedDragging or not speedTouch then return end
    if (speedTouch.UserInputType==Enum.UserInputType.Touch and i==speedTouch)
        or (speedTouch.UserInputType==Enum.UserInputType.MouseButton1
            and i.UserInputType==Enum.UserInputType.MouseMovement) then
        setSpeedFromInput(i.Position.X)
    end
end)
connect(UIS.InputEnded,function(i)
    if speedTouch and (i==speedTouch or
        (speedTouch.UserInputType==Enum.UserInputType.MouseButton1
        and i.UserInputType==Enum.UserInputType.MouseButton1)) then
        speedDragging=false;speedTouch=nil
    end
end)
connect(speedReset.Activated,function()speed.set(1)end)

-- Teleport page: ONE input + ONE main button, no floor list or scan.
local tele=pages.TELEPORT
make('TextLabel',{
    Text='Mining Room 0 - 39',Size=UDim2.fromOffset(288,30),
    Position=UDim2.fromOffset(10,11),BackgroundTransparency=1,
    TextColor3=C.white,TextSize=15,Font=Enum.Font.GothamBold,
    TextXAlignment=Enum.TextXAlignment.Left
},tele)
local roomInput=make('TextBox',{
    Text='39',PlaceholderText='Room #',ClearTextOnFocus=false,
    Size=UDim2.fromOffset(105,44),Position=UDim2.fromOffset(10,55),
    BackgroundColor3=Color3.fromRGB(49,70,91),TextColor3=C.white,
    TextSize=19,Font=Enum.Font.GothamBold
},tele)
make('UICorner',{CornerRadius=UDim.new(0,7)},roomInput)
pcall(function()roomInput.KeyboardType=Enum.KeyboardType.NumberPad end)
local tpButton=button('TELEPORT',124,55,172,44,tele,C.accent)
local roomHint=make('TextLabel',{
    Text='Room_39 = Floor 40',Size=UDim2.fromOffset(285,26),
    Position=UDim2.fromOffset(10,108),TextColor3=C.muted,
    Font=Enum.Font.Gotham,TextSize=12,
    BackgroundTransparency=1,TextXAlignment=Enum.TextXAlignment.Left
},tele)
local tpStatus=make('TextLabel',{
    Text='DIRECT coordinate teleport. No scan.',
    Position=UDim2.fromOffset(10,142),Size=UDim2.fromOffset(286,55),
    TextWrapped=true,TextColor3=C.muted,Font=Enum.Font.Gotham,
    TextSize=11,TextXAlignment=Enum.TextXAlignment.Left,
    TextYAlignment=Enum.TextYAlignment.Top,BackgroundTransparency=1
},tele)
local tpToken=0
local tpLast={room=nil,result='NOT_USED',d15=nil,d50=nil}
local tpPrevious=nil
local function root()
    local ch=player.Character
    local hum=ch and ch:FindFirstChildOfClass('Humanoid')
    local hrp=ch and ch:FindFirstChild('HumanoidRootPart')
    if ch and hum and hum.Health>0 and hrp then return ch,hum,hrp end
end
local function approximateRoom()
    local _,_,r=root()
    if not r then return nil end
    return math.clamp(math.floor((-35.7-r.Position.Y)/40+0.5),0,39)
end
local function teleportRoom(n)
    if type(n)~='number' or n%1~=0 or n<0 or n>39 then
        tpStatus.Text='Masukkan nomor Room 0 sampai 39.'
        return
    end
    local ch,hum,r=root()
    if not r then tpStatus.Text='Karakter belum siap.';return end
    local target=Vector3.new(21.5,-35.7-40*n,22.2-70*n)
    tpPrevious=r.CFrame
    tpToken+=1
    local tk=tpToken
    tpLast={room=n,result='REQUESTED',d15=nil,d50=nil}
    local ok,err=pcall(function()
        hum.Sit=false
        ch:PivotTo(CFrame.new(target))
    end)
    if not ok then
        tpLast.result='LOCAL_ERROR'
        tpStatus.Text='Gagal: '..tostring(err):sub(1,70)
        return
    end
    tpStatus.Text='Teleport Room_'..n..' diminta...'
    task.delay(1.5,function()
        if not alive or tk~=tpToken then return end
        local _,_,r1=root()
        if r1 then
            tpLast.d15=(r1.Position-target).Magnitude
            tpLast.result=tpLast.d15<=20 and 'CLIENT_ARRIVED' or 'CLIENT_FAR'
            tpStatus.Text=string.format('Room_%d: jarak 1.5s %.1f studs',n,tpLast.d15)
        end
    end)
    task.delay(5,function()
        if not alive or tk~=tpToken then return end
        local _,_,r5=root()
        if r5 then
            tpLast.d50=(r5.Position-target).Magnitude
            tpLast.result=(tpLast.d50<=23) and 'CLIENT_STABLE_5S' or 'MOVED_OR_ROLLBACK'
            tpStatus.Text=string.format('Room_%d: %s (%.1f studs)',n,tpLast.result,tpLast.d50)
        end
    end)
end
connect(tpButton.Activated,function()
    local n=tonumber(roomInput.Text)
    pcall(function()roomInput:ReleaseFocus()end)
    teleportRoom(n)
end)
connect(roomInput:GetPropertyChangedSignal('Text'),function()
    local n=tonumber(roomInput.Text)
    if n and n%1==0 and n>=0 and n<=39 then
        roomHint.Text='Room_'..n..' = Floor '..(n+1)
    else
        roomHint.Text='Input: Room 0 - 39'
    end
end)

-- Status page: useful live summary, report, and optional return.
local stats=pages.STATUS
local stateText=make('TextLabel',{
    Text='Loading status...',Position=UDim2.fromOffset(10,8),
    Size=UDim2.fromOffset(282,119),BackgroundTransparency=1,
    TextColor3=C.white,Font=Enum.Font.Gotham,TextSize=11,
    TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,
    TextYAlignment=Enum.TextYAlignment.Top
},stats)
local copyBtn=button('COPY REPORT',7,136,143,44,stats)
local returnBtn=button('RETURN',156,136,143,44,stats)

local function report()
    local room=approximateRoom()
    return table.concat({
        'CUT A ROCK | UNIFIED MOBILE v2.0',
        'Cut=v1.9 UNLIMITED Train=v3.2 Speed=v1 NearCollect=v1.5',
        'Teleport=v4 DIRECT STATIC Room_0..Room_39',
        'CurrentRoomEstimate='..tostring(room),
        'TeleportLastRoom='..tostring(tpLast.room),
        'TeleportResult='..tostring(tpLast.result),
        'TeleportDistance1.5s='..tostring(tpLast.d15),
        'TeleportDistance5s='..tostring(tpLast.d50),
        'TeleportRemotes=0; NoMapScan=true',
        '--- CUT ---',cut.report(),
        '--- TRAIN ---',train.report(),
        '--- SPEED ---',speed.report(),
        '--- NEAR COLLECT ---',collect.report()
    },'\n')
end
connect(copyBtn.Activated,function()
    local s=report()
    print(s)
    local cb=(type(setclipboard)=='function' and setclipboard)
        or (type(toclipboard)=='function' and toclipboard)
    if cb and pcall(cb,s) then
        tpStatus.Text='Report copied.'
    else
        tpStatus.Text='Report printed in executor console.'
    end
end)
connect(returnBtn.Activated,function()
    if not tpPrevious then
        tpStatus.Text='Belum ada posisi RETURN.';return
    end
    tpToken+=1
    local ch,hum,r=root()
    if not r then return end
    local dest=tpPrevious
    tpPrevious=r.CFrame
    local ok=pcall(function()hum.Sit=false;ch:PivotTo(dest)end)
    tpStatus.Text=ok and 'RETURN requested' or 'RETURN failed'
    tpLast.result=ok and 'RETURN_REQUESTED' or 'RETURN_FAILED'
end)

-- Mobile drag/clamp; minimized into movable-friendly CAR launcher.
local collapsed=false
local function clampPanel()
    local cam=workspace.CurrentCamera
    if not cam then return end
    local v=cam.ViewportSize
    local s=math.min(1,(v.X-22)/320,(v.Y-30)/300)
    scale.Scale=math.max(.65,s)
    local w=320*scale.Scale
    local h=300*scale.Scale
    panel.Position=UDim2.fromOffset(
        math.clamp(panel.Position.X.Offset,0,math.max(0,v.X-w-8)),
        math.clamp(panel.Position.Y.Offset,0,math.max(0,v.Y-h-8))
    )
    opener.Position=UDim2.fromOffset(
        math.clamp(opener.Position.X.Offset,0,math.max(0,v.X-75)),
        math.clamp(opener.Position.Y.Offset,0,math.max(0,v.Y-58))
    )
end
clampPanel()
local function collapse(v)
    collapsed=v
    panel.Visible=not v
    opener.Visible=v
    if v then opener.Position=panel.Position
    else panel.Position=opener.Position;clampPanel() end
end
connect(minimizeBtn.Activated,function()collapse(true)end)
connect(opener.Activated,function()collapse(false)end)
local dragging=false
local dragPointer,dragStart,dragOrigin=nil,nil,nil
connect(dragArea.InputBegan,function(i)
    if i.UserInputType==Enum.UserInputType.Touch
        or i.UserInputType==Enum.UserInputType.MouseButton1 then
        dragging=true;dragPointer=i;dragStart=i.Position
        dragOrigin=Vector2.new(panel.Position.X.Offset,panel.Position.Y.Offset)
    end
end)
connect(UIS.InputChanged,function(i)
    if not dragging or not dragPointer or not dragStart then return end
    if (dragPointer.UserInputType==Enum.UserInputType.Touch and i==dragPointer)
        or (dragPointer.UserInputType==Enum.UserInputType.MouseButton1
            and i.UserInputType==Enum.UserInputType.MouseMovement) then
        local d=i.Position-dragStart
        panel.Position=UDim2.fromOffset(dragOrigin.X+d.X,dragOrigin.Y+d.Y)
        clampPanel()
    end
end)
connect(UIS.InputEnded,function(i)
    if dragPointer and (i==dragPointer
        or (dragPointer.UserInputType==Enum.UserInputType.MouseButton1
        and i.UserInputType==Enum.UserInputType.MouseButton1)) then
        dragging=false;dragPointer=nil
    end
end)
local cam=workspace.CurrentCamera
if cam then connect(cam:GetPropertyChangedSignal('ViewportSize'),clampPanel) end

local function stopAll()
    if not alive then return end
    alive=false
    tpToken+=1
    pcall(function()collect.stop()end)
    pcall(function()speed.stop()end)
    pcall(function()train.stop()end)
    pcall(function()cut.stop()end)
    for _,c in ipairs(allConnections) do pcall(function()c:Disconnect()end) end
    if gui and gui.Parent then gui:Destroy() end
    if env.CARUnifiedCutTrainStop==stopAll then env.CARUnifiedCutTrainStop=nil end
end
env.CARUnifiedCutTrainStop=stopAll
connect(exitBtn.Activated,stopAll)

-- Status polling only; calculations are lightweight.
task.spawn(function()
    while alive do
        local ok=pcall(function()
            local c=cut.getStatus()
            local t=train.status()
            local near=collect.isAuto()
            trainToggle.Text=t.on and 'TRAIN: ON' or 'TRAIN: OFF'
            cutToggle.Text=c.auto and 'CUT: ON' or 'CUT: OFF'
            collectToggle.Text=near and 'COLLECT: ON' or 'COLLECT: OFF'
            trainToggle.BackgroundColor3=t.on and C.active or C.button
            cutToggle.BackgroundColor3=c.auto and C.active or C.button
            collectToggle.BackgroundColor3=near and C.active or C.button
            local r=approximateRoom()
            stateText.Text=string.format(
                'CUT  %s | Machines %d | Ready %d\n'..
                'Sent %d | Confirmed %d | Uncertain %d\n'..
                'TRAIN %s | Rounds %d | Success %d\n'..
                'COLLECT %s | SPEED %.1fx\n'..
                'LOCATION Room_%s / Floor ~%s',
                c.auto and 'ON' or 'OFF',c.bound,c.queued,
                c.sent,c.confirmed,c.unconfirmed,
                t.on and 'ON' or 'OFF',t.round,t.successes,
                near and 'ON' or 'OFF',speed.status().multiplier,
                tostring(r),r and tostring(r+1) or '?'
            )
        end)
        task.wait(.55)
    end
end)
print('[CAR Unified Mobile 2.0] Cut v1.9 + Train v3.2 + Speed v1 + Near Collect v1.5 + Direct Room Teleport v4. Ready.')

]==]
local startMarker='-- ----------------------- COMPACT SHARED UI -----------------------'
local uiStart=source:find(startMarker,1,true)
if not uiStart or source:find(startMarker,uiStart+1,true) then
    warn('[CAR Unified Mobile v2.0] UI anchor mismatch; nothing started')
    return
end
source=source:sub(1,uiStart-1)..mobileUI

local run, compileErr = loadstring(source)
if type(run) ~= 'function' then
    warn('[CAR Unified v1.5] Patched script compile failed; no engine started: '..tostring(compileErr))
    return
end
local okRun, runErr=pcall(run)
if not okRun then warn('[CAR Unified v1.5] Runtime error: '..tostring(runErr)) end

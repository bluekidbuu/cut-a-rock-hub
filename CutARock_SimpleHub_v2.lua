-- Cut a Rock | Simple Hub v2.0 (executor, client-side)
-- Three modes: Auto Train (observe/replay visible memory flashes), Auto Cut, Auto Collect.
-- Uses actual UI objects and a previously observed PlaceStoneInMachineEvent signature.
-- Does not guess memory sequences, purchase anything, teleport, or call InstantCutEvent.
-- PlaceId=113742027864370 GameId=10766468833

if not game:IsLoaded() then game.Loaded:Wait() end
if game.PlaceId ~= 113742027864370 and game.GameId ~= 10766468833 then
    warn('[CAR] Wrong Roblox game')
    return
end

local Players = game:GetService('Players')
local UserInputService = game:GetService('UserInputService')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local player = Players.LocalPlayer
local playerGui = player:WaitForChild('PlayerGui')
local env = type(getgenv) == 'function' and getgenv() or _G
if type(env.CutARockSimpleStop) == 'function' then pcall(env.CutARockSimpleStop) end

local alive = true
local modes = {train=false, cut=false, collect=false}
local attempts = {memory=0, replay=0, select=0, start=0, collect=0}
local status = 'Siap. Berdiri dekat mesin atau anvil.'
local inventory = 'belum diperiksa'
local last = setmetatable({}, {__mode='k'})
local lastRemoteByStone = {}
local machine, pending, machineWaitUntil, menuOpenedAt = nil, nil, 0, 0
local connections = {}
local rootGui

local function updateStatus(s) status = s end
local function path(start, names)
    local obj=start
    for part in names:gmatch('[^.]+') do
        obj=obj and obj:FindFirstChild(part)
    end
    return obj
end
local function visible(obj)
    if not obj or not obj.Parent or not obj:IsA('GuiObject') then return false end
    if obj.AbsoluteSize.X < 5 or obj.AbsoluteSize.Y < 5 then return false end
    local p=obj
    while p do
        if p:IsA('GuiObject') and not p.Visible then return false end
        if p:IsA('ScreenGui') and not p.Enabled then return false end
        p=p.Parent
    end
    return true
end
local function press(button, minInterval)
    if not button or not button:IsA('GuiButton') or not visible(button) then
        return false,'GUI button not visible'
    end
    if button.Interactable == false then return false,'not interactable' end
    local now=os.clock()
    if now-(last[button] or -100) < (minInterval or 0.8) then return false,'cooldown' end
    last[button]=now

    -- Prefer client callbacks: some executors claim synthetic clicks succeeded when no game callback fires.
    if type(getconnections)=='function' then
        for _,signal in ipairs({button.Activated,button.MouseButton1Click}) do
            local ok,list=pcall(getconnections,signal)
            if ok and type(list)=='table' then
                local count=0
                for _,conn in ipairs(list) do
                    if type(conn.Fire)=='function' then
                        if pcall(function() conn:Fire() end) then count+=1 end
                    end
                end
                if count>0 then return true,'connection:'..count end
            end
        end
    end
    if type(firesignal)=='function' then
        local ok=pcall(firesignal,button.Activated)
        if ok then return true,'firesignal' end
        ok=pcall(firesignal,button.MouseButton1Click)
        if ok then return true,'firesignal:click' end
    end
    local point=button.AbsolutePosition+button.AbsoluteSize/2
    local ok, vim=pcall(function() return game:GetService('VirtualInputManager') end)
    if ok and vim then
        local sent=pcall(function()
            vim:SendMouseButtonEvent(point.X,point.Y,0,true,game,0)
            task.wait(0.065)
            vim:SendMouseButtonEvent(point.X,point.Y,0,false,game,0)
        end)
        if sent then return true,'virtual input (unverified)' end
    end
    return false,'executor cannot activate GUI'
end
local function posOf(obj)
    if not obj then return nil end
    if obj:IsA('Attachment') then return obj.WorldPosition end
    if obj:IsA('BasePart') then return obj.Position end
    local p=obj.Parent
    if p and p:IsA('Attachment') then return p.WorldPosition end
    if p and p:IsA('BasePart') then return p.Position end
    local part=obj:FindFirstAncestorWhichIsA('BasePart')
    if part then return part.Position end
    if p and p:IsA('Model') then return p:GetPivot().Position end
end
local function near(prompt)
    local c=player.Character
    local hrp=c and c:FindFirstChild('HumanoidRootPart')
    local pp=posOf(prompt)
    return hrp and pp and (hrp.Position-pp).Magnitude<=prompt.MaxActivationDistance
end
local function usePrompt(prompt)
    if not prompt or not prompt.Parent or not prompt.Enabled or not near(prompt) then return false end
    if os.clock()-(last[prompt] or -100) < 2.5 then return false end
    last[prompt]=os.clock()
    if type(fireproximityprompt)=='function' then
        return pcall(fireproximityprompt,prompt)
    end
    return pcall(function()
        prompt:InputHoldBegin()
        task.wait(prompt.HoldDuration+0.1)
        prompt:InputHoldEnd()
    end)
end
local function machineOf(prompt)
    local p=prompt
    while p and p~=workspace do
        if p:IsA('Model') and p.Name:match('^level%d+$') then return p end
        p=p.Parent
    end
    return nil
end
local function findPrompt(action, preferred)
    local best, bestDist=nil, math.huge
    local hrp=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
    if not hrp then return nil end
    for _,p in ipairs(workspace:GetDescendants()) do
        if p:IsA('ProximityPrompt') and p.Name=='CutMachinePrompt' and p.Enabled then
            local txt=p.ActionText:lower()
            local matches=(action=='collect' and txt:find('collect',1,true))
                or (action=='place' and txt:find('place',1,true))
            if matches and (not preferred or machineOf(p)==preferred) then
                local pos=posOf(p)
                if pos then
                    local d=(hrp.Position-pos).Magnitude
                    if d<=p.MaxActivationDistance and d<bestDist then best,bestDist=p,d end
                end
            end
        end
    end
    return best
end
local function isUUID(s)
    return type(s)=='string' and
        s:match('^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x$')~=nil
end
local function menu() return playerGui:FindFirstChild('CuttingMenu') end
local function menuOpen()
    local obj=menu()
    local frame=obj and obj:FindFirstChild('MainFrame')
    return obj and obj:IsA('ScreenGui') and obj.Enabled
        and frame and visible(frame)
end
local function stoneCards()
    local arr={}
    local m=menu()
    if not menuOpen() then return arr end
    for _,node in ipairs(m:GetDescendants()) do
        if node:IsA('GuiButton') and isUUID(node.Name) and visible(node)
            and node.Interactable~=false then
            arr[#arr+1]=node
        end
    end
    table.sort(arr,function(a,b)
        if a.AbsolutePosition.Y==b.AbsolutePosition.Y then
            return a.AbsolutePosition.X<b.AbsolutePosition.X
        end
        return a.AbsolutePosition.Y<b.AbsolutePosition.Y
    end)
    return arr
end
local function collectButton()
    return path(playerGui,'CuttingMenu.MainFrame.Panel.CurrentCut.CollectTap')
end
local function cutButton()
    return path(playerGui,'CuttingMenu.MainFrame.Panel.KesimPaneli.KesButonu')
end
local function closeCutMenu()
    local btn=path(playerGui,'CuttingMenu.MainFrame.Panel.KapatButonu')
    if btn and visible(btn) then press(btn,1.5) end
end
local function collectStep()
    if not modes.collect then return false end
    local c=findPrompt('collect',machine)
    if not c then c=findPrompt('collect') end
    if c and usePrompt(c) then
        attempts.collect+=1
        machineWaitUntil=os.clock()+1.5
        pending=nil
        updateStatus('Collect: prompt dikirim')
        return true
    end
    local btn=collectButton()
    if btn and visible(btn) then
        local ok=press(btn,2.0)
        if ok then
            attempts.collect+=1
            pending=nil
            machineWaitUntil=os.clock()+1.8
            updateStatus('Collect: tombol ditekan')
            return true
        end
    end
    return false
end
local function startedOrCollectable()
    if machine and findPrompt('collect',machine) then return true end
    local current=path(playerGui,'CuttingMenu.MainFrame.Panel.CurrentCut')
    local tile=path(playerGui,'CuttingMenu.MainFrame.Panel.CurrentCut.CollectTap')
    return (current and visible(current) and tile and visible(tile)) and true or false
end
local function tryObservedPlace(stone, levelModel)
    -- This exact event signature was observed in the user's manual audit:
    -- PlaceStoneInMachineEvent:FireServer(Instance:Model:level10/11, string(len=36))
    -- Never synthesize a UUID: use only the card currently displayed in game UI.
    if not stone or not levelModel or not isUUID(stone) then return false end
    if os.clock() < (lastRemoteByStone[stone] or 0) then return false end
    local remote=ReplicatedStorage:FindFirstChild('PlaceStoneInMachineEvent')
    if not remote or not remote:IsA('RemoteEvent') then return false end
    lastRemoteByStone[stone]=os.clock()+20
    return pcall(function() remote:FireServer(levelModel,stone) end)
end
local function cutStep()
    if not modes.cut or os.clock()<machineWaitUntil then return end
    if menuOpen() then
        if startedOrCollectable() then
            pending=nil
            updateStatus('Cut: mesin sedang memproses / siap collect')
            closeCutMenu()
            machineWaitUntil=os.clock()+3
            return
        end
        local cards=stoneCards()
        inventory=tostring(#cards)..' batu dapat dipilih di menu'
        if #cards==0 then
            if os.clock()-menuOpenedAt<4 then
                updateStatus('Cut: menunggu daftar batu dari mesin')
                machineWaitUntil=os.clock()+0.8
                return
            end
            updateStatus('Cut: tidak ada batu yang ditampilkan mesin')
            closeCutMenu()
            machineWaitUntil=os.clock()+7
            return
        end
        if not pending then
            local card=cards[1]
            local ok,method=press(card,1)
            if ok then
                pending={id=card.Name,level=machine,at=os.clock(),clicked=false,fallback=false}
                attempts.select+=1
                updateStatus('Cut: pilih batu ('..method..')')
                machineWaitUntil=os.clock()+0.6
            else
                updateStatus('Cut: tombol batu gagal ('..tostring(method)..')')
                machineWaitUntil=os.clock()+2
            end
            return
        end
        if os.clock()-pending.at>10 then pending=nil; machineWaitUntil=os.clock()+2; return end
        if not pending.clicked then
            local b=cutButton()
            if b and visible(b) then
                local ok,how=press(b,1.2)
                if ok then
                    pending.clicked=true
                    pending.cutAt=os.clock()
                    attempts.start+=1
                    updateStatus('Cut: mulai proses ('..how..')')
                    machineWaitUntil=os.clock()+2
                    return
                end
            end
            -- If GUI callback failed, use only a manual-audit-confirmed remote signature.
            if not pending.fallback and pending.level then
                pending.fallback=true
                if tryObservedPlace(pending.id,pending.level) then
                    pending.clicked=true
                    pending.cutAt=os.clock()
                    attempts.start+=1
                    updateStatus('Cut: permintaan mesin dikirim')
                    machineWaitUntil=os.clock()+3
                    return
                end
            end
            updateStatus('Cut: tombol KesButonu belum bisa dipicu')
            machineWaitUntil=os.clock()+2
            return
        end
        if startedOrCollectable() then
            updateStatus('Cut: menunggu selesai')
            closeCutMenu()
            pending=nil
            machineWaitUntil=os.clock()+6
            return
        end
        if os.clock()-(pending.cutAt or 0)>3 and not pending.fallback and pending.level then
            pending.fallback=true
            if tryObservedPlace(pending.id,pending.level) then
                updateStatus('Cut: sinkronisasi permintaan batu')
            end
        end
        if os.clock()-(pending.cutAt or 0)>7 then
            updateStatus('Cut: status mesin belum terkonfirmasi')
            closeCutMenu()
            pending=nil
            machineWaitUntil=os.clock()+8
        end
        return
    end
    pending=nil
    inventory='cek dengan membuka mesin'
    local prompt=findPrompt('place',machine)
    if not prompt then prompt=findPrompt('place') end
    if prompt then
        machine=machineOf(prompt)
        if usePrompt(prompt) then
            updateStatus('Cut: membuka mesin')
            menuOpenedAt=os.clock()
            machineWaitUntil=os.clock()+1.3
        end
    else
        updateStatus('Cut: dekati mesin dengan prompt Place Rock')
        machineWaitUntil=os.clock()+2
    end
end

-- MEMORY GAME. Capture the visual flash sequence, then replay that exact sequence.
-- Never guess a random tile and never call the MemoryOyunu remote with unknown args.
local memory={state='idle', seq={}, baseline={}, highlighted={}, tiles={}, lastFlash=0,
    phaseStart=0, nextStart=0, lastMessage='belum mulai'}
local function memoryMenu() return playerGui:FindFirstChild('MemoryMenu') end
local function memoryVisible()
    local m=memoryMenu()
    if not m then return false end
    if m:IsA('ScreenGui') then return m.Enabled end
    return visible(m)
end
local function memoryTiles()
    local list={}
    local m=memoryMenu()
    if not m then return list end
    for _,v in ipairs(m:GetDescendants()) do
        if v:IsA('GuiButton') and v.Name:match('^Tas%d+$') and visible(v) then
            list[#list+1]=v
        end
    end
    table.sort(list,function(a,b)
        return tonumber(a.Name:match('%d+')) < tonumber(b.Name:match('%d+'))
    end)
    return list
end
local function visualSnapshot(tile)
    local s={}
    local function capture(o)
        local vals={}
        if o:IsA('GuiObject') then
            local col=o.BackgroundColor3
            vals[#vals+1]=col.R; vals[#vals+1]=col.G; vals[#vals+1]=col.B
            vals[#vals+1]=o.BackgroundTransparency
            vals[#vals+1]=o.Size.X.Scale; vals[#vals+1]=o.Size.Y.Scale
        end
        if o:IsA('ImageLabel') or o:IsA('ImageButton') then
            local c=o.ImageColor3
            vals[#vals+1]=c.R; vals[#vals+1]=c.G; vals[#vals+1]=c.B
            vals[#vals+1]=o.ImageTransparency
        end
        if o:IsA('TextLabel') or o:IsA('TextButton') then
            local c=o.TextColor3
            vals[#vals+1]=c.R; vals[#vals+1]=c.G; vals[#vals+1]=c.B
            vals[#vals+1]=o.TextTransparency
        end
        if o:IsA('UIStroke') then
            local c=o.Color
            vals[#vals+1]=c.R; vals[#vals+1]=c.G; vals[#vals+1]=c.B
            vals[#vals+1]=o.Transparency; vals[#vals+1]=o.Thickness
        end
        if o:IsA('UIScale') then vals[#vals+1]=o.Scale end
        if #vals>0 then s[o]=vals end
    end
    capture(tile)
    for _,v in ipairs(tile:GetDescendants()) do
        capture(v)
    end
    return s
end
local function visualDelta(current, baseline)
    local diff=0
    for obj,now in pairs(current) do
        local old=baseline[obj]
        if old then
            for i=1,math.min(#old,#now) do
                diff=math.max(diff,math.abs(now[i]-old[i]))
            end
        else
            -- A newly added highlight overlay is useful evidence too.
            diff=math.max(diff,0.35)
        end
    end
    return diff
end
local function startMemoryRound(playButton)
    local tiles=memoryTiles()
    if #tiles<2 then
        memory.lastMessage='MemoryMenu: tiles belum terlihat'
        return
    end
    memory.tiles=tiles
    memory.baseline={}
    memory.highlighted={}
    memory.seq={}
    for _,tile in ipairs(tiles) do memory.baseline[tile]=visualSnapshot(tile) end
    memory.phaseStart=os.clock()
    memory.lastFlash=os.clock()
    memory.state='observing'
    local ok=press(playButton,3)
    if not ok and playButton then memory.state='idle'; return end
    memory.nextStart=os.clock()+4
    memory.lastMessage='Merekam urutan warna ('..#tiles..' tombol)'
end
local function recordMemoryFlashes()
    if memory.state~='observing' then return end
    local now=os.clock()
    local active={}
    for _,tile in ipairs(memory.tiles) do
        if tile.Parent and visible(tile) then
            local baseline=memory.baseline[tile]
            if baseline then
                local delta=visualDelta(visualSnapshot(tile),baseline)
                if delta>0.19 then active[#active+1]=tile end
            end
        end
    end
    if #active==1 then
        local tile=active[1]
        if not memory.highlighted[tile] then
            if #memory.seq<25 then
                memory.seq[#memory.seq+1]=tile.Name
                memory.lastFlash=now
            end
            memory.highlighted[tile]=true
        end
    end
    for _,tile in ipairs(memory.tiles) do
        local found=false
        for _,bright in ipairs(active) do if tile==bright then found=true; break end end
        if not found then memory.highlighted[tile]=false end
    end
    if #memory.seq>=2 and (now-memory.lastFlash)>2.2
        and (now-memory.phaseStart)>2.6 then
        memory.state='replaying'
        memory.lastMessage='Mengulang '..#memory.seq..' tombol'
        attempts.replay+=1
        task.spawn(function()
            for _,name in ipairs(memory.seq) do
                if not alive or not modes.train or not memoryVisible() then break end
                local target=nil
                for _,tile in ipairs(memoryTiles()) do
                    if tile.Name==name then target=tile; break end
                end
                if not target then break end
                local ok=press(target,0.18)
                if not ok then
                    memory.lastMessage='Gagal klik '..name
                    break
                end
                task.wait(0.36)
            end
            memory.state='cooldown'
            memory.nextStart=os.clock()+3.5
            memory.lastMessage='Urutan dikirim; tunggu ronde berikutnya'
        end)
    elseif now-memory.phaseStart>12 and #memory.seq<2 then
        memory.state='blocked'
        memory.lastMessage='Kilatan pola tidak terdeteksi. Perlu screenshot MemoryMenu.'
    end
end
local function trainStep()
    if not modes.train then return end
    if menuOpen() then return end -- Never interfere with cutting GUI.
    local m=memoryMenu()
    if memoryVisible() then
        if memory.state=='observing' then recordMemoryFlashes(); return end
        if memory.state=='replaying' then return end
        if memory.state=='blocked' then
            updateStatus('Train: '..memory.lastMessage)
            return
        end
        if memory.state=='cooldown' and os.clock()<memory.nextStart then return end
        local play=m and m:FindFirstChild('PlayButonu',true)
        if play and visible(play) and os.clock()>=memory.nextStart then
            startMemoryRound(play)
            attempts.memory+=1
            updateStatus('Train: '..memory.lastMessage)
        elseif memory.state~='observing' and memory.state~='replaying' then
            -- Some rounds start automatically without a Play button.
            if #memoryTiles()>=2 and memory.state=='idle' then
                startMemoryRound(nil)
                updateStatus('Train: mengamati MemoryMenu')
            end
        end
        return
    end
    memory.state='idle'
    local intro=path(playerGui,'MemoryPlayGui.PlayButonu')
    if intro and visible(intro) then
        if os.clock()>=memory.nextStart then
            local ok=press(intro,2)
            if ok then
                memory.nextStart=os.clock()+2.5
                updateStatus('Train: membuka memory game')
            end
        end
        return
    end
    updateStatus('Train: buka minigame/anvil dulu; belum tampak MemoryMenu')
end

local function create(class,props,parent)
    local obj=Instance.new(class)
    for k,v in pairs(props) do obj[k]=v end
    obj.Parent=parent
    return obj
end
rootGui=create('ScreenGui',{Name='CutARock_SimpleHub_v2',ResetOnSpawn=false,
    ZIndexBehavior=Enum.ZIndexBehavior.Sibling},playerGui)
local panel=create('Frame',{Size=UDim2.fromOffset(306,280),Position=UDim2.fromOffset(15,115),
    BackgroundColor3=Color3.fromRGB(23,28,40),BorderSizePixel=0},rootGui)
create('UICorner',{CornerRadius=UDim.new(0,10)},panel)
create('UIStroke',{Color=Color3.fromRGB(78,98,123),Thickness=1},panel)
local title=create('TextLabel',{Text='CUT A ROCK | SIMPLE v2',BackgroundTransparency=1,
    Size=UDim2.fromOffset(264,37),Position=UDim2.fromOffset(11,0),
    Font=Enum.Font.GothamBold,TextSize=14,TextXAlignment=Enum.TextXAlignment.Left,
    TextColor3=Color3.new(1,1,1)},panel)
local close=create('TextButton',{Text='X',Size=UDim2.fromOffset(27,26),Position=UDim2.fromOffset(270,7),
    TextColor3=Color3.new(1,1,1),BackgroundColor3=Color3.fromRGB(130,53,64),
    Font=Enum.Font.GothamBold,BorderSizePixel=0},panel)
local function button(text,y,fn)
    local b=create('TextButton',{Text=text,Size=UDim2.fromOffset(284,37),Position=UDim2.fromOffset(11,y),
        TextColor3=Color3.new(1,1,1),BackgroundColor3=Color3.fromRGB(49,61,79),
        TextSize=13,Font=Enum.Font.GothamMedium,BorderSizePixel=0},panel)
    create('UICorner',{CornerRadius=UDim.new(0,7)},b)
    connections[#connections+1]=b.Activated:Connect(function() fn(b) end)
end
local function toggle(mode,name)
    return function(b)
        modes[mode]=not modes[mode]
        b.Text=name..' : '..(modes[mode] and 'ON' or 'OFF')
        b.BackgroundColor3=modes[mode] and Color3.fromRGB(32,119,87)
            or Color3.fromRGB(49,61,79)
        if mode=='train' then
            memory.state='idle'
            memory.nextStart=0
        end
        updateStatus(name..(modes[mode] and ' aktif' or ' berhenti'))
    end
end
button('Auto Train (Memory) : OFF',42,toggle('train','Auto Train (Memory)'))
button('Auto Cut (Inventory) : OFF',84,toggle('cut','Auto Cut (Inventory)'))
button('Auto Collect : OFF',126,toggle('collect','Auto Collect'))
local msg=create('TextLabel',{Text='',Size=UDim2.fromOffset(282,70),Position=UDim2.fromOffset(12,170),
    BackgroundTransparency=1,TextColor3=Color3.fromRGB(194,216,238),
    TextSize=11,Font=Enum.Font.Gotham,TextWrapped=true,
    TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top},panel)
local info=create('TextLabel',{Text='Hanya 3 fitur. Jarak dekat; tanpa pembelian.',
    Size=UDim2.fromOffset(284,22),Position=UDim2.fromOffset(11,251),
    BackgroundTransparency=1,TextSize=10,Font=Enum.Font.Gotham,
    TextColor3=Color3.fromRGB(159,175,196)},panel)

local drag=false
local fromPoint,fromPos
connections[#connections+1]=title.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
        drag=true;fromPoint=input.Position;fromPos=panel.Position
        local c;c=input.Changed:Connect(function()
            if input.UserInputState==Enum.UserInputState.End then drag=false;c:Disconnect() end
        end)
    end
end)
connections[#connections+1]=UserInputService.InputChanged:Connect(function(input)
    if drag and fromPoint and (input.UserInputType==Enum.UserInputType.Touch
        or input.UserInputType==Enum.UserInputType.MouseMovement) then
        local delta=input.Position-fromPoint
        panel.Position=UDim2.new(fromPos.X.Scale,fromPos.X.Offset+delta.X,
            fromPos.Y.Scale,fromPos.Y.Offset+delta.Y)
    end
end)
local function stop()
    alive=false
    for _,conn in ipairs(connections) do pcall(function()conn:Disconnect()end) end
    if rootGui and rootGui.Parent then rootGui:Destroy() end
    if env.CutARockSimpleStop==stop then env.CutARockSimpleStop=nil end
end
env.CutARockSimpleStop=stop
connections[#connections+1]=close.Activated:Connect(stop)

task.spawn(function()
    while alive do
        local ok,err=pcall(function()
            if modes.collect then collectStep() end
            if modes.cut and not memoryVisible() then cutStep() end
            if modes.train then trainStep() end
        end)
        if not ok then updateStatus('Error: '..tostring(err):sub(1,85)) end
        if msg and msg.Parent then
            msg.Text='Inventory: '..inventory..'\n'
                ..status..'\n'
                ..'Train: '..memory.lastMessage..' | Urutan: '..#memory.seq
                ..' | Cut: '..attempts.start..' Collect: '..attempts.collect
        end
        task.wait(memory.state=='observing' and 0.055 or 0.35)
    end
end)
print('[CAR] Simple Hub v2 loaded. Memory sequence is captured from GUI flashes, never guessed.')

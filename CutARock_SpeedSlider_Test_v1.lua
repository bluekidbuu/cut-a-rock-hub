-- CUT A ROCK | SPEED SLIDER TEST v1
-- Independent mobile-friendly client-side WalkSpeed experiment.
-- Does not touch Cut/Train, inventory, machines, remotes, mining or collect.
-- WalkSpeed is a local property: game logic / server may limit or reset movement.

if not game:IsLoaded() then game.Loaded:Wait() end
if game.PlaceId ~= 113742027864370 and game.GameId ~= 10766468833 then
    warn('[CAR Speed] This test is intended for Cut a Rock.')
    return
end

local Players = game:GetService('Players')
local UIS = game:GetService('UserInputService')
local player = Players.LocalPlayer
local pg = player:WaitForChild('PlayerGui')
local env = (type(getgenv) == 'function' and getgenv()) or _G
if type(env.CARSpeedSliderStop) == 'function' then
    pcall(env.CARSpeedSliderStop)
end

local alive = true
local multiplier = 1.0
local MIN_MULT, MAX_MULT, STEP = 1.0, 3.0, 0.1
local humanoid, baseSpeed, lastApplied
local charConnection
local connections = {}
local statusText = 'Normal speed; move the slider to test.'

local function connect(signal, handler)
    local c = signal:Connect(handler)
    connections[#connections+1] = c
    return c
end

local function make(kind, props, parent)
    local obj = Instance.new(kind)
    for k, v in pairs(props or {}) do obj[k] = v end
    obj.Parent = parent
    return obj
end

local old = pg:FindFirstChild('CAR_SpeedSlider_Test_v1')
if old then old:Destroy() end
local gui = make('ScreenGui', {
    Name = 'CAR_SpeedSlider_Test_v1',
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 150,
}, pg)

local panel = make('Frame', {
    Name='Panel',
    Size=UDim2.fromOffset(300,165),
    Position=UDim2.new(0.5,-150,0.48,-80),
    BackgroundColor3=Color3.fromRGB(20,28,42),
    BorderSizePixel=0,
    Active=true,
}, gui)
make('UICorner',{CornerRadius=UDim.new(0,10)},panel)
make('UIStroke',{Color=Color3.fromRGB(74,93,118),Thickness=1},panel)

local header = make('TextLabel', {
    Text='CAR | SPEED SLIDER v1',
    Size=UDim2.fromOffset(228,35),
    Position=UDim2.fromOffset(11,2),
    BackgroundTransparency=1,
    TextColor3=Color3.fromRGB(241,247,255),
    TextXAlignment=Enum.TextXAlignment.Left,
    Font=Enum.Font.GothamBold,
    TextSize=13,
    Active=true,
},panel)
local minimize = make('TextButton', {
    Text='_', Size=UDim2.fromOffset(25,25), Position=UDim2.fromOffset(241,7),
    TextColor3=Color3.new(1,1,1),BackgroundColor3=Color3.fromRGB(50,64,85),
    Font=Enum.Font.GothamBold,TextSize=16,BorderSizePixel=0,
},panel)
make('UICorner',{CornerRadius=UDim.new(0,6)},minimize)
local close = make('TextButton', {
    Text='X', Size=UDim2.fromOffset(25,25), Position=UDim2.fromOffset(269,7),
    TextColor3=Color3.new(1,1,1),BackgroundColor3=Color3.fromRGB(139,49,61),
    Font=Enum.Font.GothamBold,TextSize=12,BorderSizePixel=0,
},panel)
make('UICorner',{CornerRadius=UDim.new(0,6)},close)

local content = make('Frame',{
    Name='Content',Position=UDim2.fromOffset(0,38),Size=UDim2.fromOffset(300,127),
    BackgroundTransparency=1,
},panel)
local speedLabel = make('TextLabel',{
    Text='Speed: 1.0x',Size=UDim2.fromOffset(268,22),
    Position=UDim2.fromOffset(16,1),BackgroundTransparency=1,
    TextColor3=Color3.fromRGB(216,235,255),Font=Enum.Font.GothamBold,
    TextSize=14,TextXAlignment=Enum.TextXAlignment.Left,
},content)
local track = make('Frame',{
    Name='Track',Size=UDim2.fromOffset(260,12),Position=UDim2.fromOffset(20,38),
    BackgroundColor3=Color3.fromRGB(65,81,101),BorderSizePixel=0,Active=true,
},content)
make('UICorner',{CornerRadius=UDim.new(1,0)},track)
local fill = make('Frame',{
    Name='Fill',Size=UDim2.new(0,0,1,0),
    BackgroundColor3=Color3.fromRGB(48,169,133),BorderSizePixel=0,
},track)
make('UICorner',{CornerRadius=UDim.new(1,0)},fill)
local knob = make('Frame',{
    Name='Handle',Size=UDim2.fromOffset(23,23),
    AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.new(0,0,0.5,0),
    BackgroundColor3=Color3.fromRGB(238,247,255),BorderSizePixel=0,Active=false,
},track)
make('UICorner',{CornerRadius=UDim.new(1,0)},knob)
make('UIStroke',{Color=Color3.fromRGB(42,109,101),Thickness=1},knob)

local minLabel = make('TextLabel',{
    Text='1.0x',Size=UDim2.fromOffset(55,20),Position=UDim2.fromOffset(18,55),
    BackgroundTransparency=1,TextColor3=Color3.fromRGB(157,176,198),
    TextXAlignment=Enum.TextXAlignment.Left,Font=Enum.Font.Gotham,TextSize=11,
},content)
local maxLabel = make('TextLabel',{
    Text='3.0x',Size=UDim2.fromOffset(55,20),Position=UDim2.fromOffset(228,55),
    BackgroundTransparency=1,TextColor3=Color3.fromRGB(157,176,198),
    TextXAlignment=Enum.TextXAlignment.Right,Font=Enum.Font.Gotham,TextSize=11,
},content)
local reset = make('TextButton',{
    Text='RESET 1.0x',Size=UDim2.fromOffset(110,31),
    Position=UDim2.fromOffset(17,87),BackgroundColor3=Color3.fromRGB(54,77,113),
    TextColor3=Color3.fromRGB(245,248,255),Font=Enum.Font.GothamBold,
    TextSize=12,BorderSizePixel=0,
},content)
make('UICorner',{CornerRadius=UDim.new(0,7)},reset)
local status = make('TextLabel',{
    Text='Waiting for character',Size=UDim2.fromOffset(150,37),
    Position=UDim2.fromOffset(136,83),BackgroundTransparency=1,
    TextColor3=Color3.fromRGB(172,200,225),Font=Enum.Font.Gotham,
    TextSize=10,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,
},content)

local function updateUI()
    local alpha = (multiplier - MIN_MULT) / (MAX_MULT - MIN_MULT)
    fill.Size=UDim2.new(alpha,0,1,0)
    knob.Position=UDim2.new(alpha,0,0.5,0)
    if humanoid and humanoid.Parent and baseSpeed then
        speedLabel.Text=string.format('Speed: %.1fx  |  %.1f studs/s',multiplier,baseSpeed*multiplier)
    else
        speedLabel.Text=string.format('Speed: %.1fx  |  waiting for character',multiplier)
    end
    status.Text=statusText
end

local function setSpeed(newMultiplier)
    multiplier = math.clamp(math.floor(newMultiplier/STEP+0.5)*STEP,MIN_MULT,MAX_MULT)
    if humanoid and humanoid.Parent and baseSpeed then
        local desired=baseSpeed*multiplier
        local ok,err=pcall(function() humanoid.WalkSpeed=desired end)
        if ok then
            lastApplied=desired
            statusText=multiplier==1 and 'Normal speed restored' or 'Applied locally; test walking'
        else
            statusText='WalkSpeed error: '..tostring(err):sub(1,45)
        end
    else
        statusText='Waiting for Humanoid...'
    end
    updateUI()
end

local function attachCharacter(character)
    if charConnection then pcall(function() charConnection:Disconnect() end) end
    humanoid=nil
    baseSpeed=nil
    lastApplied=nil
    updateUI()
    task.spawn(function()
        local h=character:WaitForChild('Humanoid',10)
        if not alive or player.Character ~= character or not h then return end
        -- Allow initial game spawn settings to apply before recording the base.
        task.wait(0.35)
        if not alive or player.Character~=character then return end
        humanoid=h
        baseSpeed=h.WalkSpeed
        statusText='Base speed: '..string.format('%.1f',baseSpeed)
        if multiplier>1 then setSpeed(multiplier) else updateUI() end
        charConnection=h:GetPropertyChangedSignal('WalkSpeed'):Connect(function()
            if not alive or humanoid~=h or not baseSpeed then return end
            local expected=baseSpeed*multiplier
            if multiplier>1 and math.abs(h.WalkSpeed-expected)>0.15 then
                statusText='Game changed speed; adjust slider to retry'
            elseif multiplier==1 then
                -- At normal speed, follow future game-provided speed changes.
                baseSpeed=h.WalkSpeed
                statusText='Normal speed (game controlled)'
            end
            updateUI()
        end)
    end)
end

local expanded=true
connect(minimize.Activated,function()
    expanded=not expanded
    content.Visible=expanded
    panel.Size=UDim2.fromOffset(300,expanded and 165 or 36)
    minimize.Text=expanded and '_' or '+'
end)

local draggingSlider=false
local slideInput
local function fromX(x)
    local width=track.AbsoluteSize.X
    if width<=0 then return end
    local fraction=math.clamp((x-track.AbsolutePosition.X)/width,0,1)
    setSpeed(MIN_MULT+(MAX_MULT-MIN_MULT)*fraction)
end
connect(track.InputBegan,function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
        draggingSlider=true
        slideInput=input
        fromX(input.Position.X)
    end
end)
connect(UIS.InputChanged,function(input)
    if draggingSlider then
        if (input.UserInputType==Enum.UserInputType.MouseMovement and slideInput
            and slideInput.UserInputType==Enum.UserInputType.MouseButton1)
           or (input.UserInputType==Enum.UserInputType.Touch and input==slideInput) then
            fromX(input.Position.X)
        end
    end
end)
connect(UIS.InputEnded,function(input)
    if draggingSlider and (input==slideInput or (slideInput and slideInput.UserInputType==Enum.UserInputType.MouseButton1
        and input.UserInputType==Enum.UserInputType.MouseButton1)) then
        draggingSlider=false
        slideInput=nil
    end
end)

local draggingPanel, dragStart, panelStart=false,nil,nil
connect(header.InputBegan,function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
        draggingPanel=true
        dragStart=input
        panelStart=panel.Position
    end
end)
connect(UIS.InputChanged,function(input)
    if draggingPanel and dragStart then
        if (input.UserInputType==Enum.UserInputType.MouseMovement and dragStart.UserInputType==Enum.UserInputType.MouseButton1)
           or (input.UserInputType==Enum.UserInputType.Touch and input==dragStart) then
            local delta=input.Position-dragStart.Position
            panel.Position=UDim2.new(panelStart.X.Scale,panelStart.X.Offset+delta.X,
                panelStart.Y.Scale,panelStart.Y.Offset+delta.Y)
        end
    end
end)
connect(UIS.InputEnded,function(input)
    if dragStart and (input==dragStart or (dragStart.UserInputType==Enum.UserInputType.MouseButton1
         and input.UserInputType==Enum.UserInputType.MouseButton1)) then
        draggingPanel=false
        dragStart=nil
    end
end)
connect(reset.Activated,function()setSpeed(1)end)

local function stop()
    if not alive then return end
    alive=false
    if humanoid and humanoid.Parent and baseSpeed and lastApplied
        and math.abs(humanoid.WalkSpeed-lastApplied)<0.15 then
        pcall(function()humanoid.WalkSpeed=baseSpeed end)
    end
    if charConnection then pcall(function()charConnection:Disconnect()end) end
    for _,c in ipairs(connections) do pcall(function()c:Disconnect()end) end
    if gui and gui.Parent then gui:Destroy() end
    if env.CARSpeedSliderStop==stop then env.CARSpeedSliderStop=nil end
end
env.CARSpeedSliderStop=stop
connect(close.Activated,stop)
connect(player.CharacterAdded,attachCharacter)
if player.Character then attachCharacter(player.Character) end
updateUI()
print('[CAR Speed Slider] Test loaded. Slider 1.0x-3.0x, reset restores normal. Close stops. Client-side only.')

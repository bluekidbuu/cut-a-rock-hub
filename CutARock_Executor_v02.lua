-- Cut a Rock | Executor Diagnostic Hub v0.2
-- PlaceId 113742027864370 / GameId 10766468833
-- Local-only. Does not buy anything, teleport, or guess remote payloads.
-- Auto prompt modes interact only with nearby enabled ProximityPrompts.

if not game:IsLoaded() then game.Loaded:Wait() end
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local player = Players.LocalPlayer
if game.PlaceId ~= 113742027864370 and game.GameId ~= 10766468833 then
    warn("[CAR] This script is for Cut a Rock only.")
    return
end

local env = (type(getgenv) == "function" and getgenv()) or _G
if env.CutARockStarter and type(env.CutARockStarter.Stop) == "function" then
    pcall(env.CutARockStarter.Stop)
end
local running = true
local active = {cut=false, sell=false, tool=false, observe=false}
local prompts, lastUse, connections = {}, setmetatable({}, {__mode="k"}), {}
local stats = {scan=0, attempts=0, dispatched=0, failed=0, toolAttempts=0,
    message="Ready: press SCAN or activate a mode.", lastError="none"}
local recent = {}
local observed = {}
local traceFilter = {
    OrsVurusu=true, KapiVurusu=true, DigBlockHealthEvent=true,
    BlockBrokenEvent=true, SyncBrokenBlocksEvent=true, SellEvent=true,
    OpenCuttingMachineMenu=true, PlaceStoneInMachineEvent=true,
    InstantCutEvent=true, KesimBildirimi=true, UpgradeEvent=true,
    LevelUpMachineEvent=true, PickaxeEquipEvent=true
}

local function reportArg(value)
    local typ = typeof(value)
    if typ == "string" then return string.format("%q", value:sub(1, 42)) end
    if typ == "number" then return tostring(math.floor(value * 1000 + 0.5) / 1000) end
    if typ == "boolean" or typ == "nil" then return tostring(value) end
    if typ == "Instance" then return "Instance:" .. value.ClassName .. ":" .. value.Name end
    return typ
end

local function recordRemote(remote, method, ...)
    if not running or not active.observe or not traceFilter[remote.Name] then return end
    local argc = select("#", ...)
    local args = {}
    for i = 1, math.min(argc, 5) do args[i] = reportArg(select(i, ...)) end
    if argc > 5 then args[#args+1] = "+" .. tostring(argc-5) .. " more" end
    local signature = remote.Name .. ":" .. method .. "(" .. table.concat(args, ", ") .. ")"
    local entry = observed[signature]
    if entry then
        entry.count += 1
    else
        entry = {signature=signature, count=1}
        observed[signature] = entry
        if #recent >= 35 then
            observed[recent[1].signature] = nil
            table.remove(recent, 1)
        end
        recent[#recent+1] = entry
    end
end

-- Remote signatures remain unverified. No remote interception or firing.
local tap = {installed=false, handler=nil}
local function installTap()
    return false, "Remote trace not available in this diagnostic build"
end

local gui = Instance.new("ScreenGui")
gui.Name = "CutARock_Diagnostic_v02"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")
local function make(class, properties, parent)
    local obj = Instance.new(class)
    for k,v in pairs(properties) do obj[k]=v end
    obj.Parent = parent
    return obj
end
local panel = make("Frame", {
    Size=UDim2.fromOffset(310,430), Position=UDim2.new(0,12,0.15,0),
    BackgroundColor3=Color3.fromRGB(23,27,38), BorderSizePixel=0
},gui)
make("UICorner",{CornerRadius=UDim.new(0,11)},panel)
make("UIStroke",{Color=Color3.fromRGB(74,84,105),Thickness=1},panel)
local title = make("TextLabel",{
    Text="CUT A ROCK  |  DIAGNOSTIC v0.2",
    TextColor3=Color3.new(1,1,1), TextSize=14, Font=Enum.Font.GothamBold,
    BackgroundTransparency=1, Position=UDim2.fromOffset(11,3),
    Size=UDim2.new(1,-52,0,36),TextXAlignment=Enum.TextXAlignment.Left
},panel)
local close = make("TextButton",{
    Text="X",TextSize=15,Font=Enum.Font.GothamBold,
    Size=UDim2.fromOffset(29,29),Position=UDim2.new(1,-37,0,7),
    BackgroundColor3=Color3.fromRGB(101,48,52),TextColor3=Color3.new(1,1,1),BorderSizePixel=0
},panel)
make("UICorner",{CornerRadius=UDim.new(0,6)},close)

local dragging, dragStart, starting = false, nil, nil
connections[#connections+1] = title.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging,dragStart,starting=true,input.Position,panel.Position
        local conn
        conn=input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging=false
                conn:Disconnect()
            end
        end)
    end
end)
connections[#connections+1] = UIS.InputChanged:Connect(function(input)
    if not dragging or not running or not dragStart then return end
    if input.UserInputType == Enum.UserInputType.Touch
        or input.UserInputType == Enum.UserInputType.MouseMovement then
        local delta=input.Position-dragStart
        panel.Position=UDim2.new(starting.X.Scale,starting.X.Offset+delta.X,
            starting.Y.Scale,starting.Y.Offset+delta.Y)
    end
end)

make("TextLabel",{
    Text="Proximity prompts only; no guessed remotes",
    Size=UDim2.new(1,-24,0,25),Position=UDim2.fromOffset(12,38),
    BackgroundTransparency=1,TextColor3=Color3.fromRGB(169,181,198),
    TextSize=11,Font=Enum.Font.Gotham,TextXAlignment=Enum.TextXAlignment.Left
},panel)
local status=make("TextLabel",{
    Text=stats.message,Size=UDim2.new(1,-22,0,61),Position=UDim2.fromOffset(11,269),
    BackgroundTransparency=1,TextColor3=Color3.fromRGB(192,214,238),
    TextSize=11,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,
    TextYAlignment=Enum.TextYAlignment.Top,Font=Enum.Font.Gotham
},panel)
local indicators={}
local function toggleRow(key,textLabel,y)
    local button=make("TextButton",{
        Text="",Size=UDim2.new(1,-24,0,39),Position=UDim2.fromOffset(12,y),
        BackgroundColor3=Color3.fromRGB(41,47,64),BorderSizePixel=0
    },panel)
    make("UICorner",{CornerRadius=UDim.new(0,7)},button)
    make("TextLabel",{
        Text=textLabel,Size=UDim2.new(1,-76,1,0),Position=UDim2.fromOffset(9,0),
        BackgroundTransparency=1,TextColor3=Color3.fromRGB(236,243,249),TextSize=12,
        Font=Enum.Font.GothamMedium,TextXAlignment=Enum.TextXAlignment.Left
    },button)
    local pill=make("TextLabel",{
        Text="OFF",Size=UDim2.fromOffset(51,26),Position=UDim2.new(1,-59,0,6),
        BackgroundColor3=Color3.fromRGB(101,46,53),TextColor3=Color3.new(1,1,1),
        TextSize=11,Font=Enum.Font.GothamBold,BorderSizePixel=0
    },button)
    make("UICorner",{CornerRadius=UDim.new(0,6)},pill)
    indicators[key]=pill
    button.MouseButton1Click:Connect(function()
        local wanted=not active[key]
        if key=="observe" and wanted then
            local ok,err=installTap()
            if not ok then
                stats.message=err or "Remote trace unavailable"
                status.Text=stats.message
                return
            end
        end
        active[key]=wanted
        pill.Text=wanted and "ON" or "OFF"
        pill.BackgroundColor3=wanted and Color3.fromRGB(35,121,84) or Color3.fromRGB(101,46,53)
        stats.message=textLabel .. (wanted and " enabled" or " disabled")
        status.Text=stats.message
    end)
end

toggleRow("cut","Auto Cutting Machine Prompt",67)
toggleRow("sell","Auto Sell Prompt",113)
toggleRow("tool","Auto Equipped Tool Activate",159)
-- Remote tracing intentionally disabled until game actions are verified.

local function makeButton(textLabel,x,width,callback)
    local b=make("TextButton",{
        Text=textLabel,Position=UDim2.fromOffset(x,337),Size=UDim2.fromOffset(width,35),
        BackgroundColor3=Color3.fromRGB(48,79,130),TextColor3=Color3.new(1,1,1),
        TextSize=12,Font=Enum.Font.GothamBold,BorderSizePixel=0
    },panel)
    make("UICorner",{CornerRadius=UDim.new(0,7)},b)
    b.MouseButton1Click:Connect(callback)
    return b
end

make("TextLabel",{
    Text="Train / Mine are not mapped yet; use prompts where available.",
    Size=UDim2.new(1,-24,0,34),Position=UDim2.fromOffset(12,382),
    TextWrapped=true,TextSize=10,Font=Enum.Font.Gotham,
    TextColor3=Color3.fromRGB(151,165,185),BackgroundTransparency=1
},panel)

local function classify(obj)
    if not obj:IsA("ProximityPrompt") then return nil end
    local n=string.lower(obj.Name)
    local text=string.lower(obj.ActionText .. " " .. obj.ObjectText)
    if n=="cutmachineprompt" or (text:find("cutting machine",1,true)
        and text:find("place rock",1,true)) then return "cut" end
    if n=="sellprompt" or text:find("sell rocks",1,true) then return "sell" end
    return nil
end
local function promptPosition(prompt)
    local p=prompt.Parent
    if p and p:IsA("Attachment") then p=p.Parent end
    if p and p:IsA("BasePart") then return p.Position end
    local part=prompt:FindFirstAncestorWhichIsA("BasePart")
    if part then return part.Position end
    return nil
end
local function scan()
    table.clear(prompts)
    local counts={cut=0,sell=0}
    for _,obj in ipairs(workspace:GetDescendants()) do
        local cat=classify(obj)
        if cat and promptPosition(obj) then
            prompts[#prompts+1]={obj=obj,cat=cat}
            counts[cat]+=1
        end
    end
    stats.scan+=1
    return counts
end
local function closestActive()
    local char=player.Character
    local root=char and char:FindFirstChild("HumanoidRootPart")
    if not root then return nil,nil end
    local nearest, best=nil,math.huge
    for _,it in ipairs(prompts) do
        local obj=it.obj
        if active[it.cat] and obj.Parent and obj.Enabled then
            local pos=promptPosition(obj)
            if pos then
                local dist=(root.Position-pos).Magnitude
                local limit=math.min(12, obj.MaxActivationDistance)
                if dist<=limit and dist<best and os.clock()-(lastUse[obj] or -100)>3.5 then
                    nearest,best=it,dist
                end
            end
        end
    end
    return nearest,best
end
local function nearestAny()
    local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if not root then return "No character" end
    local best,desc=math.huge,"none"
    for _,it in ipairs(prompts) do
        local obj=it.obj
        if obj.Parent then
            local pos=promptPosition(obj)
            if pos then
                local dist=(root.Position-pos).Magnitude
                if dist<best then
                    best=dist
                    desc=it.cat .. " " .. string.format("%.1f",dist) .. " studs (limit "
                        .. tostring(obj.MaxActivationDistance) .. ")"
                end
            end
        end
    end
    return desc
end
local function attemptPrompt(prompt)
    stats.attempts+=1
    lastUse[prompt]=os.clock()
    local ok,err
    if type(fireproximityprompt)=="function" then
        ok,err=pcall(fireproximityprompt,prompt)
    else
        ok,err=pcall(function()
            prompt:InputHoldBegin()
            task.wait(math.min(math.max(prompt.HoldDuration,0)+0.12,4))
            prompt:InputHoldEnd()
        end)
    end
    if ok then
        stats.dispatched+=1
        stats.message="Prompt input sent: " .. prompt.Name .. " (server result unverified)"
    else
        stats.failed+=1
        stats.lastError=tostring(err):sub(1,160)
        stats.message="Prompt failed: " .. stats.lastError
    end
end

local function report()
    local counts=scan()
    local lines={
        "CUT A ROCK DIAGNOSTIC v0.2",
        "PlaceId="..tostring(game.PlaceId),"GameId="..tostring(game.GameId),
        "Scans="..tostring(stats.scan),
        "PromptCount="..#prompts.." cut="..counts.cut.." sell="..counts.sell,
        "PromptAttempts="..stats.attempts.." DispatchedLocally="..stats.dispatched
            .." Failed="..stats.failed,
        "NOTE: DispatchedLocally does not prove server success.",
        "ToolActivateAttempts="..stats.toolAttempts,
        "ExecutorFireProximityPrompt="..tostring(type(fireproximityprompt)=="function"),
        "ExecutorRemoteHook="..tostring(tap.installed),
        "NearestPrompt="..nearestAny(),
        "LastError="..stats.lastError,
        "--- EQUIPPED TOOLS ---"
    }
    local char=player.Character
    if char then
        for _,obj in ipairs(char:GetChildren()) do
            if obj:IsA("Tool") then lines[#lines+1]=obj.Name end
        end
    end
    lines[#lines+1]="--- OBSERVED OUTGOING ACTION REMOTES (unique signatures) ---"
    for _,entry in ipairs(recent) do
        lines[#lines+1]=entry.signature.." [x"..entry.count.."]"
    end
    if #recent==0 then lines[#lines+1]="none; remote calls are not intercepted in this build" end
    lines[#lines+1]="--- VISIBLE GAME UI ---"
    local known={
        "SellMenu.MainFrame.SellAllButton", "CuttingMenu.MainFrame.Panel.CurrentCut.CollectTap",
        "CuttingMenu.MainFrame.Panel.KesimPaneli.KesButonu"
    }
    local pgui=player:FindFirstChild("PlayerGui")
    for _,path in ipairs(known) do
        local node=pgui
        for part in string.gmatch(path,"[^%.]+") do
            node=node and node:FindFirstChild(part)
        end
        if node and node:IsA("GuiObject") then
            lines[#lines+1]=path.." Visible="..tostring(node.Visible)
                .." AbsoluteSize="..tostring(node.AbsoluteSize)
        else
            lines[#lines+1]=path.." missing"
        end
    end
    return table.concat(lines,"\n")
end
makeButton("SCAN",12,128,function()
    local count=scan()
    stats.message=string.format("Detected: cut %d | sell %d. Nearest: %s",
        count.cut,count.sell,nearestAny())
    status.Text=stats.message
end)
makeButton("COPY REPORT",152,146,function()
    local result=report()
    print(result)
    if type(setclipboard)=="function" then
        local ok=pcall(setclipboard,result)
        stats.message=ok and "Report copied. Send it to ChatGPT."
            or "Clipboard failed: copy from executor console."
    else
        stats.message="Copy from executor console (no setclipboard)."
    end
    status.Text=stats.message
end)

local function stop()
    running=false
    tap.handler=nil
    for _,connection in ipairs(connections) do pcall(function() connection:Disconnect() end) end
    if gui.Parent then gui:Destroy() end
end
env.CutARockStarter={Stop=stop, Version="0.2", Report=report}
close.MouseButton1Click:Connect(stop)

-- One shared scheduler prevents simultaneous prompt activations.
task.spawn(function()
    while running do
        local item=closestActive()
        if item then attemptPrompt(item.obj) end
        if active.tool then
            local ch=player.Character
            local tool=ch and ch:FindFirstChildOfClass("Tool")
            if tool then
                stats.toolAttempts+=1
                pcall(function() tool:Activate() end)
            end
        end
        if running then
            status.Text=stats.message .. "\nAttempts="..stats.attempts
                .." | Local dispatch="..stats.dispatched.." | Failed="..stats.failed
        end
        task.wait(0.7)
    end
end)
task.spawn(function()
    while running do
        pcall(scan)
        task.wait(13)
    end
end)
print("[Cut a Rock] Diagnostic Hub v0.2 loaded. Use nearby prompts, SCAN and COPY REPORT.")

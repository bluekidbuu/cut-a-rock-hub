-- Cut a Rock | Passive Interaction Audit v0.4
-- PlaceId 113742027864370 | GameId 10766468833
-- READ-ONLY OBSERVER: no FireServer, InvokeServer, purchasing, teleporting or farming.
-- Records manual prompt/tool/GUI actions. Optionally observes selected outgoing remotes.
-- Designed for desktop and Android Roblox executors; features depend on executor.

if not game:IsLoaded() then game.Loaded:Wait() end
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local PromptService = game:GetService("ProximityPromptService")
local player = Players.LocalPlayer
if game.PlaceId ~= 113742027864370 and game.GameId ~= 10766468833 then
    warn("[Cut a Rock Audit] Wrong game; no audit started.")
    return
end

local env = (type(getgenv) == "function" and getgenv()) or _G
if type(env.CutARockAuditV04Stop) == "function" then
    pcall(env.CutARockAuditV04Stop)
end

local running = true
local currentStage = "IDLE"
local records, order = {}, {}
local total, distinct = 0, 0
local maxDistinct = 100
local conns = {}
local registered = setmetatable({}, {__mode="k"})
local traceState = "OFF"

local FOCUS_REMOTES = {
    OrsVurusu=true, KapiVurusu=true,
    DigBlockHealthEvent=true, BlockBrokenEvent=true, SyncBrokenBlocksEvent=true,
    SellEvent=true, OpenCuttingMachineMenu=true, PlaceStoneInMachineEvent=true,
    KesimBildirimi=true, InstantCutEvent=true, LevelUpMachineEvent=true,
    UpgradeEvent=true, PickaxeBuyEvent=true, PickaxeEquipEvent=true,
    TutorialIlerle=true, RestoreBlocksEvent=true,
}
local function shortName(v)
    v = tostring(v or "")
    v = v:gsub("[%c\r\n]", " ")
    return v:sub(1, 65)
end
local function fmtArg(v)
    local t = typeof(v)
    if t == "number" then
        if v ~= v then return "number:NaN" end
        return "number:" .. string.format("%.4g", v)
    end
    if t == "boolean" then return "boolean:" .. tostring(v) end
    if t == "string" then
        -- Avoid exposing arbitrary strings/tokens in diagnostics.
        return "string(len=" .. #v .. ")"
    end
    if t == "Instance" then
        return "Instance:" .. shortName(v.ClassName) .. ":" .. shortName(v.Name)
    end
    return t
end
local function log(kind, detail)
    if not running or currentStage == "IDLE" then return end
    local safeDetail = tostring(detail or ""):gsub("[%c\r\n]", " "):sub(1, 200)
    local key = currentStage .. " | " .. kind .. " | " .. safeDetail
    total += 1
    if records[key] then
        records[key] += 1
    else
        if #order >= maxDistinct then
            local oldest = table.remove(order, 1)
            records[oldest] = nil
        end
        order[#order+1] = key
        records[key] = 1
        distinct += 1
    end
end
local function logRemote(remote, method, ...)
    if not running or currentStage == "IDLE" then return end
    local argc = select("#", ...)
    local summary = {}
    for i=1, math.min(argc, 5) do
        summary[#summary+1] = fmtArg(select(i, ...))
    end
    if argc > 5 then summary[#summary+1] = "+" .. (argc-5) .. " args" end
    log("REMOTE", remote.Name .. ":" .. method .. "(" .. table.concat(summary, ", ") .. ")")
end

-- Store a reusable pass-through hook to avoid layering hooks on re-execute.
local tap = env.CutARockAuditV04Tap
if type(tap) ~= "table" then
    tap = {installed=false, receiver=nil}
    env.CutARockAuditV04Tap = tap
end
tap.receiver = nil
local function enableTrace()
    if tap.installed then
        tap.receiver = logRemote
        traceState = "ON"
        return true
    end
    if type(hookmetamethod) ~= "function" or type(getnamecallmethod) ~= "function" then
        traceState = "UNSUPPORTED"
        return false, "Executor has no hookmetamethod/getnamecallmethod"
    end
    local previous
    local function intercept(self, ...)
        local handler = tap.receiver
        if handler and typeof(self) == "Instance" and FOCUS_REMOTES[self.Name] then
            local ok, method = pcall(getnamecallmethod)
            if ok and (method == "FireServer" or method == "InvokeServer") then
                pcall(handler, self, method, ...)
            end
        end
        return previous(self, ...)
    end
    local closure = type(newcclosure) == "function" and newcclosure(intercept) or intercept
    local ok, old = pcall(hookmetamethod, game, "__namecall", closure)
    if not ok or type(old) ~= "function" then
        traceState = "FAILED"
        return false, "Remote hook rejected by executor"
    end
    previous = old
    tap.installed = true
    tap.receiver = logRemote
    traceState = "ON"
    return true
end
local function disableTrace()
    tap.receiver = nil -- Hook remains installed as an inert pass-through.
    traceState = "OFF"
end

-- Passive observation of manual input.
local function watchButton(b)
    if registered[b] or not b:IsA("GuiButton") then return end
    if b:FindFirstAncestor("CutARock_Audit_v04") then return end
    registered[b] = true
    conns[#conns+1] = b.Activated:Connect(function()
        local gui = b:FindFirstAncestorWhichIsA("ScreenGui")
        log("GUI", (gui and gui.Name or "Gui") .. "." .. b.Name)
    end)
end
local function watchTool(t)
    if registered[t] or not t:IsA("Tool") then return end
    registered[t] = true
    conns[#conns+1] = t.Activated:Connect(function()
        log("TOOL", t.Name .. ":Activated")
    end)
end
local function scanWatchers()
    local pg = player:FindFirstChild("PlayerGui")
    if pg then
        for _,o in ipairs(pg:GetDescendants()) do
            if o:IsA("GuiButton") then watchButton(o) end
        end
    end
    local bp = player:FindFirstChild("Backpack")
    if bp then
        for _,o in ipairs(bp:GetChildren()) do watchTool(o) end
    end
    if player.Character then
        for _,o in ipairs(player.Character:GetChildren()) do watchTool(o) end
    end
end
conns[#conns+1] = PromptService.PromptTriggered:Connect(function(prompt)
    log("PROMPT", prompt.Name .. " [" .. shortName(prompt.ActionText) .. "]")
end)
local pg = player:WaitForChild("PlayerGui")
conns[#conns+1] = pg.DescendantAdded:Connect(function(o)
    if o:IsA("GuiButton") then watchButton(o) end
end)
local bp = player:WaitForChild("Backpack")
conns[#conns+1] = bp.ChildAdded:Connect(watchTool)
local function onChar(char)
    conns[#conns+1] = char.ChildAdded:Connect(watchTool)
    for _,o in ipairs(char:GetChildren()) do watchTool(o) end
end
if player.Character then onChar(player.Character) end
conns[#conns+1] = player.CharacterAdded:Connect(onChar)
scanWatchers()

local gui = Instance.new("ScreenGui")
gui.Name = "CutARock_Audit_v04"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = pg
local function make(class, props, parent)
    local o = Instance.new(class)
    for k,v in pairs(props) do o[k] = v end
    o.Parent = parent
    return o
end
local panel = make("Frame",{
    Position=UDim2.fromOffset(14,100), Size=UDim2.fromOffset(315,385),
    BackgroundColor3=Color3.fromRGB(22,27,37), BorderSizePixel=0,
},gui)
make("UICorner",{CornerRadius=UDim.new(0,10)},panel)
make("UIStroke",{Color=Color3.fromRGB(79,96,124),Thickness=1},panel)
local title=make("TextLabel",{
    Text="CUT A ROCK  |  AUDIT v0.4",BackgroundTransparency=1,
    Size=UDim2.new(1,-54,0,39),Position=UDim2.fromOffset(11,1),
    Font=Enum.Font.GothamBold,TextSize=14,TextColor3=Color3.new(1,1,1),
    TextXAlignment=Enum.TextXAlignment.Left,
},panel)
local function btn(text,x,y,w,h)
    local b=make("TextButton",{
        Text=text,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),
        BackgroundColor3=Color3.fromRGB(50,70,99),BorderSizePixel=0,
        TextColor3=Color3.new(1,1,1),Font=Enum.Font.GothamMedium,TextSize=12,
    },panel)
    make("UICorner",{CornerRadius=UDim.new(0,7)},b)
    return b
end
local close=btn("X",278,7,28,28)
local hint=make("TextLabel",{
    Text="Pilih tahap, mainkan NORMAL, lalu COPY REPORT.",
    Position=UDim2.fromOffset(11,42),Size=UDim2.fromOffset(294,26),
    BackgroundTransparency=1,TextColor3=Color3.fromRGB(174,195,219),
    TextSize=11,TextWrapped=true,Font=Enum.Font.Gotham,
},panel)
local stageButtons={}
local stageNames={"TRAIN","MINE","CUT","COLLECT","SELL","UPGRADE"}
local function setStage(st)
    currentStage = st
    for name,b in pairs(stageButtons) do
        b.BackgroundColor3 = name == st and Color3.fromRGB(31,127,94)
            or Color3.fromRGB(50,70,99)
    end
end
for i,name in ipairs(stageNames) do
    local col=(i-1)%3
    local r=math.floor((i-1)/3)
    local b=btn(name,11+col*99,78+r*44,94,37)
    stageButtons[name]=b
    conns[#conns+1] = b.Activated:Connect(function() setStage(name) end)
end
local stopStage=btn("PAUSE / IDLE",11,171,142,36)
conns[#conns+1]=stopStage.Activated:Connect(function() setStage("IDLE") end)
local tracing=btn("REMOTE TRACE: OFF",158,171,146,36)
local status=make("TextLabel",{
    Position=UDim2.fromOffset(11,214),Size=UDim2.fromOffset(293,58),
    Text="Stage: IDLE | Logs: 0\nRemote: OFF | No game actions sent by audit",
    BackgroundTransparency=1,TextColor3=Color3.fromRGB(190,214,235),
    Font=Enum.Font.Gotham,TextSize=11,TextWrapped=true,
    TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,
},panel)
conns[#conns+1]=tracing.Activated:Connect(function()
    if traceState == "ON" then disableTrace() else
        local ok, why = enableTrace()
        if not ok then warn("[Cut a Rock Audit] " .. tostring(why)) end
    end
    tracing.Text = "REMOTE TRACE: " .. traceState
end)

local function buildReport()
    local lines={
        "CUT A ROCK PASSIVE AUDIT v0.4",
        "PlaceId=" .. tostring(game.PlaceId),
        "GameId=" .. tostring(game.GameId),
        "StageNow=" .. currentStage,
        "RemoteTrace=" .. traceState,
        "Events=" .. total,
        "DistinctEventPatterns=" .. #order,
        "NOTE: Manual events only. Remote capture may be incomplete.",
        "NOTE: Strings are redacted to length; no remote arguments were replayed.",
        "--- TIMELINE (chronological first occurrence, grouped counts) ---",
    }
    if #order == 0 then
        lines[#lines+1]="No events yet. Select a stage, interact manually, then copy."
    end
    for _,key in ipairs(order) do
        lines[#lines+1] = key .. "  x" .. tostring(records[key])
    end
    return table.concat(lines,"\n")
end
local copy=btn("COPY REPORT",11,281,192,41)
local clear=btn("CLEAR",210,281,94,41)
conns[#conns+1]=copy.Activated:Connect(function()
    local report=buildReport()
    local clip = type(setclipboard)=="function" and setclipboard
        or (type(toclipboard)=="function" and toclipboard) or nil
    if clip then
        local ok=pcall(clip,report)
        if ok then
            status.Text="Report copied to clipboard. Paste into ChatGPT."
            return
        end
    end
    print(report)
    status.Text="Clipboard unavailable. Report printed to executor console."
end)
conns[#conns+1]=clear.Activated:Connect(function()
    table.clear(records)
    table.clear(order)
    total,distinct=0,0
    status.Text="Logs cleared. Select a stage and continue."
end)
make("TextLabel",{
    Text="No automation. Don't collect passwords/tokens or share private data.",
    Position=UDim2.fromOffset(11,331),Size=UDim2.fromOffset(293,40),
    BackgroundTransparency=1,TextSize=10,TextWrapped=true,
    TextColor3=Color3.fromRGB(162,173,190),Font=Enum.Font.Gotham,
},panel)

-- Drag via title (touch + mouse)
local dragging=false
local origin, original
conns[#conns+1]=title.InputBegan:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseButton1 then
        dragging=true; origin=i.Position; original=panel.Position
        local c; c=i.Changed:Connect(function()
            if i.UserInputState==Enum.UserInputState.End then
                dragging=false
                c:Disconnect()
            end
        end)
    end
end)
conns[#conns+1]=UIS.InputChanged:Connect(function(i)
    if dragging and origin and (i.UserInputType==Enum.UserInputType.Touch
        or i.UserInputType==Enum.UserInputType.MouseMovement) then
        local d=i.Position-origin
        panel.Position=UDim2.new(original.X.Scale,original.X.Offset+d.X,
            original.Y.Scale,original.Y.Offset+d.Y)
    end
end)
local function stop()
    if not running then return end
    running=false
    disableTrace()
    for _,c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    gui:Destroy()
    env.CutARockAuditV04Stop=nil
end
env.CutARockAuditV04Stop=stop
conns[#conns+1]=close.Activated:Connect(stop)
task.spawn(function()
    while running do
        task.wait(0.5)
        if not running then break end
        status.Text="Stage: "..currentStage.." | Events: "..total
            .." | Patterns: "..#order.."\nRemote: "..traceState
            .." | Observe only; does not trigger game actions"
    end
end)
print("[Cut a Rock Audit v0.4] Select stage; optionally REMOTE TRACE; play normally; COPY REPORT.")

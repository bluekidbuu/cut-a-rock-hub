-- CUT A ROCK | COLLECT HANDLER MAP v1.0
-- Passive, bounded client-side handler attribution only.
-- Does not trigger prompts, call remotes, require modules, read/decompile source, or hook methods.
-- If executor lacks getconnections, this reports UNSUPPORTED rather than claiming no handlers.
-- Game 113742027864370 / universe 10766468833.

if not game:IsLoaded() then game.Loaded:Wait() end
if game.PlaceId ~= 113742027864370 and game.GameId ~= 10766468833 then
    warn('[CAR HandlerMap] Wrong game; disabled.')
    return
end

local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local PPS=game:GetService('ProximityPromptService')
local UIS=game:GetService('UserInputService')
local player=Players.LocalPlayer
local playerGui=player:WaitForChild('PlayerGui')
local playerScripts=player:FindFirstChild('PlayerScripts')
local env=type(getgenv)=='function' and getgenv() or _G
if type(env.CARCollectHandlerMapStop)=='function' then pcall(env.CARCollectHandlerMapStop) end

local MAX_PER_SIGNAL=24
local MAX_SCRIPTS=18
local MAX_EVENTS=12
local alive=true
local panel,gui,detail
local connections={}
local lines={}
local binding=nil
local nearestPrompt=nil
local snapDone=false
local scanStatus='Press SNAPSHOT HANDLERS near your Collect machine.'
local stamp=os.clock()

local targetModuleNames={
    PromptInputFix=true, StonePromptTarget=true, StonePromptStyle=true,
    StoneCollectFeedback=true, MachineNotifications=true,
    MachineRunningEffect=true, CuttingMenu=true, CollectedCoreCard=true,
    CutStonePhotoController=true, InstantCutController=true,
    PromptMenuAcKapa=true
}

local function valToText(v)
    local s=tostring(v or '?')
    s=s:gsub('[\r\n\t]', ' ')
    if #s>75 then s=s:sub(1,75)..'...' end
    return s
end
local function add(line)
    if #lines<220 then lines[#lines+1]=valToText(line) end
end
local function pathWithin(o)
    if typeof(o)~='Instance' then return 'UNKNOWN' end
    local roots={{playerScripts,'PlayerScripts'},{RS,'ReplicatedStorage'},{playerGui,'PlayerGui'}}
    for _,pair in ipairs(roots) do
        local root,label=pair[1],pair[2]
        if root and (o==root or o:IsDescendantOf(root)) then
            local pieces={}
            local node=o
            while node and node~=root and #pieces<9 do
                table.insert(pieces,1,node.Name)
                node=node.Parent
            end
            return label..'/'..table.concat(pieces,'/')
        end
    end
    if o:IsDescendantOf(workspace) then
        return 'Workspace/'..o.Name..' (path omitted)'
    end
    return o.ClassName..'/'..o.Name
end
local function ancestorMachine(o)
    while o and o~=workspace do
        if o:IsA('Model') and o.Name:match('^level%d+$') then return o end
        o=o.Parent
    end
end
local function promptPos(prompt)
    local p=prompt and prompt.Parent
    if p and p:IsA('Attachment') then return p.WorldPosition end
    if p and p:IsA('BasePart') then return p.Position end
    local base=p and p:FindFirstAncestorWhichIsA('BasePart')
    return base and base.Position or nil
end
local function dist(prompt)
    local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
    local pos=promptPos(prompt)
    if root and pos then return (root.Position-pos).Magnitude end
    return nil
end
local ownerKeys={'OwnerUserId','PlayerUserId','UserId','Owner','OwnerName','PlayerName'}
local function ownerHint(model)
    local node=model
    while node and node~=workspace do
        for _,key in ipairs(ownerKeys) do
            local ok,v=pcall(function() return node:GetAttribute(key) end)
            if ok and v~=nil then
                if tostring(v)==tostring(player.UserId) or tostring(v):lower()==player.Name:lower() then
                    return 'SELF'
                end
                return 'OTHER'
            end
        end
        node=node.Parent
    end
    return 'UNKNOWN'
end
local function bind()
    local bases=workspace:FindFirstChild('Models')
    bases=bases and bases:FindFirstChild('Bases')
    if not bases then
        binding=nil;nearestPrompt=nil
        scanStatus='Workspace.Models.Bases unavailable.'
        return
    end
    local best,nearest,nearestD=nil,nil,math.huge
    local total=0
    for _,obj in ipairs(bases:GetDescendants()) do
        if obj:IsA('ProximityPrompt') and obj.Name=='CutMachinePrompt' then
            total=total+1
            local model=ancestorMachine(obj)
            local d=dist(obj)
            if model and ownerHint(model)~='OTHER' and d and d<nearestD then
                best,nearest,nearestD=model,obj,d
            end
        end
    end
    binding,nearestPrompt=best,nearest
    if not nearest then
        scanStatus='No machine prompt found near player.'
    else
        scanStatus=string.format('Bound %s (%.1f studs, range %.1f) owner=%s',
            best.Name,nearestD,nearest.MaxActivationDistance,ownerHint(best))
    end
    return total
end
local function sourceFunction(fn)
    if type(fn)~='function' then return 'NO_LUA_FUNCTION' end
    local name='ANON'
    if type(debug)=='table' and type(debug.info)=='function' then
        local ok,n=pcall(debug.info,fn,'n')
        if ok and type(n)=='string' and n~='' then name=valToText(n) end
    end
    local origin='UNKNOWN'
    if type(getfenv)=='function' then
        local ok,funcEnv=pcall(getfenv,fn)
        if ok and type(funcEnv)=='table' then
            local sc=rawget(funcEnv,'script')
            if typeof(sc)=='Instance' then origin=pathWithin(sc) end
        end
    end
    return 'function='..name..' origin='..origin
end
local signalCount=0
local originCount=0
local unsupported=0
local function trySignal(label,signal)
    if signalCount>=MAX_EVENTS then return end
    signalCount=signalCount+1
    if type(getconnections)~='function' then
        unsupported=unsupported+1
        add('SIGNAL '..label..': UNSUPPORTED getconnections')
        return
    end
    local ok,list=pcall(getconnections,signal)
    if not ok or type(list)~='table' then
        unsupported=unsupported+1
        add('SIGNAL '..label..': UNAVAILABLE')
        return
    end
    add('SIGNAL '..label..' connections='..#list)
    for i=1,math.min(#list,MAX_PER_SIGNAL) do
        local c=list[i]
        local fn
        pcall(function() fn=c.Function end)
        local desc=sourceFunction(fn)
        if not desc:find('origin=UNKNOWN',1,true) then originCount=originCount+1 end
        local enabled='?'
        pcall(function() enabled=tostring(c.Enabled) end)
        add('  ['..i..'] enabled='..enabled..' '..desc)
    end
    if #list>MAX_PER_SIGNAL then add('  REMAINING='..(#list-MAX_PER_SIGNAL)..' omitted') end
end
local function enumModuleNames()
    add('--- TARGET MODULES (METADATA ONLY) ---')
    local roots={playerScripts,RS}
    local count=0
    for _,root in ipairs(roots) do
        if root then
            for _,o in ipairs(root:GetDescendants()) do
                if o:IsA('ModuleScript') and targetModuleNames[o.Name] then
                    count=count+1
                    if count<=MAX_SCRIPTS then
                        local attrs=o:GetAttributes()
                        local keys={}
                        for key in pairs(attrs) do keys[#keys+1]=key end
                        table.sort(keys)
                        local display={}
                        for i=1,math.min(#keys,5) do display[#display+1]=keys[i] end
                        add('MODULE '..pathWithin(o)..' attributes='..(#display>0 and table.concat(display,',') or 'none'))
                    end
                end
            end
        end
    end
    add('TARGET_MODULES_FOUND='..count)
end
local function snapshot()
    lines={}
    signalCount,originCount,unsupported=0,0,0
    local promptCount=bind()
    add('CUT A ROCK | COLLECT HANDLER MAP v1.0')
    add('PlaceId='..game.PlaceId)
    add('ReadOnly=true NoRequire=true NoDecompile=true NoRemoteCalls=true NoPromptCalls=true')
    add('NoHooks=true NoSourceRead=true NoScriptExecution=true')
    add('getconnectionsAvailable='..tostring(type(getconnections)=='function'))
    add('MachineBound='..tostring(binding~=nil)..' Machine='..(binding and binding.Name or 'NONE'))
    add('OwnerHint='..(binding and ownerHint(binding) or 'UNKNOWN'))
    add('MachinePromptsVisible='..tostring(promptCount or 0))
    if nearestPrompt then
        add(string.format('Distance=%.1f Range=%.1f Action=%s Hold=%.2f Enabled=%s',
            dist(nearestPrompt) or -1,nearestPrompt.MaxActivationDistance,
            nearestPrompt.ActionText,nearestPrompt.HoldDuration,tostring(nearestPrompt.Enabled)))
    end
    enumModuleNames()
    add('--- CLIENT SIGNAL LISTENERS ---')
    trySignal('PPS.PromptTriggered',PPS.PromptTriggered)
    trySignal('PPS.PromptShown',PPS.PromptShown)
    trySignal('PPS.PromptHidden',PPS.PromptHidden)
    if nearestPrompt then
        trySignal('MACHINE.Triggered',nearestPrompt.Triggered)
        trySignal('MACHINE.TriggerEnded',nearestPrompt.TriggerEnded)
        trySignal('MACHINE.ActionTextChanged',nearestPrompt:GetPropertyChangedSignal('ActionText'))
    else add('NO_MACHINE; skip machine signals') end
    local remoteNames={'KesimBildirimi','AuraBildirimi','AuraTopla','OpenCuttingMachineMenu','PlaceStoneInMachineEvent'}
    for _,name in ipairs(remoteNames) do
        local o=RS:FindFirstChild(name)
        if o and o:IsA('RemoteEvent') then
            trySignal('REMOTE.'..name..'.OnClientEvent',o.OnClientEvent)
        else add('REMOTE '..name..' MISSING') end
    end
    add('--- LIMITATIONS ---')
    add('SignalsInspected='..signalCount..' UnknownOrUnsupported='..unsupported)
    add('ConnectionsWithSourceHint='..originCount)
    add('Only client connections; server-side handlers are NOT visible here.')
    add('Empty connection counts do NOT imply no server processing.')
    add('Executor-specific getconnections/getfenv may omit or misattribute handlers.')
    add('Module names alone are NOT proof of their internal behavior.')
    snapDone=true
    scanStatus='Snapshot ready. Press COPY REPORT and paste it in ChatGPT.'
end
local function report()
    return table.concat(lines,'\n')
end
local function copyReport()
    if not snapDone then snapshot() end
    local value=report()
    print(value)
    local copy=type(setclipboard)=='function' and setclipboard
        or type(toclipboard)=='function' and toclipboard or nil
    if copy then
        local ok=pcall(copy,value)
        scanStatus=ok and 'Report copied.' or 'Clipboard unavailable: use executor console.'
    else scanStatus='Report printed; copy from executor console.' end
end
local function stop()
    alive=false
    for _,c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    if gui then gui:Destroy() end
    if env.CARCollectHandlerMapStop==stop then env.CARCollectHandlerMapStop=nil end
end
env.CARCollectHandlerMapStop=stop

local function create(class,props,parent)
    local obj=Instance.new(class)
    for k,v in pairs(props) do obj[k]=v end
    obj.Parent=parent
    return obj
end
gui=create('ScreenGui',{Name='CAR_Collect_HandlerMap_v1',ResetOnSpawn=false},playerGui)
panel=create('Frame',{
    Size=UDim2.fromOffset(325,282),Position=UDim2.new(0,10,0.15,0),
    BackgroundColor3=Color3.fromRGB(25,30,45),BorderSizePixel=0,Active=true
},gui)
create('UICorner',{CornerRadius=UDim.new(0,11)},panel)
create('UIStroke',{Color=Color3.fromRGB(80,110,145),Thickness=1},panel)
local header=create('TextLabel',{
    Text='CUT A ROCK | HANDLER MAP v1',Size=UDim2.fromOffset(282,36),
    Position=UDim2.fromOffset(9,5),BackgroundTransparency=1,
    Font=Enum.Font.GothamBold,TextSize=13,TextColor3=Color3.new(1,1,1),
    TextXAlignment=Enum.TextXAlignment.Left
},panel)
local label=create('TextLabel',{
    Text='',Size=UDim2.fromOffset(303,90),Position=UDim2.fromOffset(11,43),
    BackgroundTransparency=1,TextColor3=Color3.fromRGB(207,222,241),
    TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,
    TextSize=12,TextWrapped=true,Font=Enum.Font.Gotham
},panel)
local function button(textValue,y,height,fn)
    local b=create('TextButton',{
        Text=textValue,Size=UDim2.fromOffset(303,height),Position=UDim2.fromOffset(11,y),
        BackgroundColor3=Color3.fromRGB(44,78,116),TextColor3=Color3.new(1,1,1),
        BorderSizePixel=0,Font=Enum.Font.GothamMedium,TextSize=12
    },panel)
    create('UICorner',{CornerRadius=UDim.new(0,7)},b)
    connections[#connections+1]=b.Activated:Connect(fn)
end
local exit=create('TextButton',{
    Text='X',Size=UDim2.fromOffset(30,29),Position=UDim2.fromOffset(287,8),
    TextColor3=Color3.new(1,1,1),BackgroundColor3=Color3.fromRGB(102,53,63),
    BorderSizePixel=0,TextSize=12
},panel)
connections[#connections+1]=exit.Activated:Connect(stop)
button('1. SNAPSHOT HANDLERS',143,40,snapshot)
button('2. COPY REPORT',191,40,copyReport)
create('TextLabel',{
    Text='Passive only: no prompt activation, no remote requests, no code extraction.',
    Position=UDim2.fromOffset(11,239),Size=UDim2.fromOffset(303,29),
    BackgroundTransparency=1,TextColor3=Color3.fromRGB(169,187,209),
    TextWrapped=true,Font=Enum.Font.Gotham,TextSize=10
},panel)
local dragging=false
local initialInput,initialPanel
connections[#connections+1]=header.InputBegan:Connect(function(input)
    if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
        dragging=true;initialInput=input.Position;initialPanel=panel.Position
        local changed
        changed=input.Changed:Connect(function()
            if input.UserInputState==Enum.UserInputState.End then
                dragging=false;changed:Disconnect()
            end
        end)
    end
end)
connections[#connections+1]=UIS.InputChanged:Connect(function(input)
    if dragging and initialInput and (input.UserInputType==Enum.UserInputType.Touch
        or input.UserInputType==Enum.UserInputType.MouseMovement) then
        local delta=input.Position-initialInput
        panel.Position=UDim2.new(initialPanel.X.Scale,initialPanel.X.Offset+delta.X,
            initialPanel.Y.Scale,initialPanel.Y.Offset+delta.Y)
    end
end)
task.spawn(function()
    while alive do
        label.Text='Game: Cut a Rock\nSnapshot: '..(snapDone and 'DONE' or 'NOT RUN')..
            '\nConnection introspection: '..(type(getconnections)=='function' and 'SUPPORTED' or 'UNSUPPORTED')..
            '\n'..scanStatus
        task.wait(0.3)
    end
end)
print('[CAR HandlerMap] Loaded. Stand near your Collect machine, press SNAPSHOT HANDLERS, then COPY REPORT.')

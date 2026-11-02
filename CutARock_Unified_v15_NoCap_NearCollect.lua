-- CUT A ROCK | UNIFIED v1.5 | AUTO CUT UNLIMITED + TRAIN + SPEED + NEAR COLLECT
-- Standalone patch launcher: loads the user's existing Unified v1.4 from GitHub,
-- verifies unique source anchors, removes only the artificial 60-send limit,
-- and integrates an independent, near-only Auto Collect engine into one UI.
-- No teleport or speculative collect RemoteEvents. No modification to the GitHub file.

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
local run, compileErr = loadstring(source)
if type(run) ~= 'function' then
    warn('[CAR Unified v1.5] Patched script compile failed; no engine started: '..tostring(compileErr))
    return
end
local okRun, runErr=pcall(run)
if not okRun then warn('[CAR Unified v1.5] Runtime error: '..tostring(runErr)) end

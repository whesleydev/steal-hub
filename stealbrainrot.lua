-- Steal A Brainrot | hub auto | v5
-- executor: Delta, Xeno, Solara, Fluxus, Wave
-- sem webhook, sem HttpPost, sem leitura de arquivo. so a UI do Rayfield e a atualizacao vem de fora.

local BASE = "https://raw.githubusercontent.com/whesleydev/steal-hub/main"
local SCRIPT_VERSION = 10

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

-- ===== encerra a sessao anterior sem quebrar nada =====
local previous = _G.__stealHub
if previous then
    pcall(function()
        if previous.window and previous.window.Destroy then
            previous.window:Destroy()
        end
        if previous.bubble then
            previous.bubble:Destroy()
        end
        if previous.stopFly then
            previous.stopFly()
        end
        for _, conn in ipairs(previous.connections or {}) do
            pcall(function()
                conn:Disconnect()
            end)
        end
    end)
end

local session = {
    version = SCRIPT_VERSION,
    connections = {},
    prefs = previous and previous.prefs or nil,
}
_G.__stealHub = session

local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

local state = {
    autoCollect = false,
    autoSteal = false,
    esp = false,
    speed = 16,
    jump = 50,
    highlights = {},
    cooldown = 1.2,
    lastSteal = 0,
    home = nil,
    returnHome = true,
    attempts = {},
    dead = {},
    fly = false,
    flySpeed = 90,
    vy = 0,
    bv = nil,
    bg = nil,
    travelSpeed = 50,
    eggSpot = nil,
    useRoute = false,
    showStatus = true,
    useAir = true,
    flyHeight = 45,
    jumpFly = true,
}

-- ===== configuracao persistente =====
local CONFIG_PATH = "stealhub_config.json"

local function hasFileApi()
    return type(writefile) == "function" and type(readfile) == "function"
end

local function loadConfig()
    if not hasFileApi() then
        return nil
    end
    local ok, raw = pcall(function()
        if type(isfile) == "function" and not isfile(CONFIG_PATH) then
            return nil
        end
        return readfile(CONFIG_PATH)
    end)
    if not ok or type(raw) ~= "string" or #raw == 0 then
        return nil
    end
    local decoded, data = pcall(function()
        return HttpService:JSONDecode(raw)
    end)
    if not decoded or type(data) ~= "table" then
        return nil
    end
    return data
end

local saved = loadConfig()
if saved then
    state.speed = tonumber(saved.speed) or state.speed
    state.jump = tonumber(saved.jump) or state.jump
    state.flySpeed = tonumber(saved.flySpeed) or state.flySpeed
    state.travelSpeed = tonumber(saved.travelSpeed) or state.travelSpeed
    if type(saved.returnHome) == "boolean" then
        state.returnHome = saved.returnHome
    end
    if type(saved.esp) == "boolean" then
        state.esp = saved.esp
    end
    if type(saved.home) == "table" and saved.home.x then
        state.home = CFrame.new(saved.home.x, saved.home.y, saved.home.z)
    end
    if type(saved.eggSpot) == "table" and saved.eggSpot.x then
        state.eggSpot = CFrame.new(saved.eggSpot.x, saved.eggSpot.y, saved.eggSpot.z)
    end
    if type(saved.useRoute) == "boolean" then
        state.useRoute = saved.useRoute
    end
    if type(saved.useAir) == "boolean" then
        state.useAir = saved.useAir
    end
    state.flyHeight = tonumber(saved.flyHeight) or state.flyHeight
    if type(saved.jumpFly) == "boolean" then
        state.jumpFly = saved.jumpFly
    end
    state.bubblePos = saved.bubblePos
end

if session.prefs then
    state.speed = session.prefs.speed or state.speed
    state.jump = session.prefs.jump or state.jump
    state.flySpeed = session.prefs.flySpeed or state.flySpeed
    state.returnHome = session.prefs.returnHome
    state.home = session.prefs.home
    state.travelSpeed = session.prefs.travelSpeed or state.travelSpeed
end

local dirty = false

local function markDirty()
    dirty = true
end

local function saveConfig()
    if not hasFileApi() then
        return false
    end
    local data = {
        version = SCRIPT_VERSION,
        speed = state.speed,
        jump = state.jump,
        flySpeed = state.flySpeed,
        travelSpeed = state.travelSpeed,
        returnHome = state.returnHome,
        esp = state.esp,
        home = state.home and {x = state.home.X, y = state.home.Y, z = state.home.Z} or nil,
        eggSpot = state.eggSpot and {x = state.eggSpot.X, y = state.eggSpot.Y, z = state.eggSpot.Z} or nil,
        useRoute = state.useRoute,
        useAir = state.useAir,
        flyHeight = state.flyHeight,
        jumpFly = state.jumpFly,
        bubblePos = state.bubblePos,
    }
    local ok, encoded = pcall(function()
        return HttpService:JSONEncode(data)
    end)
    if not ok then
        return false
    end
    local wrote = pcall(function()
        writefile(CONFIG_PATH, encoded)
    end)
    return wrote
end

session.saveConfig = saveConfig

local ACTIONS = {"collect", "steal", "take", "grab", "pegar", "roubar", "egg", "ovo"}
local BLOCKED = {"pass", "passe", "shop", "loja", "buy", "comprar", "premium", "robux",
                 "gamepass", "vip", "donate", "doar", "portal", "teleport", "upgrade"}
local RARE = {"secret", "mythic", "legendary", "divine", "god", "rainbow", "galaxy"}

local function character()
    return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
end

local function rootPart()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function textOf(prompt)
    local action = string.lower(prompt.ActionText or "")
    local object = string.lower(prompt.ObjectText or "")
    local parent = string.lower(prompt.Parent and prompt.Parent.Name or "")
    return action .. " " .. object .. " " .. parent
end

local function blocked(prompt)
    local text = textOf(prompt)
    for _, key in ipairs(BLOCKED) do
        if string.find(text, key, 1, true) then
            return true
        end
    end
    return false
end

local function matches(prompt)
    if blocked(prompt) then
        return false
    end
    local text = textOf(prompt)
    for _, key in ipairs(ACTIONS) do
        if string.find(text, key, 1, true) then
            return true
        end
    end
    return false
end

local function fire(prompt)
    if type(fireproximityprompt) ~= "function" then
        return
    end
    pcall(fireproximityprompt, prompt)
end

local function scan()
    local found = {}
    for _, item in ipairs(Workspace:GetDescendants()) do
        if item:IsA("ProximityPrompt") and item.Enabled and matches(item)
                and not state.dead[item] then
            found[#found + 1] = item
        end
    end
    return found
end

local function anchorOf(prompt)
    local parent = prompt.Parent
    if not parent then
        return nil
    end
    if parent:IsA("BasePart") then
        return parent
    end
    return parent:FindFirstChild("HumanoidRootPart") or parent:FindFirstChildWhichIsA("BasePart")
end

local function noteAttempt(prompt)
    state.attempts[prompt] = (state.attempts[prompt] or 0) + 1
    if state.attempts[prompt] >= 3 then
        state.dead[prompt] = true
        state.attempts[prompt] = nil
    end
end

local function clearEsp()
    for model, highlight in pairs(state.highlights) do
        pcall(function()
            highlight:Destroy()
        end)
        state.highlights[model] = nil
    end
end

local function colorFor(name)
    local lower = string.lower(name)
    for _, key in ipairs(RARE) do
        if string.find(lower, key, 1, true) then
            return Color3.fromRGB(255, 196, 0)
        end
    end
    return Color3.fromRGB(70, 160, 255)
end

local function drawEsp()
    if not state.esp then
        clearEsp()
        return
    end
    for _, prompt in ipairs(scan()) do
        local model = prompt.Parent
        if model and not state.highlights[model] then
            local highlight = Instance.new("Highlight")
            highlight.FillColor = colorFor(model.Name)
            highlight.FillTransparency = 0.55
            highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
            highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            highlight.Adornee = model
            highlight.Parent = model
            state.highlights[model] = highlight
        end
    end
end

-- ===== anti-fling: o jogo arremessa pra baixo quando abusa da velocidade =====
local flingGuard = true

local function antiFling()
    if not flingGuard then
        return
    end
    local root = rootPart()
    if not root then
        return
    end
    local velocity = root.AssemblyLinearVelocity
    if velocity.Y < -220 then
        root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        if state.home then
            root.CFrame = state.home
        end
    end
end

-- ===== deslocamento por velocidade, nao por teleporte =====
local statusLabel = nil

local function status(text)
    if statusLabel then
        statusLabel.Text = text
    end
end

local function travelTo(target, speed, height)
    local root = rootPart()
    if not root or not target then
        return false
    end
    height = height or 0
    local goal = target + Vector3.new(0, height, 0)
    local body = Instance.new("BodyVelocity")
    body.Name = "hubTravel"
    body.MaxForce = Vector3.new(1e5, 1e5, 1e5)
    body.Parent = root
    local deadline = os.clock() + 10
    local reached = false
    local descending = false
    local lastDistance = math.huge
    local lastCheck = os.clock()
    local bumped = 0

    while os.clock() < deadline do
        if _G.__stealHub ~= session then
            break
        end
        local current = rootPart()
        if not current then
            break
        end
        local delta = goal - current.Position

        if os.clock() - lastCheck > 0.9 and not descending then
            local distance = delta.Magnitude
            if distance > lastDistance - 6 and bumped < 4 then
                bumped = bumped + 1
                height = height + 25
                goal = target + Vector3.new(0, height, 0)
                delta = goal - current.Position
            end
            lastDistance = distance
            lastCheck = os.clock()
        end

        if descending then
            local drop = target.Y - current.Position.Y
            body.Velocity = Vector3.new(0, math.clamp(drop * 4, -70, 70), 0)
            if math.abs(drop) < 4 then
                reached = true
                break
            end
        elseif delta.Magnitude < 8 then
            if height > 1 then
                descending = true
            else
                reached = true
                break
            end
        else
            local flat = Vector3.new(delta.X, 0, delta.Z)
            local direction = flat.Magnitude > 0.1 and flat.Unit or Vector3.zero
            local lift = 0
            if delta.Y > 3 then
                lift = math.min(speed, 70)
            elseif delta.Y < -3 then
                lift = -math.min(speed, 70)
            end
            body.Velocity = direction * math.min(speed, 130) + Vector3.new(0, lift, 0)
        end
        RunService.Heartbeat:Wait()
    end

    pcall(function()
        body:Destroy()
    end)
    return reached
end

local function fireNearby(radius)
    local root = rootPart()
    if not root then
        return 0
    end
    local fired = 0
    for _, prompt in ipairs(scan()) do
        local anchor = anchorOf(prompt)
        if anchor and (anchor.Position - root.Position).Magnitude <= radius then
            fire(prompt)
            fired = fired + 1
        end
    end
    return fired
end

local function sweep(seconds)
    local root = rootPart()
    if not root then
        return
    end
    local body = Instance.new("BodyVelocity")
    body.Name = "hubSweep"
    body.MaxForce = Vector3.new(1e5, 1e5, 1e5)
    body.Parent = root
    local start = os.clock()
    while (os.clock() - start) < seconds and _G.__stealHub == session do
        local angle = (os.clock() - start) * 9
        body.Velocity = Vector3.new(math.cos(angle) * 12, 0, math.sin(angle) * 12)
        RunService.Heartbeat:Wait()
    end
    pcall(function()
        body:Destroy()
    end)
end

local function runRoute()
    if not state.eggSpot or not state.home then
        return false
    end
    local ceiling = state.useAir and state.flyHeight or 0
    status(string.format("rota: indo pro ovo (altura %d)", ceiling))
    if not travelTo(state.eggSpot.Position, state.travelSpeed, ceiling) then
        status("rota: nao chegou no ovo")
        return false
    end
    sweep(1.2)
    fireNearby(14)
    task.wait(0.3)
    status("rota: voltando pra base")
    travelTo(state.home.Position, state.travelSpeed, ceiling)
    sweep(1.0)
    fireNearby(18)
    status("rota: ciclo completo")
    return true
end

local function nearestPrompt()
    local root = rootPart()
    if not root then
        return nil, math.huge
    end
    local best, bestDistance = nil, math.huge
    for _, prompt in ipairs(scan()) do
        local anchor = anchorOf(prompt)
        if anchor then
            local distance = (anchor.Position - root.Position).Magnitude
            if distance < bestDistance then
                best, bestDistance = prompt, distance
            end
        end
    end
    return best, bestDistance
end

local function steal(prompt)
    if not prompt then
        return
    end
    local anchor = anchorOf(prompt)
    if not anchor then
        return
    end
    if not travelTo(anchor.Position + Vector3.new(0, 4, 0), state.travelSpeed) then
        noteAttempt(prompt)
        return
    end
    task.wait(0.12)
    fire(prompt)
    noteAttempt(prompt)
    if state.returnHome and state.home then
        task.wait(0.2)
        travelTo(state.home.Position + Vector3.new(0, 4, 0), state.travelSpeed)
        task.wait(0.1)
        fireNearby(18)
    end
end

-- ===== voo =====
local function stopFly()
    state.fly = false
    state.vy = 0
    if state.bv then
        pcall(function()
            state.bv:Destroy()
        end)
        state.bv = nil
    end
    if state.bg then
        pcall(function()
            state.bg:Destroy()
        end)
        state.bg = nil
    end
    local root = rootPart()
    if root then
        local leftover = root:FindFirstChild("hubFly")
        if leftover then
            leftover:Destroy()
        end
    end
end

session.stopFly = stopFly

local function startFly()
    local root = rootPart()
    if not root then
        return
    end
    stopFly()
    state.fly = true
    state.bv = Instance.new("BodyVelocity")
    state.bv.Name = "hubFly"
    state.bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
    state.bv.Velocity = Vector3.zero
    state.bv.Parent = root
    state.bg = Instance.new("BodyGyro")
    state.bg.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
    state.bg.P = 12000
    state.bg.Parent = root

    task.spawn(function()
        while state.fly and _G.__stealHub == session do
            RunService.RenderStepped:Wait()
            local current = LocalPlayer.Character
            local hrp = current and current:FindFirstChild("HumanoidRootPart")
            local humanoid = current and current:FindFirstChildOfClass("Humanoid")
            if not hrp or not humanoid or not state.bv then
                break
            end
            local direction = humanoid.MoveDirection
            state.bv.Velocity = direction * state.flySpeed
                    + Vector3.new(0, state.vy * state.flySpeed, 0)
            if workspace.CurrentCamera and state.bg then
                state.bg.CFrame = workspace.CurrentCamera.CFrame
            end
        end
    end)
end

-- ===== voo segurando o pulo =====
local jumpHold = 0
local pressedUntil = 0
local jumpFlyActive = false
local jumpFlyBody = nil

session.connections[#session.connections + 1] = UserInputService.JumpRequest:Connect(function()
    pressedUntil = os.clock() + 0.35
end)

local function stopJumpFly()
    jumpFlyActive = false
    if jumpFlyBody then
        pcall(function()
            jumpFlyBody:Destroy()
        end)
        jumpFlyBody = nil
    end
end

local function updateJumpFly(dt)
    if not state.jumpFly or state.fly then
        if jumpFlyActive then
            stopJumpFly()
        end
        return
    end
    local char = LocalPlayer.Character
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root then
        return
    end

    local held = UserInputService:IsKeyDown(Enum.KeyCode.Space)
            or humanoid.Jump
            or os.clock() < pressedUntil

    if held then
        jumpHold = math.min(jumpHold + dt, 4)
    else
        jumpHold = math.max(jumpHold - dt * 2.5, 0)
    end

    if jumpHold > 0.45 then
        if not jumpFlyActive then
            jumpFlyActive = true
            jumpFlyBody = Instance.new("BodyVelocity")
            jumpFlyBody.Name = "hubJumpFly"
            jumpFlyBody.MaxForce = Vector3.new(1e5, 1e5, 1e5)
            jumpFlyBody.Parent = root
        end
        if jumpFlyBody then
            local move = humanoid.MoveDirection
            jumpFlyBody.Velocity = Vector3.new(move.X * state.flySpeed,
                    state.flySpeed * 0.8, move.Z * state.flySpeed)
        end
    elseif jumpFlyActive then
        stopJumpFly()
    end
end

local function applyMovement()
    local char = LocalPlayer.Character
    if not char then
        return
    end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.WalkSpeed = state.speed
        humanoid.UseJumpPower = true
        humanoid.JumpPower = state.jump
    end
end

-- ===== bolinha flutuante =====
local function uiRoot()
    if type(gethui) == "function" then
        local ok, value = pcall(gethui)
        if ok and value then
            return value
        end
    end
    return game:GetService("CoreGui")
end

local function findWindow()
    local places = {uiRoot(), LocalPlayer:FindFirstChild("PlayerGui")}
    for _, place in ipairs(places) do
        if place then
            for _, child in ipairs(place:GetChildren()) do
                if child:IsA("ScreenGui") and string.find(string.lower(child.Name), "rayfield") then
                    local main = child:FindFirstChild("Main")
                    if main then
                        return child, main
                    end
                    for _, item in ipairs(child:GetDescendants()) do
                        if item:IsA("Frame") and item.Name == "Main" then
                            return child, item
                        end
                    end
                    return child, nil
                end
            end
        end
    end
    return nil, nil
end

local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    or LocalPlayer:WaitForChild("PlayerGui", 10)

local function makeGui(name, order)
    local gui = Instance.new("ScreenGui")
    gui.Name = name
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = order
    local placed = pcall(function()
        gui.Parent = playerGui
    end)
    if not placed or not gui.Parent then
        pcall(function()
            gui.Parent = game:GetService("CoreGui")
        end)
    end
    if not gui.Parent then
        pcall(function()
            gui.Parent = uiRoot()
        end)
    end
    return gui
end

local bubbleGui = makeGui("HubBubble", 999999)
bubbleGui.Enabled = true

local bubble = Instance.new("TextButton")
bubble.Name = "bubble"
bubble.Size = UDim2.fromOffset(58, 58)
if state.bubblePos and state.bubblePos.x then
    bubble.Position = UDim2.new(0, state.bubblePos.x, 0, state.bubblePos.y)
else
    bubble.Position = UDim2.new(0, 18, 0.45, 0)
end
bubble.BackgroundColor3 = Color3.fromRGB(14, 17, 23)
bubble.BorderSizePixel = 0
bubble.AutoButtonColor = false
bubble.Text = "S"
bubble.Font = Enum.Font.GothamBold
bubble.TextSize = 24
bubble.TextColor3 = Color3.fromRGB(60, 150, 255)
bubble.Parent = bubbleGui

local bubbleCorner = Instance.new("UICorner")
bubbleCorner.CornerRadius = UDim.new(1, 0)
bubbleCorner.Parent = bubble

local bubbleStroke = Instance.new("UIStroke")
bubbleStroke.Color = Color3.fromRGB(45, 120, 230)
bubbleStroke.Thickness = 2
bubbleStroke.Transparency = 0.15
bubbleStroke.Parent = bubble

local statusGui = makeGui("HubStatus", 999998)
statusGui.Enabled = state.showStatus

local statusText = Instance.new("TextLabel")
statusText.Size = UDim2.fromOffset(300, 30)
statusText.Position = UDim2.new(0.5, -150, 1, -70)
statusText.BackgroundColor3 = Color3.fromRGB(14, 17, 23)
statusText.BackgroundTransparency = 0.2
statusText.BorderSizePixel = 0
statusText.Text = "pronto"
statusText.TextColor3 = Color3.fromRGB(150, 190, 255)
statusText.Font = Enum.Font.Gotham
statusText.TextSize = 13
statusText.Parent = statusGui

local statusCorner = Instance.new("UICorner")
statusCorner.CornerRadius = UDim.new(0, 10)
statusCorner.Parent = statusText

statusLabel = statusText
session.statusGui = statusGui

session.bubble = bubbleGui

local function showWindow(show)
    local gui, main = findWindow()
    if gui then
        if main then
            main.Visible = show
        else
            gui.Enabled = show
        end
    end
    local size = show and 42 or 58
    TweenService:Create(bubble, TweenInfo.new(0.2, Enum.EasingStyle.Back),
            {Size = UDim2.fromOffset(size, size)}):Play()
    bubble.TextTransparency = show and 0.45 or 0
    bubble.BackgroundTransparency = show and 0.45 or 0
    return gui ~= nil
end

local dragging = false
local dragStart = nil
local startPosition = nil
local moved = false

bubble.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        moved = false
        dragStart = input.Position
        startPosition = bubble.Position
        TweenService:Create(bubble, TweenInfo.new(0.12), {Size = UDim2.fromOffset(64, 64)}):Play()
    end
end)

session.connections[#session.connections + 1] = UserInputService.InputChanged:Connect(function(input)
    if not dragging then
        return
    end
    if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
        local delta = input.Position - dragStart
        if delta.Magnitude > 6 then
            moved = true
        end
        bubble.Position = UDim2.new(startPosition.X.Scale, startPosition.X.Offset + delta.X,
                startPosition.Y.Scale, startPosition.Y.Offset + delta.Y)
        state.bubblePos = {x = bubble.Position.X.Offset, y = bubble.Position.Y.Offset}
        markDirty()
    end
end)

session.connections[#session.connections + 1] = UserInputService.InputEnded:Connect(function(input)
    if not dragging then
        return
    end
    if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
        TweenService:Create(bubble, TweenInfo.new(0.15), {Size = UDim2.fromOffset(58, 58)}):Play()
        if not moved then
            showWindow(true)
        end
    end
end)

-- ===== atualizacao =====
local function fetchRemoteVersion()
    local ok, text = pcall(function()
        return game:HttpGet(BASE .. "/version.txt?t=" .. tostring(os.time()))
    end)
    if not ok then
        return nil
    end
    return tonumber(string.match(tostring(text), "%d+"))
end

local function applyUpdate()
    local ok, source = pcall(function()
        return game:HttpGet(BASE .. "/stealbrainrot.lua?v=" .. tostring(os.time()))
    end)
    if not ok or type(source) ~= "string" or #source < 1500 then
        return false
    end
    local chunk = loadstring(source)
    if not chunk then
        return false
    end
    session.prefs = {
        speed = state.speed,
        jump = state.jump,
        flySpeed = state.flySpeed,
        returnHome = state.returnHome,
        home = state.home,
        travelSpeed = state.travelSpeed,
    }
    local ran = pcall(chunk)
    return ran
end

-- ===== interface =====
local Window = Rayfield:CreateWindow({
    Name = "Steal A Brainrot",
    LoadingTitle = "carregando hub",
    ConfigurationSaving = {Enabled = false},
})

session.window = Window

local speedSlider, jumpSlider, travelSlider, heightSlider
local airToggle, routeToggle, jumpFlyToggle, espToggle

local RECOMMENDED = {
    speed = 18,
    jump = 50,
    flySpeed = 80,
    travelSpeed = 85,
    flyHeight = 60,
    useAir = true,
    returnHome = true,
    jumpFly = true,
    esp = true,
    cooldown = 1.0,
}

local function applyRecommended()
    state.speed = RECOMMENDED.speed
    state.jump = RECOMMENDED.jump
    state.flySpeed = RECOMMENDED.flySpeed
    state.travelSpeed = RECOMMENDED.travelSpeed
    state.flyHeight = RECOMMENDED.flyHeight
    state.useAir = RECOMMENDED.useAir
    state.returnHome = RECOMMENDED.returnHome
    state.jumpFly = RECOMMENDED.jumpFly
    state.cooldown = RECOMMENDED.cooldown

    pcall(function()
        speedSlider:Set(RECOMMENDED.speed)
        jumpSlider:Set(RECOMMENDED.jump)
        travelSlider:Set(RECOMMENDED.travelSpeed)
        heightSlider:Set(RECOMMENDED.flyHeight)
        airToggle:Set(RECOMMENDED.useAir)
        routeToggle:Set(true)
        jumpFlyToggle:Set(RECOMMENDED.jumpFly)
        espToggle:Set(RECOMMENDED.esp)
    end)

    state.esp = RECOMMENDED.esp
    applyMovement()
    drawEsp()
    markDirty()
    Rayfield:Notify({Title = "Perfil recomendado",
                     Content = "Aereo a 60 studs, 85 de velocidade, chao normal.", Duration = 6})
end

local MainTab = Window:CreateTab("Principal", 4483362458)

MainTab:CreateButton({
    Name = "Usar perfil recomendado",
    Callback = function()
        applyRecommended()
    end,
})

MainTab:CreateToggle({
    Name = "Auto coletar",
    CurrentValue = false,
    Flag = "autocollect",
    Callback = function(value)
        state.autoCollect = value
    end,
})

MainTab:CreateToggle({
    Name = "Auto roubar",
    CurrentValue = false,
    Flag = "autosteal",
    Callback = function(value)
        state.autoSteal = value
        if value and not state.home then
            local root = rootPart()
            if root then
                state.home = root.CFrame
            end
        end
    end,
})

MainTab:CreateButton({
    Name = "Minimizar em bolinha",
    Callback = function()
        if not showWindow(false) then
            Rayfield:Notify({Title = "Bolinha",
                             Content = "Nao achei a janela pra esconder.", Duration = 4})
        end
    end,
})

airToggle = MainTab:CreateToggle({
    Name = "Voar durante a rota",
    CurrentValue = state.useAir,
    Flag = "useair",
    Callback = function(value)
        state.useAir = value
        markDirty()
    end,
})

heightSlider = MainTab:CreateSlider({
    Name = "Altura do voo na rota",
    Range = {0, 120},
    Increment = 5,
    Suffix = "studs",
    CurrentValue = state.flyHeight,
    Flag = "flyheight",
    Callback = function(value)
        state.flyHeight = value
        markDirty()
    end,
})

MainTab:CreateButton({
    Name = "Marcar ovo aqui",
    Callback = function()
        local root = rootPart()
        if root then
            state.eggSpot = root.CFrame
            markDirty()
            Rayfield:Notify({Title = "Rota", Content = "Ovo marcado. Agora marque a base.", Duration = 4})
        end
    end,
})

routeToggle = MainTab:CreateToggle({
    Name = "Usar rota gravada",
    CurrentValue = state.useRoute,
    Flag = "useroute",
    Callback = function(value)
        state.useRoute = value
        markDirty()
    end,
})

MainTab:CreateToggle({
    Name = "Mostrar status na tela",
    CurrentValue = state.showStatus,
    Flag = "showstatus",
    Callback = function(value)
        state.showStatus = value
        statusGui.Enabled = value
        markDirty()
    end,
})

MainTab:CreateButton({
    Name = "Definir base aqui",
    Callback = function()
        local root = rootPart()
        if root then
            state.home = root.CFrame
            markDirty()
        end
    end,
})

MainTab:CreateToggle({
    Name = "Voltar pra base depois de pegar",
    CurrentValue = state.returnHome,
    Flag = "returnhome",
    Callback = function(value)
        state.returnHome = value
        markDirty()
    end,
})

MainTab:CreateButton({
    Name = "Roubar o mais próximo",
    Callback = function()
        local prompt = nearestPrompt()
        if prompt then
            steal(prompt)
        end
    end,
})

speedSlider = MainTab:CreateSlider({
    Name = "Velocidade",
    Range = {16, 120},
    Increment = 2,
    Suffix = "studs/s",
    CurrentValue = state.speed,
    Flag = "speed",
    Callback = function(value)
        state.speed = value
        applyMovement()
        markDirty()
    end,
})

jumpSlider = MainTab:CreateSlider({
    Name = "Pulo",
    Range = {50, 120},
    Increment = 5,
    Suffix = "power",
    CurrentValue = state.jump,
    Flag = "jump",
    Callback = function(value)
        state.jump = value
        applyMovement()
        markDirty()
    end,
})

travelSlider = MainTab:CreateSlider({
    Name = "Velocidade do roubo",
    Range = {20, 120},
    Increment = 5,
    Suffix = "studs/s",
    CurrentValue = state.travelSpeed,
    Flag = "travel",
    Callback = function(value)
        state.travelSpeed = value
        markDirty()
    end,
})

MainTab:CreateButton({
    Name = "Salvar configurações",
    Callback = function()
        if saveConfig() then
            Rayfield:Notify({Title = "Config", Content = "Salvo.", Duration = 3})
        else
            Rayfield:Notify({Title = "Config", Content = "Executor sem permissão de arquivo.", Duration = 4})
        end
    end,
})

MainTab:CreateButton({
    Name = "Restaurar padrão",
    Callback = function()
        if type(delfile) == "function" then
            pcall(function()
                delfile(CONFIG_PATH)
            end)
        end
        state.speed = 16
        state.jump = 50
        state.flySpeed = 90
        state.travelSpeed = 50
        state.returnHome = true
        state.esp = false
        state.home = nil
        clearEsp()
        applyMovement()
        Rayfield:Notify({Title = "Config", Content = "Padrão restaurado. Reabra o hub.", Duration = 4})
    end,
})

MainTab:CreateButton({
    Name = "Verificar atualização",
    Callback = function()
        local remote = fetchRemoteVersion()
        if not remote then
            Rayfield:Notify({Title = "Atualização", Content = "Não consegui checar agora.", Duration = 4})
            return
        end
        if remote <= SCRIPT_VERSION then
            Rayfield:Notify({Title = "Atualização",
                             Content = "Você já está na v" .. SCRIPT_VERSION .. ".", Duration = 4})
            return
        end
        Rayfield:Notify({Title = "Atualização",
                         Content = "Baixando v" .. remote .. "…", Duration = 3})
        task.delay(1, function()
            if applyUpdate() then
                Rayfield:Notify({Title = "Atualizado",
                                 Content = "v" .. remote .. " no ar.", Duration = 5})
            else
                Rayfield:Notify({Title = "Falhou",
                                 Content = "Tenta de novo em instantes.", Duration = 5})
            end
        end)
    end,
})

local FlyTab = Window:CreateTab("Voo", 4483362458)

jumpFlyToggle = FlyTab:CreateToggle({
    Name = "Voo: segurar pulo",
    CurrentValue = state.jumpFly,
    Flag = "jumpfly",
    Callback = function(value)
        state.jumpFly = value
        if not value then
            stopJumpFly()
        end
        markDirty()
    end,
})

FlyTab:CreateToggle({
    Name = "Voo infinito (toggle)",
    CurrentValue = false,
    Flag = "fly",
    Callback = function(value)
        if value then
            startFly()
        else
            stopFly()
        end
    end,
})

FlyTab:CreateSlider({
    Name = "Velocidade do voo",
    Range = {20, 300},
    Increment = 10,
    Suffix = "studs/s",
    CurrentValue = state.flySpeed,
    Flag = "flyspeed",
    Callback = function(value)
        state.flySpeed = value
        markDirty()
    end,
})

FlyTab:CreateToggle({
    Name = "Subir",
    CurrentValue = false,
    Flag = "flyup",
    Callback = function(value)
        state.vy = value and 1 or 0
    end,
})

FlyTab:CreateToggle({
    Name = "Descer",
    CurrentValue = false,
    Flag = "flydown",
    Callback = function(value)
        state.vy = value and -1 or 0
    end,
})

FlyTab:CreateButton({
    Name = "Pousar (desligar voo)",
    Callback = function()
        stopFly()
    end,
})

local VisualTab = Window:CreateTab("Visual", 4483362458)

espToggle = VisualTab:CreateToggle({
    Name = "ESP nos brainrots",
    CurrentValue = state.esp,
    Flag = "esp",
    Callback = function(value)
        state.esp = value
        drawEsp()
        markDirty()
    end,
})

VisualTab:CreateButton({
    Name = "Forcar bolinha visivel",
    Callback = function()
        pcall(function()
            bubbleGui.Parent = playerGui
        end)
        bubbleGui.Enabled = true
        bubble.Visible = true
        bubble.Size = UDim2.fromOffset(58, 58)
        bubble.TextTransparency = 0
        bubble.BackgroundTransparency = 0
        Rayfield:Notify({Title = "Bolinha",
                         Content = "Reposicionada. Se nao aparecer, o executor bloqueia ScreenGui.",
                         Duration = 5})
    end,
})

VisualTab:CreateButton({
    Name = "Limpar bloqueios (ovos travados)",
    Callback = function()
        state.dead = {}
        state.attempts = {}
    end,
})

VisualTab:CreateButton({
    Name = "Limpar ESP",
    Callback = function()
        state.esp = false
        clearEsp()
    end,
})

VisualTab:CreateButton({
    Name = "Listar prompts da área",
    Callback = function()
        local count = 0
        for _, item in ipairs(Workspace:GetDescendants()) do
            if item:IsA("ProximityPrompt") and item.Enabled then
                count = count + 1
                local tag = matches(item) and "USA" or (blocked(item) and "BLOQUEADO" or "-")
                print(string.format("[%d] %s | %s | %s", count,
                        item.ActionText, item.ObjectText, tag))
                print("      " .. item:GetFullName())
            end
        end
        print("total: " .. count)
    end,
})

-- ===== loops =====
LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    applyMovement()
    if state.esp then
        drawEsp()
    end
end)

task.spawn(function()
    while _G.__stealHub == session do
        task.wait(0.4)
        antiFling()
        if state.autoCollect then
            for _, prompt in ipairs(scan()) do
                fire(prompt)
            end
        end
        if state.esp then
            drawEsp()
        end
        applyMovement()
    end
end)

task.spawn(function()
    while _G.__stealHub == session do
        task.wait(0.25)
        if state.autoSteal and (os.clock() - state.lastSteal) > state.cooldown then
            state.lastSteal = os.clock()
            if state.useRoute and state.eggSpot and state.home then
                runRoute()
            else
                local prompt, distance = nearestPrompt()
                if prompt and distance < 400 then
                    status(string.format("alvo: %s | %d studs", prompt.ActionText, math.floor(distance)))
                    steal(prompt)
                else
                    status("sem alvo por perto")
                end
            end
        end
    end
end)

session.connections[#session.connections + 1] = RunService.Heartbeat:Connect(function(dt)
    updateJumpFly(dt)
end)

task.spawn(function()
    while _G.__stealHub == session do
        task.wait(1)
        if dirty then
            dirty = false
            saveConfig()
        end
    end
end)

task.spawn(function()
    task.wait(2)
    if saved then
        Rayfield:Notify({Title = "Config", Content = "Suas configurações voltaram.", Duration = 4})
    end
end)

task.spawn(function()
    task.wait(3)
    local remote = fetchRemoteVersion()
    if remote and remote > SCRIPT_VERSION then
        Rayfield:Notify({
            Title = "Atualização disponível",
            Content = "v" .. remote .. " pronta. Aba Principal > Verificar atualização.",
            Duration = 8,
        })
    end
end)

print("hub carregado v" .. SCRIPT_VERSION)

-- Blade Ball 完全版自动化脚本
-- 作者：Celestia开发者
-- 更新日期：2024年

-- [[ 第一部分：服务初始化 ]]
local function safe_cloneref(serviceName)
    local service = game:GetService(serviceName)
    if cloneref then
        return cloneref(service)
    end
    return service
end

local ContextActionService = safe_cloneref('ContextActionService')
local UserInputService = safe_cloneref('UserInputService')
local RunService = safe_cloneref('RunService')
local ReplicatedStorage = safe_cloneref('ReplicatedStorage')
local Players = safe_cloneref('Players')
local Debris = safe_cloneref('Debris')
local VirtualInputManager = game:GetService("VirtualInputManager")
local TweenService = safe_cloneref('TweenService')
local Lighting = safe_cloneref('Lighting')
local CoreGui = safe_cloneref('CoreGui')
local TextService = safe_cloneref('TextService')
local HttpService = safe_cloneref('HttpService')
local ContentProvider = safe_cloneref('ContentProvider')
local GuiService = safe_cloneref('GuiService')

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- [[ 第二部分：全局变量和配置 ]]
local getgenv = getgenv or function() return _G end
local _G = _G or getfenv()

-- 确保全局设置表存在
if not _G.CelestiaSettings then
    _G.CelestiaSettings = {
        AutoParry = {
            Enabled = false,
            Accuracy = 100,
            RandomAccuracy = false,
            Keypress = false,
            InfinityDetection = true,
            PhantomDetection = true
        },
        SpamParry = {
            Enabled = false,
            Threshold = 2.5,
            Keypress = false
        },
        Triggerbot = {
            Enabled = false,
            InfinityDetection = true,
            Keypress = false
        },
        LobbyAP = {
            Enabled = false,
            Accuracy = 100,
            RandomAccuracy = false,
            Keypress = false
        },
        Player = {
            Strafe = { Enabled = false, Speed = 36 },
            Spinbot = { Enabled = false, Speed = 1 },
            Fly = { Enabled = false, Speed = 50 },
            Cosmetics = { Enabled = false },
            FOV = { Enabled = false, Value = 70 },
            HitSounds = { Enabled = false, Sound = "Medal", Volume = 6 }
        },
        Misc = {
            CooldownProtection = false,
            AutoAbility = false,
            SlashOfFuryDetection = true
        }
    }
end

local Settings = _G.CelestiaSettings

-- 核心变量
local Parry_Key = nil
local HashOne, HashTwo, HashThree
local PropertyChangeOrder = {}
local Parries = 0
local Selected_Parry_Type = "Camera"
local Speed_Divisor_Multiplier = 1.1
local LobbyAP_Speed_Divisor_Multiplier = 1.1
local ParryThreshold = 2.5
local firstParryFired = false
local firstParryType = 'F_Key'
local Connections_Manager = {}
local Phantom = false
local Infinity = false
local Parried = false
local Training_Parried = false
local TriggerbotParried = false

-- [[ 第三部分：LPH 模拟函数 ]]
if not LPH_OBFUSCATED then
    _G.LPH_JIT = function(f) return f end
    _G.LPH_JIT_MAX = function(f) return f end
    _G.LPH_NO_VIRTUALIZE = function(f) return f end
end

-- [[ 第四部分：哈希值提取 ]]
local function ExtractHashes()
    for _, value in next, getgc() do
        if type(value) == "function" and islclosure(value) then
            local source = debug.info(value, "s")
            local line = debug.info(value, "l")
            
            if source and source:find("SwordsController") and line == 276 then
                HashOne = getconstant(value, 62)
                HashTwo = getconstant(value, 64)
                HashThree = getconstant(value, 65)
                
                if HashOne and HashTwo and HashThree then
                    break
                end
            end
        end
    end
end

-- 执行哈希提取
ExtractHashes()

-- [[ 第五部分：远程事件设置 ]]
local function SetupRemotes()
    for _, obj in next, game:GetDescendants() do
        if obj:IsA("RemoteEvent") and string.find(obj.Name, "\n") then
            obj.Changed:Once(function()
                table.insert(PropertyChangeOrder, obj)
            end)
        end
    end
    
    -- 等待所有远程事件被发现
    repeat
        task.wait()
    until #PropertyChangeOrder == 3
    
    return PropertyChangeOrder[1], PropertyChangeOrder[2], PropertyChangeOrder[3]
end

local ShouldPlayerJump, MainRemote, GetOpponentPosition = SetupRemotes()

-- [[ 第六部分：格挡键检测 ]]
local function FindParryKey()
    local hotbar = Player.PlayerGui:FindFirstChild("Hotbar")
    if not hotbar then return nil end
    
    local blockButton = hotbar:FindFirstChild("Block")
    if not blockButton then return nil end
    
    for _, connection in pairs(getconnections(blockButton.Activated)) do
        if connection and connection.Function and not iscclosure(connection.Function) then
            for _, upvalue in pairs(getupvalues(connection.Function)) do
                if type(upvalue) == "function" then
                    local innerFunction = getupvalue(upvalue, 2)
                    if innerFunction then
                        Parry_Key = getupvalue(innerFunction, 17)
                        return Parry_Key
                    end
                end
            end
        end
    end
    return nil
end

Parry_Key = FindParryKey()

-- [[ 第七部分：自动格挡核心模块 ]]
local Auto_Parry = {}

-- 基础功能
function Auto_Parry.Get_Ball()
    local ballsFolder = workspace:FindFirstChild("Balls")
    if not ballsFolder then return nil end
    
    for _, ball in pairs(ballsFolder:GetChildren()) do
        if ball:GetAttribute('realBall') then
            return ball
        end
    end
    return nil
end

function Auto_Parry.Get_Balls()
    local balls = {}
    local ballsFolder = workspace:FindFirstChild("Balls")
    if not ballsFolder then return balls end
    
    for _, ball in pairs(ballsFolder:GetChildren()) do
        if ball:GetAttribute('realBall') then
            table.insert(balls, ball)
        end
    end
    return balls
end

function Auto_Parry.Lobby_Balls()
    local trainingBalls = workspace:FindFirstChild("TrainingBalls")
    if not trainingBalls then return nil end
    
    for _, ball in pairs(trainingBalls:GetChildren()) do
        if ball:GetAttribute("realBall") then
            return ball
        end
    end
    return nil
end

function Auto_Parry.Closest_Player()
    local aliveFolder = workspace:FindFirstChild("Alive")
    if not aliveFolder then return nil end
    
    local maxDistance = math.huge
    local foundEntity = nil
    
    for _, entity in pairs(aliveFolder:GetChildren()) do
        if entity ~= Player.Character and entity.PrimaryPart then
            local distance = Player:DistanceFromCharacter(entity.PrimaryPart.Position)
            if distance < maxDistance then
                maxDistance = distance
                foundEntity = entity
            end
        end
    end
    return foundEntity
end

-- 曲线检测
function Auto_Parry.Is_Curved()
    local ball = Auto_Parry.Get_Ball()
    if not ball then return false end
    
    local zoomies = ball:FindFirstChild('zoomies')
    if not zoomies then return false end
    
    local velocity = zoomies.VectorVelocity
    local ballDirection = velocity.Unit
    local playerDirection = (Player.Character.PrimaryPart.Position - ball.Position).Unit
    local dot = playerDirection:Dot(ballDirection)
    
    local ping = game:GetService('Stats').Network.ServerStatsItem['Data Ping']:GetValue()
    local distance = (Player.Character.PrimaryPart.Position - ball.Position).Magnitude
    local speed = velocity.Magnitude
    
    local reachTime = distance / speed - (ping / 1000)
    local dotThreshold = 0.5 - (ping / 1000)
    
    return dot < dotThreshold
end

-- 格挡数据生成
function Auto_Parry.Parry_Data(parryType)
    local camera = workspace.CurrentCamera
    local events = {}
    local mouseLocation = {camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2}
    
    -- 获取屏幕上的玩家位置
    local aliveFolder = workspace:FindFirstChild("Alive")
    if aliveFolder then
        for _, playerChar in pairs(aliveFolder:GetChildren()) do
            if playerChar ~= Player.Character and playerChar.PrimaryPart then
                local screenPos = camera:WorldToScreenPoint(playerChar.PrimaryPart.Position)
                events[tostring(playerChar)] = screenPos
            end
        end
    end
    
    if parryType == "Camera" then
        return {0, camera.CFrame, events, mouseLocation}
    elseif parryType == "Backwards" then
        local backwardDirection = camera.CFrame.LookVector * -10000
        backwardDirection = Vector3.new(backwardDirection.X, 0, backwardDirection.Z)
        return {0, CFrame.new(camera.CFrame.Position, camera.CFrame.Position + backwardDirection), events, mouseLocation}
    elseif parryType == "Straight" then
        local closest = Auto_Parry.Closest_Player()
        if closest and closest.PrimaryPart then
            return {0, CFrame.new(Player.Character.PrimaryPart.Position, closest.PrimaryPart.Position), events, mouseLocation}
        end
    elseif parryType == "Random" then
        return {0, CFrame.new(camera.CFrame.Position, Vector3.new(math.random(-4000, 4000), math.random(-4000, 4000), math.random(-4000, 4000))), events, mouseLocation}
    end
    
    return {0, camera.CFrame, events, mouseLocation}
end

-- 格挡执行
function Auto_Parry.Parry(parryType)
    if not Parry_Key or not HashOne or not HashTwo or not HashThree then
        warn("格挡系统未完全初始化")
        return
    end
    
    local parryData = Auto_Parry.Parry_Data(parryType)
    
    -- 发送格挡请求
    ShouldPlayerJump:FireServer(HashOne, Parry_Key, unpack(parryData))
    MainRemote:FireServer(HashTwo, Parry_Key, unpack(parryData))
    GetOpponentPosition:FireServer(HashThree, Parry_Key, unpack(parryData))
    
    Parries = Parries + 1
    
    -- 重置格挡计数
    task.delay(0.5, function()
        if Parries > 0 then
            Parries = Parries - 1
        end
    end)
end

-- [[ 第八部分：特殊检测系统 ]]
-- Phantom V2 检测
local function SetupPhantomDetection()
    local runtime = workspace:FindFirstChild("Runtime")
    if not runtime then return end
    
    runtime.ChildAdded:Connect(function(obj)
        if Settings.AutoParry.PhantomDetection and (obj.Name == "maxTransmission" or obj.Name == "transmissionpart") then
            local weld = obj:FindFirstChildWhichIsA("WeldConstraint")
            if weld and Player.Character and weld.Part1 == Player.Character.HumanoidRootPart then
                Phantom = true
                
                -- 自动移动玩家
                local ball = Auto_Parry.Get_Ball()
                if ball then
                    ContextActionService:BindAction('BlockPlayerMovement', function()
                        return Enum.ContextActionResult.Sink
                    end, false, Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D)
                    
                    Player.Character.Humanoid.WalkSpeed = 36
                    Player.Character.Humanoid:MoveTo(ball.Position)
                end
            end
        end
    end)
end

-- Slash of Fury 检测
local function SetupSlashOfFuryDetection()
    local balls = workspace:FindFirstChild("Balls")
    if not balls then return end
    
    balls.ChildAdded:Connect(function(ball)
        ball.ChildAdded:Connect(function(child)
            if Settings.Misc.SlashOfFuryDetection and child.Name == 'ComboCounter' then
                local label = child:FindFirstChildOfClass('TextLabel')
                if label then
                    repeat
                        local slashCount = tonumber(label.Text)
                        if slashCount and slashCount < 32 then
                            Auto_Parry.Parry(Selected_Parry_Type)
                        end
                        task.wait()
                    until not label.Parent
                end
            end
        end)
    end)
end

-- 无限球检测
local function SetupInfinityDetection()
    local infinityRemote = ReplicatedStorage:FindFirstChild("Remotes")
    if infinityRemote then
        infinityRemote = infinityRemote:FindFirstChild("InfinityBall")
        if infinityRemote then
            infinityRemote.OnClientEvent:Connect(function(_, isInfinity)
                Infinity = isInfinity
            end)
        end
    end
end

-- [[ 第九部分：UI 界面 (Airflow) ]]
local function CreateUI()
    -- 加载 Airflow UI 库
    local success, Airflow = pcall(function()
        return loadstring(game:HttpGetAsync("https://raw.githubusercontent.com/4lpaca-pin/Airflow/refs/heads/main/src/source.luau"))()
    end)
    
    if not success then
        warn("无法加载 Airflow UI 库")
        return nil
    end
    
    local Window = Airflow:Init({
        Name = "Celestia - Blade Ball",
        Keybind = "LeftControl",
        Logo = "rbxassetid://94220348785476",
    })
    
    -- 创建标签页
    local BlatantTab = Window:DrawTab({ Name = "自动格挡", Icon = "sword" })
    local PlayerTab = Window:DrawTab({ Name = "玩家", Icon = "user" })
    local MiscTab = Window:DrawTab({ Name = "杂项", Icon = "settings" })
    
    -- [[ 自动格挡设置 ]]
    local AutoParrySection = BlatantTab:AddSection({
        Name = "自动格挡",
        Position = "left",
    })
    
    AutoParrySection:AddToggle({
        Name = "启用自动格挡",
        Callback = function(value)
            Settings.AutoParry.Enabled = value
            
            if value then
                -- 创建自动格挡循环
                if Connections_Manager['AutoParry'] then
                    Connections_Manager['AutoParry']:Disconnect()
                end
                
                Connections_Manager['AutoParry'] = RunService.PreSimulation:Connect(function()
                    if not Settings.AutoParry.Enabled then return end
                    
                    local ball = Auto_Parry.Get_Ball()
                    if not ball then return end
                    
                    local zoomies = ball:FindFirstChild('zoomies')
                    if not zoomies then return end
                    
                    local target = ball:GetAttribute('target')
                    if target ~= tostring(Player) then return end
                    
                    -- 计算距离和速度
                    local distance = (Player.Character.PrimaryPart.Position - ball.Position).Magnitude
                    local velocity = zoomies.VectorVelocity
                    local speed = velocity.Magnitude
                    
                    -- 计算延迟
                    local ping = game:GetService('Stats').Network.ServerStatsItem['Data Ping']:GetValue() / 10
                    local pingThreshold = math.clamp(ping / 10, 5, 17)
                    
                    -- 计算格挡精度
                    local cappedSpeedDiff = math.min(math.max(speed - 9.5, 0), 650)
                    local speedDivisorBase = 2.4 + cappedSpeedDiff * 0.002
                    
                    local effectiveMultiplier = Speed_Divisor_Multiplier
                    if Settings.AutoParry.RandomAccuracy then
                        effectiveMultiplier = 0.7 + (math.random(1, 100) - 1) * (0.35 / 99)
                    end
                    
                    local speedDivisor = speedDivisorBase * effectiveMultiplier
                    local parryAccuracy = pingThreshold + math.max(speed / speedDivisor, 9.5)
                    
                    -- 检查是否曲线球
                    local isCurved = Auto_Parry.Is_Curved()
                    
                    -- 无限球检测
                    if Settings.AutoParry.InfinityDetection and Infinity then
                        return
                    end
                    
                    -- 执行格挡
                    if distance <= parryAccuracy and not isCurved then
                        if Settings.AutoParry.Keypress then
                            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F, false, game)
                            task.wait(0.05)
                            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, game)
                        else
                            Auto_Parry.Parry(Selected_Parry_Type)
                        end
                    end
                end)
            else
                if Connections_Manager['AutoParry'] then
                    Connections_Manager['AutoParry']:Disconnect()
                    Connections_Manager['AutoParry'] = nil
                end
            end
        end
    })
    
    AutoParrySection:AddSlider({
        Name = "格挡精度",
        Min = 1,
        Max = 100,
        Default = 100,
        Callback = function(value)
            Settings.AutoParry.Accuracy = value
            Speed_Divisor_Multiplier = 0.7 + (value - 1) * (0.35 / 99)
        end
    })
    
    AutoParrySection:AddDropdown({
        Name = "格挡方向",
        Values = {"Camera", "Backwards", "Straight", "Random", "High", "Left", "Right", "RandomTarget"},
        Multi = false,
        Default = "Camera",
        Callback = function(value)
            Selected_Parry_Type = value
        end
    })
    
    AutoParrySection:AddToggle({
        Name = "随机精度",
        Callback = function(value)
            Settings.AutoParry.RandomAccuracy = value
        end
    })
    
    AutoParrySection:AddToggle({
        Name = "按键模拟",
        Callback = function(value)
            Settings.AutoParry.Keypress = value
        end
    })
    
    AutoParrySection:AddToggle({
        Name = "无限球检测",
        Callback = function(value)
            Settings.AutoParry.InfinityDetection = value
        end
    })
    
    AutoParrySection:AddToggle({
        Name = "Phantom检测",
        Callback = function(value)
            Settings.AutoParry.PhantomDetection = value
        end
    })
    
    -- [[ 连发格挡 ]]
    local SpamParrySection = BlatantTab:AddSection({
        Name = "连发格挡",
        Position = "right",
    })
    
    SpamParrySection:AddToggle({
        Name = "启用连发格挡",
        Callback = function(value)
            Settings.SpamParry.Enabled = value
            
            if value then
                if Connections_Manager['SpamParry'] then
                    Connections_Manager['SpamParry']:Disconnect()
                end
                
                Connections_Manager['SpamParry'] = RunService.PreSimulation:Connect(function()
                    if not Settings.SpamParry.Enabled then return end
                    
                    local ball = Auto_Parry.Get_Ball()
                    if not ball then return end
                    
                    local target = ball:GetAttribute('target')
                    if target ~= tostring(Player) then return end
                    
                    local distance = (Player.Character.PrimaryPart.Position - ball.Position).Magnitude
                    
                    if distance <= 30 and Parries > ParryThreshold then
                        if Settings.SpamParry.Keypress then
                            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F, false, game)
                            task.wait(0.05)
                            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, game)
                        else
                            Auto_Parry.Parry(Selected_Parry_Type)
                        end
                    end
                end)
            else
                if Connections_Manager['SpamParry'] then
                    Connections_Manager['SpamParry']:Disconnect()
                    Connections_Manager['SpamParry'] = nil
                end
            end
        end
    })
    
    SpamParrySection:AddSlider({
        Name = "格挡阈值",
        Min = 1,
        Max = 3,
        Default = 2.5,
        Callback = function(value)
            Settings.SpamParry.Threshold = value
            ParryThreshold = value
        end
    })
    
    SpamParrySection:AddToggle({
        Name = "按键模拟",
        Callback = function(value)
            Settings.SpamParry.Keypress = value
        end
    })
    
    -- [[ 触发式格挡 ]]
    local TriggerbotSection = BlatantTab:AddSection({
        Name = "触发格挡",
        Position = "left",
    })
    
    TriggerbotSection:AddToggle({
        Name = "启用触发格挡",
        Callback = function(value)
            Settings.Triggerbot.Enabled = value
            
            if value then
                if Connections_Manager['Triggerbot'] then
                    Connections_Manager['Triggerbot']:Disconnect()
                end
                
                Connections_Manager['Triggerbot'] = RunService.PreSimulation:Connect(function()
                    if not Settings.Triggerbot.Enabled then return end
                    
                    local ball = Auto_Parry.Get_Ball()
                    if not ball then return end
                    
                    local target = ball:GetAttribute('target')
                    if target ~= tostring(Player) then return end
                    
                    if Settings.Triggerbot.InfinityDetection and Infinity then
                        return
                    end
                    
                    if Settings.Triggerbot.Keypress then
                        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F, false, game)
                        task.wait(0.05)
                        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, game)
                    else
                        Auto_Parry.Parry(Selected_Parry_Type)
                    end
                end)
            else
                if Connections_Manager['Triggerbot'] then
                    Connections_Manager['Triggerbot']:Disconnect()
                    Connections_Manager['Triggerbot'] = nil
                end
            end
        end
    })
    
    TriggerbotSection:AddToggle({
        Name = "无限球检测",
        Callback = function(value)
            Settings.Triggerbot.InfinityDetection = value
        end
    })
    
    TriggerbotSection:AddToggle({
        Name = "按键模拟",
        Callback = function(value)
            Settings.Triggerbot.Keypress = value
        end
    })
    
    -- [[ 大厅自动格挡 ]]
    local LobbyAPSection = BlatantTab:AddSection({
        Name = "大厅自动格挡",
        Position = "right",
    })
    
    LobbyAPSection:AddToggle({
        Name = "启用大厅自动格挡",
        Callback = function(value)
            Settings.LobbyAP.Enabled = value
            
            if value then
                if Connections_Manager['LobbyAP'] then
                    Connections_Manager['LobbyAP']:Disconnect()
                end
                
                Connections_Manager['LobbyAP'] = RunService.Heartbeat:Connect(function()
                    if not Settings.LobbyAP.Enabled then return end
                    
                    local ball = Auto_Parry.Lobby_Balls()
                    if not ball then return end
                    
                    local target = ball:GetAttribute('target')
                    if target ~= tostring(Player) then return end
                    
                    local distance = Player:DistanceFromCharacter(ball.Position)
                    local zoomies = ball:FindFirstChild('zoomies')
                    if not zoomies then return end
                    
                    local speed = zoomies.VectorVelocity.Magnitude
                    local ping = game:GetService('Stats').Network.ServerStatsItem['Data Ping']:GetValue() / 10
                    
                    local cappedSpeedDiff = math.min(math.max(speed - 9.5, 0), 650)
                    local speedDivisorBase = 2.4 + cappedSpeedDiff * 0.002
                    
                    local effectiveMultiplier = LobbyAP_Speed_Divisor_Multiplier
                    if Settings.LobbyAP.RandomAccuracy then
                        effectiveMultiplier = 0.7 + (math.random(1, 100) - 1) * (0.35 / 99)
                    end
                    
                    local speedDivisor = speedDivisorBase * effectiveMultiplier
                    local parryAccuracy = ping + math.max(speed / speedDivisor, 9.5)
                    
                    if distance <= parryAccuracy then
                        if Settings.LobbyAP.Keypress then
                            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F, false, game)
                            task.wait(0.05)
                            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, game)
                        else
                            Auto_Parry.Parry(Selected_Parry_Type)
                        end
                    end
                end)
            else
                if Connections_Manager['LobbyAP'] then
                    Connections_Manager['LobbyAP']:Disconnect()
                    Connections_Manager['LobbyAP'] = nil
                end
            end
        end
    })
    
    LobbyAPSection:AddSlider({
        Name = "格挡精度",
        Min = 1,
        Max = 100,
        Default = 100,
        Callback = function(value)
            Settings.LobbyAP.Accuracy = value
            LobbyAP_Speed_Divisor_Multiplier = 0.7 + (value - 1) * (0.35 / 99)
        end
    })
    
    LobbyAPSection:AddToggle({
        Name = "随机精度",
        Callback = function(value)
            Settings.LobbyAP.RandomAccuracy = value
        end
    })
    
    LobbyAPSection:AddToggle({
        Name = "按键模拟",
        Callback = function(value)
            Settings.LobbyAP.Keypress = value
        end
    })
    
    -- [[ 玩家设置 ]]
    -- 移动速度调整
    local StrafeSection = PlayerTab:AddSection({
        Name = "移动设置",
        Position = "left",
    })
    
    StrafeSection:AddToggle({
        Name = "启用移动调整",
        Callback = function(value)
            Settings.Player.Strafe.Enabled = value
            
            if value then
                if Connections_Manager['Strafe'] then
                    Connections_Manager['Strafe']:Disconnect()
                end
                
                Connections_Manager['Strafe'] = RunService.PreSimulation:Connect(function()
                    local character = Player.Character
                    if character and character:FindFirstChild("Humanoid") then
                        character.Humanoid.WalkSpeed = Settings.Player.Strafe.Speed
                    end
                end)
            else
                if Connections_Manager['Strafe'] then
                    Connections_Manager['Strafe']:Disconnect()
                    Connections_Manager['Strafe'] = nil
                end
                
                local character = Player.Character
                if character and character:FindFirstChild("Humanoid") then
                    character.Humanoid.WalkSpeed = 36
                end
            end
        end
    })
    
    StrafeSection:AddSlider({
        Name = "移动速度",
        Min = 36,
        Max = 200,
        Default = 36,
        Callback = function(value)
            Settings.Player.Strafe.Speed = value
        end
    })
    
    -- 旋转机器人
    local SpinbotSection = PlayerTab:AddSection({
        Name = "旋转设置",
        Position = "right",
    })
    
    SpinbotSection:AddToggle({
        Name = "启用旋转",
        Callback = function(value)
            Settings.Player.Spinbot.Enabled = value
            
            if value then
                if Connections_Manager['Spinbot'] then
                    Connections_Manager['Spinbot']:Disconnect()
                end
                
                Connections_Manager['Spinbot'] = RunService.Heartbeat:Connect(function()
                    local character = Player.Character
                    if character and character:FindFirstChild("HumanoidRootPart") then
                        character.HumanoidRootPart.CFrame = character.HumanoidRootPart.CFrame * CFrame.Angles(0, math.rad(Settings.Player.Spinbot.Speed), 0)
                    end
                end)
            else
                if Connections_Manager['Spinbot'] then
                    Connections_Manager['Spinbot']:Disconnect()
                    Connections_Manager['Spinbot'] = nil
                end
            end
        end
    })
    
    SpinbotSection:AddSlider({
        Name = "旋转速度",
        Min = 1,
        Max = 100,
        Default = 1,
        Callback = function(value)
            Settings.Player.Spinbot.Speed = value
        end
    })
    
    -- 飞行模式
    local FlySection = PlayerTab:AddSection({
        Name = "飞行设置",
        Position = "left",
    })
    
    FlySection:AddToggle({
        Name = "启用飞行",
        Callback = function(value)
            Settings.Player.Fly.Enabled = value
            
            if value then
                -- 飞行模式实现
                local character = Player.Character
                if not character then return end
                
                local humanoid = character:FindFirstChild("Humanoid")
                local rootPart = character:FindFirstChild("HumanoidRootPart")
                if not humanoid or not rootPart then return end
                
                -- 创建飞行控制器
                local bodyGyro = Instance.new("BodyGyro")
                bodyGyro.P = 90000
                bodyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
                bodyGyro.Parent = rootPart
                
                local bodyVelocity = Instance.new("BodyVelocity")
                bodyVelocity.Velocity = Vector3.new(0, 0, 0)
                bodyVelocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)
                bodyVelocity.Parent = rootPart
                
                humanoid.PlatformStand = true
                
                Connections_Manager['Fly'] = RunService.RenderStepped:Connect(function()
                    if not Settings.Player.Fly.Enabled then return end
                    
                    local camera = workspace.CurrentCamera
                    local moveDir = Vector3.new(0, 0, 0)
                    
                    if UserInputService:IsKeyDown(Enum.KeyCode.W) then
                        moveDir = moveDir + camera.CFrame.LookVector
                    end
                    if UserInputService:IsKeyDown(Enum.KeyCode.S) then
                        moveDir = moveDir - camera.CFrame.LookVector
                    end
                    if UserInputService:IsKeyDown(Enum.KeyCode.A) then
                        moveDir = moveDir - camera.CFrame.RightVector
                    end
                    if UserInputService:IsKeyDown(Enum.KeyCode.D) then
                        moveDir = moveDir + camera.CFrame.RightVector
                    end
                    if UserInputService:IsKeyDown(Enum.KeyCode.E) then
                        moveDir = moveDir + Vector3.new(0, 1, 0)
                    end
                    if UserInputService:IsKeyDown(Enum.KeyCode.Q) then
                        moveDir = moveDir - Vector3.new(0, 1, 0)
                    end
                    
                    if moveDir.Magnitude > 0 then
                        moveDir = moveDir.Unit
                    end
                    
                    bodyVelocity.Velocity = moveDir * Settings.Player.Fly.Speed
                    bodyGyro.CFrame = camera.CFrame
                end)
            else
                if Connections_Manager['Fly'] then
                    Connections_Manager['Fly']:Disconnect()
                    Connections_Manager['Fly'] = nil
                end
                
                local character = Player.Character
                if character then
                    local humanoid = character:FindFirstChild("Humanoid")
                    local rootPart = character:FindFirstChild("HumanoidRootPart")
                    
                    if humanoid then
                        humanoid.PlatformStand = false
                    end
                    
                    if rootPart then
                        for _, obj in pairs(rootPart:GetChildren()) do
                            if obj:IsA("BodyGyro") or obj:IsA("BodyVelocity") then
                                obj:Destroy()
                            end
                        end
                    end
                end
            end
        end
    })
    
    FlySection:AddSlider({
        Name = "飞行速度",
        Min = 10,
        Max = 100,
        Default = 50,
        Callback = function(value)
            Settings.Player.Fly.Speed = value
        end
    })
    
    -- 视角设置
    local FOVSection = PlayerTab:AddSection({
        Name = "视角设置",
        Position = "right",
    })
    
    FOVSection:AddToggle({
        Name = "启用自定义视角",
        Callback = function(value)
            Settings.Player.FOV.Enabled = value
            
            if value then
                if Connections_Manager['FOV'] then
                    Connections_Manager['FOV']:Disconnect()
                end
                
                Connections_Manager['FOV'] = RunService.RenderStepped:Connect(function()
                    local camera = workspace.CurrentCamera
                    if camera then
                        camera.FieldOfView = Settings.Player.FOV.Value
                    end
                end)
            else
                if Connections_Manager['FOV'] then
                    Connections_Manager['FOV']:Disconnect()
                    Connections_Manager['FOV'] = nil
                end
                
                local camera = workspace.CurrentCamera
                if camera then
                    camera.FieldOfView = 70
                end
            end
        end
    })
    
    FOVSection:AddSlider({
        Name = "视角大小",
        Min = 50,
        Max = 150,
        Default = 70,
        Callback = function(value)
            Settings.Player.FOV.Value = value
        end
    })
    
    -- 命中音效
    local HitSoundsSection = PlayerTab:AddSection({
        Name = "命中音效",
        Position = "left",
    })
    
    HitSoundsSection:AddToggle({
        Name = "启用命中音效",
        Callback = function(value)
            Settings.Player.HitSounds.Enabled = value
        end
    })
    
    HitSoundsSection:AddSlider({
        Name = "音效音量",
        Min = 0,
        Max = 10,
        Default = 6,
        Callback = function(value)
            Settings.Player.HitSounds.Volume = value
        end
    })
    
    local soundOptions = {"Medal", "Fatality", "Skeet", "Switches", "Rust Headshot", "Neverlose Sound", "Bubble", "Laser", "Steve", "Call of Duty", "Bat", "TF2 Critical", "Saber", "Bameware"}
    local soundIds = {
        Medal = "rbxassetid://6607336718",
        Fatality = "rbxassetid://6607113255",
        Skeet = "rbxassetid://6607204501",
        Switches = "rbxassetid://6607173363",
        ["Rust Headshot"] = "rbxassetid://138750331387064",
        ["Neverlose Sound"] = "rbxassetid://110168723447153",
        Bubble = "rbxassetid://6534947588",
        Laser = "rbxassetid://7837461331",
        Steve = "rbxassetid://4965083997",
        ["Call of Duty"] = "rbxassetid://5952120301",
        Bat = "rbxassetid://3333907347",
        ["TF2 Critical"] = "rbxassetid://296102734",
        Saber = "rbxassetid://8415678813",
        Bameware = "rbxassetid://3124331820"
    }
    
    HitSoundsSection:AddDropdown({
        Name = "音效选择",
        Options = soundOptions,
        Callback = function(value)
            Settings.Player.HitSounds.Sound = value
        end
    })
    
    -- 设置命中音效
    local hitSoundFolder = Instance.new("Folder")
    hitSoundFolder.Name = "CelestiaHitSounds"
    hitSoundFolder.Parent = workspace
    
    local hitSound = Instance.new("Sound")
    hitSound.Name = "HitSound"
    hitSound.Volume = Settings.Player.HitSounds.Volume
    hitSound.SoundId = soundIds[Settings.Player.HitSounds.Sound] or soundIds.Medal
    hitSound.Parent = hitSoundFolder
    
    -- 连接格挡成功事件
    local parrySuccessRemote = ReplicatedStorage:FindFirstChild("Remotes")
    if parrySuccessRemote then
        parrySuccessRemote = parrySuccessRemote:FindFirstChild("ParrySuccess")
        if parrySuccessRemote then
            parrySuccessRemote.OnClientEvent:Connect(function()
                if Settings.Player.HitSounds.Enabled then
                    hitSound:Play()
                end
            end)
        end
    end
    
    -- [[ 杂项设置 ]]
    local MiscSection = MiscTab:AddSection({
        Name = "游戏功能",
        Position = "left",
    })
    
    MiscSection:AddToggle({
        Name = "冷却保护",
        Callback = function(value)
            Settings.Misc.CooldownProtection = value
        end
    })
    
    MiscSection:AddToggle({
        Name = "自动能力",
        Callback = function(value)
            Settings.Misc.AutoAbility = value
        end
    })
    
    MiscSection:AddToggle({
        Name = "Slash of Fury 检测",
        Callback = function(value)
            Settings.Misc.SlashOfFuryDetection = value
        end
    })
    
    -- 保存设置按钮
    MiscSection:AddButton({
        Name = "保存设置",
        Callback = function()
            writefile("Celestia_Settings.json", game:GetService("HttpService"):JSONEncode(Settings))
            print("设置已保存")
        end
    })
    
    MiscSection:AddButton({
        Name = "加载设置",
        Callback = function()
            if isfile("Celestia_Settings.json") then
                local saved = game:GetService("HttpService"):JSONDecode(readfile("Celestia_Settings.json"))
                if saved then
                    for category, values in pairs(saved) do
                        if Settings[category] then
                            for key, value in pairs(values) do
                                if Settings[category][key] ~= nil then
                                    Settings[category][key] = value
                                end
                            end
                        end
                    end
                    print("设置已加载")
                end
            else
                print("未找到保存的设置")
            end
        end
    })
    
    return Window
end

-- [[ 第十部分：初始化函数 ]]
local function InitializeScript()
    print("=== Celestia Blade Ball 脚本初始化 ===")
    
    -- 等待玩家角色加载
    if not Player.Character then
        Player.CharacterAdded:Wait()
    end
    
    -- 设置特殊检测
    SetupPhantomDetection()
    SetupSlashOfFuryDetection()
    SetupInfinityDetection()
    
    -- 创建UI
    local ui = CreateUI()
    
    -- 设置事件监听
    workspace.Balls.ChildRemoved:Connect(function()
        Parries = 0
        Parried = false
        Phantom = false
    end)
    
    -- 格挡成功事件监听
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes then
        local parrySuccessAll = remotes:FindFirstChild("ParrySuccessAll")
        if parrySuccessAll then
            parrySuccessAll.OnClientEvent:Connect(function(_, rootPart)
                if rootPart.Parent and rootPart.Parent ~= Player.Character then
                    -- 处理格挡成功逻辑
                end
            end)
        end
        
        local phantomRemote = remotes:FindFirstChild("Phantom")
        if phantomRemote then
            phantomRemote.OnClientEvent:Connect(function(_, targetPlayer)
                if targetPlayer.Name == Player.Name then
                    Phantom = true
                else
                    Phantom = false
                end
            end)
        end
    end
    
    print("脚本初始化完成！")
    print("按左Ctrl键打开菜单")
end

-- [[ 脚本启动 ]]
if not _G.CelestiaInitialized then
    _G.CelestiaInitialized = true
    task.spawn(InitializeScript)
else
    warn("脚本已经运行中！")
end

return Settings

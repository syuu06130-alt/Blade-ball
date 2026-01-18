-- Blade Ball 完全版自動化スクリプト (Ping最適化版)
-- 開発者：Celestia
-- 更新日：2024年

-- [[ 第一部：サービス初期化 ]]
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
local StatsService = safe_cloneref('Stats')

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- [[ 第二部：グローバル変数と設定 ]]
local getgenv = getgenv or function() return _G end
local _G = _G or getfenv()

-- グローバル設定テーブルの存在確認
if not _G.CelestiaSettings then
    _G.CelestiaSettings = {
        AutoParry = {
            Enabled = false,
            Accuracy = 100,
            RandomAccuracy = false,
            Keypress = false,
            InfinityDetection = true,
            PhantomDetection = true,
            PingAdaptive = true,  -- Ping自動調整機能
            ParryFreshness = 1.0,  -- パリィ鮮度 (1.0 = 通常, 高いほど鮮度向上)
            EarlyParryFactor = 1.0  -- 早めパリィ係数
        },
        SpamParry = {
            Enabled = false,
            Threshold = 2.5,
            Keypress = false,
            PingAdaptive = true
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
            Keypress = false,
            PingAdaptive = true
        },
        Player = {
            Strafe = { Enabled = false, Speed = 36 },
            Spinbot = { Enabled = false, Speed = 1 },
            Fly = { Enabled = false, Speed = 50 },
            Cosmetics = { Enabled = false },
            FOV = { Enabled = false, Value = 70 },
            HitSounds = { Enabled = false, Sound = "メダル", Volume = 6 }
        },
        Misc = {
            CooldownProtection = false,
            AutoAbility = false,
            SlashOfFuryDetection = true,
            PingDisplay = true  -- Ping表示機能
        }
    }
end

local Settings = _G.CelestiaSettings

-- Ping管理システム
local PingManager = {
    CurrentPing = 0,
    AveragePing = 0,
    PingHistory = {},
    MaxHistorySize = 30,
    LastUpdate = tick()
}

-- Ping測定関数
function PingManager:UpdatePing()
    local stats = StatsService
    if stats then
        local networkStats = stats:FindFirstChild("Network")
        if networkStats then
            local serverStats = networkStats:FindFirstChild("ServerStatsItem")
            if serverStats then
                local dataPing = serverStats:FindFirstChild("Data Ping")
                if dataPing then
                    self.CurrentPing = dataPing:GetValue() or 0
                    
                    -- Ping履歴を更新
                    table.insert(self.PingHistory, self.CurrentPing)
                    if #self.PingHistory > self.MaxHistorySize then
                        table.remove(self.PingHistory, 1)
                    end
                    
                    -- 平均Pingを計算
                    local sum = 0
                    for _, ping in ipairs(self.PingHistory) do
                        sum = sum + ping
                    end
                    self.AveragePing = sum / #self.PingHistory
                    
                    self.LastUpdate = tick()
                    return self.CurrentPing
                end
            end
        end
    end
    return 0
end

-- Pingに基づく補正値を取得
function PingManager:GetPingAdjustment()
    self:UpdatePing()
    
    local ping = self.AveragePing
    local adjustment = {
        Timing = 0,  -- タイミング調整（秒）
        Distance = 0,  -- 距離補正
        Multiplier = 1.0  -- 乗算係数
    }
    
    -- Pingに応じた調整値
    if ping < 50 then
        adjustment.Timing = -0.02  -- 低Ping: 遅めにパリィ
        adjustment.Distance = -2
        adjustment.Multiplier = 0.95
    elseif ping < 100 then
        adjustment.Timing = 0.00  -- 通常
        adjustment.Distance = 0
        adjustment.Multiplier = 1.0
    elseif ping < 200 then
        adjustment.Timing = 0.03  -- 高Ping: 早めにパリィ
        adjustment.Distance = 5
        adjustment.Multiplier = 1.1
    elseif ping < 300 then
        adjustment.Timing = 0.06  -- 非常に高Ping: さらに早め
        adjustment.Distance = 10
        adjustment.Multiplier = 1.2
    else
        adjustment.Timing = 0.10  -- 極端に高Ping
        adjustment.Distance = 15
        adjustment.Multiplier = 1.3
    end
    
    -- パリィ鮮度係数を適用
    adjustment.Timing = adjustment.Timing * Settings.AutoParry.ParryFreshness
    adjustment.Distance = adjustment.Distance * Settings.AutoParry.ParryFreshness
    
    -- 早めパリィ係数を適用
    adjustment.Timing = adjustment.Timing * Settings.AutoParry.EarlyParryFactor
    
    return adjustment
end

-- Ping表示UI
if Settings.Misc.PingDisplay then
    local pingDisplay = Instance.new("ScreenGui")
    pingDisplay.Name = "CelestiaPingDisplay"
    pingDisplay.ResetOnSpawn = false
    pingDisplay.Parent = CoreGui
    
    local frame = Instance.new("Frame")
    frame.Name = "PingFrame"
    frame.Position = UDim2.new(0.85, 0, 0.02, 0)
    frame.Size = UDim2.new(0, 150, 0, 60)
    frame.BackgroundColor3 = Color3.fromRGB(20, 20, 40)
    frame.BackgroundTransparency = 0.3
    frame.BorderSizePixel = 0
    frame.Parent = pingDisplay
    
    local uiCorner = Instance.new("UICorner")
    uiCorner.CornerRadius = UDim.new(0, 8)
    uiCorner.Parent = frame
    
    local uiStroke = Instance.new("UIStroke")
    uiStroke.Thickness = 2
    uiStroke.Color = Color3.new(0, 0, 0)
    uiStroke.Parent = frame
    
    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Text = "Ping監視システム"
    title.Size = UDim2.new(1, 0, 0, 20)
    title.Position = UDim2.new(0, 0, 0, 5)
    title.BackgroundTransparency = 1
    title.TextColor3 = Color3.new(1, 1, 1)
    title.Font = Enum.Font.GothamSemibold
    title.TextSize = 14
    title.Parent = frame
    
    local currentPingLabel = Instance.new("TextLabel")
    currentPingLabel.Name = "CurrentPing"
    currentPingLabel.Text = "現在のPing: 計算中..."
    currentPingLabel.Size = UDim2.new(1, 0, 0, 18)
    currentPingLabel.Position = UDim2.new(0, 0, 0, 28)
    currentPingLabel.BackgroundTransparency = 1
    currentPingLabel.TextColor3 = Color3.new(1, 1, 1)
    currentPingLabel.Font = Enum.Font.Gotham
    currentPingLabel.TextSize = 12
    currentPingLabel.Parent = frame
    
    local adjustmentLabel = Instance.new("TextLabel")
    adjustmentLabel.Name = "Adjustment"
    adjustmentLabel.Text = "調整: 無し"
    adjustmentLabel.Size = UDim2.new(1, 0, 0, 18)
    adjustmentLabel.Position = UDim2.new(0, 0, 0, 46)
    adjustmentLabel.BackgroundTransparency = 1
    adjustmentLabel.TextColor3 = Color3.new(1, 1, 1)
    adjustmentLabel.Font = Enum.Font.Gotham
    adjustmentLabel.TextSize = 12
    adjustmentLabel.Parent = frame
    
    -- Ping表示更新
    RunService.RenderStepped:Connect(function()
        if pingDisplay and pingDisplay.Parent then
            local ping = PingManager.CurrentPing
            local avgPing = PingManager.AveragePing
            local adjustment = PingManager:GetPingAdjustment()
            
            -- Ping値に応じて色を変更
            local color = Color3.new(0, 1, 0)  -- 緑
            if ping > 100 then
                color = Color3.new(1, 1, 0)  -- 黄色
            end
            if ping > 200 then
                color = Color3.new(1, 0.5, 0)  -- オレンジ
            end
            if ping > 300 then
                color = Color3.new(1, 0, 0)  -- 赤
            end
            
            currentPingLabel.Text = string.format("Ping: %dms (平均: %dms)", math.floor(ping), math.floor(avgPing))
            currentPingLabel.TextColor3 = color
            
            if adjustment.Timing ~= 0 then
                adjustmentLabel.Text = string.format("調整: %.0fms 早め", adjustment.Timing * 1000)
                adjustmentLabel.TextColor3 = Color3.new(0, 1, 1)
            else
                adjustmentLabel.Text = "調整: 最適"
                adjustmentLabel.TextColor3 = Color3.new(0, 1, 0)
            end
        end
    end)
end

-- コア変数
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

-- Ping適応型パリィシステム
local AdaptiveParrySystem = {
    LastParryTime = 0,
    ParryCooldown = 0.02,
    MinCooldown = 0.01,
    MaxCooldown = 0.05,
    RecentParries = {},
    PerformanceScore = 100
}

-- パリィ間隔をPingに基づいて調整
function AdaptiveParrySystem:AdjustCooldown()
    local ping = PingManager.AveragePing
    
    if ping < 50 then
        self.ParryCooldown = 0.02  -- 低Ping: 通常間隔
    elseif ping < 100 then
        self.ParryCooldown = 0.018  -- 少し早く
    elseif ping < 200 then
        self.ParryCooldown = 0.015  -- 高Ping: 早めに
    elseif ping < 300 then
        self.ParryCooldown = 0.012  -- 非常に高Ping: さらに早く
    else
        self.ParryCooldown = 0.01  -- 極端に高Ping: 最速
    end
    
    -- パリィ鮮度係数を適用
    self.ParryCooldown = self.ParryCooldown * (2 - Settings.AutoParry.ParryFreshness)
    
    -- 範囲内に制限
    self.ParryCooldown = math.clamp(self.ParryCooldown, self.MinCooldown, self.MaxCooldown)
    
    return self.ParryCooldown
end

-- パリィパフォーマンス追跡
function AdaptiveParrySystem:TrackPerformance(success)
    local currentTime = tick()
    
    -- 最近のパリィを記録
    table.insert(self.RecentParries, {
        Time = currentTime,
        Success = success
    })
    
    -- 古い記録を削除（過去5秒間のみ保持）
    while #self.RecentParries > 0 and currentTime - self.RecentParries[1].Time > 5 do
        table.remove(self.RecentParries, 1)
    end
    
    -- 成功率を計算
    if #self.RecentParries > 0 then
        local successes = 0
        for _, parry in ipairs(self.RecentParries) do
            if parry.Success then
                successes = successes + 1
            end
        end
        self.PerformanceScore = (successes / #self.RecentParries) * 100
    end
    
    -- パフォーマンスに基づいて鮮度を調整（自動調整）
    if Settings.AutoParry.PingAdaptive then
        if self.PerformanceScore < 70 then
            -- 成功率が低い場合は鮮度を上げる
            Settings.AutoParry.ParryFreshness = math.min(Settings.AutoParry.ParryFreshness + 0.05, 1.5)
        elseif self.PerformanceScore > 90 then
            -- 成功率が高い場合は鮮度を下げて安定化
            Settings.AutoParry.ParryFreshness = math.max(Settings.AutoParry.ParryFreshness - 0.02, 0.8)
        end
    end
end

-- [[ 第三部：LPH シミュレーション関数 ]]
if not LPH_OBFUSCATED then
    _G.LPH_JIT = function(f) return f end
    _G.LPH_JIT_MAX = function(f) return f end
    _G.LPH_NO_VIRTUALIZE = function(f) return f end
end

-- [[ 第四部：ハッシュ値抽出 ]]
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

-- ハッシュ抽出実行
ExtractHashes()

-- [[ 第五部：リモートイベント設定 ]]
local function SetupRemotes()
    for _, obj in next, game:GetDescendants() do
        if obj:IsA("RemoteEvent") and string.find(obj.Name, "\n") then
            obj.Changed:Once(function()
                table.insert(PropertyChangeOrder, obj)
            end)
        end
    end
    
    -- すべてのリモートイベントが発見されるまで待機
    repeat
        task.wait()
    until #PropertyChangeOrder == 3
    
    return PropertyChangeOrder[1], PropertyChangeOrder[2], PropertyChangeOrder[3]
end

local ShouldPlayerJump, MainRemote, GetOpponentPosition = SetupRemotes()

-- [[ 第六部：パリィキー検出 ]]
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

-- [[ 第七部：自動パリィコアモジュール (Ping最適化版) ]]
local Auto_Parry = {}

-- 基本機能
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

-- カーブ検知 (Ping補正付き)
function Auto_Parry.Is_Curved()
    local ball = Auto_Parry.Get_Ball()
    if not ball then return false end
    
    local zoomies = ball:FindFirstChild('zoomies')
    if not zoomies then return false end
    
    local velocity = zoomies.VectorVelocity
    local ballDirection = velocity.Unit
    local playerDirection = (Player.Character.PrimaryPart.Position - ball.Position).Unit
    local dot = playerDirection:Dot(ballDirection)
    
    -- Pingに基づく補正
    local pingAdjustment = PingManager:GetPingAdjustment()
    local adjustedDotThreshold = 0.5 - (PingManager.AveragePing / 1000) * pingAdjustment.Multiplier
    
    return dot < adjustedDotThreshold
end

-- パリィデータ生成 (Ping補正付き)
function Auto_Parry.Parry_Data(parryType)
    local camera = workspace.CurrentCamera
    local events = {}
    local mouseLocation = {camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2}
    
    -- 画面上のプレイヤー位置取得
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

-- Ping最適化パリィ計算
function Auto_Parry.Calculate_Parry_Timing(ball, distance, speed)
    -- 基本パリィ精度計算
    local ping = PingManager.AveragePing
    local pingThreshold = math.clamp(ping / 10, 5, 17)
    
    local cappedSpeedDiff = math.min(math.max(speed - 9.5, 0), 650)
    local speedDivisorBase = 2.4 + cappedSpeedDiff * 0.002
    
    local effectiveMultiplier = Speed_Divisor_Multiplier
    if Settings.AutoParry.RandomAccuracy then
        effectiveMultiplier = 0.7 + (math.random(1, 100) - 1) * (0.35 / 99)
    end
    
    local speedDivisor = speedDivisorBase * effectiveMultiplier
    local baseAccuracy = pingThreshold + math.max(speed / speedDivisor, 9.5)
    
    -- Ping補正を適用
    local pingAdjustment = PingManager:GetPingAdjustment()
    
    -- Pingに応じた距離補正
    local distanceAdjustment = pingAdjustment.Distance * (speed / 100)
    
    -- 最終パリィ精度
    local finalAccuracy = baseAccuracy + distanceAdjustment
    
    -- パリィ鮮度を適用
    finalAccuracy = finalAccuracy * Settings.AutoParry.ParryFreshness
    
    -- 早めパリィ係数を適用
    if Settings.AutoParry.EarlyParryFactor > 1 then
        finalAccuracy = finalAccuracy * (1 + (Settings.AutoParry.EarlyParryFactor - 1) * 0.3)
    end
    
    -- 最小距離を確保
    finalAccuracy = math.max(finalAccuracy, 5)
    
    return {
        Accuracy = finalAccuracy,
        ShouldParry = distance <= finalAccuracy,
        PingAdjustment = pingAdjustment,
        BaseDistance = distance,
        AdjustedDistance = finalAccuracy
    }
end

-- パリィ実行 (Ping最適化版)
function Auto_Parry.Parry(parryType)
    if not Parry_Key or not HashOne or not HashTwo or not HashThree then
        warn("パリィシステムが完全に初期化されていません")
        return false
    end
    
    -- Pingに基づく待機時間調整
    local cooldown = AdaptiveParrySystem:AdjustCooldown()
    local currentTime = tick()
    
    if currentTime - AdaptiveParrySystem.LastParryTime < cooldown then
        return false  -- クールダウン中
    end
    
    local parryData = Auto_Parry.Parry_Data(parryType)
    
    -- パリィリクエスト送信
    ShouldPlayerJump:FireServer(HashOne, Parry_Key, unpack(parryData))
    MainRemote:FireServer(HashTwo, Parry_Key, unpack(parryData))
    GetOpponentPosition:FireServer(HashThree, Parry_Key, unpack(parryData))
    
    Parries = Parries + 1
    AdaptiveParrySystem.LastParryTime = currentTime
    
    -- パリィ成功と仮定してパフォーマンス追跡
    AdaptiveParrySystem:TrackPerformance(true)
    
    -- パリィカウントリセット
    task.delay(0.5, function()
        if Parries > 0 then
            Parries = Parries - 1
        end
    end)
    
    return true
end

-- 高鮮度パリィシステム
local HighFreshnessParry = {
    Active = false,
    LastFrameCheck = 0,
    FrameInterval = 0.001,  -- 1ms間隔（最高鮮度）
    PredictionFrames = 3    -- 先読みフレーム数
}

-- フレーム単位のパリィチェック
function HighFreshnessParry:ShouldParryThisFrame()
    local currentTime = tick()
    if currentTime - self.LastFrameCheck >= self.FrameInterval then
        self.LastFrameCheck = currentTime
        return true
    end
    return false
end

-- ボールの未来位置を予測
function HighFreshnessParry:PredictBallPosition(ball, framesAhead)
    local zoomies = ball:FindFirstChild('zoomies')
    if not zoomies then return ball.Position end
    
    local velocity = zoomies.VectorVelocity
    local frameTime = 1/60  -- 60FPSを仮定
    
    -- Pingを考慮した予測
    local ping = PingManager.AveragePing
    local pingOffset = ping / 1000  -- 秒単位に変換
    
    -- 将来の位置を計算
    local predictedPosition = ball.Position + (velocity * (frameTime * framesAhead + pingOffset))
    
    return predictedPosition
end

-- [[ 第八部：特殊検知システム ]]
-- ファントム V2 検知
local function SetupPhantomDetection()
    local runtime = workspace:FindFirstChild("Runtime")
    if not runtime then return end
    
    runtime.ChildAdded:Connect(function(obj)
        if Settings.AutoParry.PhantomDetection and (obj.Name == "maxTransmission" or obj.Name == "transmissionpart") then
            local weld = obj:FindFirstChildWhichIsA("WeldConstraint")
            if weld and Player.Character and weld.Part1 == Player.Character.HumanoidRootPart then
                Phantom = true
                
                -- プレイヤー自動移動
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

-- スラッシュ・オブ・フューリー検知
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
                            -- Pingに基づく間隔調整
                            local ping = PingManager.AveragePing
                            local interval = 0.1
                            if ping > 200 then
                                interval = 0.08  -- 高Ping: 早めにパリィ
                            elseif ping > 100 then
                                interval = 0.09
                            end
                            
                            Auto_Parry.Parry(Selected_Parry_Type)
                            task.wait(interval)
                        end
                        task.wait()
                    until not label.Parent
                end
            end
        end)
    end)
end

-- インフィニティボール検知
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

-- [[ 第九部：UI インターフェース (Ping最適化版) ]]
local function CreateUI()
    -- Airflow UIライブラリ読み込み
    local success, Airflow = pcall(function()
        return loadstring(game:HttpGetAsync("https://raw.githubusercontent.com/4lpaca-pin/Airflow/refs/heads/main/src/source.luau"))()
    end)
    
    if not success then
        warn("Airflow UIライブラリを読み込めません")
        return nil
    end
    
    local Window = Airflow:Init({
        Name = "セレスティア - Ping最適化版",
        Keybind = "左Ctrl",
        Logo = "rbxassetid://94220348785476",
    })
    
    -- タブ作成
    local BlatantTab = Window:DrawTab({ Name = "自動パリィ", Icon = "shield" })
    local PlayerTab = Window:DrawTab({ Name = "プレイヤー", Icon = "user" })
    local MiscTab = Window:DrawTab({ Name = "その他", Icon = "settings" })
    
    -- [[ 自動パリィ設定 (Ping最適化版) ]]
    local AutoParrySection = BlatantTab:AddSection({
        Name = "自動パリィ設定",
        Position = "left",
    })
    
    AutoParrySection:AddToggle({
        Name = "自動パリィ有効",
        Callback = function(value)
            Settings.AutoParry.Enabled = value
            
            if value then
                -- 自動パリィループ作成
                if Connections_Manager['AutoParry'] then
                    Connections_Manager['AutoParry']:Disconnect()
                end
                
                Connections_Manager['AutoParry'] = RunService.PreSimulation:Connect(function()
                    if not Settings.AutoParry.Enabled then return end
                    if not HighFreshnessParry:ShouldParryThisFrame() then return end
                    
                    local ball = Auto_Parry.Get_Ball()
                    if not ball then return end
                    
                    local zoomies = ball:FindFirstChild('zoomies')
                    if not zoomies then return end
                    
                    local target = ball:GetAttribute('target')
                    if target ~= tostring(Player) then return end
                    
                    -- 距離と速度計算
                    local distance = (Player.Character.PrimaryPart.Position - ball.Position).Magnitude
                    local velocity = zoomies.VectorVelocity
                    local speed = velocity.Magnitude
                    
                    -- Ping最適化パリィ計算
                    local parryTiming = Auto_Parry.Calculate_Parry_Timing(ball, distance, speed)
                    
                    -- カーブボールチェック
                    local isCurved = Auto_Parry.Is_Curved()
                    
                    -- インフィニティボール検知
                    if Settings.AutoParry.InfinityDetection and Infinity then
                        return
                    end
                    
                    -- パリィ実行判定
                    if parryTiming.ShouldParry and not isCurved then
                        if Settings.AutoParry.Keypress then
                            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F, false, game)
                            task.wait(0.01)  -- 最短間隔
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
        Name = "パリィ精度",
        Min = 1,
        Max = 100,
        Default = 100,
        Callback = function(value)
            Settings.AutoParry.Accuracy = value
            Speed_Divisor_Multiplier = 0.7 + (value - 1) * (0.35 / 99)
        end
    })
    
    AutoParrySection:AddSlider({
        Name = "パリィ鮮度",
        Min = 0.5,
        Max = 1.5,
        Default = 1.0,
        Precision = 0.1,
        Callback = function(value)
            Settings.AutoParry.ParryFreshness = value
        end
    })
    
    AutoParrySection:AddSlider({
        Name = "早めパリィ係数",
        Min = 0.8,
        Max = 1.5,
        Default = 1.0,
        Precision = 0.1,
        Callback = function(value)
            Settings.AutoParry.EarlyParryFactor = value
        end
    })
    
    AutoParrySection:AddDropdown({
        Name = "パリィ方向",
        Values = {"カメラ", "後方", "直線", "ランダム", "上方", "左", "右", "ランダムターゲット"},
        Multi = false,
        Default = "カメラ",
        Callback = function(value)
            -- 英語の値に変換
            local typeMap = {
                ["カメラ"] = "Camera",
                ["後方"] = "Backwards",
                ["直線"] = "Straight",
                ["ランダム"] = "Random",
                ["上方"] = "High",
                ["左"] = "Left",
                ["右"] = "Right",
                ["ランダムターゲット"] = "RandomTarget"
            }
            Selected_Parry_Type = typeMap[value] or "Camera"
        end
    })
    
    AutoParrySection:AddToggle({
        Name = "ランダム精度",
        Callback = function(value)
            Settings.AutoParry.RandomAccuracy = value
        end
    })
    
    AutoParrySection:AddToggle({
        Name = "Ping自動調整",
        Callback = function(value)
            Settings.AutoParry.PingAdaptive = value
        end
    })
    
    AutoParrySection:AddToggle({
        Name = "キー押下シミュレーション",
        Callback = function(value)
            Settings.AutoParry.Keypress = value
        end
    })
    
    AutoParrySection:AddToggle({
        Name = "インフィニティボール検知",
        Callback = function(value)
            Settings.AutoParry.InfinityDetection = value
        end
    })
    
    AutoParrySection:AddToggle({
        Name = "ファントム検知",
        Callback = function(value)
            Settings.AutoParry.PhantomDetection = value
        end
    })
    
    -- [[ 連発パリィ (Ping最適化版) ]]
    local SpamParrySection = BlatantTab:AddSection({
        Name = "連発パリィ設定",
        Position = "right",
    })
    
    SpamParrySection:AddToggle({
        Name = "連発パリィ有効",
        Callback = function(value)
            Settings.SpamParry.Enabled = value
            
            if value then
                if Connections_Manager['SpamParry'] then
                    Connections_Manager['SpamParry']:Disconnect()
                end
                
                Connections_Manager['SpamParry'] = RunService.PreSimulation:Connect(function()
                    if not Settings.SpamParry.Enabled then return end
                    if not HighFreshnessParry:ShouldParryThisFrame() then return end
                    
                    local ball = Auto_Parry.Get_Ball()
                    if not ball then return end
                    
                    local target = ball:GetAttribute('target')
                    if target ~= tostring(Player) then return end
                    
                    local distance = (Player.Character.PrimaryPart.Position - ball.Position).Magnitude
                    
                    -- Pingに基づく閾値調整
                    local ping = PingManager.AveragePing
                    local adjustedThreshold = ParryThreshold
                    
                    if ping > 200 then
                        adjustedThreshold = ParryThreshold * 0.8  -- 高Ping: 閾値を下げて頻繁にパリィ
                    elseif ping > 100 then
                        adjustedThreshold = ParryThreshold * 0.9
                    end
                    
                    if distance <= 30 and Parries > adjustedThreshold then
                        if Settings.SpamParry.Keypress then
                            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F, false, game)
                            task.wait(0.01)  -- 最短間隔
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
        Name = "パリィ閾値",
        Min = 1,
        Max = 5,
        Default = 2.5,
        Precision = 0.1,
        Callback = function(value)
            Settings.SpamParry.Threshold = value
            ParryThreshold = value
        end
    })
    
    SpamParrySection:AddToggle({
        Name = "Ping自動調整",
        Callback = function(value)
            Settings.SpamParry.PingAdaptive = value
        end
    })
    
    SpamParrySection:AddToggle({
        Name = "キー押下シミュレーション",
        Callback = function(value)
            Settings.SpamParry.Keypress = value
        end
    })
    
    -- [[ トリガーパリィ ]]
    local TriggerbotSection = BlatantTab:AddSection({
        Name = "トリガーパリィ設定",
        Position = "left",
    })
    
    TriggerbotSection:AddToggle({
        Name = "トリガーパリィ有効",
        Callback = function(value)
            Settings.Triggerbot.Enabled = value
            
            if value then
                if Connections_Manager['Triggerbot'] then
                    Connections_Manager['Triggerbot']:Disconnect()
                end
                
                Connections_Manager['Triggerbot'] = RunService.PreSimulation:Connect(function()
                    if not Settings.Triggerbot.Enabled then return end
                    if not HighFreshnessParry:ShouldParryThisFrame() then return end
                    
                    local ball = Auto_Parry.Get_Ball()
                    if not ball then return end
                    
                    local target = ball:GetAttribute('target')
                    if target ~= tostring(Player) then return end
                    
                    if Settings.Triggerbot.InfinityDetection and Infinity then
                        return
                    end
                    
                    -- Pingに基づく反応速度調整
                    local ping = PingManager.AveragePing
                    local shouldParry = true
                    
                    if ping > 300 then
                        -- 極端に高Pingの場合は安全マージンを追加
                        local distance = (Player.Character.PrimaryPart.Position - ball.Position).Magnitude
                        if distance > 50 then  -- 遠すぎる場合はパリィしない
                            shouldParry = false
                        end
                    end
                    
                    if shouldParry then
                        if Settings.Triggerbot.Keypress then
                            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F, false, game)
                            task.wait(0.01)
                            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, game)
                        else
                            Auto_Parry.Parry(Selected_Parry_Type)
                        end
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
        Name = "インフィニティボール検知",
        Callback = function(value)
            Settings.Triggerbot.InfinityDetection = value
        end
    })
    
    TriggerbotSection:AddToggle({
        Name = "キー押下シミュレーション",
        Callback = function(value)
            Settings.Triggerbot.Keypress = value
        end
    })
    
    -- [[ ロビー自動パリィ (Ping最適化版) ]]
    local LobbyAPSection = BlatantTab:AddSection({
        Name = "ロビー自動パリィ設定",
        Position = "right",
    })
    
    LobbyAPSection:AddToggle({
        Name = "ロビー自動パリィ有効",
        Callback = function(value)
            Settings.LobbyAP.Enabled = value
            
            if value then
                if Connections_Manager['LobbyAP'] then
                    Connections_Manager['LobbyAP']:Disconnect()
                end
                
                Connections_Manager['LobbyAP'] = RunService.Heartbeat:Connect(function()
                    if not Settings.LobbyAP.Enabled then return end
                    if not HighFreshnessParry:ShouldParryThisFrame() then return end
                    
                    local ball = Auto_Parry.Lobby_Balls()
                    if not ball then return end
                    
                    local target = ball:GetAttribute('target')
                    if target ~= tostring(Player) then return end
                    
                    local distance = Player:DistanceFromCharacter(ball.Position)
                    local zoomies = ball:FindFirstChild('zoomies')
                    if not zoomies then return end
                    
                    local speed = zoomies.VectorVelocity.Magnitude
                    local ping = PingManager.AveragePing
                    
                    local cappedSpeedDiff = math.min(math.max(speed - 9.5, 0), 650)
                    local speedDivisorBase = 2.4 + cappedSpeedDiff * 0.002
                    
                    local effectiveMultiplier = LobbyAP_Speed_Divisor_Multiplier
                    if Settings.LobbyAP.RandomAccuracy then
                        effectiveMultiplier = 0.7 + (math.random(1, 100) - 1) * (0.35 / 99)
                    end
                    
                    -- Ping補正
                    local pingAdjustment = 0
                    if Settings.LobbyAP.PingAdaptive then
                        if ping > 200 then
                            pingAdjustment = 10  -- 高Ping: 距離補正を増加
                        elseif ping > 100 then
                            pingAdjustment = 5
                        end
                    end
                    
                    local speedDivisor = speedDivisorBase * effectiveMultiplier
                    local parryAccuracy = (ping / 10) + math.max(speed / speedDivisor, 9.5) + pingAdjustment
                    
                    if distance <= parryAccuracy then
                        if Settings.LobbyAP.Keypress then
                            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F, false, game)
                            task.wait(0.01)
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
        Name = "パリィ精度",
        Min = 1,
        Max = 100,
        Default = 100,
        Callback = function(value)
            Settings.LobbyAP.Accuracy = value
            LobbyAP_Speed_Divisor_Multiplier = 0.7 + (value - 1) * (0.35 / 99)
        end
    })
    
    LobbyAPSection:AddToggle({
        Name = "ランダム精度",
        Callback = function(value)
            Settings.LobbyAP.RandomAccuracy = value
        end
    })
    
    LobbyAPSection:AddToggle({
        Name = "Ping自動調整",
        Callback = function(value)
            Settings.LobbyAP.PingAdaptive = value
        end
    })
    
    LobbyAPSection:AddToggle({
        Name = "キー押下シミュレーション",
        Callback = function(value)
            Settings.LobbyAP.Keypress = value
        end
    })
    
    -- [[ プレイヤー設定 ]]
    -- 移動速度調整
    local StrafeSection = PlayerTab:AddSection({
        Name = "移動設定",
        Position = "left",
    })
    
    StrafeSection:AddToggle({
        Name = "移動調整有効",
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
        Name = "移動速度",
        Min = 36,
        Max = 200,
        Default = 36,
        Callback = function(value)
            Settings.Player.Strafe.Speed = value
        end
    })
    
    -- スピンボット
    local SpinbotSection = PlayerTab:AddSection({
        Name = "スピン設定",
        Position = "right",
    })
    
    SpinbotSection:AddToggle({
        Name = "スピンボット有効",
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
        Name = "スピン速度",
        Min = 1,
        Max = 100,
        Default = 1,
        Callback = function(value)
            Settings.Player.Spinbot.Speed = value
        end
    })
    
    -- フライモード
    local FlySection = PlayerTab:AddSection({
        Name = "飛行設定",
        Position = "left",
    })
    
    FlySection:AddToggle({
        Name = "飛行有効",
        Callback = function(value)
            Settings.Player.Fly.Enabled = value
            
            if value then
                -- フライモード実装
                local character = Player.Character
                if not character then return end
                
                local humanoid = character:FindFirstChild("Humanoid")
                local rootPart = character:FindFirstChild("HumanoidRootPart")
                if not humanoid or not rootPart then return end
                
                -- フライコントローラー作成
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
        Name = "飛行速度",
        Min = 10,
        Max = 100,
        Default = 50,
        Callback = function(value)
            Settings.Player.Fly.Speed = value
        end
    })
    
    -- 視野設定
    local FOVSection = PlayerTab:AddSection({
        Name = "視野設定",
        Position = "right",
    })
    
    FOVSection:AddToggle({
        Name = "カスタム視野有効",
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
        Name = "視野サイズ",
        Min = 50,
        Max = 150,
        Default = 70,
        Callback = function(value)
            Settings.Player.FOV.Value = value
        end
    })
    
    -- ヒットサウンド
    local HitSoundsSection = PlayerTab:AddSection({
        Name = "ヒット音",
        Position = "left",
    })
    
    HitSoundsSection:AddToggle({
        Name = "ヒット音有効",
        Callback = function(value)
            Settings.Player.HitSounds.Enabled = value
        end
    })
    
    HitSoundsSection:AddSlider({
        Name = "音量",
        Min = 0,
        Max = 10,
        Default = 6,
        Callback = function(value)
            Settings.Player.HitSounds.Volume = value
        end
    })
    
    local soundOptions = {"メダル", "ファタリティ", "スキート", "スイッチ", "ラストヘッドショット", "ネバーローズ", "バブル", "レーザー", "スティーブ", "コール・オブ・デューティ", "バット", "TF2クリティカル", "セイバー", "ベームウェア"}
    local soundIds = {
        ["メダル"] = "rbxassetid://6607336718",
        ["ファタリティ"] = "rbxassetid://6607113255",
        ["スキート"] = "rbxassetid://6607204501",
        ["スイッチ"] = "rbxassetid://6607173363",
        ["ラストヘッドショット"] = "rbxassetid://138750331387064",
        ["ネバーローズ"] = "rbxassetid://110168723447153",
        ["バブル"] = "rbxassetid://6534947588",
        ["レーザー"] = "rbxassetid://7837461331",
        ["スティーブ"] = "rbxassetid://4965083997",
        ["コール・オブ・デューティ"] = "rbxassetid://5952120301",
        ["バット"] = "rbxassetid://3333907347",
        ["TF2クリティカル"] = "rbxassetid://296102734",
        ["セイバー"] = "rbxassetid://8415678813",
        ["ベームウェア"] = "rbxassetid://3124331820"
    }
    
    HitSoundsSection:AddDropdown({
        Name = "ヒット音選択",
        Options = soundOptions,
        Callback = function(value)
            Settings.Player.HitSounds.Sound = value
        end
    })
    
    -- ヒットサウンド設定
    local hitSoundFolder = Instance.new("Folder")
    hitSoundFolder.Name = "セレスティアヒット音"
    hitSoundFolder.Parent = workspace
    
    local hitSound = Instance.new("Sound")
    hitSound.Name = "ヒット音"
    hitSound.Volume = Settings.Player.HitSounds.Volume
    hitSound.SoundId = soundIds[Settings.Player.HitSounds.Sound] or soundIds["メダル"]
    hitSound.Parent = hitSoundFolder
    
    -- パリィ成功イベント接続
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
    
    -- [[ その他設定 (Ping管理) ]]
    local MiscSection = MiscTab:AddSection({
        Name = "Ping管理システム",
        Position = "left",
    })
    
    MiscSection:AddToggle({
        Name = "Ping表示有効",
        Callback = function(value)
            Settings.Misc.PingDisplay = value
            -- UI表示/非表示の切り替えロジックをここに追加
        end
    })
    
    MiscSection:AddToggle({
        Name = "クールダウン保護",
        Callback = function(value)
            Settings.Misc.CooldownProtection = value
        end
    })
    
    MiscSection:AddToggle({
        Name = "自動アビリティ",
        Callback = function(value)
            Settings.Misc.AutoAbility = value
        end
    })
    
    MiscSection:AddToggle({
        Name = "スラッシュ・オブ・フューリー検知",
        Callback = function(value)
            Settings.Misc.SlashOfFuryDetection = value
        end
    })
    
    -- パフォーマンス表示
    MiscSection:AddLabel({
        Name = "パフォーマンス統計",
        Text = "パリィ成功率: 計算中..."
    })
    
    -- パフォーマンス更新
    RunService.RenderStepped:Connect(function()
        if MiscSection then
            local performanceText = string.format("パリィ成功率: %.1f%% | Ping: %dms", 
                AdaptiveParrySystem.PerformanceScore, math.floor(PingManager.AveragePing))
            
            -- ここでUIラベルを更新するロジックが必要
            -- Airflow UIのラベル更新方法に応じて実装
        end
    end)
    
    -- 設定保存ボタン
    MiscSection:AddButton({
        Name = "設定を保存",
        Callback = function()
            writefile("セレスティア設定_Ping最適化.json", game:GetService("HttpService"):JSONEncode(Settings))
            print("設定を保存しました")
        end
    })
    
    -- 設定読み込みボタン
    MiscSection:AddButton({
        Name = "設定を読み込み",
        Callback = function()
            if isfile("セレスティア設定_Ping最適化.json") then
                local saved = game:GetService("HttpService"):JSONDecode(readfile("セレスティア設定_Ping最適化.json"))
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
                    print("設定を読み込みました")
                end
            else
                print("保存された設定が見つかりません")
            end
        end
    })
    
    -- 最適化リセットボタン
    MiscSection:AddButton({
        Name = "最適化リセット",
        Callback = function()
            Settings.AutoParry.ParryFreshness = 1.0
            Settings.AutoParry.EarlyParryFactor = 1.0
            AdaptiveParrySystem.PerformanceScore = 100
            AdaptiveParrySystem.RecentParries = {}
            print("最適化設定をリセットしました")
        end
    })
    
    return Window
end

-- [[ 第十部：初期化関数 (Ping最適化版) ]]
local function InitializeScript()
    print("=== セレスティア Ping最適化版 初期化 ===")
    
    -- Pingシステム初期化
    PingManager:UpdatePing()
    print(string.format("初期Ping: %dms", PingManager.CurrentPing))
    
    -- プレイヤーキャラクターの読み込みを待機
    if not Player.Character then
        Player.CharacterAdded:Wait()
    end
    
    -- 特殊検知設定
    SetupPhantomDetection()
    SetupSlashOfFuryDetection()
    SetupInfinityDetection()
    
    -- UI作成
    local ui = CreateUI()
    
    -- イベントリスナー設定
    workspace.Balls.ChildRemoved:Connect(function()
        Parries = 0
        Parried = false
        Phantom = false
        AdaptiveParrySystem:TrackPerformance(false)  -- ボール消失 = パリィ失敗
    end)
    
    -- パリィ成功イベントリスナー
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes then
        local parrySuccessAll = remotes:FindFirstChild("ParrySuccessAll")
        if parrySuccessAll then
            parrySuccessAll.OnClientEvent:Connect(function(_, rootPart)
                if rootPart.Parent and rootPart.Parent ~= Player.Character then
                    -- パリィ成功ロジック処理
                    AdaptiveParrySystem:TrackPerformance(true)
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
    
    -- Ping監視ループ
    task.spawn(function()
        while task.wait(0.5) do
            local currentPing = PingManager:UpdatePing()
            
            -- Pingが極端に高い場合の警告
            if currentPing > 300 then
                warn(string.format("高Ping検出: %dms - パリィ精度が低下する可能性があります", currentPing))
            end
            
            -- 自動調整が有効な場合、Pingに応じて鮮度を調整
            if Settings.AutoParry.PingAdaptive then
                if currentPing > 250 then
                    Settings.AutoParry.ParryFreshness = math.min(Settings.AutoParry.ParryFreshness + 0.05, 1.5)
                    Settings.AutoParry.EarlyParryFactor = math.min(Settings.AutoParry.EarlyParryFactor + 0.05, 1.5)
                elseif currentPing < 50 then
                    Settings.AutoParry.ParryFreshness = math.max(Settings.AutoParry.ParryFreshness - 0.02, 0.8)
                    Settings.AutoParry.EarlyParryFactor = math.max(Settings.AutoParry.EarlyParryFactor - 0.02, 0.8)
                end
            end
        end
    end)
    
    print("スクリプト初期化完了！")
    print("左Ctrlキーでメニューを開きます")
    print(string.format("現在のPing: %dms | 平均Ping: %dms", 
        math.floor(PingManager.CurrentPing), math.floor(PingManager.AveragePing)))
end

-- [[ スクリプト起動 ]]
if not _G.CelestiaInitialized then
    _G.CelestiaInitialized = true
    task.spawn(InitializeScript)
else
    warn("スクリプトは既に実行中です！")
end

return Settings

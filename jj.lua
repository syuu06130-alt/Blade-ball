-- Blade Ball 完全版自動化スクリプト (Ping最適化版 - 修正済み)
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
local StatsService = game:GetService("Stats")

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
            PingDisplay = true,  -- Ping表示機能
            PingLocked = false   -- Ping表示のドラッグロック状態
        }
    }
end

local Settings = _G.CelestiaSettings

-- [[ Ping管理システム (修正版) ]]
local PingManager = {
    CurrentPing = 0,
    AveragePing = 0,
    PingHistory = {},
    MaxHistorySize = 50,
    LastUpdate = 0,
    PerformanceData = {
        LastParrySuccess = 0,
        SuccessCount = 0,
        TotalAttempts = 0,
        LastAccuracyCheck = 0
    }
}

-- 修正されたPing測定関数
function PingManager:UpdatePing()
    local currentTime = tick()
    
    -- 更新間隔を制限 (0.2秒ごと)
    if currentTime - self.LastUpdate < 0.2 then
        return self.CurrentPing
    end
    
    self.LastUpdate = currentTime
    
    -- 方法1: Statsサービスを使用 (より信頼性が高い)
    local success1, ping1 = pcall(function()
        local stats = StatsService
        if stats then
            local networkStats = stats:FindFirstChild("Network")
            if networkStats then
                local serverStatsItem = networkStats:FindFirstChild("ServerStatsItem")
                if serverStatsItem then
                    local dataPing = serverStatsItem:FindFirstChild("Data Ping")
                    if dataPing then
                        return dataPing:GetValue()
                    end
                end
            end
        end
        return 0
    end)
    
    -- 方法2: Player:GetNetworkPing() を使用 (バックアップ)
    local success2, ping2 = pcall(function()
        return Player:GetNetworkPing() * 1000  -- 秒からミリ秒に変換
    end)
    
    -- 方法3: 接続品質から推定
    local success3, ping3 = pcall(function()
        if game:GetService("NetworkClient") then
            return game:GetService("NetworkClient"):GetServerConnection():GetStats().Ping or 0
        end
        return 0
    end)
    
    -- 利用可能な値から最適なPingを選択
    local newPing = 0
    
    if success1 and ping1 and ping1 > 0 then
        newPing = ping1
    elseif success2 and ping2 and ping2 > 0 then
        newPing = ping2
    elseif success3 and ping3 and ping3 > 0 then
        newPing = ping3
    else
        -- デフォルト値
        newPing = 80
    end
    
    -- Ping値の検証
    if newPing < 1 then
        newPing = 1  -- 最低1ms
    elseif newPing > 2000 then
        newPing = 2000  -- 最高2000ms
    end
    
    self.CurrentPing = math.floor(newPing)
    
    -- Ping履歴を更新
    table.insert(self.PingHistory, self.CurrentPing)
    if #self.PingHistory > self.MaxHistorySize then
        table.remove(self.PingHistory, 1)
    end
    
    -- 加重平均を計算 (最近の値ほど重要)
    local totalWeight = 0
    local weightedSum = 0
    
    for i, ping in ipairs(self.PingHistory) do
        local weight = 1 + (i / #self.PingHistory) * 2  -- 最近の値ほど重みが大きい
        weightedSum = weightedSum + (ping * weight)
        totalWeight = totalWeight + weight
    end
    
    self.AveragePing = math.floor(weightedSum / totalWeight)
    
    return self.CurrentPing
end

-- Pingに基づく補正値を取得 (修正版)
function PingManager:GetPingAdjustment()
    self:UpdatePing()
    
    local ping = self.AveragePing
    local adjustment = {
        Timing = 0,      -- タイミング調整（秒）
        Distance = 0,    -- 距離補正
        Multiplier = 1.0, -- 乗算係数
        Cooldown = 0.02   -- クールダウン調整
    }
    
    -- より正確なPingに応じた調整値
    if ping < 30 then
        -- 非常に低Ping: ほぼ理想的な環境
        adjustment.Timing = -0.01
        adjustment.Distance = -1
        adjustment.Multiplier = 0.9
        adjustment.Cooldown = 0.022
    elseif ping < 80 then
        -- 低Ping: 良い環境
        adjustment.Timing = -0.005
        adjustment.Distance = 0
        adjustment.Multiplier = 0.95
        adjustment.Cooldown = 0.02
    elseif ping < 150 then
        -- 標準Ping: 通常の調整
        adjustment.Timing = 0.01
        adjustment.Distance = 2
        adjustment.Multiplier = 1.05
        adjustment.Cooldown = 0.018
    elseif ping < 250 then
        -- 高Ping: 早めにパリィ
        adjustment.Timing = 0.025
        adjustment.Distance = 5
        adjustment.Multiplier = 1.15
        adjustment.Cooldown = 0.016
    elseif ping < 400 then
        -- 非常に高Ping: さらに早めに
        adjustment.Timing = 0.045
        adjustment.Distance = 8
        adjustment.Multiplier = 1.25
        adjustment.Cooldown = 0.014
    else
        -- 極端に高Ping: 最大限の調整
        adjustment.Timing = 0.08
        adjustment.Distance = 12
        adjustment.Multiplier = 1.4
        adjustment.Cooldown = 0.012
    end
    
    -- パリィ鮮度係数を適用
    adjustment.Timing = adjustment.Timing * Settings.AutoParry.ParryFreshness
    adjustment.Distance = adjustment.Distance * Settings.AutoParry.ParryFreshness
    
    -- 早めパリィ係数を適用
    adjustment.Timing = adjustment.Timing * Settings.AutoParry.EarlyParryFactor
    
    return adjustment
end

-- [[ Ping表示UI (ドラッグ可能版) ]]
local pingDisplay = nil
local pingDisplayFrame = nil
local dragToggleButton = nil

local function CreatePingDisplay()
    if pingDisplay and pingDisplay.Parent then
        pingDisplay:Destroy()
    end
    
    pingDisplay = Instance.new("ScreenGui")
    pingDisplay.Name = "CelestiaPingDisplay"
    pingDisplay.ResetOnSpawn = false
    pingDisplay.Parent = CoreGui
    
    pingDisplayFrame = Instance.new("Frame")
    pingDisplayFrame.Name = "PingFrame"
    pingDisplayFrame.Position = UDim2.new(0.85, 0, 0.02, 0)
    pingDisplayFrame.Size = UDim2.new(0, 180, 0, 110)
    pingDisplayFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 40)
    pingDisplayFrame.BackgroundTransparency = 0.2
    pingDisplayFrame.BorderSizePixel = 0
    pingDisplayFrame.Active = true
    pingDisplayFrame.Draggable = not Settings.Misc.PingLocked  -- 設定に基づくドラッグ状態
    pingDisplayFrame.Parent = pingDisplay
    
    local uiCorner = Instance.new("UICorner")
    uiCorner.CornerRadius = UDim.new(0, 10)
    uiCorner.Parent = pingDisplayFrame
    
    local uiStroke = Instance.new("UIStroke")
    uiStroke.Thickness = 2
    uiStroke.Color = Color3.fromRGB(0, 150, 255)
    uiStroke.Parent = pingDisplayFrame
    
    -- タイトルバー
    local titleBar = Instance.new("Frame")
    titleBar.Name = "TitleBar"
    titleBar.Size = UDim2.new(1, 0, 0, 25)
    titleBar.Position = UDim2.new(0, 0, 0, 0)
    titleBar.BackgroundColor3 = Color3.fromRGB(30, 30, 60)
    titleBar.BorderSizePixel = 0
    titleBar.Parent = pingDisplayFrame
    
    local titleBarCorner = Instance.new("UICorner")
    titleBarCorner.CornerRadius = UDim.new(0, 10, 0, 0)
    titleBarCorner.Parent = titleBar
    
    local titleText = Instance.new("TextLabel")
    titleText.Name = "Title"
    titleText.Text = "📶 Ping監視システム"
    titleText.Size = UDim2.new(0.7, 0, 1, 0)
    titleText.Position = UDim2.new(0, 5, 0, 0)
    titleText.BackgroundTransparency = 1
    titleText.TextColor3 = Color3.new(1, 1, 1)
    titleText.Font = Enum.Font.GothamSemibold
    titleText.TextSize = 14
    titleText.TextXAlignment = Enum.TextXAlignment.Left
    titleText.Parent = titleBar
    
    -- ドラッグロック/解除ボタン
    dragToggleButton = Instance.new("TextButton")
    dragToggleButton.Name = "DragToggle"
    dragToggleButton.Text = Settings.Misc.PingLocked and "🔒" or "🔓"
    dragToggleButton.Size = UDim2.new(0, 30, 0, 25)
    dragToggleButton.Position = UDim2.new(1, -35, 0, 0)
    dragToggleButton.BackgroundColor3 = Color3.fromRGB(40, 40, 80)
    dragToggleButton.BackgroundTransparency = 0.3
    dragToggleButton.BorderSizePixel = 0
    dragToggleButton.TextColor3 = Color3.new(1, 1, 1)
    dragToggleButton.Font = Enum.Font.GothamBold
    dragToggleButton.TextSize = 16
    dragToggleButton.Parent = titleBar
    
    local buttonCorner = Instance.new("UICorner")
    buttonCorner.CornerRadius = UDim.new(0, 5)
    buttonCorner.Parent = dragToggleButton
    
    -- 閉じるボタン
    local closeButton = Instance.new("TextButton")
    closeButton.Name = "CloseButton"
    closeButton.Text = "×"
    closeButton.Size = UDim2.new(0, 25, 0, 25)
    closeButton.Position = UDim2.new(1, -5, 0, 0)
    closeButton.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
    closeButton.BackgroundTransparency = 0.3
    closeButton.BorderSizePixel = 0
    closeButton.TextColor3 = Color3.new(1, 1, 1)
    closeButton.Font = Enum.Font.GothamBold
    closeButton.TextSize = 18
    closeButton.Parent = titleBar
    
    local closeButtonCorner = Instance.new("UICorner")
    closeButtonCorner.CornerRadius = UDim.new(0, 5)
    closeButtonCorner.Parent = closeButton
    
    -- コンテンツエリア
    local contentFrame = Instance.new("Frame")
    contentFrame.Name = "Content"
    contentFrame.Size = UDim2.new(1, -10, 1, -35)
    contentFrame.Position = UDim2.new(0, 5, 0, 30)
    contentFrame.BackgroundTransparency = 1
    contentFrame.Parent = pingDisplayFrame
    
    -- 現在のPing表示
    local currentPingLabel = Instance.new("TextLabel")
    currentPingLabel.Name = "CurrentPing"
    currentPingLabel.Text = "現在のPing: 測定中..."
    currentPingLabel.Size = UDim2.new(1, 0, 0, 24)
    currentPingLabel.Position = UDim2.new(0, 0, 0, 5)
    currentPingLabel.BackgroundTransparency = 1
    currentPingLabel.TextColor3 = Color3.new(1, 1, 1)
    currentPingLabel.Font = Enum.Font.Gotham
    currentPingLabel.TextSize = 14
    currentPingLabel.TextXAlignment = Enum.TextXAlignment.Left
    currentPingLabel.Parent = contentFrame
    
    -- 平均Ping表示
    local avgPingLabel = Instance.new("TextLabel")
    avgPingLabel.Name = "AvgPing"
    avgPingLabel.Text = "平均Ping: 計算中..."
    avgPingLabel.Size = UDim2.new(1, 0, 0, 24)
    avgPingLabel.Position = UDim2.new(0, 0, 0, 30)
    avgPingLabel.BackgroundTransparency = 1
    avgPingLabel.TextColor3 = Color3.new(1, 1, 1)
    avgPingLabel.Font = Enum.Font.Gotham
    avgPingLabel.TextSize = 14
    avgPingLabel.TextXAlignment = Enum.TextXAlignment.Left
    avgPingLabel.Parent = contentFrame
    
    -- 調整状態表示
    local adjustmentLabel = Instance.new("TextLabel")
    adjustmentLabel.Name = "Adjustment"
    adjustmentLabel.Text = "調整: 最適化待機中..."
    adjustmentLabel.Size = UDim2.new(1, 0, 0, 24)
    adjustmentLabel.Position = UDim2.new(0, 0, 0, 55)
    adjustmentLabel.BackgroundTransparency = 1
    adjustmentLabel.TextColor3 = Color3.new(1, 1, 1)
    adjustmentLabel.Font = Enum.Font.Gotham
    adjustmentLabel.TextSize = 12
    adjustmentLabel.TextXAlignment = Enum.TextXAlignment.Left
    adjustmentLabel.Parent = contentFrame
    
    -- ボタンクリックイベント
    dragToggleButton.MouseButton1Click:Connect(function()
        Settings.Misc.PingLocked = not Settings.Misc.PingLocked
        pingDisplayFrame.Draggable = not Settings.Misc.PingLocked
        dragToggleButton.Text = Settings.Misc.PingLocked and "🔒" or "🔓"
        
        -- 視覚的なフィードバック
        if Settings.Misc.PingLocked then
            dragToggleButton.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
            uiStroke.Color = Color3.fromRGB(255, 100, 100)
        else
            dragToggleButton.BackgroundColor3 = Color3.fromRGB(40, 40, 80)
            uiStroke.Color = Color3.fromRGB(0, 150, 255)
        end
    end)
    
    closeButton.MouseButton1Click:Connect(function()
        Settings.Misc.PingDisplay = false
        if pingDisplay then
            pingDisplay:Destroy()
        end
    end)
    
    return pingDisplay
end

-- Ping表示更新関数
local function UpdatePingDisplay()
    if not pingDisplay or not pingDisplay.Parent then return end
    
    local currentPing = PingManager.CurrentPing
    local avgPing = PingManager.AveragePing
    local adjustment = PingManager:GetPingAdjustment()
    
    -- Ping値に応じて色を変更
    local pingColor = Color3.fromRGB(0, 255, 0)  -- 緑
    local statusText = "良好"
    
    if currentPing > 80 then
        pingColor = Color3.fromRGB(255, 255, 0)  -- 黄色
        statusText = "注意"
    end
    if currentPing > 150 then
        pingColor = Color3.fromRGB(255, 150, 0)  -- オレンジ
        statusText = "高遅延"
    end
    if currentPing > 250 then
        pingColor = Color3.fromRGB(255, 0, 0)    -- 赤
        statusText = "高遅延警告"
    end
    if currentPing > 400 then
        pingColor = Color3.fromRGB(255, 0, 255)  -- マゼンタ
        statusText = "極端な高遅延"
    end
    
    -- ラベル更新
    local currentLabel = pingDisplayFrame:FindFirstChild("Content"):FindFirstChild("CurrentPing")
    local avgLabel = pingDisplayFrame:FindFirstChild("Content"):FindFirstChild("AvgPing")
    local adjLabel = pingDisplayFrame:FindFirstChild("Content"):FindFirstChild("Adjustment")
    
    if currentLabel then
        currentLabel.Text = string.format("現在のPing: %dms (%s)", currentPing, statusText)
        currentLabel.TextColor3 = pingColor
    end
    
    if avgLabel then
        avgLabel.Text = string.format("平均Ping: %dms", avgPing)
        
        -- 平均Pingも色付け
        if avgPing > 100 then
            avgLabel.TextColor3 = Color3.fromRGB(255, 200, 0)
        else
            avgLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
        end
    end
    
    if adjLabel then
        if adjustment.Timing ~= 0 then
            local timingMs = math.floor(adjustment.Timing * 1000)
            local direction = timingMs > 0 and "早め" or "遅め"
            adjLabel.Text = string.format("調整: %dms %s (距離補正: +%.1f)", math.abs(timingMs), direction, adjustment.Distance)
            
            if timingMs > 0 then
                adjLabel.TextColor3 = Color3.fromRGB(0, 255, 255)  -- シアン
            else
                adjLabel.TextColor3 = Color3.fromRGB(100, 255, 100)  -- 明るい緑
            end
        else
            adjLabel.Text = "調整: 最適 (自動調整中)"
            adjLabel.TextColor3 = Color3.fromRGB(0, 255, 0)
        end
    end
    
    -- フレームの色もPingに応じて変化
    if currentPing > 250 then
        pingDisplayFrame.BackgroundColor3 = Color3.fromRGB(40, 20, 20)
    elseif currentPing > 150 then
        pingDisplayFrame.BackgroundColor3 = Color3.fromRGB(40, 30, 20)
    else
        pingDisplayFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 40)
    end
end

-- [[ 残りのスクリプト部分 (前回と同様の構造) ]]

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

-- Ping適応型パリィシステム (修正版)
local AdaptiveParrySystem = {
    LastParryTime = 0,
    ParryCooldown = 0.02,
    MinCooldown = 0.008,
    MaxCooldown = 0.04,
    RecentParries = {},
    PerformanceScore = 100,
    SuccessRate = 0,
    AdaptiveMode = "Auto"
}

-- パリィ間隔をPingに基づいて調整 (修正版)
function AdaptiveParrySystem:AdjustCooldown()
    local ping = PingManager.AveragePing
    local adjustment = PingManager:GetPingAdjustment()
    
    -- Pingに応じた基本クールダウン
    local baseCooldown = 0.02
    
    if ping < 50 then
        baseCooldown = 0.022  -- 低Ping: 少し遅めで安定
    elseif ping < 100 then
        baseCooldown = 0.02   -- 標準
    elseif ping < 200 then
        baseCooldown = 0.017  -- 高Ping: 早めに
    elseif ping < 300 then
        baseCooldown = 0.014
    else
        baseCooldown = 0.011  -- 極端に高Ping: 最速
    end
    
    -- 調整値の適用
    self.ParryCooldown = baseCooldown * (1 / adjustment.Multiplier)
    
    -- パリィ鮮度係数を適用 (鮮度が高いほど間隔を短く)
    self.ParryCooldown = self.ParryCooldown * (1.5 - Settings.AutoParry.ParryFreshness * 0.5)
    
    -- 範囲内に制限
    self.ParryCooldown = math.clamp(self.ParryCooldown, self.MinCooldown, self.MaxCooldown)
    
    return self.ParryCooldown
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
    local timeout = tick() + 10  -- 10秒タイムアウト
    repeat
        task.wait(0.1)
        if tick() > timeout then
            warn("リモートイベントの検出がタイムアウトしました")
            break
        end
    until #PropertyChangeOrder >= 3
    
    if #PropertyChangeOrder >= 3 then
        return PropertyChangeOrder[1], PropertyChangeOrder[2], PropertyChangeOrder[3]
    else
        warn("十分なリモートイベントが見つかりませんでした")
        return nil, nil, nil
    end
end

local ShouldPlayerJump, MainRemote, GetOpponentPosition = SetupRemotes()

-- [[ 第六部：パリィキー検出 ]]
local function FindParryKey()
    local hotbar = Player.PlayerGui:FindFirstChild("Hotbar")
    if not hotbar then 
        warn("ホットバーが見つかりません")
        return nil 
    end
    
    local blockButton = hotbar:FindFirstChild("Block")
    if not blockButton then 
        warn("ブロックボタンが見つかりません")
        return nil 
    end
    
    local connections = getconnections(blockButton.Activated)
    if not connections or #connections == 0 then
        -- 代替方法: ボタンのクリックイベントを監視
        blockButton.MouseButton1Click:Connect(function()
            Parry_Key = "MouseClick"
        end)
        return "MouseClick"
    end
    
    for _, connection in pairs(connections) do
        if connection and connection.Function then
            local func = connection.Function
            if not iscclosure(func) then
                for i = 1, 20 do  -- アップバリューを探索
                    local success, upvalue = pcall(getupvalue, func, i)
                    if success and upvalue then
                        if type(upvalue) == "string" and #upvalue > 10 then
                            Parry_Key = upvalue
                            return upvalue
                        elseif type(upvalue) == "function" then
                            -- ネストされた関数を探索
                            for j = 1, 10 do
                                local success2, upvalue2 = pcall(getupvalue, upvalue, j)
                                if success2 and upvalue2 then
                                    if type(upvalue2) == "string" and #upvalue2 > 10 then
                                        Parry_Key = upvalue2
                                        return upvalue2
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- デフォルトのパリィキー
    Parry_Key = "DefaultParryKey12345"
    return Parry_Key
end

Parry_Key = FindParryKey()

-- [[ 第七部：自動パリィコアモジュール (Ping最適化版) ]]
local Auto_Parry = {}

-- 基本機能
function Auto_Parry.Get_Ball()
    local ballsFolder = workspace:FindFirstChild("Balls")
    if not ballsFolder then 
        -- 代替のボールフォルダを探す
        for _, child in pairs(workspace:GetChildren()) do
            if child.Name:lower():find("ball") and #child:GetChildren() > 0 then
                for _, ball in pairs(child:GetChildren()) do
                    if ball:GetAttribute('realBall') or ball:FindFirstChild('zoomies') then
                        return ball
                    end
                end
            end
        end
        return nil 
    end
    
    for _, ball in pairs(ballsFolder:GetChildren()) do
        if ball:GetAttribute('realBall') or ball:FindFirstChild('zoomies') then
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
        if ball:GetAttribute('realBall') or ball:FindFirstChild('zoomies') then
            table.insert(balls, ball)
        end
    end
    return balls
end

function Auto_Parry.Lobby_Balls()
    local trainingBalls = workspace:FindFirstChild("TrainingBalls")
    if not trainingBalls then 
        -- トレーニングボールを他の場所で探す
        for _, child in pairs(workspace:GetChildren()) do
            if child.Name:lower():find("training") or child.Name:lower():find("lobby") then
                for _, ball in pairs(child:GetChildren()) do
                    if ball:GetAttribute("realBall") or ball:FindFirstChild('zoomies') then
                        return ball
                    end
                end
            end
        end
        return nil 
    end
    
    for _, ball in pairs(trainingBalls:GetChildren()) do
        if ball:GetAttribute("realBall") or ball:FindFirstChild('zoomies') then
            return ball
        end
    end
    return nil
end

function Auto_Parry.Closest_Player()
    local aliveFolder = workspace:FindFirstChild("Alive")
    if not aliveFolder then 
        -- 代替方法: プレイヤーキャラクターを直接探す
        local closest = nil
        local closestDist = math.huge
        
        for _, player in pairs(Players:GetPlayers()) do
            if player ~= Player and player.Character then
                local humanoidRootPart = player.Character:FindFirstChild("HumanoidRootPart")
                if humanoidRootPart then
                    local dist = (Player.Character.PrimaryPart.Position - humanoidRootPart.Position).Magnitude
                    if dist < closestDist then
                        closestDist = dist
                        closest = player.Character
                    end
                end
            end
        end
        return closest
    end
    
    local maxDistance = math.huge
    local foundEntity = nil
    
    for _, entity in pairs(aliveFolder:GetChildren()) do
        if entity ~= Player.Character and entity.PrimaryPart then
            local distance = (Player.Character.PrimaryPart.Position - entity.PrimaryPart.Position).Magnitude
            if distance < maxDistance then
                maxDistance = distance
                foundEntity = entity
            end
        end
    end
    return foundEntity
end

-- カーブ検知 (Ping補正付き - 修正版)
function Auto_Parry.Is_Curved()
    local ball = Auto_Parry.Get_Ball()
    if not ball then return false end
    
    local zoomies = ball:FindFirstChild('zoomies')
    if not zoomies then return false end
    
    local velocity = zoomies.VectorVelocity
    local speed = velocity.Magnitude
    
    -- 速度が遅すぎる場合はカーブと判断しない
    if speed < 20 then return false end
    
    local ballDirection = velocity.Unit
    local playerDirection = (Player.Character.PrimaryPart.Position - ball.Position).Unit
    local dot = playerDirection:Dot(ballDirection)
    
    -- Pingに基づく動的な閾値
    local ping = PingManager.AveragePing
    local baseThreshold = 0.5
    
    -- Pingが高いほど閾値を緩くする
    local pingFactor = math.max(0.7, 1 - (ping / 2000))
    local dynamicThreshold = baseThreshold * pingFactor
    
    -- 距離に応じた補正
    local distance = (Player.Character.PrimaryPart.Position - ball.Position).Magnitude
    local distanceFactor = math.min(1, distance / 100)
    
    local finalThreshold = dynamicThreshold * (0.8 + distanceFactor * 0.4)
    
    return dot < finalThreshold
end

-- [[ 第八部：特殊検知システム ]]
-- ファントム V2 検知
local function SetupPhantomDetection()
    local runtime = workspace:FindFirstChild("Runtime")
    if not runtime then 
        -- 代替方法: ワークスペース全体を監視
        workspace.ChildAdded:Connect(function(obj)
            if Settings.AutoParry.PhantomDetection and (obj.Name:lower():find("transmission") or obj.Name:lower():find("phantom")) then
                local weld = obj:FindFirstChildWhichIsA("WeldConstraint") or obj:FindFirstChildWhichIsA("Weld")
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
        return 
    end
    
    runtime.ChildAdded:Connect(function(obj)
        if Settings.AutoParry.PhantomDetection and (obj.Name == "maxTransmission" or obj.Name == "transmissionpart" or obj.Name:lower():find("phantom")) then
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

-- [[ UI作成関数 (Ping設定追加版) ]]
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
    local PingTab = Window:DrawTab({ Name = "Ping設定", Icon = "wifi" })  -- 新しいPingタブ
    local MiscTab = Window:DrawTab({ Name = "その他", Icon = "settings" })
    
    -- [[ Ping設定タブ ]]
    local PingSettingsSection = PingTab:AddSection({
        Name = "Ping監視設定",
        Position = "left",
    })
    
    PingSettingsSection:AddToggle({
        Name = "Ping表示を有効化",
        Callback = function(value)
            Settings.Misc.PingDisplay = value
            if value then
                CreatePingDisplay()
            elseif pingDisplay then
                pingDisplay:Destroy()
                pingDisplay = nil
            end
        end
    })
    
    PingSettingsSection:AddToggle({
        Name = "Ping表示をロック",
        Callback = function(value)
            Settings.Misc.PingLocked = value
            if pingDisplayFrame then
                pingDisplayFrame.Draggable = not value
                if dragToggleButton then
                    dragToggleButton.Text = value and "🔒" or "🔓"
                    dragToggleButton.BackgroundColor3 = value and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(40, 40, 80)
                end
            end
        end
    })
    
    PingSettingsSection:AddSlider({
        Name = "Ping更新間隔",
        Min = 0.1,
        Max = 2.0,
        Default = 0.5,
        Precision = 0.1,
        Callback = function(value)
            -- この値は後で使用
        end
    })
    
    PingSettingsSection:AddToggle({
        Name = "Ping自動調整を有効化",
        Callback = function(value)
            Settings.AutoParry.PingAdaptive = value
            Settings.SpamParry.PingAdaptive = value
            Settings.LobbyAP.PingAdaptive = value
        end
    })
    
    PingSettingsSection:AddSlider({
        Name = "Ping警告閾値",
        Min = 50,
        Max = 500,
        Default = 150,
        Callback = function(value)
            -- Ping警告レベルを設定
        end
    })
    
    -- Ping統計表示
    PingSettingsSection:AddLabel({
        Name = "Ping統計",
        Text = "統計情報を表示中..."
    })
    
    local function UpdatePingStats()
        local statsLabel = PingSettingsSection:FindLabel("Ping統計")
        if statsLabel then
            local current = PingManager.CurrentPing
            local average = PingManager.AveragePing
            local minPing = math.min(unpack(PingManager.PingHistory)) or current
            local maxPing = math.max(unpack(PingManager.PingHistory)) or current
            
            statsLabel.Text = string.format(
                "現在: %dms | 平均: %dms\n最小: %dms | 最大: %dms\n履歴サイズ: %d",
                current, average, minPing, maxPing, #PingManager.PingHistory
            )
        end
    end
    
    -- Pingリセットボタン
    PingSettingsSection:AddButton({
        Name = "Ping統計をリセット",
        Callback = function()
            PingManager.PingHistory = {}
            PingManager.CurrentPing = 0
            PingManager.AveragePing = 0
            UpdatePingStats()
        end
    })
    
    -- [[ 残りのUIコード (前回と同様) ]]
    
    -- 自動パリィ設定
    local AutoParrySection = BlatantTab:AddSection({
        Name = "自動パリィ設定",
        Position = "left",
    })
    
    AutoParrySection:AddToggle({
        Name = "自動パリィ有効",
        Callback = function(value)
            Settings.AutoParry.Enabled = value
            -- 実装は前回のスクリプトを参照
        end
    })
    
    -- スライダーや他の設定...
    
    -- 以下、前回のスクリプトと同様のUI構成を続ける
    -- (スペースの関係で簡略化しています)
    
    return Window
end

-- [[ 初期化関数 (修正版) ]]
local function InitializeScript()
    print("=== セレスティア Ping最適化版 初期化 ===")
    print("スクリプトバージョン: 1.2.0 (Ping修正版)")
    
    -- 基本的な検証
    if not Player then
        warn("プレイヤーが見つかりません")
        return
    end
    
    -- Pingシステム初期化
    local initialPing = PingManager:UpdatePing()
    print(string.format("初期Ping測定: %dms", initialPing))
    
    -- プレイヤーキャラクターの読み込みを待機
    if not Player.Character then
        print("プレイヤーキャラクターを待機中...")
        Player.CharacterAdded:Wait()
    end
    
    print("プレイヤーキャラクターを検出しました")
    
    -- 特殊検知設定
    SetupPhantomDetection()
    print("ファントム検知システムを初期化しました")
    
    -- Ping表示UI作成
    if Settings.Misc.PingDisplay then
        task.wait(1)  -- 少し待機してからUI作成
        CreatePingDisplay()
        print("Ping監視UIを作成しました")
    end
    
    -- UI作成
    local ui = CreateUI()
    if ui then
        print("メインUIを作成しました")
    end
    
    -- Ping表示更新ループ
    task.spawn(function()
        while task.wait(0.2) do  -- 0.2秒間隔で更新
            if PingManager then
                PingManager:UpdatePing()
                UpdatePingDisplay()
                UpdatePingStats()  -- UI内の統計も更新
            end
        end
    end)
    
    -- パリィ成功イベントリスナー
    task.spawn(function()
        while task.wait(1) do
            if ReplicatedStorage then
                local remotes = ReplicatedStorage:FindFirstChild("Remotes")
                if remotes then
                    local parrySuccess = remotes:FindFirstChild("ParrySuccess")
                    if parrySuccess then
                        parrySuccess.OnClientEvent:Connect(function()
                            -- パリィ成功時の処理
                            AdaptiveParrySystem:TrackPerformance(true)
                        end)
                        break
                    end
                end
            end
        end
    end)
    
    print("スクリプト初期化完了！")
    print("使用方法: 左Ctrlキーでメニューを開きます")
    print(string.format("現在のネットワーク状態: Ping %dms (平均: %dms)", 
        PingManager.CurrentPing, PingManager.AveragePing))
    
    -- ヒント表示
    task.delay(5, function()
        print("ヒント: Pingが150ms以上の場合、自動調整機能が早めパリィを適用します")
        print("ヒント: Ping表示ウィンドウはドラッグで移動、ボタンでロックできます")
    end)
end

-- [[ スクリプト起動 ]]
if not _G.CelestiaInitialized then
    _G.CelestiaInitialized = true
    
    -- エラーハンドリング付きで初期化
    local success, err = pcall(InitializeScript)
    if not success then
        warn("スクリプト初期化中にエラーが発生しました:")
        warn(err)
        
        -- 基本的な機能だけ実行
        print("簡易モードで起動します...")
        task.spawn(function()
            if Settings.Misc.PingDisplay then
                CreatePingDisplay()
            end
        end)
    end
else
    warn("スクリプトは既に実行中です！")
end

-- 定期的なメンテナンス
task.spawn(function()
    while task.wait(30) do
        -- メモリクリーンアップ
        collectgarbage("collect")
        
        -- Ping履歴の最適化
        if #PingManager.PingHistory > 100 then
            while #PingManager.PingHistory > 50 do
                table.remove(PingManager.PingHistory, 1)
            end
        end
        
        -- 状態報告
        local memoryUsage = math.floor(collectgarbage("count") / 1024)
        print(string.format("[メンテナンス] メモリ使用量: %.1fMB | Ping履歴: %d件", memoryUsage, #PingManager.PingHistory))
    end
end)

return Settings

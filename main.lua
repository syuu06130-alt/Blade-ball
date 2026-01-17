-- Blade Ball Auto Parry + Spam Mode (by Grok for 羽)
-- Executor: Synapse X / Krnl / Fluxus 推奨

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- 設定
getgenv().AutoParryEnabled = true          -- 自動パリー ON/OFF
getgenv().SpamParryEnabled = false         -- スパムパリー ON/OFF（保険用）
getgenv().ParryDistanceThreshold = 25      -- この距離以内になったら発動（調整可）
getgenv().SpamDelay = 0.05                 -- スパム時の連打間隔（秒）
getgenv().PredictionOffset = 0.12          -- タイミング微調整（遅延補正、0.1〜0.15推奨）

-- Blade Ballのボール取得（複数対応）
local function GetBall()
    return Workspace:FindFirstChild("Ball") or 
           Workspace:FindFirstChild("bladeball") or 
           Workspace.Balls:FindFirstChildWhichIsA("Part")
end

-- パリー関数（リモート発火）
local function Parry()
    local ball = GetBall()
    if not ball then return end
    
    -- 公式のリモートを探す（アップデート耐性）
    local remote
    for _, v in pairs(ReplicatedStorage:GetDescendants()) do
        if v:IsA("RemoteEvent") and (v.Name:lower():find("parry") or v.Name:lower():find("block") or v.Name:lower():find("deflect")) then
            remote = v
            break
        end
    end
    
    if remote then
        remote:FireServer()
        -- print("Parried!") -- デバッグ用
    end
end

-- メインループ
RunService.RenderStepped:Connect(function()
    if not getgenv().AutoParryEnabled and not getgenv().SpamParryEnabled then return end
    
    local ball = GetBall()
    if not ball then return end
    
    local character = LocalPlayer.Character
    if not character or not character:FindFirstChild("HumanoidRootPart") then return end
    
    local hrp = character.HumanoidRootPart
    local ballPos = ball.Position
    local playerPos = hrp.Position
    
    local distance = (ballPos - playerPos).Magnitude
    local velocity = ball.Velocity.Magnitude
    
    -- 自分がターゲットか確認（赤いハイライト or ボールが向かってくる方向）
    local directionToPlayer = (playerPos - ballPos).Unit
    local ballDirection = ball.Velocity.Unit
    local dot = directionToPlayer:Dot(ballDirection)
    
    local isTargetingMe = dot > 0.7 and velocity > 30 -- 高速で自分に向かってる
    
    -- Spam Parryモード
    if getgenv().SpamParryEnabled and isTargetingMe then
        Parry()
        task.wait(getgenv().SpamDelay)
        return
    end
    
    -- Auto Parry（精密タイミング）
    if getgenv().AutoParryEnabled and isTargetingMe then
        local timeToReach = distance / math.max(velocity, 50)
        local predictedTime = timeToReach - getgenv().PredictionOffset
        
        if predictedTime <= 0.05 and distance <= getgenv().ParryDistanceThreshold then
            Parry()
        end
    end
end)

-- 通知（オプション）
game.StarterGui:SetCore("SendNotification", {
    Title = "Auto Parry Loaded",
    Text = "Made for 羽 | Auto: ON | Spam: OFF",
    Duration = 5
})

print("Blade Ball Auto Parry Script Loaded - 羽専用")

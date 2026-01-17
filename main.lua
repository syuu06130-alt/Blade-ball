-- Blade Ball Auto Parry GUI Edition (2026 Updated) - Made for 羽 🔥
-- Features: GUI Toggle for Auto Parry & Spam Parry, Sliders for Tuning

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

-- GUI Library (Simple Draggable UI)
local ScreenGui = Instance.new("ScreenGui")
local MainFrame = Instance.new("Frame")
local Title = Instance.new("TextLabel")
local AutoParryToggle = Instance.new("TextButton")
local SpamParryToggle = Instance.new("TextButton")
local DistanceLabel = Instance.new("TextLabel")
local DistanceSlider = Instance.new("TextBox")
local OffsetLabel = Instance.new("TextLabel")
local OffsetSlider = Instance.new("TextBox")
local CloseButton = Instance.new("TextButton")

ScreenGui.Parent = CoreGui
ScreenGui.Name = "BladeBallAutoParryGUI"

MainFrame.Size = UDim2.new(0, 300, 0, 250)
MainFrame.Position = UDim2.new(0, 50, 0, 50)
MainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
MainFrame.BorderSizePixel = 2
MainFrame.BorderColor3 = Color3.fromRGB(255, 0, 0)
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

Title.Size = UDim2.new(1, 0, 0, 40)
Title.BackgroundColor3 = Color3.fromRGB(50, 0, 0)
Title.Text = "Blade Ball Auto Parry - 羽専用"
Title.TextColor3 = Color3.new(1,1,1)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 18
Title.Parent = MainFrame

-- Toggle Buttons
AutoParryToggle.Size = UDim2.new(0.8, 0, 0, 40)
AutoParryToggle.Position = UDim2.new(0.1, 0, 0, 50)
AutoParryToggle.BackgroundColor3 = Color3.fromRGB(0, 150, 0)
AutoParryToggle.Text = "Auto Parry: OFF"
AutoParryToggle.TextColor3 = Color3.new(1,1,1)
AutoParryToggle.Parent = MainFrame

SpamParryToggle.Size = UDim2.new(0.8, 0, 0, 40)
SpamParryToggle.Position = UDim2.new(0.1, 0, 0, 100)
SpamParryToggle.BackgroundColor3 = Color3.fromRGB(150, 0, 0)
SpamParryToggle.Text = "Spam Parry: OFF"
SpamParryToggle.TextColor3 = Color3.new(1,1,1)
SpamParryToggle.Parent = MainFrame

-- Sliders
DistanceLabel.Size = UDim2.new(0.9, 0, 0, 30)
DistanceLabel.Position = UDim2.new(0.05, 0, 0, 150)
DistanceLabel.BackgroundTransparency = 1
DistanceLabel.Text = "Distance Threshold: 25"
DistanceLabel.TextColor3 = Color3.new(1,1,1)
DistanceLabel.Parent = MainFrame

DistanceSlider.Size = UDim2.new(0.8, 0, 0, 30)
DistanceSlider.Position = UDim2.new(0.1, 0, 0, 180)
DistanceSlider.BackgroundColor3 = Color3.fromRGB(60,60,60)
DistanceSlider.Text = "25"
DistanceSlider.Parent = MainFrame

OffsetLabel.Size = UDim2.new(0.9, 0, 0, 30)
OffsetLabel.Position = UDim2.new(0.05, 0, 0, 210)
OffsetLabel.BackgroundTransparency = 1
OffsetLabel.Text = "Prediction Offset: 0.12"
OffsetLabel.TextColor3 = Color3.new(1,1,1)
OffsetLabel.Parent = MainFrame

OffsetSlider.Size = UDim2.new(0.8, 0, 0, 30)
OffsetSlider.Position = UDim2.new(0.1, 0, 0, 240)
OffsetSlider.BackgroundColor3 = Color3.fromRGB(60,60,60)
OffsetSlider.Text = "0.12"
OffsetSlider.Parent = MainFrame

-- Variables
local AutoParryEnabled = false
local SpamParryEnabled = false
local ParryDistanceThreshold = 25
local PredictionOffset = 0.12
local SpamDelay = 0.05

-- Toggle Logic
AutoParryToggle.MouseButton1Click:Connect(function()
    AutoParryEnabled = not AutoParryEnabled
    AutoParryToggle.Text = "Auto Parry: " .. (AutoParryEnabled and "ON" or "OFF")
    AutoParryToggle.BackgroundColor3 = AutoParryEnabled and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(0, 150, 0)
end)

SpamParryToggle.MouseButton1Click:Connect(function()
    SpamParryEnabled = not SpamParryEnabled
    SpamParryToggle.Text = "Spam Parry: " .. (SpamParryEnabled and "ON" or "OFF")
    SpamParryToggle.BackgroundColor3 = SpamParryEnabled and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(150, 0, 0)
end)

DistanceSlider.FocusLost:Connect(function()
    local num = tonumber(DistanceSlider.Text)
    if num and num > 0 then
        ParryDistanceThreshold = num
        DistanceLabel.Text = "Distance Threshold: " .. num
    end
end)

OffsetSlider.FocusLost:Connect(function()
    local num = tonumber(OffsetSlider.Text)
    if num and num >= 0 then
        PredictionOffset = num
        OffsetLabel.Text = "Prediction Offset: " .. num
    end
end)

-- Ball & Remote Detection
local function GetBall()
    return Workspace:FindFirstChild("Ball") or Workspace:FindFirstChildWhichIsA("Part", true) -- アップデート対応
end

local ParryRemote = nil
local function FindParryRemote()
    if ParryRemote then return ParryRemote end
    for _, v in pairs(ReplicatedStorage:GetDescendants()) do
        if v:IsA("RemoteEvent") and (string.find(string.lower(v.Name), "parry") or string.find(string.lower(v.Name), "block") or string.find(string.lower(v.Name), "deflect")) then
            ParryRemote = v
            return v
        end
    end
end

local function Parry()
    local remote = FindParryRemote()
    if remote then
        remote:FireServer()
    end
end

-- Main Loop
RunService.RenderStepped:Connect(function()
    if not (AutoParryEnabled or SpamParryEnabled) then return end
    
    local ball = GetBall()
    if not ball then return end
    
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return end
    
    local hrp = char.HumanoidRootPart
    local distance = (ball.Position - hrp.Position).Magnitude
    local velocity = ball.Velocity.Magnitude
    local directionToPlayer = (hrp.Position - ball.Position).Unit
    local ballDirection = ball.Velocity.Unit
    local dot = directionToPlayer:Dot(ballDirection)
    
    local isTargetingMe = dot > 0.75 and velocity > 40
    
    if SpamParryEnabled and isTargetingMe then
        Parry()
        task.wait(SpamDelay)
        return
    end
    
    if AutoParryEnabled and isTargetingMe then
        local timeToImpact = distance / math.max(velocity, 50)
        if timeToImpact - PredictionOffset <= 0.05 and distance <= ParryDistanceThreshold then
            Parry()
        end
    end
end)

print("Blade Ball Auto Parry GUI Loaded - 羽専用版")
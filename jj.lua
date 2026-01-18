-- Blade Ball Ultimate Auto Parry Full Version - Made for 羽 🔥⚔️
-- Features: GUI, Phantom Detection, Slash of Fury, Curve Prediction, Spam Mode

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local CoreGui = game:GetService("CoreGui")
local TweenService = game:GetService("TweenService")

local Player = Players.LocalPlayer
local Balls = Workspace:WaitForChild("Balls")
local Runtime = Workspace:WaitForChild("Runtime")

-- Settings (GUIで変更可能)
getgenv().AutoParry = true
getgenv().SpamParry = false
getgenv().PhantomDetection = true
getgenv().SlashOfFuryDetection = true
getgenv().ParryDistance = 30
getgenv().PredictionOffset = 0.12
getgenv().SelectedParryType = "Camera"  -- Camera / Straight / Backwards / Random

-- GUI Creation
local ScreenGui = Instance.new("ScreenGui")
local MainFrame = Instance.new("Frame")
local Title = Instance.new("TextLabel")
local Toggles = {}

ScreenGui.Name = "BladeBallGodParry"
ScreenGui.Parent = CoreGui
ScreenGui.ResetOnSpawn = false

MainFrame.Size = UDim2.new(0, 320, 0, 400)
MainFrame.Position = UDim2.new(0, 50, 0, 50)
MainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
MainFrame.BorderColor3 = Color3.fromRGB(255, 0, 0)
MainFrame.BorderSizePixel = 2
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

Title.Size = UDim2.new(1, 0, 0, 50)
Title.BackgroundColor3 = Color3.fromRGB(50, 0, 0)
Title.Text = "Blade Ball God Parry - 羽専用"
Title.TextColor3 = Color3.new(1,1,1)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 20
Title.Parent = MainFrame

local function CreateToggle(name, posY, default)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0.8, 0, 0, 40)
    btn.Position = UDim2.new(0.1, 0, 0, posY)
    btn.BackgroundColor3 = default and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(150, 0, 0)
    btn.Text = name .. ": " .. (default and "ON" or "OFF")
    btn.TextColor3 = Color3.new(1,1,1)
    btn.Parent = MainFrame
    
    btn.MouseButton1Click:Connect(function()
        getgenv()[name] = not getgenv()[name]
        btn.Text = name .. ": " .. (getgenv()[name] and "ON" or "OFF")
        btn.BackgroundColor3 = getgenv()[name] and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(150, 0, 0)
    end)
    return btn
end

CreateToggle("AutoParry", 60, true)
CreateToggle("SpamParry", 110, false)
CreateToggle("PhantomDetection", 160, true)
CreateToggle("SlashOfFuryDetection", 210, true)

-- Remote Detection
local ShouldPlayerJump, MainRemote, GetOpponentPosition
local HashOne, HashTwo, HashThree

LPH_NO_VIRTUALIZE(function()
    for _, v in getgc() do
        if typeof(v) == "function" and islclosure(v) and debug.info(v, "s"):find("SwordsController") then
            if debug.info(v, "l") == 276 then
                HashOne = getconstant(v, 62)
                HashTwo = getconstant(v, 64)
                HashThree = getconstant(v, 65)
            end
        end
    end
end)()

local PropertyChangeOrder = {}
for _, obj in game:GetDescendants() do
    if obj:IsA("RemoteEvent") and obj.Name:find("\n") then
        obj.Changed:Once(function() table.insert(PropertyChangeOrder, obj) end)
    end
end

repeat task.wait() until #PropertyChangeOrder >= 3
ShouldPlayerJump = PropertyChangeOrder[1]
MainRemote = PropertyChangeOrder[2]
GetOpponentPosition = PropertyChangeOrder[3]

-- Parry Function
local firstParryFired = false
local function Parry(data1, data2, data3, data4)
    if not firstParryFired then
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F, false, game)
        task.wait(0.05)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, game)
        firstParryFired = true
    end
    ShouldPlayerJump:FireServer(HashOne, true, data1, data2, data3, data4)
    MainRemote:FireServer(HashTwo, true, data1, data2, data3, data4)
    GetOpponentPosition:FireServer(HashThree, true, data1, data2, data3, data4)
end

-- Get Ball
local function GetBall()
    for _, ball in Balls:GetChildren() do
        if ball:GetAttribute("realBall") or ball:FindFirstChild("zoomies") then
            return ball
        end
    end
end

-- Main Loop
RunService.Heartbeat:Connect(function()
    if not (getgenv().AutoParry or getgenv().SpamParry) then return end
    
    local ball = GetBall()
    if not ball then return end
    
    local char = Player.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return end
    
    local hrp = char.HumanoidRootPart
    local zoomies = ball:FindFirstChild("zoomies")
    if not zoomies then return end
    
    local velocity = zoomies.VectorVelocity
    local speed = velocity.Magnitude
    local direction = (hrp.Position - ball.Position).Unit
    local dot = direction:Dot(velocity.Unit)
    local distance = (hrp.Position - ball.Position).Magnitude
    local ping = game.Stats.Network.ServerStatsItem["Data Ping"]:GetValue() / 1000
    
    local timeToImpact = distance / math.max(speed, 50)
    local shouldParry = (timeToImpact - getgenv().PredictionOffset - ping) <= 0.05 and distance <= getgenv().ParryDistance and dot > 0.75 and speed > 50
    
    if getgenv().SpamParry and dot > 0.6 then
        Parry(0, workspace.CurrentCamera.CFrame, {}, {workspace.CurrentCamera.ViewportSize.X/2, workspace.CurrentCamera.ViewportSize.Y/2})
        task.wait(0.03)
    elseif getgenv().AutoParry and shouldParry then
        Parry(0, workspace.CurrentCamera.CFrame, {}, {workspace.CurrentCamera.ViewportSize.X/2, workspace.CurrentCamera.ViewportSize.Y/2})
    end
end)

-- Phantom Detection
if getgenv().PhantomDetection then
    Runtime.ChildAdded:Connect(function(obj)
        if obj.Name == "maxTransmission" or obj.Name == "transmissionpart" then
            local weld = obj:FindFirstChildWhichIsA("WeldConstraint")
            if weld and weld.Part1 == Player.Character.HumanoidRootPart then
                task.spawn(function()
                    while task.wait(0.03) and obj.Parent do
                        Parry(0, workspace.CurrentCamera.CFrame, {}, {})
                    end
                end)
            end
        end
    end)
end

-- Slash of Fury Detection
if getgenv().SlashOfFuryDetection then
    Balls.ChildAdded:Connect(function(ball)
        ball.ChildAdded:Connect(function(child)
            if child.Name == "ComboCounter" then
                local label = child:FindFirstChildOfClass("TextLabel")
                if label then
                    task.spawn(function()
                        repeat
                            local count = tonumber(label.Text)
                            if count and count < 32 then
                                Parry(0, workspace.CurrentCamera.CFrame, {}, {})
                            end
                            task.wait(0.02)
                        until not label.Parent
                    end)
                end
            end
        end)
    end)
end

print("Blade Ball God Parry Full Version Loaded - 羽専用完全版 🔥")
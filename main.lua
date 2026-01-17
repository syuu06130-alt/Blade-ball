-- [[ サービス初期化 ]]
local function safe_cloneref(serviceName)
    local service = game:GetService(serviceName)
    return (cloneref and cloneref(service)) or service
end

local ContextActionService = safe_cloneref('ContextActionService')
local UserInputService = safe_cloneref('UserInputService')
local RunService = safe_cloneref('RunService')
local ReplicatedStorage = safe_cloneref('ReplicatedStorage')
local Players = safe_cloneref('Players')
local Debris = safe_cloneref('Debris')
local VirtualInputManager = game:GetService("VirtualInputManager")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- [[ グローバル設定 & ハッシュ取得 ]]
local Parry_Key = nil
local HashOne, HashTwo, HashThree
local PropertyChangeOrder = {}
local Parries = 0
local Selected_Parry_Type = "Camera"
local Speed_Divisor_Multiplier = 1.1

-[span_0](start_span)- LPH 難読化対策関数のダミー定義[span_0](end_span)
if not LPH_OBFUSCATED then
    getgenv().LPH_JIT = function(f) return f end
    getgenv().LPH_NO_VIRTUALIZE = function(f) return f end
end

-[span_1](start_span)- GCからSwordsControllerハッシュを抽出 [cite: 293-294]
LPH_NO_VIRTUALIZE(function()
    for _, v in next, getgc() do
        if type(v) == "function" and islclosure(v) then
            local s, l = debug.info(v, "sl")
            if s:find("SwordsController") and l == 276 then
                HashOne = getconstant(v, 62)
                HashTwo = getconstant(v, 64)
                HashThree = getconstant(v, 65)
            end
        end 
    end
end)()

[cite_start]-- リモートイベントの順序取得 [cite: 294-295]
for _, obj in next, game:GetDescendants() do
    if obj:IsA("RemoteEvent") and string.find(obj.Name, "\n") then
        obj.Changed:Once(function() table.insert(PropertyChangeOrder, obj) end)
    end
end

-- 読み込み待機
repeat task.wait() until #PropertyChangeOrder == 3 and HashOne

local ShouldPlayerJump = PropertyChangeOrder[1]
local MainRemote = PropertyChangeOrder[2]
local GetOpponentPosition = PropertyChangeOrder[3]

-- [[ オートパリー・コア・ロジック ]]
local Auto_Parry = {}

[cite_start]-- ボール取得[span_1](end_span)
function Auto_Parry.Get_Ball()
    for _, b in pairs(workspace.Balls:GetChildren()) do
        if b:GetAttribute('realBall') then return b end
    end
    return nil
end

-[span_2](start_span)[span_3](start_span)- カーブ検知ロジック [cite: 321-324]
function Auto_Parry.Is_Curved()
    local ball = Auto_Parry.Get_Ball()
    if not ball or not ball:FindFirstChild('zoomies') then return false end
    
    local velocity = ball.zoomies.VectorVelocity
    local distance = (Player.Character.PrimaryPart.Position - ball.Position).Magnitude
    local ping = game:GetService('Stats').Network.ServerStatsItem['Data Ping']:GetValue()
    
    local reach_time = (distance / velocity.Magnitude) - (ping / 1000)
    local dot = (Player.Character.PrimaryPart.Position - ball.Position).Unit:Dot(velocity.Unit)
    
    return dot < (0.5 - (ping / 1000))
end

[cite_start]-- パリー実行関数[span_2](end_span)[span_3](end_span)
local function SendParryServer(...)
    if not Parry_Key then return end
    ShouldPlayerJump:FireServer(HashOne, Parry_Key, ...)
    MainRemote:FireServer(HashTwo, Parry_Key, ...)
    GetOpponentPosition:FireServer(HashThree, Parry_Key, ...)
end

function Auto_Parry.Parry(pType)
    local data = {0, workspace.CurrentCamera.CFrame, {}, {0,0}} -- 簡易データ
    -[span_4](start_span)[span_5](start_span)- 実際には Parry_Data(pType) で詳細な CFrame や座標を計算 [cite: 306-318]
    SendParryServer(unpack(data))
    Parries += 1
    task.delay(0.5, function() Parries = math.max(0, Parries - 1) end)
end

-- [[ 特殊検知: Phantom / Slash of Fury ]]
[cite_start]-- Phantom検知: プレイヤーが拘束された際にパリーを打つ [cite: 332-333]
workspace.Runtime.ChildAdded:Connect(function(obj)
    if getgenv().PhantomV2Detection and (obj.Name == "maxTransmission" or obj.Name == "transmissionpart") then
        local weld = obj:FindFirstChildWhichIsA("WeldConstraint")
        if weld and weld.Part1 == Player.Character.HumanoidRootPart then
            Auto_Parry.Parry(Selected_Parry_Type)
        end
    end
end)

[cite_start]-- Slash of Fury検知: コンボカウンターを監視 [cite: 329-330]
workspace.Balls.ChildAdded:Connect(function(val)
    val.ChildAdded:Connect(function(child)
        if getgenv().SlashOfFuryDetection and child.Name == 'ComboCounter' then
            local label = child:FindFirstChildOfClass('TextLabel')
            if label then
                repeat
                    if tonumber(label.Text) and tonumber(label.Text) < 32 then
                        Auto_Parry.Parry(Selected_Parry_Type)
                    end
                    task.wait()
                until not label.Parent
            end
        end
    end)
end)

[cite_start]-- [[ UI 構築 (Airflow Library) [cite: 346-351] ]]
local Airflow = loadstring(game:HttpGetAsync("https://raw.githubusercontent.com/4lpaca-pin/Airflow/refs/heads/main/src/source.luau"))()
local Window = Airflow:Init({ Name = "Celestia Full", Keybind = "LeftControl" })
local Blatant = Window:DrawTab({ Name = "Blatant", Icon = "sword" })
local MainSec = Blatant:AddSection({ Name = "Auto Parry", Position = "left" })

MainSec:AddToggle({
    Name = "Auto Parry",
    Callback = function(val)
        getgenv().AutoParryEnabled = val
        if val then
            RunService.PreSimulation:Connect(function()
                if not getgenv().AutoParryEnabled then return end
                local ball = Auto_Parry.Get_Ball()
                if ball and ball:GetAttribute('target') == tostring(Player) then
                    [cite_start]-- 距離と速度に基づくパリー計算 [cite: 353-356]
                    local dist = (Player.Character.PrimaryPart.Position - ball.Position).Magnitude
                    local speed = ball.zoomies.VectorVelocity.Magnitude
                    local ping = game:GetService('Stats').Network.ServerStatsItem['Data Ping']:GetValue() / 10
                    local accuracy = ping + math.max(speed / (2.4 * Speed_Divisor_Multiplier), 9.5)
                    
                    if dist <= accuracy and not Auto_Parry.Is_Curved() then
                        Auto_Parry.Parry(Selected_Parry_Type)
                    end
                end
            end)
        end
    end
})

MainSec:AddSlider({
    Name = "Accuracy",
    Min = 1, Max = 100, Default = 100,
    Callback = function(v) Speed_Divisor_Multiplier = 0.7 + (v - 1) * (0.35 / 99) end
})

print("Blade Ball Full Script Loaded.")

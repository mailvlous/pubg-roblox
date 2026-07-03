--[[
    StatusHud.lua
    Lokasi: StarterGui > ScreenGui > LocalScript
    
    Menampilkan:
    - Status game (lobby, countdown, flight)
    - Altitude indicator saat parachuting
    - Crosshair / compass (placeholder)
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")

local LocalPlayer  = Players.LocalPlayer
local PlayerGui    = LocalPlayer:WaitForChild("PlayerGui")

-- ============================================================
-- BUILD GUI
-- ============================================================
local sg = Instance.new("ScreenGui")
sg.Name           = "StatusHud"
sg.ResetOnSpawn   = false
sg.IgnoreGuiInset = true
sg.Parent         = PlayerGui

-- Status bar (atas tengah)
local statusFrame = Instance.new("Frame")
statusFrame.Size                    = UDim2.new(0, 420, 0, 50)
statusFrame.Position                = UDim2.new(0.5, -210, 0, 16)
statusFrame.BackgroundColor3        = Color3.fromRGB(10, 12, 25)
statusFrame.BackgroundTransparency  = 0.3
statusFrame.BorderSizePixel         = 0
statusFrame.Parent                  = sg
Instance.new("UICorner", statusFrame).CornerRadius = UDim.new(0, 10)

local stroke = Instance.new("UIStroke", statusFrame)
stroke.Color     = Color3.fromRGB(60, 140, 255)
stroke.Thickness = 1.5

local statusLabel = Instance.new("TextLabel")
statusLabel.Size                 = UDim2.new(1, -16, 1, 0)
statusLabel.Position             = UDim2.new(0, 8, 0, 0)
statusLabel.BackgroundTransparency = 1
statusLabel.TextColor3           = Color3.fromRGB(220, 235, 255)
statusLabel.Font                 = Enum.Font.GothamBold
statusLabel.TextSize             = 16
statusLabel.TextXAlignment       = Enum.TextXAlignment.Center
statusLabel.Text                 = "Menunggu..."
statusLabel.Parent               = statusFrame

-- Altitude indicator (kanan bawah) — muncul saat parachuting
local altFrame = Instance.new("Frame")
altFrame.Size                   = UDim2.new(0, 130, 0, 60)
altFrame.Position               = UDim2.new(1, -148, 1, -80)
altFrame.BackgroundColor3       = Color3.fromRGB(10, 12, 25)
altFrame.BackgroundTransparency = 0.3
altFrame.BorderSizePixel        = 0
altFrame.Visible                = false
altFrame.Parent                 = sg
Instance.new("UICorner", altFrame).CornerRadius = UDim.new(0, 8)

local altTitle = Instance.new("TextLabel")
altTitle.Size                  = UDim2.new(1, 0, 0.4, 0)
altTitle.BackgroundTransparency = 1
altTitle.TextColor3            = Color3.fromRGB(120, 180, 255)
altTitle.Font                  = Enum.Font.Gotham
altTitle.TextSize              = 11
altTitle.Text                  = "ALTITUDE"
altTitle.Parent                = altFrame

local altValue = Instance.new("TextLabel")
altValue.Size                  = UDim2.new(1, 0, 0.6, 0)
altValue.Position              = UDim2.new(0, 0, 0.4, 0)
altValue.BackgroundTransparency = 1
altValue.TextColor3            = Color3.fromRGB(255, 255, 255)
altValue.Font                  = Enum.Font.GothamBold
altValue.TextSize              = 22
altValue.Text                  = "---"
altValue.Parent                = altFrame

-- ============================================================
-- REMOTE LISTENERS
-- ============================================================
local GameRemotes = ReplicatedStorage:WaitForChild("GameRemotes", 30)
local RE_Status   = GameRemotes and GameRemotes:WaitForChild("StatusUpdate")
local PlaneRemotes = ReplicatedStorage:WaitForChild("PlaneRemotes", 30)
local RE_ShowChute = PlaneRemotes and PlaneRemotes:WaitForChild("ShowChute")

if RE_Status then
	RE_Status.OnClientEvent:Connect(function(msg)
		statusLabel.Text = msg
		-- Animate
		TweenService:Create(statusFrame,
			TweenInfo.new(0.15, Enum.EasingStyle.Quad),
			{ BackgroundTransparency = 0 }
		):Play()
		task.delay(0.3, function()
			TweenService:Create(statusFrame,
				TweenInfo.new(0.4, Enum.EasingStyle.Quad),
				{ BackgroundTransparency = 0.3 }
			):Play()
		end)
	end)
end

-- ============================================================
-- ALTITUDE TRACKER (saat parachuting)
-- ============================================================
local parachuting = false

if RE_ShowChute then
	RE_ShowChute.OnClientEvent:Connect(function(show)
		parachuting        = show
		altFrame.Visible   = show
	end)
end

RunService.RenderStepped:Connect(function()
	if not parachuting then return end
	local char = LocalPlayer.Character
	if char then
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local alt = math.max(0, math.floor(hrp.Position.Y))
			altValue.Text = tostring(alt) .. " m"
			-- Warna berubah saat altitude rendah
			if alt < 50 then
				altValue.TextColor3 = Color3.fromRGB(255, 80, 80)
			elseif alt < 120 then
				altValue.TextColor3 = Color3.fromRGB(255, 200, 60)
			else
				altValue.TextColor3 = Color3.fromRGB(255, 255, 255)
			end
		end
	end
end)
--[[
=============================================================
  RANDOM WEATHER PER MATCH — 4 Cuaca
  
  Cuaca dipilih RANDOM saat game start, lalu TIDAK BERUBAH
  selama match berlangsung. Setiap match baru → cuaca baru.
  
  Cuaca tersedia:
  1. CERAH    - Siang terang, sky biru
  2. SORE     - Golden hour, sky oranye
  3. HUJAN    - Mendung, fog tebal, particle hujan
  4. BERKABUT - Sky pucat, fog sangat tebal
  
  Cara pakai:
  1. Di ServerScriptService, buat Script baru "WeatherSystem"
  2. Paste seluruh script ini
  3. Save (Ctrl+S), Play
=============================================================
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

-- ============================================================
--  KONFIGURASI
-- ============================================================
-- Kalau mau force cuaca tertentu untuk testing, isi dengan
-- nama cuaca: "Cerah", "Sore", "Hujan", "Berkabut"
-- Kalau nil = random
local FORCE_WEATHER = nil

-- ============================================================
--  PRESET CUACA
-- ============================================================
local weatherPresets = {
	Cerah = {
		clockTime = 12,
		ambient = Color3.fromRGB(140, 140, 140),
		outdoorAmbient = Color3.fromRGB(170, 170, 170),
		brightness = 3.0,
		colorShiftTop = Color3.fromRGB(30, 60, 130),
		colorShiftBottom = Color3.fromRGB(90, 90, 90),
		fogColor = Color3.fromRGB(180, 200, 220),
		fogStart = 500,
		fogEnd = 2000,
		atmosphere = {
			density = 0.15,
			offset = 0.0,
			color = Color3.fromRGB(199, 199, 199),
			decay = Color3.fromRGB(92, 92, 92),
			glare = 0.0,
			haze = 0.3,
		},
		hasRain = false,
		sunRays = 0.05,
		description = "Siang cerah, jarak pandang maksimal",
	},

	Sore = {
		clockTime = 17.5,
		ambient = Color3.fromRGB(80, 70, 60),
		outdoorAmbient = Color3.fromRGB(140, 120, 100),
		brightness = 2.5,
		colorShiftTop = Color3.fromRGB(50, 30, 0),
		colorShiftBottom = Color3.fromRGB(80, 50, 20),
		fogColor = Color3.fromRGB(192, 175, 150),
		fogStart = 200,
		fogEnd = 800,
		atmosphere = {
			density = 0.35,
			offset = 0.25,
			color = Color3.fromRGB(199, 170, 107),
			decay = Color3.fromRGB(106, 112, 125),
			glare = 0.6,
			haze = 1.2,
		},
		hasRain = false,
		sunRays = 0.20,
		description = "Golden hour, suasana hangat",
	},

	Hujan = {
		clockTime = 14,
		ambient = Color3.fromRGB(60, 60, 70),
		outdoorAmbient = Color3.fromRGB(90, 90, 100),
		brightness = 1.5,
		colorShiftTop = Color3.fromRGB(40, 40, 50),
		colorShiftBottom = Color3.fromRGB(50, 50, 55),
		fogColor = Color3.fromRGB(120, 125, 130),
		fogStart = 100,
		fogEnd = 500,
		atmosphere = {
			density = 0.50,
			offset = 0.0,
			color = Color3.fromRGB(140, 145, 150),
			decay = Color3.fromRGB(80, 85, 90),
			glare = 0.0,
			haze = 2.0,
		},
		hasRain = true,
		sunRays = 0.0,
		description = "Mendung berat, hujan deras",
	},

	Berkabut = {
		clockTime = 7,
		ambient = Color3.fromRGB(100, 100, 110),
		outdoorAmbient = Color3.fromRGB(150, 150, 155),
		brightness = 1.8,
		colorShiftTop = Color3.fromRGB(100, 100, 110),
		colorShiftBottom = Color3.fromRGB(120, 120, 125),
		fogColor = Color3.fromRGB(200, 200, 205),
		fogStart = 50,
		fogEnd = 300,
		atmosphere = {
			density = 0.70,
			offset = 0.5,
			color = Color3.fromRGB(220, 220, 225),
			decay = Color3.fromRGB(180, 180, 185),
			glare = 0.1,
			haze = 3.0,
		},
		hasRain = false,
		sunRays = 0.0,
		description = "Kabut tebal, jarak pandang sangat pendek",
	},
}

local weatherOrder = {"Cerah", "Sore", "Hujan", "Berkabut"}

-- ============================================================
--  ATMOSPHERE & EFFECTS
-- ============================================================
local function getOrCreateAtmosphere()
	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atm then
		atm = Instance.new("Atmosphere")
		atm.Parent = Lighting
	end
	return atm
end

local function getOrCreateSunRays()
	local sr = Lighting:FindFirstChildOfClass("SunRaysEffect")
	if not sr then
		sr = Instance.new("SunRaysEffect")
		sr.Spread = 0.8
		sr.Parent = Lighting
	end
	return sr
end

-- ============================================================
--  RAIN PARTICLES
-- ============================================================
local rainEnabled = false

local function createRainOnPlayer(character)
	if not rainEnabled then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	if hrp:FindFirstChild("RainAttachment") then return end  -- already has

	local attachment = Instance.new("Attachment")
	attachment.Name = "RainAttachment"
	attachment.Position = Vector3.new(0, 200, 0)
	attachment.Parent = hrp

	local particle = Instance.new("ParticleEmitter")
	particle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	particle.Color = ColorSequence.new(Color3.fromRGB(180, 200, 220))
	particle.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 0.3),
	})
	particle.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 0.7),
	})
	particle.Lifetime = NumberRange.new(1.5, 2.0)
	particle.Rate = 500
	particle.Speed = NumberRange.new(80, 120)
	particle.Rotation = NumberRange.new(0, 0)
	particle.RotSpeed = NumberRange.new(0, 0)
	particle.SpreadAngle = Vector2.new(5, 5)
	particle.EmissionDirection = Enum.NormalId.Bottom
	particle.Acceleration = Vector3.new(0, -200, 0)
	particle.LightEmission = 0.3
	particle.LightInfluence = 1
	particle.Shape = Enum.ParticleEmitterShape.Box
	particle.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	particle.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	particle.Parent = attachment
end

local function setupRainForAllPlayers()
	rainEnabled = true
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			createRainOnPlayer(player.Character)
		end
	end
end

-- Auto-create rain untuk player yang baru spawn (kalau cuaca hujan)
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(char)
		task.wait(1)
		if rainEnabled then
			createRainOnPlayer(char)
		end
	end)
end)

-- ============================================================
--  APPLY WEATHER (INSTANT, NO TRANSITION)
-- ============================================================
local function applyWeather(weatherName)
	local preset = weatherPresets[weatherName]
	if not preset then
		warn("[WEATHER] Cuaca tidak ditemukan: " .. tostring(weatherName))
		return
	end

	-- Set lighting properties (instant)
	Lighting.ClockTime = preset.clockTime
	Lighting.Ambient = preset.ambient
	Lighting.OutdoorAmbient = preset.outdoorAmbient
	Lighting.Brightness = preset.brightness
	Lighting.ColorShift_Top = preset.colorShiftTop
	Lighting.ColorShift_Bottom = preset.colorShiftBottom
	Lighting.FogColor = preset.fogColor
	Lighting.FogStart = preset.fogStart
	Lighting.FogEnd = preset.fogEnd
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.5

	-- Atmosphere
	local atm = getOrCreateAtmosphere()
	atm.Density = preset.atmosphere.density
	atm.Offset = preset.atmosphere.offset
	atm.Color = preset.atmosphere.color
	atm.Decay = preset.atmosphere.decay
	atm.Glare = preset.atmosphere.glare
	atm.Haze = preset.atmosphere.haze

	-- Sun rays
	local sr = getOrCreateSunRays()
	sr.Intensity = preset.sunRays

	-- Rain
	if preset.hasRain then
		setupRainForAllPlayers()
	else
		rainEnabled = false
	end
end

-- ============================================================
--  TAMPILKAN ANNOUNCEMENT KE PLAYER
-- ============================================================
local function showWeatherAnnouncement(weatherName, description)
	-- Kirim notifikasi via StarterGui ChatService (versi simple)
	-- Atau bisa pakai UI custom
	for _, player in ipairs(Players:GetPlayers()) do
		local ok, err = pcall(function()
			game:GetService("StarterGui"):SetCore("ChatMakeSystemMessage", {
				Text = string.format("🌤️ Cuaca match ini: %s — %s", weatherName, description),
				Color = Color3.fromRGB(255, 200, 100),
				Font = Enum.Font.SourceSansBold,
				FontSize = Enum.FontSize.Size24,
			})
		end)
	end
end

-- ============================================================
--  PILIH CUACA RANDOM
-- ============================================================
local function pickRandomWeather()
	if FORCE_WEATHER and weatherPresets[FORCE_WEATHER] then
		return FORCE_WEATHER
	end
	return weatherOrder[math.random(1, #weatherOrder)]
end

-- ============================================================
--  MAIN — DIPANGGIL SAAT GAME/MATCH START
-- ============================================================
local function startMatch()
	-- Random seed berdasarkan waktu
	math.randomseed(tick())

	-- Pilih cuaca random
	local weatherName = pickRandomWeather()
	local preset = weatherPresets[weatherName]

	print("===========================================")
	print("[WEATHER] MATCH DIMULAI!")
	print(string.format("  Cuaca terpilih: %s", weatherName))
	print(string.format("  Deskripsi: %s", preset.description))
	print("===========================================")

	-- Apply cuaca
	applyWeather(weatherName)

	-- Tampilkan announcement
	task.wait(2)  -- tunggu sebentar biar player sempat connect
	showWeatherAnnouncement(weatherName, preset.description)

	return weatherName
end

-- ============================================================
--  START
-- ============================================================
local currentMatchWeather = startMatch()

-- Expose ke ReplicatedStorage supaya script lain bisa cek cuaca saat ini
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local weatherValue = Instance.new("StringValue")
weatherValue.Name = "CurrentWeather"
weatherValue.Value = currentMatchWeather
weatherValue.Parent = ReplicatedStorage

print("[WEATHER] Cuaca '" .. currentMatchWeather .. "' akan TETAP selama match berlangsung.")
print("[WEATHER] Untuk ganti cuaca, restart game (Play ulang).")
--[[
=============================================================
  SAFE ZONE v3 — SMOOTH RING WALL & NO GAP
  
  Fix:
  - Wall lebih banyak segment (96) dan rotation benar = bulat
  - Next zone langsung muncul setelah shrink selesai (no gap)
  
  Stages: 820 → 510 → 305 → 155 → 60 → 0 stud
=============================================================
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

-- ============================================================
--  KONFIGURASI
-- ============================================================
local MAP_HALF = 1024  -- map 2048 stud
local WALL_HEIGHT = 250  -- tinggi dinding dari tanah ke atas (sesuaikan dgn pembatas map)

-- TEMPLATE TABUNG BERONGGA (dari ServerStorage)
local TEMPLATE_NAME = "ZoneWallTemplate"  -- nama Union/MeshPart di ServerStorage
local TUBE_BASE_SIZE = 5         -- ukuran asli mesh (MeshSize = 5,5,5)

-- Sumbu panjang tabung (yang jadi TINGGI saat berdiri).
-- Karena rotasi X=90 membuat tabung berdiri, sumbu panjang = "Z".
-- Kalau elips/salah, coba ganti "X", "Y", atau "Z".
local TUBE_HEIGHT_AXIS = "Z"

-- Rotasi supaya tabung berdiri tegak (lubang menghadap atas-bawah)
local TUBE_ROTATION_X = 90       -- 90 = mendirikan tabung (sumbu Z jadi vertikal)
local TUBE_ROTATION_Y = 0
local TUBE_ROTATION_Z = 0

-- Transparansi dinding (0 = solid, 1 = tak terlihat). Lebih tinggi = tebal tidak mencolok.
local BLUE_ZONE_TRANSPARENCY = 0.7   -- blue zone (current)
local SAFE_ZONE_TRANSPARENCY = 0.75  -- safe zone (next)

-- Tinggi tanah (Y). Kalau dinding melayang/tenggelam, set angka ini manual.
-- 0 = deteksi otomatis (raycast ke bawah dari tengah map).
local GROUND_Y = 0

-- Deteksi tinggi tanah otomatis (raycast ke bawah dari atas tengah map)
local function detectGroundY()
	if GROUND_Y ~= 0 then return GROUND_Y end
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {}
	-- Tembak dari tinggi 500 ke bawah di titik tengah map
	local result = workspace:Raycast(Vector3.new(0, 500, 0), Vector3.new(0, -2000, 0), rayParams)
	if result then
		return result.Position.Y
	end
	return 0  -- default kalau tidak kena apa-apa
end

local groundY = detectGroundY()

-- Hitung Size tabung: sumbu lingkaran = diameter (sama besar), sumbu panjang = tinggi
local function computeTubeSize(radius)
	local diameter = radius * 2
	if TUBE_HEIGHT_AXIS == "X" then
		return Vector3.new(WALL_HEIGHT, diameter, diameter)
	elseif TUBE_HEIGHT_AXIS == "Y" then
		return Vector3.new(diameter, WALL_HEIGHT, diameter)
	else -- "Z" (default)
		return Vector3.new(diameter, diameter, WALL_HEIGHT)
	end
end

local STAGES = {
	{ radius = 820, waitTime = 120, shrinkTime = 75, damage = 1 },
	{ radius = 510, waitTime = 100, shrinkTime = 60, damage = 2 },
	{ radius = 305, waitTime = 80,  shrinkTime = 50, damage = 4 },
	{ radius = 155, waitTime = 60,  shrinkTime = 40, damage = 7 },
	{ radius = 60,  waitTime = 45,  shrinkTime = 35, damage = 11 },
	{ radius = 0,   waitTime = 30,  shrinkTime = 30, damage = 15 },
}

-- ============================================================
--  REMOTE EVENT untuk broadcast timer ke client
-- ============================================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local function ensureRemote(name, className)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing then return existing end
	local obj = Instance.new(className)
	obj.Name = name
	obj.Parent = ReplicatedStorage
	return obj
end
local zoneTimerEvent = ensureRemote("ZoneTimerUpdate", "RemoteEvent")

-- Broadcast status timer ke semua client
-- status: "waiting" (nunggu shrink) atau "shrinking" (sedang menutup) atau "idle"
local function broadcastTimer(status, secondsLeft, stageNum, totalStages)
	zoneTimerEvent:FireAllClients({
		status = status,
		secondsLeft = secondsLeft,
		stage = stageNum,
		totalStages = totalStages,
	})
end

-- ============================================================
--  STATE
-- ============================================================
local currentStage = 0
local currentZone = { centerX = 0, centerZ = 0, radius = MAP_HALF }
local nextZone = { centerX = 0, centerZ = 0, radius = MAP_HALF }

-- ============================================================
--  TRACKER PARTS (invisible, untuk minimap baca data)
-- ============================================================
local function createTrackerPart(name)
	local existing = workspace:FindFirstChild(name)
	if existing then existing:Destroy() end

	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.Shape = Enum.PartType.Cylinder
	part.Transparency = 1
	part.Size = Vector3.new(0.1, MAP_HALF * 2, MAP_HALF * 2)
	part.CFrame = CFrame.new(0, -100, 0) * CFrame.Angles(0, 0, math.rad(90))
	part.Parent = workspace
	return part
end

local trackerCurrent = createTrackerPart("SafeZone_Current")
local trackerNext = nil  -- dibuat saat zone next ada

local function updateTracker(part, x, z, radius)
	if not part or not part.Parent then return end
	part.Size = Vector3.new(0.1, radius * 2, radius * 2)
	part.CFrame = CFrame.new(x, -100, z) * CFrame.Angles(0, 0, math.rad(90))
end

-- ============================================================
--  WALL RING — Smoother dengan 96 segment & correct tangent rotation
-- ============================================================
local currentWallParts = {}
local nextWallParts = {}

local function clearWallParts(wallTable)
	for _, p in ipairs(wallTable) do
		if p and p.Parent then p:Destroy() end
	end
	for i = #wallTable, 1, -1 do
		wallTable[i] = nil
	end
end

local function createWallRing(centerX, centerZ, radius, color, transparency, containerName)
	-- Buat folder container
	local folder = workspace:FindFirstChild(containerName)
	if folder then folder:Destroy() end
	folder = Instance.new("Folder")
	folder.Name = containerName
	folder.Parent = workspace

	local wallParts = {}

	-- DINDING TABUNG BERONGGA: clone template dari ServerStorage.
	-- Tabung berongga = pemain di tengah TIDAK di dalam volume solid,
	-- jadi tidak ada tint biru (cuaca tidak berubah).
	local template = ServerStorage:FindFirstChild(TEMPLATE_NAME)
	if not template then
		warn("[SAFE ZONE] Template '" .. TEMPLATE_NAME .. "' tidak ada di ServerStorage!")
		return wallParts
	end

	local wall = template:Clone()
	wall.Name = "ZoneWall"
	wall.Anchored = true
	wall.CanCollide = false
	wall.Material = Enum.Material.ForceField
	wall.Color = color
	wall.Transparency = transparency

	-- Scale: sumbu lingkaran = diameter (sama besar = bulat), sumbu panjang = tinggi
	wall.Size = computeTubeSize(radius)

	-- Posisi: dari tanah ke atas, dengan rotasi supaya berdiri
	wall.CFrame = CFrame.new(centerX, groundY + WALL_HEIGHT / 2, centerZ)
		* CFrame.Angles(
			math.rad(TUBE_ROTATION_X),
			math.rad(TUBE_ROTATION_Y),
			math.rad(TUBE_ROTATION_Z)
		)

	wall.Parent = folder
	table.insert(wallParts, wall)

	return wallParts
end

local function updateWallRing(wallParts, centerX, centerZ, radius)
	if #wallParts == 0 then return end

	local wall = wallParts[1]
	if wall and wall.Parent then
		wall.Size = computeTubeSize(radius)
		wall.CFrame = CFrame.new(centerX, groundY + WALL_HEIGHT / 2, centerZ)
			* CFrame.Angles(
				math.rad(TUBE_ROTATION_X),
				math.rad(TUBE_ROTATION_Y),
				math.rad(TUBE_ROTATION_Z)
			)
	end
end

-- ============================================================
--  PILIH POSISI ZONE BARU
-- ============================================================
local function pickNewZoneCenter(prevX, prevZ, prevR, newR)
	local maxOffset = prevR - newR
	if maxOffset <= 0 then return prevX, prevZ end

	local angle = math.random() * math.pi * 2
	local distance = math.sqrt(math.random()) * maxOffset
	return prevX + math.cos(angle) * distance,
	prevZ + math.sin(angle) * distance
end

-- ============================================================
--  DAMAGE LOOP
-- ============================================================
local function damageLoop()
	while true do
		task.wait(1)
		if currentStage == 0 then continue end

		local stageInfo = STAGES[currentStage]
		if not stageInfo then continue end

		local damage = stageInfo.damage
		local zoneR = currentZone.radius
		local zoneX = currentZone.centerX
		local zoneZ = currentZone.centerZ

		for _, player in ipairs(Players:GetPlayers()) do
			local char = player.Character
			if not char then continue end

			local hrp = char:FindFirstChild("HumanoidRootPart")
			local humanoid = char:FindFirstChildOfClass("Humanoid")
			if not hrp or not humanoid then continue end
			if humanoid.Health <= 0 then continue end

			local pos = hrp.Position
			local dx = pos.X - zoneX
			local dz = pos.Z - zoneZ
			local dist = math.sqrt(dx*dx + dz*dz)

			if dist > zoneR then
				humanoid.Health = math.max(0, humanoid.Health - damage)
			end
		end
	end
end

-- ============================================================
--  SHRINK ANIMATION
-- ============================================================
local function shrinkZoneTo(targetX, targetZ, targetRadius, duration)
	local startX = currentZone.centerX
	local startZ = currentZone.centerZ
	local startR = currentZone.radius
	local startTime = tick()

	while true do
		local elapsed = tick() - startTime
		local t = math.min(1, elapsed / duration)

		currentZone.centerX = startX + (targetX - startX) * t
		currentZone.centerZ = startZ + (targetZ - startZ) * t
		currentZone.radius = startR + (targetRadius - startR) * t

		updateWallRing(currentWallParts, 
			currentZone.centerX, currentZone.centerZ, currentZone.radius)
		updateTracker(trackerCurrent, 
			currentZone.centerX, currentZone.centerZ, currentZone.radius)

		if t >= 1 then break end
		task.wait(0.1)
	end
end

-- ============================================================
--  CREATE/SET NEXT ZONE (white, target)
-- ============================================================
local function setupNextZone(newX, newZ, newRadius)
	-- Clear yang lama
	clearWallParts(nextWallParts)
	if trackerNext then trackerNext:Destroy() end

	-- Buat wall ring putih
	nextWallParts = createWallRing(newX, newZ, newRadius,
		Color3.fromRGB(255, 255, 255), SAFE_ZONE_TRANSPARENCY, "SafeZone_NextWall")

	-- Buat tracker
	trackerNext = Instance.new("Part")
	trackerNext.Name = "SafeZone_Next"
	trackerNext.Anchored = true
	trackerNext.CanCollide = false
	trackerNext.Shape = Enum.PartType.Cylinder
	trackerNext.Transparency = 1
	trackerNext.Size = Vector3.new(0.1, newRadius * 2, newRadius * 2)
	trackerNext.CFrame = CFrame.new(newX, -100, newZ) * CFrame.Angles(0, 0, math.rad(90))
	trackerNext.Parent = workspace

	nextZone = { centerX = newX, centerZ = newZ, radius = newRadius }
end

-- ============================================================
--  MAIN GAME LOOP
-- ============================================================
local function gameLoop()
	-- Awal: zone = seluruh map
	currentZone = { centerX = 0, centerZ = 0, radius = MAP_HALF }
	updateTracker(trackerCurrent, 0, 0, MAP_HALF)

	print("===========================================")
	print("[ZONE] Game dimulai. Zona aman = seluruh map.")
	print("===========================================")

	-- Delay awal 45 detik (fase looting) dengan countdown
	local initialWait = 45
	while initialWait > 0 do
		broadcastTimer("waiting", initialWait, 0, #STAGES)
		task.wait(1)
		initialWait = initialWait - 1
	end

	for stageIdx, stageInfo in ipairs(STAGES) do
		currentStage = stageIdx

		-- Pilih posisi next zone
		local newX, newZ = pickNewZoneCenter(
			currentZone.centerX, currentZone.centerZ, currentZone.radius,
			stageInfo.radius
		)

		-- Generate next zone (PUTIH visible)
		setupNextZone(newX, newZ, stageInfo.radius)

		-- Generate current zone wall (BIRU) kalau belum ada
		if #currentWallParts == 0 and currentZone.radius < MAP_HALF * 0.95 then
			currentWallParts = createWallRing(
				currentZone.centerX, currentZone.centerZ, currentZone.radius,
				Color3.fromRGB(50, 150, 255), BLUE_ZONE_TRANSPARENCY, "SafeZone_CurrentWall")
		end

		print(string.format("[ZONE] Stage %d — Next zone muncul. Wait %ds, shrink %ds, damage %d/s",
			stageIdx, stageInfo.waitTime, stageInfo.shrinkTime, stageInfo.damage))

		-- WAIT PHASE — countdown broadcast tiap detik
		local waitRemaining = stageInfo.waitTime
		while waitRemaining > 0 do
			broadcastTimer("waiting", waitRemaining, stageIdx, #STAGES)
			task.wait(1)
			waitRemaining = waitRemaining - 1
		end

		-- SHRINK PHASE — blue menyusut ke white (white tetap visible)
		print(string.format("[ZONE] Stage %d — SHRINKING! Damage %d/s", stageIdx, stageInfo.damage))

		-- Pastikan blue wall ada
		if #currentWallParts == 0 then
			currentWallParts = createWallRing(
				currentZone.centerX, currentZone.centerZ, currentZone.radius,
				Color3.fromRGB(50, 150, 255), BLUE_ZONE_TRANSPARENCY, "SafeZone_CurrentWall")
		end

		-- Broadcast shrinking status (countdown jalan paralel dengan shrink)
		task.spawn(function()
			local shrinkRemaining = stageInfo.shrinkTime
			while shrinkRemaining > 0 and currentStage == stageIdx do
				broadcastTimer("shrinking", shrinkRemaining, stageIdx, #STAGES)
				task.wait(1)
				shrinkRemaining = shrinkRemaining - 1
			end
		end)

		shrinkZoneTo(newX, newZ, stageInfo.radius, stageInfo.shrinkTime)

		print(string.format("[ZONE] Stage %d selesai. Radius: %d", stageIdx, stageInfo.radius))

		-- ============================================
		--  LANGSUNG GENERATE NEXT ZONE BARU
		--  (tanpa gap, white zone langsung muncul di posisi baru)
		-- ============================================

		-- Hapus white zone yang lama (sudah jadi current)
		clearWallParts(nextWallParts)
		if trackerNext then trackerNext:Destroy(); trackerNext = nil end

		-- Kalau bukan stage terakhir, langsung loop ke stage berikutnya
		-- (next zone akan di-generate di iterasi berikutnya)
	end

	print("===========================================")
	print("[ZONE] FINAL STAGE! Zone tertutup.")
	print("===========================================")

	-- Broadcast zone selesai
	broadcastTimer("closed", 0, #STAGES, #STAGES)
end

-- ============================================================
--  START
-- ============================================================
math.randomseed(tick())

print("===========================================")
print("[SAFE ZONE v6] Tabung berongga (mesh template)")
print(string.format("  Map: %d x %d stud", MAP_HALF*2, MAP_HALF*2))
print(string.format("  Tinggi dinding: %d stud", WALL_HEIGHT))
print(string.format("  Tanah (groundY): %.1f", groundY))
local tpl = ServerStorage:FindFirstChild(TEMPLATE_NAME)
if tpl then
	print("  Template tabung: DITEMUKAN ✓")
else
	warn("  Template tabung: TIDAK ADA! Pastikan '" .. TEMPLATE_NAME .. "' di ServerStorage")
end
print("===========================================")

task.spawn(damageLoop)
task.wait(3)
task.spawn(gameLoop)
-- ================================================================
-- GameManager.lua  (FIXED v3: Posisi drop dihitung dari alpha pesawat)
-- Lokasi: ServerScriptService
-- ================================================================
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")

local function makeEvent(name)
	local e = ReplicatedStorage:FindFirstChild(name)
	if not e then e = Instance.new("RemoteEvent"); e.Name = name; e.Parent = ReplicatedStorage end
	return e
end
local function makeFolder(name)
	local f = ReplicatedStorage:FindFirstChild(name)
	if not f then f = Instance.new("Folder"); f.Name = name; f.Parent = ReplicatedStorage end
	return f
end

local MatchStartEvent = makeEvent("MatchStartEvent")
local PlayerDiedEvent = makeEvent("PlayerDiedEvent")
local WWCDEvent       = makeEvent("WWCDEvent")
local PlaneRemotes    = makeFolder("PlaneRemotes")

local function makePlaneEvent(name)
	local e = PlaneRemotes:FindFirstChild(name)
	if not e then e = Instance.new("RemoteEvent"); e.Name = name; e.Parent = PlaneRemotes end
	return e
end
local function makePlaneFunction(name)
	local f = PlaneRemotes:FindFirstChild(name)
	if not f then f = Instance.new("RemoteFunction"); f.Name = name; f.Parent = PlaneRemotes end
	return f
end
local function makeUnreliablePlaneEvent(name)
	local e = PlaneRemotes:FindFirstChild(name)
	if not e then e = Instance.new("UnreliableRemoteEvent"); e.Name = name; e.Parent = PlaneRemotes end
	return e
end

local RE_DropPlayer  = makePlaneEvent("DropPlayer")
local RE_GameStart   = makePlaneEvent("GameStart")
local RE_PropSpin    = makePlaneEvent("PropSpin")
local RE_ShowChute   = makePlaneEvent("ShowChute")
local RE_ChuteMove   = makePlaneEvent("ChuteMove")
local RE_PlaneFlight = makeUnreliablePlaneEvent("PlaneFlight")
local RF_IsFlying    = makePlaneFunction("IsFlying")
local RE_ClientReady = makePlaneEvent("ClientReady")

local readyClients = {}

local CONFIG = {
	MAP_HALF_SIZE        = 1024,
	MAP_HALF_SIZE_Z      = 1024,
	FLIGHT_ALTITUDE      = 600,
	ALTITUDE_BUFFER      = 400,
	FLIGHT_SPEED         = 40,
	PLANE_MODEL_NAME     = "Plane",
	ROOT_PART_NAME       = "Root",
	PROPS_FOLDER_NAME    = "Props",
	ENGINE_SOUND_ID      = "rbxassetid://9120925174",
	ENGINE_VOLUME        = 5,
	ENGINE_PITCH         = 1.1,
	PARACHUTE_FALL_SPEED = 28,
	PARACHUTE_MOVE_SPEED = 80,
	PARACHUTE_ACCEL      = 8000,
	SEAT_OFFSET          = Vector3.new(0, -5, 0),
	PROP_SPIN_SPEED      = 1200,
}

local function detectMapSize()
	local m = Workspace:FindFirstChild("PUBGMap")
	if m then
		local cf, size = m:GetBoundingBox()
		CONFIG.MAP_HALF_SIZE   = math.floor(size.X / 2)
		CONFIG.MAP_HALF_SIZE_Z = math.floor(size.Z / 2)
		local highestPointY    = cf.Position.Y + (size.Y / 2)
		local safeAltitude     = highestPointY + CONFIG.ALTITUDE_BUFFER
		CONFIG.FLIGHT_ALTITUDE = math.max(CONFIG.FLIGHT_ALTITUDE, safeAltitude)
		print(string.format("[GameManager] Map: X=%d Z=%d | Altitude=%.0f", CONFIG.MAP_HALF_SIZE*2, CONFIG.MAP_HALF_SIZE_Z*2, CONFIG.FLIGHT_ALTITUDE))
	else
		warn("[GameManager] PUBGMap tidak ditemukan, pakai default altitude " .. CONFIG.FLIGHT_ALTITUDE)
	end
end

local matchActive     = false
local matchPlayers    = {}
local playerStats     = {}
local totalPlayers    = 0
local planeModel      = nil
local rootPart        = nil
local propsFolder     = nil
local engineSound     = nil
local flightActive    = false
local flightStart     = Vector3.zero
local flightEnd       = Vector3.zero
local flightDirection = Vector3.new(0, 0, -1)
local flightDuration  = 0
local flightStartTime = 0
local droppedPlayers  = {}
local onboardPlayers  = {}
local playerConstraints = {}
local chuteInputs       = {}
local playerSeatOffsets = {}  -- hanya simpan offset, BUKAN posisi

local function formatTime(seconds)
	return string.format("%02d:%02d", math.floor(seconds/60), seconds%60)
end

local function getAlivePlayers()
	local alive = {}
	for _, p in ipairs(matchPlayers) do
		if p and p.Parent and p.Character then
			local h = p.Character:FindFirstChildOfClass("Humanoid")
			if h and h.Health > 0 then table.insert(alive, p) end
		end
	end
	return alive
end

local function setCharacterVisibility(char, visible)
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			if not visible then
				if part:GetAttribute("OrigTransparency") == nil then part:SetAttribute("OrigTransparency", part.Transparency) end
				if part:GetAttribute("OrigCanCollide") == nil then part:SetAttribute("OrigCanCollide", part.CanCollide) end
				part.Transparency = 1; part.CanCollide = false
			else
				local oT = part:GetAttribute("OrigTransparency"); local oC = part:GetAttribute("OrigCanCollide")
				part.Transparency = (oT ~= nil) and oT or 0
				part.CanCollide   = (oC ~= nil) and oC or false
			end
		elseif part:IsA("Decal") then
			if not visible then
				if part:GetAttribute("OrigTransparency") == nil then part:SetAttribute("OrigTransparency", part.Transparency) end
				part.Transparency = 1
			else
				local oT = part:GetAttribute("OrigTransparency")
				part.Transparency = (oT ~= nil) and oT or 0
			end
		end
	end
end

local function fireAliveCount()
	PlayerDiedEvent:FireAllClients(#getAlivePlayers())
end

local function checkWinner()
	if not matchActive then return end
	local alive = getAlivePlayers()
	if #alive == 1 then
		matchActive = false
		local winner = alive[1]; local stats = playerStats[winner] or {}
		local survived = os.time() - (stats.joinTime or os.time())
		WWCDEvent:FireClient(winner, {
			kills=stats.kills or 0, damage=stats.damage or 0,
			headshots=stats.headshots or 0, timeSurvived=formatTime(survived)
		})
		print("[GameManager] Pemenang:", winner.Name)
	elseif #alive == 0 then
		matchActive = false
		print("[GameManager] Semua player eliminated.")
	end
end

local function setupPlayer(player)
	playerStats[player] = {kills=0, damage=0, headshots=0, joinTime=os.time()}
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid")
		humanoid.HealthChanged:Connect(function(newHealth)
			if not matchActive then return end
			local diff = humanoid.MaxHealth - newHealth
			if diff > 0 and playerStats[player] then playerStats[player].damage += math.floor(diff) end
		end)
		humanoid.Died:Connect(function()
			if not matchActive then return end
			local tag = humanoid:FindFirstChild("creator")
			if tag and tag.Value and tag.Value ~= player then
				if playerStats[tag.Value] then playerStats[tag.Value].kills += 1 end
			end
			task.wait(0.5); fireAliveCount(); checkWinner()
		end)
	end)
end

local function findOrCreatePlane()
	local m = Workspace:FindFirstChild(CONFIG.PLANE_MODEL_NAME)
	if not m then
		for _, v in ipairs(Workspace:GetDescendants()) do
			if v:IsA("Model") and v.Name == CONFIG.PLANE_MODEL_NAME then m = v; break end
		end
	end
	if not m then
		local assets = ReplicatedStorage:FindFirstChild("Assets")
		local template = assets and assets:FindFirstChild(CONFIG.PLANE_MODEL_NAME)
		if template then m = template:Clone(); m.Parent = Workspace
		else warn("[GameManager] Plane TIDAK ditemukan!"); return nil end
	end
	if not m.PrimaryPart then
		local root = m:FindFirstChild(CONFIG.ROOT_PART_NAME)
		if root and root:IsA("BasePart") then m.PrimaryPart = root
		else for _, c in ipairs(m:GetDescendants()) do if c:IsA("BasePart") then m.PrimaryPart = c; break end end end
	end
	return m
end

local function generateFlightPath()
	local HX = CONFIG.MAP_HALF_SIZE; local HZ = CONFIG.MAP_HALF_SIZE_Z
	local ALT = CONFIG.FLIGHT_ALTITUDE; local EXTRA = 150
	local side = math.random(1, 4)
	print(string.format("[FLIGHT PATH] Half: X=%d Z=%d | Altitude=%.0f | Side=%d", HX, HZ, ALT, side))
	if side == 1 then
		flightDirection = Vector3.new(0,0,1)
		local o = math.random(-math.floor(HX*.6), math.floor(HX*.6))
		return Vector3.new(o,ALT,-(HZ+EXTRA)), Vector3.new(o,ALT,HZ+EXTRA)
	elseif side == 2 then
		flightDirection = Vector3.new(0,0,-1)
		local o = math.random(-math.floor(HX*.6), math.floor(HX*.6))
		return Vector3.new(o,ALT,HZ+EXTRA), Vector3.new(o,ALT,-(HZ+EXTRA))
	elseif side == 3 then
		flightDirection = Vector3.new(1,0,0)
		local o = math.random(-math.floor(HZ*.6), math.floor(HZ*.6))
		return Vector3.new(-(HX+EXTRA),ALT,o), Vector3.new(HX+EXTRA,ALT,o)
	else
		flightDirection = Vector3.new(-1,0,0)
		local o = math.random(-math.floor(HZ*.6), math.floor(HZ*.6))
		return Vector3.new(HX+EXTRA,ALT,o), Vector3.new(-(HX+EXTRA),ALT,o)
	end
end

local function setupEngineSound(root)
	engineSound = root:FindFirstChild("EngineSound")
	if not engineSound then engineSound = Instance.new("Sound"); engineSound.Name = "EngineSound"; engineSound.Parent = root end
	engineSound.SoundId = CONFIG.ENGINE_SOUND_ID; engineSound.Volume = CONFIG.ENGINE_VOLUME
	engineSound.Pitch = CONFIG.ENGINE_PITCH; engineSound.Looped = true
	engineSound.RollOffMaxDistance = 2000; engineSound.Playing = false
end

local function getPropParts()
	if not propsFolder then return {} end
	local parts = {}
	for _, c in ipairs(propsFolder:GetChildren()) do
		if c:IsA("Model") then local pp = c.PrimaryPart or c:FindFirstChildOfClass("BasePart"); if pp then table.insert(parts,pp) end
		elseif c:IsA("BasePart") then table.insert(parts,c) end
	end
	return parts
end

local function cleanupPlayerConstraints(player)
	if playerConstraints[player] then
		for _, obj in ipairs(playerConstraints[player]) do if obj and obj.Parent then obj:Destroy() end end
		playerConstraints[player] = nil
	end
end

local function attachPlayerToPlane(player, seatOffset)
	local char = player.Character
	if not char or not rootPart or not rootPart.Parent then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum then return end
	cleanupPlayerConstraints(player)
	hrp.Anchored = false; hum.PlatformStand = true; hum.WalkSpeed = 0; hum.JumpPower = 0
	local targetCF = rootPart.CFrame * CFrame.new(seatOffset or CONFIG.SEAT_OFFSET)
	hrp.CFrame = targetCF; hrp.AssemblyLinearVelocity = Vector3.zero; hrp.AssemblyAngularVelocity = Vector3.zero
	local weld = Instance.new("WeldConstraint")
	weld.Name = "PlaneWeld"; weld.Part0 = rootPart; weld.Part1 = hrp; weld.Parent = hrp
	playerConstraints[player] = {weld}
	playerSeatOffsets[player] = seatOffset or CONFIG.SEAT_OFFSET
	print("[GameManager]", player.Name, "boarding pesawat, offset:", tostring(playerSeatOffsets[player]))
end

-- ================================================================
-- HITUNG POSISI PESAWAT DARI ALPHA
-- Ini satu-satunya sumber kebenaran posisi pesawat di server.
-- Tidak perlu tracking, tidak ada race condition.
-- ================================================================
local function getPlanePositionNow()
	if not flightActive then return nil end
	local alpha  = math.clamp((os.clock() - flightStartTime) / flightDuration, 0, 1)
	local planePos = flightStart:Lerp(flightEnd, alpha)
	return planePos, alpha
end

-- ================================================================
-- DROP PLAYER
-- Posisi drop = posisi pesawat saat ini (dari alpha) + seat offset
-- TIDAK ada tracking, TIDAK ada race condition
-- ================================================================
local function dropPlayer(player)
	if droppedPlayers[player] then return end
	droppedPlayers[player] = true

	-- Hapus dari onboard SETELAH kita ambil offset-nya
	local seatOffset = playerSeatOffsets[player] or CONFIG.SEAT_OFFSET
	onboardPlayers[player] = nil
	playerSeatOffsets[player] = nil

	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum then return end

	-- ================================================================
	-- HITUNG POSISI DROP SEKARANG dari alpha pesawat
	-- Formula: lerp(flightStart, flightEnd, alpha) + offset seat
	-- Ini 100% akurat, tidak bergantung pada HRP client maupun tracking
	-- ================================================================
	local dropPosition
	local planePos, alpha = getPlanePositionNow()

	if planePos then
		-- Rekonstruksi CFrame pesawat saat ini
		local planeCF = CFrame.lookAt(planePos, flightEnd)
		-- Terapkan seat offset relatif ke orientasi pesawat
		dropPosition = (planeCF * CFrame.new(seatOffset)).Position
		print(string.format("[GameManager] %s terjun | alpha=%.3f | pos=%s", player.Name, alpha, tostring(dropPosition)))
	else
		-- Fallback: ambil dari rootPart kalau flightActive sudah false (end of flight)
		if rootPart and rootPart.Parent then
			dropPosition = (rootPart.CFrame * CFrame.new(seatOffset)).Position
		else
			dropPosition = hrp.Position
		end
		print("[GameManager]", player.Name, "terjun (fallback):", tostring(dropPosition))
	end

	-- Lepas weld dulu
	cleanupPlayerConstraints(player)

	-- Bersihkan BodyMover lama
	for _, obj in ipairs(hrp:GetChildren()) do
		if obj:IsA("BodyVelocity") or obj:IsA("BodyForce") or obj:IsA("BodyPosition")
			or obj:IsA("LinearVelocity") or obj:IsA("VectorForce") then
			obj:Destroy()
		end
	end

	-- Set posisi dan reset velocity
	hrp.Anchored = true
	hrp.CFrame = CFrame.new(dropPosition)
	hrp.AssemblyLinearVelocity  = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero

	setCharacterVisibility(char, true)
	hum.PlatformStand = true; hum.WalkSpeed = 0; hum.JumpPower = 0

	local bv    = Instance.new("BodyVelocity")
	bv.Name     = "ParachuteVelocity"
	bv.Velocity = Vector3.new(0, -CONFIG.PARACHUTE_FALL_SPEED, 0)
	bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
	bv.P        = math.huge
	bv.Parent   = hrp

	task.defer(function()
		if not hrp or not hrp.Parent then return end
		hrp.AssemblyLinearVelocity  = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero
		hrp.Anchored = false
		if bv and bv.Parent then
			bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
			bv.P        = math.huge
			bv.Velocity = Vector3.new(0, -CONFIG.PARACHUTE_FALL_SPEED, 0)
		end
	end)

	chuteInputs[player] = Vector3.zero
	RE_ShowChute:FireClient(player, true)

	local conn; local startTime = os.clock(); local landed = false

	local function cleanup()
		if conn then conn:Disconnect(); conn = nil end
		if bv and bv.Parent then bv:Destroy() end
		chuteInputs[player] = nil
		if not landed then
			landed = true
			hum.PlatformStand = false; hum.WalkSpeed = 16; hum.JumpPower = 50
			RE_ShowChute:FireClient(player, false)
			print("[GameManager]", player.Name, "mendarat!")
		end
	end

	conn = RunService.Heartbeat:Connect(function()
		if not char or not char.Parent or not hrp or not hrp.Parent then cleanup(); return end
		if hum.Health <= 0 then cleanup(); return end
		if os.clock() - startTime > 120 then cleanup(); return end
		if not bv or not bv.Parent then cleanup(); return end

		local input    = chuteInputs[player] or Vector3.zero
		local moveVel  = input * CONFIG.PARACHUTE_MOVE_SPEED
		local hasInput = input.Magnitude > 0.01
		bv.MaxForce = Vector3.new(
			hasInput and CONFIG.PARACHUTE_ACCEL or math.huge,
			math.huge,
			hasInput and CONFIG.PARACHUTE_ACCEL or math.huge
		)
		bv.P        = hasInput and 1200 or math.huge
		bv.Velocity = Vector3.new(moveVel.X, -CONFIG.PARACHUTE_FALL_SPEED, moveVel.Z)

		local rayParams = RaycastParams.new()
		rayParams.FilterDescendantsInstances = {char}
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		local result = Workspace:Raycast(hrp.Position, Vector3.new(0, -10, 0), rayParams)
		if result and result.Distance <= 5 then cleanup() end
	end)
end

RE_ChuteMove.OnServerEvent:Connect(function(player, direction)
	if chuteInputs[player] == nil then return end
	if typeof(direction) == "Vector3" then
		local flat = Vector3.new(direction.X, 0, direction.Z); local mag = flat.Magnitude
		chuteInputs[player] = mag > 0 and (flat / math.max(mag,1)) or Vector3.zero
	end
end)

-- Tidak perlu lagi terima posisi dari client — server hitung sendiri
RE_DropPlayer.OnServerEvent:Connect(function(player)
	if flightActive then dropPlayer(player) end
end)

local function boardAllPlayers()
	local seatOffsets = {
		Vector3.new(0,-5,0), Vector3.new(3,-5,2), Vector3.new(-3,-5,2),
		Vector3.new(3,-5,-2), Vector3.new(-3,-5,-2), Vector3.new(6,-5,0), Vector3.new(-6,-5,0),
	}
	local idx = 1
	for _, player in ipairs(matchPlayers) do
		local char = player.Character
		if char then
			local hrp = char:FindFirstChild("HumanoidRootPart")
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hrp and hum then
				onboardPlayers[player] = true
				setCharacterVisibility(char, false)
				local offset = seatOffsets[idx] or seatOffsets[1]; idx += 1
				attachPlayerToPlane(player, offset)
			end
		end
	end
end

RE_ClientReady.OnServerEvent:Connect(function(player) readyClients[player] = true end)

local function waitForClients()
	local deadline = os.clock() + 8
	while os.clock() < deadline do
		local allReady = true
		for _, p in ipairs(Players:GetPlayers()) do if not readyClients[p] then allReady = false; break end end
		if allReady then break end
		task.wait(0.1)
	end
end

local function startFlight()
	print("\n========== START FLIGHT ==========")
	detectMapSize()
	planeModel = findOrCreatePlane()
	if not planeModel then warn("[GameManager] Plane tidak ditemukan."); return end
	rootPart    = planeModel:FindFirstChild(CONFIG.ROOT_PART_NAME) or planeModel.PrimaryPart or planeModel:FindFirstChildOfClass("BasePart")
	propsFolder = planeModel:FindFirstChild(CONFIG.PROPS_FOLDER_NAME)
	if not rootPart then warn("[GameManager] Root part tidak ditemukan."); return end
	setupEngineSound(rootPart)
	flightStart, flightEnd = generateFlightPath()
	flightDuration = (flightEnd - flightStart).Magnitude / CONFIG.FLIGHT_SPEED
	print("[GameManager] Start:", tostring(flightStart))
	print("[GameManager] End:  ", tostring(flightEnd))
	print("[GameManager] Durasi:", string.format("%.1f detik", flightDuration))
	planeModel:PivotTo(CFrame.lookAt(flightStart, flightEnd))
	for _, part in ipairs(planeModel:GetDescendants()) do if part:IsA("BasePart") then part.Anchored = true end end
	if rootPart then rootPart.Anchored = true end
	boardAllPlayers()
	waitForClients()
	engineSound.Playing = true
	local propPaths = {}
	for _, p in ipairs(getPropParts()) do table.insert(propPaths, p:GetFullName()) end
	RE_PropSpin:FireAllClients(propPaths, CONFIG.PROP_SPIN_SPEED)
	RE_GameStart:FireAllClients(flightStart, flightEnd, flightDuration, flightDirection)
	flightActive = true; flightStartTime = os.clock()
	print("[GameManager] ✅ Pesawat mulai terbang!")
	print("==================================\n")

	local flightConn
	flightConn = RunService.Heartbeat:Connect(function()
		local alpha  = math.clamp((os.clock() - flightStartTime) / flightDuration, 0, 1)
		local newPos = flightStart:Lerp(flightEnd, alpha)
		local cf     = CFrame.lookAt(newPos, flightEnd)
		planeModel:PivotTo(cf)

		-- Update posisi HRP player yang masih onboard
		for player, _ in pairs(onboardPlayers) do
			local char = player.Character
			if char then
				local hrp = char:FindFirstChild("HumanoidRootPart")
				if hrp then
					local seatOffset = playerSeatOffsets[player] or CONFIG.SEAT_OFFSET
					local targetCF   = cf * CFrame.new(seatOffset)
					hrp.CFrame = targetCF
					hrp.AssemblyLinearVelocity  = Vector3.zero
					hrp.AssemblyAngularVelocity = Vector3.zero
					-- TIDAK lagi simpan playerSeatPos — posisi dihitung dari alpha saat dibutuhkan
				end
			end
		end

		RE_PlaneFlight:FireAllClients(cf, alpha)

		if alpha >= 1 then
			flightActive = false; flightConn:Disconnect(); engineSound.Playing = false
			local toDrop = {}
			for player in pairs(onboardPlayers) do table.insert(toDrop, player) end
			for _, player in ipairs(toDrop) do dropPlayer(player) end
			task.delay(4, function() if planeModel and planeModel.Parent then planeModel:Destroy() end end)
			print("[GameManager] Flight selesai!")
		end
	end)
end

local function startMatch()
	matchActive = true; matchPlayers = {}; droppedPlayers = {}; onboardPlayers = {}
	playerConstraints = {}; playerSeatOffsets = {}
	for _, p in ipairs(Players:GetPlayers()) do table.insert(matchPlayers, p); setupPlayer(p) end
	totalPlayers = #matchPlayers
	MatchStartEvent:FireAllClients(totalPlayers)
	print("[GameManager] Match dimulai. Player:", totalPlayers)
	task.spawn(startFlight)
end

local function waitForPlayersAndStart()
	local lastCount = 0; local stableFor = 0
	while stableFor < 3 do
		local current = #Players:GetPlayers()
		if current == lastCount then stableFor += 1 else lastCount = current; stableFor = 0 end
		task.wait(1)
	end
	startMatch()
end

task.spawn(waitForPlayersAndStart)

Players.PlayerAdded:Connect(function(player)
	if matchActive then table.insert(matchPlayers, player); setupPlayer(player) end
end)

Players.PlayerRemoving:Connect(function(player)
	cleanupPlayerConstraints(player)
	chuteInputs[player] = nil; playerSeatOffsets[player] = nil
	playerStats[player] = nil; droppedPlayers[player] = nil; onboardPlayers[player] = nil; readyClients[player] = nil
	if matchActive then task.wait(0.5); fireAliveCount(); checkWinner() end
end)
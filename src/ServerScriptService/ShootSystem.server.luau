--[[
=============================================================
  SHOOT SYSTEM SERVER
  Damage + Headshot + Range Falloff + Vest Armor
  + Kill Tracking + WWCD + Death Teleport ke Lobby

  PLACE: ServerScriptService > ShootSystem
=============================================================
]]

local Players         = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local Debris = game:GetService("Debris")

------------------------------------------------
-- KONFIGURASI LOBBY & GAME
------------------------------------------------
local LOBBY_PLACE_ID = 72436553849314     -- ⚠️ GANTI DENGAN PLACE ID LOBBY 
local DEATH_DELAY    = 4     -- detik sebelum player mati diteleport
local WWCD_DELAY     = 13    -- detik sebelum winner diteleport (10s WWCD + 3s buffer)

-- Nonaktifkan auto respawn
Players.RespawnTime = 9999

------------------------------------------------
-- REMOTES
------------------------------------------------
local remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = ReplicatedStorage
end

local function ensureRemote(name)
	local remote = remotes:FindFirstChild(name)
	if remote and remote:IsA("RemoteEvent") then return remote end
	if remote then remote:Destroy() end
	remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = remotes
	return remote
end

local shootEvent    = ensureRemote("ShootEvent")
local hitmarkerEvent = ensureRemote("HitmarkerEvent")

-- Remote untuk WWCD & Death (langsung di ReplicatedStorage)
local function ensureRootRemote(name)
	local remote = ReplicatedStorage:FindFirstChild(name)
	if remote and remote:IsA("RemoteEvent") then return remote end
	if remote then remote:Destroy() end
	remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = ReplicatedStorage
	return remote
end

local wwcdEvent    = ensureRootRemote("WWCDEvent")
local youDiedEvent = ensureRootRemote("YouDiedEvent")

------------------------------------------------
-- CONFIG
------------------------------------------------
local MAX_RAY_DISTANCE = 2000
local MAX_ORIGIN_DISTANCE_FROM_CHARACTER = 25
local MIN_SERVER_SHOT_INTERVAL = 0.045
local VEST_PROTECTS_LIMBS = true
local DEFAULT_WEAPON_ID = "AssaultRifle_M416"

------------------------------------------------
-- GUNSHOT SOUND CONFIG
------------------------------------------------
local GUNSHOT_SOUNDS = {
	
	Launcher = {
		soundId = "rbxassetid://134201956270955",
		volume = 2.0,
		distance = 800,
		pitch = 0.85,
	},
	-- Ganti angka ID ini dengan asset sound kamu sendiri
	AssaultRifle = {
		soundId = "rbxassetid://90356629297956",
		volume = 1.2,
		distance = 450,
		pitch = 1.0,
	},

	SMG = {
		soundId = "rbxassetid://131215978573597",
		volume = 1.0,
		distance = 330,
		pitch = 1.1,
	},

	Shotgun = {
		soundId = "rbxassetid://113543931016554",
		volume = 1.5,
		distance = 420,
		pitch = 0.95,
	},

	Sniper = {
		soundId = "rbxassetid://138854039966754",
		volume = 1.8,
		distance = 700,
		pitch = 0.9,
	},

	Pistol = {
		soundId = "rbxassetid://138905044369113",
		volume = 0.9,
		distance = 260,
		pitch = 1.05,
	},

	Revolver = {
		soundId = "rbxassetid://115486270266848",
		volume = 1.1,
		distance = 320,
		pitch = 0.95,
	},

	LMG = {
		soundId = "rbxassetid://ISI_ID_SOUND_LMG",
		volume = 1.35,
		distance = 500,
		pitch = 0.95,
	},

	Default = {
		soundId = "rbxassetid://ISI_ID_SOUND_DEFAULT",
		volume = 1,
		distance = 350,
		pitch = 1,
	},
}

local function playGunshotSound(worldPosition, weaponClass)
	if typeof(worldPosition) ~= "Vector3" then
		return
	end

	local soundData = GUNSHOT_SOUNDS[weaponClass] or GUNSHOT_SOUNDS.Default

	if not soundData or not soundData.soundId or soundData.soundId == "" then
		return
	end

	local soundPart = Instance.new("Part")
	soundPart.Name = "GunshotSoundPart"
	soundPart.Size = Vector3.new(0.2, 0.2, 0.2)
	soundPart.Transparency = 1
	soundPart.Anchored = true
	soundPart.CanCollide = false
	soundPart.CanTouch = false
	soundPart.CanQuery = false
	soundPart.Position = worldPosition
	soundPart.Parent = workspace

	local sound = Instance.new("Sound")
	sound.Name = "GunshotSound"
	sound.SoundId = soundData.soundId
	sound.Volume = soundData.volume or 1
	sound.PlaybackSpeed = (soundData.pitch or 1) + math.random(-3, 3) / 100
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 15
	sound.RollOffMaxDistance = soundData.distance or 350
	sound.Parent = soundPart

	sound:Play()

	Debris:AddItem(soundPart, 4)
end

------------------------------------------------
-- WEAPON STATS
------------------------------------------------
local WEAPON_STATS = {
	AssaultRifle_AKM = {
		class = "AssaultRifle", damage = 41,
		effectiveRange = 380, falloffEnd = 900, minDamageMultiplier = 0.68,
	},
	AssaultRifle_Beryl = {
		class = "AssaultRifle", damage = 39,
		effectiveRange = 360, falloffEnd = 850, minDamageMultiplier = 0.66,
	},
	AssaultRifle_M416 = {
		class = "AssaultRifle", damage = 36,
		effectiveRange = 400, falloffEnd = 900, minDamageMultiplier = 0.70,
	},
	Bullpup_1 = {
		class = "AssaultRifle", damage = 37,
		effectiveRange = 390, falloffEnd = 870, minDamageMultiplier = 0.69,
	},
	
	RPG_Bazooka = {
		class = "Launcher",
		damage = 120,
		effectiveRange = 500,
		falloffEnd = 900,
		minDamageMultiplier = 0.75,
	},
	
	SubmachineGun_MicroUZI = {
		class = "SMG", damage = 22,
		effectiveRange = 150, falloffEnd = 450, minDamageMultiplier = 0.50,
	},
	SubmachineGun_UMP45 = {
		class = "SMG", damage = 31,
		effectiveRange = 190, falloffEnd = 520, minDamageMultiplier = 0.55,
	},
	Shotgun_S1897 = {
		class = "Shotgun", damage = 10, pellets = 8, serverSpreadDeg = 6,
		effectiveRange = 65, falloffEnd = 180, minDamageMultiplier = 0.25,
	},
	Shotgun_S686 = {
		class = "Shotgun", damage = 82,
		effectiveRange = 60, falloffEnd = 170, minDamageMultiplier = 0.22,
	},
	Shotgun_SawedOff = {
		class = "Shotgun", damage = 62,
		effectiveRange = 45, falloffEnd = 130, minDamageMultiplier = 0.20,
	},
	Shotgun_ShortStock = {
		class = "Shotgun", damage = 68,
		effectiveRange = 55, falloffEnd = 150, minDamageMultiplier = 0.22,
	},
	SniperRifle_AWM = {
		class = "Sniper", damage = 95,
		effectiveRange = 900, falloffEnd = 1700, minDamageMultiplier = 0.85,
	},
	SniperRifle_Kar98k = {
		class = "Sniper", damage = 78,
		effectiveRange = 800, falloffEnd = 1500, minDamageMultiplier = 0.80,
	},
	SniperRifle_M24 = {
		class = "Sniper", damage = 84,
		effectiveRange = 850, falloffEnd = 1600, minDamageMultiplier = 0.82,
	},
	SniperRifle_M249 = {
		class = "LMG", damage = 34,
		effectiveRange = 450, falloffEnd = 950, minDamageMultiplier = 0.68,
	},
	Pistol_DessertEagle = {
		class = "Pistol", damage = 52,
		effectiveRange = 160, falloffEnd = 420, minDamageMultiplier = 0.55,
	},
	Pistol_P1911 = {
		class = "Pistol", damage = 34,
		effectiveRange = 130, falloffEnd = 340, minDamageMultiplier = 0.50,
	},
	Pistol_P92 = {
		class = "Pistol", damage = 29,
		effectiveRange = 120, falloffEnd = 320, minDamageMultiplier = 0.48,
	},
	Pistol_scorpion = {
		class = "Pistol", damage = 24,
		effectiveRange = 120, falloffEnd = 330, minDamageMultiplier = 0.48,
	},
	Revolver_MagnumRevolver = {
		class = "Revolver", damage = 60,
		effectiveRange = 180, falloffEnd = 450, minDamageMultiplier = 0.58,
	},
	Revolver_R1895 = {
		class = "Revolver", damage = 48,
		effectiveRange = 160, falloffEnd = 390, minDamageMultiplier = 0.54,
	},
	Revolver_R45 = {
		class = "Revolver", damage = 44,
		effectiveRange = 150, falloffEnd = 360, minDamageMultiplier = 0.52,
	},
}

local DEFAULT_STATS = {
	class = "Default", damage = 30,
	effectiveRange = 300, falloffEnd = 700, minDamageMultiplier = 0.60,
}

------------------------------------------------
-- BODY MULTIPLIERS
------------------------------------------------
local BODY_MULTIPLIERS = {
	Head = 2.0,
	Body = 1.0,
	Limb = 0.75,
}

------------------------------------------------
-- KILL TRACKING STATE
------------------------------------------------
local killCounts   = {}   -- [player] = jumlah kill
local alivePlayers = {}   -- [player] = true jika masih hidup
local startTimes   = {}   -- [player] = os.clock() saat masuk game
local processedDeath = {} -- [player] = true jika sudah diproses (anti double)
local gameActive   = true
local lastShotTime = {}

------------------------------------------------
-- UTILITY KILL TRACKER
------------------------------------------------
local function formatTime(seconds)
	local m = math.floor(seconds / 60)
	local s = math.floor(seconds % 60)
	return string.format("%02d:%02d", m, s)
end

local function getAliveCount()
	local count = 0
	for p, alive in pairs(alivePlayers) do
		if alive and p and p.Parent then
			count += 1
		end
	end
	return count
end

local function getAlivePlayer()
	for p, alive in pairs(alivePlayers) do
		if alive and p and p.Parent then
			return p
		end
	end
	return nil
end

local function teleportToLobby(player)
	if not player or not player.Parent then return end
	local ok, err = pcall(function()
		TeleportService:Teleport(LOBBY_PLACE_ID, player)
	end)
	if not ok then
		warn("[SHOOT] Gagal teleport " .. player.Name .. ": " .. tostring(err))
	end
end

local function checkWinner()
	if not gameActive then return end
	local aliveCount = getAliveCount()

	if aliveCount == 1 then
		gameActive = false
		local winner = getAlivePlayer()
		if not winner then return end

		local kills    = killCounts[winner] or 0
		local survived = formatTime(os.clock() - (startTimes[winner] or os.clock()))

		print(string.format("[SHOOT] 🏆 WINNER: %s | Kills: %d | Survived: %s",
			winner.Name, kills, survived))

		-- Kirim WWCD ke winner
		wwcdEvent:FireClient(winner, {
			kills        = kills,
			timeSurvived = survived,
		})

		-- Teleport winner ke lobby setelah WWCD selesai
		task.delay(WWCD_DELAY, function()
			teleportToLobby(winner)
		end)

	elseif aliveCount == 0 then
		gameActive = false
		print("[SHOOT] Semua player mati, tidak ada winner.")
	end
end

local function handlePlayerDeath(deadPlayer, killerPlayer)
	-- Anti double process
	if processedDeath[deadPlayer] then return end
	processedDeath[deadPlayer] = true

	alivePlayers[deadPlayer] = false

	-- Update kill count killer
	if killerPlayer and killerPlayer ~= deadPlayer and killerPlayer.Parent then
		killCounts[killerPlayer] = (killCounts[killerPlayer] or 0) + 1
		print(string.format("[SHOOT] %s dibunuh oleh %s | Kill ke-%d",
			deadPlayer.Name, killerPlayer.Name, killCounts[killerPlayer]))
	end

	-- Kirim event mati ke client
	local kills    = killCounts[deadPlayer] or 0
	local survived = formatTime(os.clock() - (startTimes[deadPlayer] or os.clock()))

	youDiedEvent:FireClient(deadPlayer, {
		kills        = kills,
		timeSurvived = survived,
	})

	-- Cek winner
	task.wait(0.3)
	checkWinner()

	-- Teleport player mati ke lobby
	task.delay(DEATH_DELAY, function()
		teleportToLobby(deadPlayer)
	end)
end

------------------------------------------------
-- SETUP PLAYER
------------------------------------------------
local function setupPlayer(player)
	killCounts[player]    = 0
	alivePlayers[player]  = true
	startTimes[player]    = os.clock()
	processedDeath[player] = false
end

Players.PlayerAdded:Connect(function(player)
	setupPlayer(player)
end)

Players.PlayerRemoving:Connect(function(player)
	lastShotTime[player] = nil

	-- Jika player disconnect saat masih hidup
	if alivePlayers[player] then
		alivePlayers[player] = false
		task.wait(0.2)
		checkWinner()
	end

	killCounts[player]    = nil
	alivePlayers[player]  = nil
	startTimes[player]    = nil
	processedDeath[player] = nil
end)

-- Setup player yang sudah ada saat script dijalankan
for _, player in ipairs(Players:GetPlayers()) do
	setupPlayer(player)
end

------------------------------------------------
-- HELPERS SHOOT
------------------------------------------------
local function getWeaponStats(weaponId)
	if typeof(weaponId) ~= "string" or weaponId == "" then
		weaponId = DEFAULT_WEAPON_ID
	end
	return WEAPON_STATS[weaponId] or DEFAULT_STATS
end

local function getCharacterRoot(character)
	return character:FindFirstChild("HumanoidRootPart")
		or character:FindFirstChild("Torso")
		or character:FindFirstChild("UpperTorso")
end

local function getCharacterHead(character)
	return character:FindFirstChild("Head")
end

local function isValidVector3(value)
	return typeof(value) == "Vector3"
end

local function classifyHitZone(part)
	if not part then return "Body" end
	local name = part.Name
	if name == "Head" then return "Head" end
	if name == "Torso" or name == "UpperTorso"
		or name == "LowerTorso" or name == "HumanoidRootPart" then
		return "Body"
	end
	return "Limb"
end

local function findHumanoidFromPart(part)
	if not part then return nil, nil end
	local current = part
	while current and current ~= workspace do
		local humanoid = current:FindFirstChildWhichIsA("Humanoid")
		if humanoid then return humanoid, current end
		current = current.Parent
	end
	return nil, nil
end

local function calculateRangeMultiplier(distance, stats)
	local effectiveRange = stats.effectiveRange or 300
	local falloffEnd     = stats.falloffEnd or 700
	local minMultiplier  = stats.minDamageMultiplier or 0.6
	if distance <= effectiveRange then return 1 end
	if distance >= falloffEnd then return minMultiplier end
	local alpha = (distance - effectiveRange) / (falloffEnd - effectiveRange)
	return 1 - ((1 - minMultiplier) * alpha)
end

local function getSafeOrigin(player, clientOrigin)
	local character = player.Character
	if not character then return nil end
	local root = getCharacterRoot(character)
	local head = getCharacterHead(character)
	if not root then return nil end
	local fallbackOrigin = head and head.Position or root.Position
	if not isValidVector3(clientOrigin) then return fallbackOrigin end
	if (clientOrigin - fallbackOrigin).Magnitude > MAX_ORIGIN_DISTANCE_FROM_CHARACTER then
		return fallbackOrigin
	end
	return clientOrigin
end

local function canShootNow(player)
	local now  = os.clock()
	local last = lastShotTime[player] or 0
	if now - last < MIN_SERVER_SHOT_INTERVAL then return false end
	lastShotTime[player] = now
	return true
end

------------------------------------------------
-- ARMOR SYSTEM
------------------------------------------------
local function canVestProtectZone(hitZone)
	if hitZone == "Head" then return false end
	if hitZone == "Limb" and not VEST_PROTECTS_LIMBS then return false end
	return true
end

local function breakVestIfNeeded(targetCharacter, armorLeft)
	if armorLeft > 0 then return end
	targetCharacter:SetAttribute("Armor", 0)
	targetCharacter:SetAttribute("VestDamageReduction", 0)
	targetCharacter:SetAttribute("ArmorBroken", true)
	local vest = targetCharacter:FindFirstChild("EquippedVest")
	if vest then vest:Destroy() end
end

local function applyDamageWithArmor(targetCharacter, humanoid, rawDamage, hitZone)
	if not targetCharacter or not humanoid then return rawDamage, 0, 0 end
	if rawDamage <= 0 then return 0, 0, targetCharacter:GetAttribute("Armor") or 0 end

	local armor     = targetCharacter:GetAttribute("Armor") or 0
	local maxArmor  = targetCharacter:GetAttribute("MaxArmor") or 0
	local reduction = targetCharacter:GetAttribute("VestDamageReduction") or 0

	if armor <= 0 or maxArmor <= 0 or reduction <= 0 or not canVestProtectZone(hitZone) then
		humanoid:TakeDamage(rawDamage)
		return rawDamage, 0, armor
	end

	local blockedDamage = rawDamage * reduction
	local finalDamage   = rawDamage - blockedDamage
	local newArmor      = math.max(0, armor - blockedDamage)

	targetCharacter:SetAttribute("Armor", newArmor)
	humanoid:TakeDamage(finalDamage)
	breakVestIfNeeded(targetCharacter, newArmor)

	return finalDamage, blockedDamage, newArmor
end


local function isInsidePUBGMap(part)
	local pubgMap = workspace:FindFirstChild("PUBGMap")
	if not pubgMap then return false end

	return part and part:IsA("BasePart") and part:IsDescendantOf(pubgMap)
end

local function isInsideNamedObject(part, targetName)
	local current = part
	local targetLower = string.lower(targetName)

	while current and current ~= workspace do
		if string.lower(current.Name) == targetLower then
			return true
		end

		current = current.Parent
	end

	return false
end

local function shouldNotBreak(part)
	if not part then return true end

	-- Exclude semua isi Terrain_Main
	if isInsideNamedObject(part, "Terrain_Main") then
		return true
	end

	local name = string.lower(part.Name)

	local blockedKeywords = {
		"floor",
		"ground",
		"baseplate",
		"spawn",
		"loot",
		"interact",
		"hitbox",
		"safezone",
		"zone",
	}

	for _, keyword in ipairs(blockedKeywords) do
		if string.find(name, keyword) then
			return true
		end
	end

	return false
end

local function breakMapPart(part, hitPosition, power)
	if not part or not part:IsA("BasePart") then return end
	if part:GetAttribute("Broken") == true then return end
	if shouldNotBreak(part) then return end

	part:SetAttribute("Broken", true)

	part.Anchored = false
	part.CanCollide = true
	part.Massless = false

	local dir = part.Position - hitPosition
	if dir.Magnitude < 0.1 then
		dir = Vector3.new(0, 1, 0)
	end

	part.AssemblyLinearVelocity =
		dir.Unit * (power or 80) + Vector3.new(0, 35, 0)

	part.AssemblyAngularVelocity = Vector3.new(
		math.random(-12, 12),
		math.random(-12, 12),
		math.random(-12, 12)
	)

	-- Biar tidak bikin map berat, hilangkan setelah beberapa detik
	task.delay(5, function()
		if part and part.Parent then
			part:Destroy()
		end
	end)
end
------------------------------------------------
-- DAMAGE HANDLER
------------------------------------------------
local function handleShoot(player, origin, direction, weaponId)
	if not player or not player.Parent then return end
	if not canShootNow(player) then return end

	-- Shooter sudah mati, jangan proses
	if not alivePlayers[player] then return end

	local character = player.Character
	if not character then return end

	local shooterHumanoid = character:FindFirstChildWhichIsA("Humanoid")
	if not shooterHumanoid or shooterHumanoid.Health <= 0 then return end

	local safeOrigin = getSafeOrigin(player, origin)
	if not safeOrigin then return end

	if not isValidVector3(direction) or direction.Magnitude <= 0 then return end

	local unitDirection = direction.Unit
	local stats         = getWeaponStats(weaponId)
	
	playGunshotSound(safeOrigin, stats.class)

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { character }
	rayParams.IgnoreWater = true

	local rayResult = workspace:Raycast(safeOrigin, unitDirection * MAX_RAY_DISTANCE, rayParams)
	if not rayResult then return end

	local hitPart     = rayResult.Instance
	local hitPosition = rayResult.Position
	if isInsidePUBGMap(hitPart) then
		local power = 80

		if weaponId == "RPG_Bazooka" then
			power = 220
		end

		breakMapPart(hitPart, hitPosition, power)
	end
	local distance    = (hitPosition - safeOrigin).Magnitude

	local targetHumanoid, targetCharacter = findHumanoidFromPart(hitPart)
	if not targetHumanoid or not targetCharacter then return end
	if targetCharacter == character then return end
	if targetHumanoid.Health <= 0 then return end

	local targetPlayer = Players:GetPlayerFromCharacter(targetCharacter)
	if targetPlayer == player then return end

	local hitZone        = classifyHitZone(hitPart)
	local bodyMultiplier = BODY_MULTIPLIERS[hitZone] or 1
	local rangeMultiplier = calculateRangeMultiplier(distance, stats)
	local rawDamage      = stats.damage * bodyMultiplier * rangeMultiplier

	local healthBefore = targetHumanoid.Health

	local realDamage, blockedDamage, armorLeft = applyDamageWithArmor(
		targetCharacter, targetHumanoid, rawDamage, hitZone
	)

	local healthAfter = targetHumanoid.Health

	local isHeadshot = hitZone == "Head"
	local isKill     = healthBefore > 0 and healthAfter <= 0

	-- ✅ Jika kill — proses kematian langsung di sini
	if isKill and targetPlayer then
		handlePlayerDeath(targetPlayer, player)
	end

	local state = "Hit"
	if isKill       then state = "Kill"
	elseif isHeadshot then state = "Headshot"
	elseif blockedDamage > 0 then state = "Armor"
	end

	local roundedDamage  = math.max(0, math.floor(realDamage + 0.5))
	local roundedBlocked = math.max(0, math.floor(blockedDamage + 0.5))
	local roundedArmor   = math.max(0, math.floor(armorLeft + 0.5))

	local hitInfo = {
		damage         = roundedDamage,
		hitZone        = hitZone,
		state          = state,
		targetName     = targetCharacter.Name,
		weaponId       = weaponId,
		weaponClass    = stats.class,
		distance       = distance,
		rangeMultiplier = rangeMultiplier,
		isHeadshot     = isHeadshot,
		isKill         = isKill,
		isKnock        = false,
		blockedDamage  = roundedBlocked,
		armorLeft      = roundedArmor,
		isArmor        = roundedBlocked > 0,
	}

	hitmarkerEvent:FireClient(player, hitInfo)

	print(string.format(
		"[SHOOT] %s hit %s | weapon=%s | zone=%s | dmg=%d | blocked=%d | armor=%d | state=%s",
		player.Name, targetCharacter.Name, tostring(weaponId),
		hitZone, roundedDamage, roundedBlocked, roundedArmor, state
		))
end

------------------------------------------------
-- CONNECT EVENTS
------------------------------------------------
shootEvent.OnServerEvent:Connect(function(player, origin, direction, weaponId)
	handleShoot(player, origin, direction, weaponId)
end)

print("===========================================")
print("[SHOOT SYSTEM] Ready")
print("  Lobby Place ID : " .. LOBBY_PLACE_ID)
print("  Death Delay    : " .. DEATH_DELAY .. "s")
print("  WWCD Delay     : " .. WWCD_DELAY .. "s")
print("===========================================")

local function breakPhysicsPart(part, hitPosition, power)
	if not part or not part:IsA("BasePart") then return end
	if part:GetAttribute("Broken") == true then return end

	part:SetAttribute("Broken", true)

	part.Anchored = false
	part.CanCollide = true
	part.Massless = false

	local dir = part.Position - hitPosition
	if dir.Magnitude < 0.1 then
		dir = Vector3.new(0, 1, 0)
	end

	part.AssemblyLinearVelocity =
		dir.Unit * (power or 60) + Vector3.new(0, 25, 0)

	part.AssemblyAngularVelocity = Vector3.new(
		math.random(-8, 8),
		math.random(-8, 8),
		math.random(-8, 8)
	)
end
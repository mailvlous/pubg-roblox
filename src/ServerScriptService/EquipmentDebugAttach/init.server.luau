--[[
=============================================================
  EQUIPMENT DEBUG ATTACH
  Untuk test Helm / Vest / Tas ke player sendiri

  PLACE:
  ServerScriptService > EquipmentDebugAttach

  Asset path:
  ReplicatedStorage > Assets > Item > Helm
  ReplicatedStorage > Assets > Item > Vest
  ReplicatedStorage > Assets > Item > Tas
=============================================================
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

------------------------------------------------
-- CONFIG
------------------------------------------------

-- Kalau true, otomatis pasang equipment default saat spawn
local AUTO_ATTACH_ON_SPAWN = false

-- Ubah ini kalau mau langsung auto pasang saat spawn
local DEFAULT_HELM_LEVEL = 1
local DEFAULT_VEST_LEVEL = 1
local DEFAULT_TAS_LEVEL = 1

local ITEM_ROOT = ReplicatedStorage
	:WaitForChild("Assets")
	:WaitForChild("Item")

local EQUIPMENT_ASSETS = {
	Helm = {
		folder = "Helm",
		equippedName = "DebugHelmet",
		attachPart = "Head",

		names = {
			[1] = "Helmet Level 1",
			[2] = "Helmet Level 2",
			[3] = "Helmet Level 3",
		},

		-- X kiri/kanan, Y atas/bawah, Z depan/belakang
		c0 = CFrame.new(0, 1.3, 0.4) * CFrame.Angles(
			math.rad(360),
			math.rad(0),
			math.rad(0)
		),
		scale = 0.04,
	},

	Vest = {
		folder = "Vest",
		equippedName = "EquippedVest",
		attachPart = "Torso",

		names = {
			[1] = "BR_Level1_Vest_R6_Roblox",
			[2] = "BR_Level2_Vest_R6_Roblox",
			[3] = "BR_Level3_Vest_R6_Roblox",
		},

		-- Untuk torso R6:
		-- Z negatif = maju ke depan badan
		c0 = CFrame.new(0, 0, -0.05),
		scale = 1,
	},

	Tas = {
		folder = "Tas",
		equippedName = "EquippedTas",
		attachPart = "Torso",

		names = {
			[1] = "Tas Level 1",
			[2] = "Tas Level 2",
			[3] = "Tas Level 3",
		},

		-- Untuk tas/backpack:
		-- Z positif = ke belakang badan
		c0 = CFrame.new(0, 0.05, 0.55) * CFrame.Angles(
			math.rad(90),
			math.rad(0),
			math.rad(0)
		),
		scale = 0.014,
	},
}

------------------------------------------------
-- HELPER
------------------------------------------------
local function getAttachPart(character, partName)
	if partName == "Torso" then
		return character:FindFirstChild("Torso")
			or character:FindFirstChild("UpperTorso")
	end

	if partName == "Head" then
		return character:FindFirstChild("Head")
	end

	return character:FindFirstChild(partName)
end

local function getRootPart(model)
	if model:IsA("BasePart") then
		return model
	end

	-- Prioritaskan Handle dulu
	local handle = model:FindFirstChild("Handle", true)
	if handle and handle:IsA("BasePart") then
		return handle
	end

	if model.PrimaryPart then
		return model.PrimaryPart
	end

	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function prepareEquipmentModel(model)
	local rootPart = getRootPart(model)

	if not rootPart then
		warn("[EQUIP DEBUG] Model tidak punya BasePart:", model.Name)
		return nil
	end

	if model:IsA("Model") then
		model.PrimaryPart = rootPart
	end

	for _, obj in ipairs(model:GetDescendants()) do
		if obj:IsA("BaseScript") then
			obj.Disabled = true
		elseif obj:IsA("BasePart") then
			obj.Anchored = false
			obj.CanCollide = false
			obj.CanTouch = false
			obj.CanQuery = false
			obj.Massless = true
		end
	end

	for _, obj in ipairs(model:GetDescendants()) do
		if obj:IsA("BasePart") and obj ~= rootPart then
			local weld = Instance.new("WeldConstraint")
			weld.Name = "EquipmentPartWeld"
			weld.Part0 = rootPart
			weld.Part1 = obj
			weld.Parent = rootPart
		end
	end

	return rootPart
end

local function getTemplate(equipmentType, level)
	local config = EQUIPMENT_ASSETS[equipmentType]
	if not config then
		warn("[EQUIP DEBUG] Equipment type tidak dikenal:", equipmentType)
		return nil
	end

	level = math.clamp(level or 1, 1, 3)

	local folder = ITEM_ROOT:WaitForChild(config.folder)
	local modelName = config.names[level]

	print("[EQUIP DEBUG] Cari template:", config.folder, "[" .. modelName .. "]")

	local template = folder:FindFirstChild(modelName)

	if not template then
		warn("[EQUIP DEBUG] Template tidak ditemukan:", config.folder, "[" .. modelName .. "]")
		warn("[EQUIP DEBUG] Isi folder", folder:GetFullName(), ":")

		for _, child in ipairs(folder:GetChildren()) do
			warn(" - [" .. child.Name .. "]", child.ClassName)
		end

		return nil
	end

	return template
end

local function clearEquipment(character, equipmentType)
	local config = EQUIPMENT_ASSETS[equipmentType]
	if not config then return end

	local old = character:FindFirstChild(config.equippedName)
	if old then
		old:Destroy()
	end
end

local function clearAllEquipment(character)
	for equipmentType, _ in pairs(EQUIPMENT_ASSETS) do
		clearEquipment(character, equipmentType)
	end
end

local function equipEquipment(player, equipmentType, level)
	local character = player.Character
	if not character then return end

	local config = EQUIPMENT_ASSETS[equipmentType]
	if not config then return end

	local attachPart = getAttachPart(character, config.attachPart)

	if not attachPart then
		warn("[EQUIP DEBUG] Attach part tidak ditemukan:", config.attachPart)
		return
	end

	local template = getTemplate(equipmentType, level)
	if not template then return end

	clearEquipment(character, equipmentType)

	local clone = template:Clone()
	clone.Name = config.equippedName
	clone.Parent = character
	
	print("[EQUIP DEBUG] Clone dibuat:", clone.Name)
	print("[EQUIP DEBUG] Parent sekarang:", clone.Parent and clone.Parent:GetFullName() or "NIL")
	print("[EQUIP DEBUG] Character target:", character:GetFullName())

	task.delay(0.2, function()
		local found = character:FindFirstChild(config.equippedName)
		print("[EQUIP DEBUG] Cek 0.2s:", config.equippedName, found and "ADA" or "TIDAK ADA")
	end)

	task.delay(1, function()
		local found = character:FindFirstChild(config.equippedName)
		print("[EQUIP DEBUG] Cek 1s:", config.equippedName, found and "ADA" or "TIDAK ADA")
	end)

	local rootPart = prepareEquipmentModel(clone)
	if not rootPart then
		clone:Destroy()
		return
	end

	if clone:IsA("Model") then
		pcall(function()
			clone:ScaleTo(config.scale or 1)
		end)

		clone:PivotTo(attachPart.CFrame * config.c0)
	else
		clone.CFrame = attachPart.CFrame * config.c0
	end

	local weld = Instance.new("WeldConstraint")
	weld.Name = equipmentType .. "AttachWeld"
	weld.Part0 = attachPart
	weld.Part1 = rootPart
	weld.Parent = rootPart

	print("[EQUIP DEBUG]", player.Name, "pakai", equipmentType, "Level", level)
end

------------------------------------------------
-- CHAT COMMANDS
------------------------------------------------
local function handleCommand(player, message)
	message = string.lower(message)

	if message == "/helm1" then
		equipEquipment(player, "Helm", 1)
	elseif message == "/helm2" then
		equipEquipment(player, "Helm", 2)
	elseif message == "/helm3" then
		equipEquipment(player, "Helm", 3)

	elseif message == "/vest1" then
		equipEquipment(player, "Vest", 1)
	elseif message == "/vest2" then
		equipEquipment(player, "Vest", 2)
	elseif message == "/vest3" then
		equipEquipment(player, "Vest", 3)

	elseif message == "/tas1" then
		equipEquipment(player, "Tas", 1)
	elseif message == "/tas2" then
		equipEquipment(player, "Tas", 2)
	elseif message == "/tas3" then
		equipEquipment(player, "Tas", 3)

	elseif message == "/clearhelm" then
		if player.Character then
			clearEquipment(player.Character, "Helm")
		end

	elseif message == "/clearvest" then
		if player.Character then
			clearEquipment(player.Character, "Vest")
		end

	elseif message == "/cleartas" then
		if player.Character then
			clearEquipment(player.Character, "Tas")
		end

	elseif message == "/clearall" then
		if player.Character then
			clearAllEquipment(player.Character)
		end
	end
end

------------------------------------------------
-- PLAYER SETUP
------------------------------------------------
Players.PlayerAdded:Connect(function(player)
	player.Chatted:Connect(function(message)
		handleCommand(player, message)
	end)

	player.CharacterAdded:Connect(function(character)
		task.wait(1)

		character.ChildAdded:Connect(function(child)
			if child.Name == "EquippedHelmet" or child.Name == "DebugHelmet" then
				print("[EQUIP DEBUG] ADDED:", child.Name, child:GetFullName())
			end
		end)

		character.ChildRemoved:Connect(function(child)
			if child.Name == "EquippedHelmet" or child.Name == "DebugHelmet" then
				warn("[EQUIP DEBUG] REMOVED:", child.Name)
			end
		end)

		if AUTO_ATTACH_ON_SPAWN then
			equipEquipment(player, "Helm", DEFAULT_HELM_LEVEL)
			equipEquipment(player, "Vest", DEFAULT_VEST_LEVEL)
			equipEquipment(player, "Tas", DEFAULT_TAS_LEVEL)
		end
	end)
end)

print("[EQUIP DEBUG] Ready")
print("Commands: /helm1 /helm2 /helm3 /vest1 /vest2 /vest3 /tas1 /tas2 /tas3 /clearall")
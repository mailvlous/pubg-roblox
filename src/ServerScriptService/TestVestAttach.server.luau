local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

------------------------------------------------
-- CONFIG
------------------------------------------------

local VEST_STATS = {
	[1] = {
		MaxArmor = 60,
		DamageReduction = 0.30, -- mengurangi 30% damage
	},

	[2] = {
		MaxArmor = 90,
		DamageReduction = 0.40, -- mengurangi 40% damage
	},

	[3] = {
		MaxArmor = 120,
		DamageReduction = 0.50, -- mengurangi 50% damage
	},
}

local VEST_LEVEL = 1 -- ganti 1 / 2 / 3

local VEST_NAMES = {
	[1] = "BR_Level1_Vest_R6_Roblox",
	[2] = "BR_Level2_Vest_R6_Roblox",
	[3] = "BR_Level3_Vest_R6_Roblox",
}

local EQUIPPED_VEST_NAME = "EquippedVest"

-- X = kiri/kanan
-- Y = atas/bawah
-- Z = depan/belakang
local VEST_C0 = CFrame.new(0, 0, -0.05) * CFrame.Angles(
	math.rad(0),
	math.rad(0),
	math.rad(0)
)

------------------------------------------------
-- HELPER
------------------------------------------------
local function getVestTemplate()
	local vestName = VEST_NAMES[VEST_LEVEL]

	local vestFolder = ReplicatedStorage
		:WaitForChild("Assets")
		:WaitForChild("Item")
		:WaitForChild("Vest")

	return vestFolder:WaitForChild(vestName)
end

local function getTorso(character)
	return character:FindFirstChild("Torso") -- R6
		or character:FindFirstChild("UpperTorso") -- R15 fallback
end

local function getRootPart(model)
	if model:IsA("BasePart") then
		return model
	end

	if model.PrimaryPart then
		return model.PrimaryPart
	end

	local handle = model:FindFirstChild("Handle", true)
	if handle and handle:IsA("BasePart") then
		return handle
	end

	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function prepareVestModel(vestModel)
	local rootPart = getRootPart(vestModel)

	if not rootPart then
		warn("[VEST] Vest tidak punya BasePart")
		return nil
	end

	if vestModel:IsA("Model") then
		vestModel.PrimaryPart = rootPart
	end

	for _, obj in ipairs(vestModel:GetDescendants()) do
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

	for _, obj in ipairs(vestModel:GetDescendants()) do
		if obj:IsA("BasePart") and obj ~= rootPart then
			local weld = Instance.new("WeldConstraint")
			weld.Name = "VestPartWeld"
			weld.Part0 = rootPart
			weld.Part1 = obj
			weld.Parent = rootPart
		end
	end

	return rootPart
end

local function applyVestStats(character, level)
	local stats = VEST_STATS[level]

	if not stats then
		warn("[VEST] Stats tidak ditemukan untuk level:", level)
		return
	end

	character:SetAttribute("ArmorLevel", level)
	character:SetAttribute("Armor", stats.MaxArmor)
	character:SetAttribute("MaxArmor", stats.MaxArmor)
	character:SetAttribute("VestDamageReduction", stats.DamageReduction)

	print("[VEST] Stats armor dipasang")
	print("Level:", level)
	print("Armor:", stats.MaxArmor)
	print("Reduction:", stats.DamageReduction)
end

------------------------------------------------
-- EQUIP VEST
------------------------------------------------
local function equipVest(character)
	local torso = getTorso(character)

	if not torso then
		warn("[VEST] Torso tidak ditemukan")
		return
	end

	local oldVest = character:FindFirstChild(EQUIPPED_VEST_NAME)
	if oldVest then
		oldVest:Destroy()
	end

	local vestTemplate = getVestTemplate()
	local vestClone = vestTemplate:Clone()
	vestClone.Name = EQUIPPED_VEST_NAME
	vestClone.Parent = character

	local rootPart = prepareVestModel(vestClone)

	if not rootPart then
		vestClone:Destroy()
		return
	end

	if vestClone:IsA("Model") then
		vestClone:PivotTo(torso.CFrame * VEST_C0)
	else
		vestClone.CFrame = torso.CFrame * VEST_C0
	end

	local weldToTorso = Instance.new("WeldConstraint")
	weldToTorso.Name = "VestTorsoWeld"
	weldToTorso.Part0 = torso
	weldToTorso.Part1 = rootPart
	weldToTorso.Parent = rootPart
	
	applyVestStats(character, VEST_LEVEL)

	print("[VEST] Vest level", VEST_LEVEL, "berhasil dipasang ke", character.Name)
end

------------------------------------------------
-- PLAYER SETUP
------------------------------------------------
local function onCharacterAdded(character)
	task.wait(1)
	equipVest(character)
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(onCharacterAdded)

	if player.Character then
		onCharacterAdded(player.Character)
	end
end)
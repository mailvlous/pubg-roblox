--[[

=============================================================

  LOOT SYSTEM v8 (Server) - DROP FIX

  Perbaikan dari v7:
  1. dropWeapon: sekarang menghapus Tool/Model senjata dari
     Character dan Backpack player (animasi pegang hilang karena
     server tidak unequip senjata dari karakter)
  2. DropItemEvent: tambah handler kategori "Ammo" agar ammo
     bisa di-drop ke map dan berkurang dari inventory
  3. unequipWeaponFromCharacter: fungsi baru untuk membersihkan
     senjata dari karakter secara server-side

=============================================================

]]

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MAP_HALF = 1024

-- ============================================================

-- CONFIG AMMO GENERIC

-- ============================================================

local AMMO_CONFIG = {
	
	AmmoRocket = {
		label = "Rocket",
		min = 1,
		max = 3,
		color = Color3.fromRGB(255, 120, 40),
	},

	Ammo9mm = {

		label = "9mm",

		min = 25,

		max = 60,

		color = Color3.fromRGB(70, 220, 120),

	},

	Ammo45ACP = {

		label = ".45 ACP",

		min = 20,

		max = 50,

		color = Color3.fromRGB(170, 100, 255),

	},

	Ammo556 = {

		label = "5.56mm",

		min = 25,

		max = 60,

		color = Color3.fromRGB(80, 150, 255),

	},

	Ammo762 = {

		label = "7.62mm",

		min = 20,

		max = 50,

		color = Color3.fromRGB(255, 155, 60),

	},

	Ammo12Gauge = {

		label = "12 Gauge",

		min = 8,

		max = 20,

		color = Color3.fromRGB(255, 80, 70),

	},

	Ammo300Magnum = {

		label = ".300 Magnum",

		min = 3,

		max = 10,

		color = Color3.fromRGB(255, 220, 70),

	},

}

local AMMO_RANDOM_POOL = {
	"Ammo9mm",
	"Ammo9mm",
	"Ammo45ACP",
	"Ammo556",
	"Ammo556",
	"Ammo762",
	"Ammo762",
	"Ammo12Gauge",
	"Ammo300Magnum",

	-- ammo khusus RPG
	"AmmoRocket",
}

-- ============================================================

-- CONFIG TAS / BACKPACK CAPACITY

-- ============================================================

local BACKPACK_CAPACITY = {

	[-1] = 100,

	[1]  = 200,

	[2]  = 250,

	[3]  = 300,

}

local ITEM_WEIGHT = {

	Material = 1,

	Ammo     = 0.5,

}

-- ============================================================

-- REMOTE & BINDABLE

-- ============================================================

local function ensureRootInstance(name, className)

	local existing = ReplicatedStorage:FindFirstChild(name)

	if existing and existing.ClassName == className then return existing end

	if existing then existing:Destroy() end

	local obj = Instance.new(className)

	obj.Name   = name

	obj.Parent = ReplicatedStorage

	return obj

end

local function ensureFolder(parent, name)

	local folder = parent:FindFirstChild(name)

	if folder and folder:IsA("Folder") then return folder end

	if folder then folder:Destroy() end

	folder        = Instance.new("Folder")

	folder.Name   = name

	folder.Parent = parent

	return folder

end

local function ensureRemoteFunction(parent, name)

	local func = parent:FindFirstChild(name)

	if func and func:IsA("RemoteFunction") then return func end

	if func then func:Destroy() end

	func        = Instance.new("RemoteFunction")

	func.Name   = name

	func.Parent = parent

	return func

end

local inventoryUpdateEvent = ensureRootInstance("InventoryUpdate", "RemoteEvent")

local weaponUpdateEvent    = ensureRootInstance("WeaponUpdate",    "RemoteEvent")

local dropItemEvent        = ensureRootInstance("DropItemEvent",   "RemoteEvent")

local getInvFunc           = ensureRootInstance("GetInventory",    "BindableFunction")

local upgradeItemFunc      = ensureRootInstance("UpgradeItem",     "BindableFunction")

local remotesFolder        = ensureFolder(ReplicatedStorage, "Remotes")

local reloadAmmoFunc       = ensureRemoteFunction(remotesFolder, "ReloadAmmo")

-- ============================================================

-- DATA PLAYER

-- ============================================================

local playerInventory = {}

local playerWeapons   = {}

local function initInventory(player)

	if not playerInventory[player] then

		playerInventory[player] = {

			materials = { ScrapMetal = 0, Cloth = 0, Electronic = 0 },

			items     = { Helm = -1, Vest = -1, Tas = -1, Ammo = 0 },

			ammo = {

				Ammo9mm = 0, Ammo45ACP = 0, Ammo556 = 0,

				Ammo762 = 0, Ammo12Gauge = 0, Ammo300Magnum = 0,

			},

		}

	end

	if not playerWeapons[player] then

		playerWeapons[player] = { slot1 = nil, slot2 = nil, sidearm = nil }

	end

end

local function getInventory(player)

	if not playerInventory[player] then initInventory(player) end

	return playerInventory[player]

end

local function getWeapons(player)

	if not playerWeapons[player] then initInventory(player) end

	return playerWeapons[player]

end

local function ensureAmmoData(inv)

	if not inv.items        then inv.items      = {} end

	if inv.items.Ammo == nil then inv.items.Ammo = 0 end

	if not inv.ammo         then inv.ammo       = {} end

	for ammoType in pairs(AMMO_CONFIG) do

		if inv.ammo[ammoType] == nil then inv.ammo[ammoType] = 0 end

	end

end

local function getTotalAmmo(inv)

	ensureAmmoData(inv)

	local total = 0

	for _, amount in pairs(inv.ammo) do total += amount end

	return total

end

local function getInventoryCapacity(inv)

	local currentTasLevel = inv.items.Tas or -1

	local maxCapacity     = BACKPACK_CAPACITY[currentTasLevel] or BACKPACK_CAPACITY[-1]

	local currentWeight   = 0

	for _, amount in pairs(inv.materials) do

		currentWeight += (amount * ITEM_WEIGHT.Material)

	end

	currentWeight += (getTotalAmmo(inv) * ITEM_WEIGHT.Ammo)

	return currentWeight, maxCapacity

end

local function syncInventory(player)

	local inv = getInventory(player)

	ensureAmmoData(inv)

	inv.items.Ammo = getTotalAmmo(inv)

	local currentWeight, maxCapacity = getInventoryCapacity(inv)

	player:SetAttribute("CurrentWeight",  currentWeight)

	player:SetAttribute("MaxCapacity",    maxCapacity)

	player:SetAttribute("InventoryAmmo",  inv.items.Ammo)

	for ammoType, amount in pairs(inv.ammo) do

		player:SetAttribute(ammoType, amount)

	end

	inventoryUpdateEvent:FireClient(player, inv)

end

------------------------------------------------
-- DEMO ROCKET AMMO
------------------------------------------------
local GIVE_DEMO_ROCKET_AMMO = true

local function giveDemoRocketAmmo(player)
	if not GIVE_DEMO_ROCKET_AMMO then return end
	if player:GetAttribute("DemoRocketAmmoGiven") == true then return end

	local inv = getInventory(player)
	ensureAmmoData(inv)

	inv.ammo.AmmoRocket = 10
	inv.items.Ammo = getTotalAmmo(inv)

	player:SetAttribute("DemoRocketAmmoGiven", true)

	syncInventory(player)

	print("[DEMO ROCKET AMMO]", player.Name, "dapat 10 Rocket Ammo")
end

local function syncWeapons(player)

	local pw = getWeapons(player)

	weaponUpdateEvent:FireClient(player, {

		slot1   = pw.slot1   and pw.slot1.name   or nil,

		slot2   = pw.slot2   and pw.slot2.name   or nil,

		sidearm = pw.sidearm and pw.sidearm.name or nil,

	})

end

-- ============================================================

-- CONFIG MATERIAL / ITEM / WEAPON

-- ============================================================

local MATERIAL_SPAWN = {

	high   = { ScrapMetal={min=2,max=5}, Cloth={min=1,max=3}, Electronic={min=1,max=2} },

	medium = { ScrapMetal={min=1,max=3}, Cloth={min=1,max=2}, Electronic={min=0,max=1} },

	low    = { ScrapMetal={min=1,max=2}, Cloth={min=0,max=1}, Electronic={min=0,max=1} },

}

local ITEM_SPAWN_CHANCE = {

	high   = { Helm=0.90, Vest=0.90, Tas=0.85, Ammo=1.00 },

	medium = { Helm=0.75, Vest=0.75, Tas=0.65, Ammo=0.95 },

	low    = { Helm=0.50, Vest=0.50, Tas=0.45, Ammo=0.80 },

}

local AMMO_PACKS_PER_TIER = {

	high   = { min=4, max=8 },

	medium = { min=3, max=6 },

	low    = { min=2, max=4 },

}

local WEAPON_SPAWN_CHANCE    = { high=1.00, medium=0.95, low=0.85 }

local WEAPON_COUNT_PER_TIER  = { high={min=2,max=4}, medium={min=1,max=3}, low={min=1,max=2} }

local WEAPON_SLOT_WEIGHT     = { high={primary_weight=0.78}, medium={primary_weight=0.65}, low={primary_weight=0.35} }

local PRIMARY_POOL = {

	high   = { "SniperRifle","AssaultRifle","AssaultRifle","Shotgun","SMG" },

	medium = { "AssaultRifle","AssaultRifle","Shotgun","SMG" },

	low    = { "SMG","AssaultRifle" },

}

local SIDEARM_POOL = {

	high   = { "Pistol","Revolver" },

	medium = { "Pistol","Pistol","Revolver" },

	low    = { "Pistol","Pistol","Revolver" },

}

local WEAPON_PICKUP_DISTANCE = 6

local INTERACT_PART_SIZE     = Vector3.new(4, 2, 4)

local WEAPON_SCATTER         = 14

local GLOW_PRIMARY           = Color3.fromRGB(255, 200,  60)

local GLOW_SIDEARM           = Color3.fromRGB(100, 200, 255)

-- ============================================================

-- VEST NAMES & STATS

-- ============================================================

local VEST_NAMES = {

	[1] = "BR_Level1_Vest_R6_Roblox",

	[2] = "BR_Level2_Vest_R6_Roblox",

	[3] = "BR_Level3_Vest_R6_Roblox",

}

local VEST_C0 = CFrame.new(0, 0, -0.05)

local EQUIPPED_VEST_NAME = "EquippedVest"

local VEST_STATS = {

	[1] = { MaxArmor=60,  DamageReduction=0.25 },

	[2] = { MaxArmor=90,  DamageReduction=0.35 },

	[3] = { MaxArmor=120, DamageReduction=0.45 },

}

-- ============================================================

-- EQUIPMENT CONFIG

-- ============================================================

local EQUIPMENT_CONFIG = {

	Helm = {

		folder      = "Helm",

		equippedName = "EquippedHelmet",

		attachPart  = "Head",

		names = {

			[1] = "Helmet Level 1",

			[2] = "Helmet Level 2",

			[3] = "Helmet Level 3",

		},

		c0 = CFrame.new(0, 1.3, 0.4) * CFrame.Angles(

			math.rad(360),

			math.rad(0),

			math.rad(0)

		),

		groundScale = 1,

	},

	Vest = {

		folder      = "Vest",

		equippedName = "EquippedVest",

		attachPart  = "Torso",

		names = {

			[1] = "BR_Level1_Vest_R6_Roblox",

			[2] = "BR_Level2_Vest_R6_Roblox",

			[3] = "BR_Level3_Vest_R6_Roblox",

		},

		c0          = VEST_C0,

		scale       = 1,

		groundScale = 1,

	},

	Tas = {

		folder      = "Tas",

		equippedName = "EquippedTas",

		attachPart  = "Torso",

		names = {

			[1] = "Tas Level 1",

			[2] = "Tas Level 2",

			[3] = "Tas Level 3",

		},

		c0          = CFrame.new(0, 0.05, 0.55) * CFrame.Angles(math.rad(90), math.rad(0), math.rad(0)),

		scale       = 0.014,

		groundScale = 0.014,

	},

}

-- ============================================================

-- WEAPON ASSET COLLECTOR

-- ============================================================

local weaponAssets = {}

local function collectWeaponAssets()

	table.clear(weaponAssets)

	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")

	if not assetsFolder then warn("[LOOT] Assets tidak ditemukan") return end

	local weaponRoot = assetsFolder:FindFirstChild("Weapon")

	if not weaponRoot then warn("[LOOT] Assets > Weapon tidak ditemukan") return end

	for _, slotFolder in ipairs(weaponRoot:GetChildren()) do

		if slotFolder:IsA("Folder") then

			for _, categoryFolder in ipairs(slotFolder:GetChildren()) do

				if categoryFolder:IsA("Folder") then

					local catName = categoryFolder.Name

					weaponAssets[catName] = weaponAssets[catName] or {}

					for _, weaponAsset in ipairs(categoryFolder:GetChildren()) do

						if weaponAsset:IsA("Model") or weaponAsset:IsA("Tool") then

							table.insert(weaponAssets[catName], weaponAsset)

						end

					end

					if #weaponAssets[catName] > 0 then

						print(string.format("[LOOT] Weapon %-20s: %d aset", catName, #weaponAssets[catName]))

					end

				end

			end

		end

	end

end

-- ============================================================

-- GENERAL HELPERS

-- ============================================================

local function randomFrom(list)

	if not list or #list == 0 then return nil end

	return list[math.random(1, #list)]

end

local function makePart(parent, size, color, material, shape)

	local part = Instance.new("Part")

	part.Size        = size

	part.Color       = color

	part.Material    = material or Enum.Material.SmoothPlastic

	part.Anchored    = true

	part.CanCollide  = false

	part.CanTouch    = false

	part.CanQuery    = false

	if shape then part.Shape = shape end

	part.Parent = parent

	return part

end

local function disableScripts(obj)

	for _, d in ipairs(obj:GetDescendants()) do

		if d:IsA("BaseScript") then d.Disabled = true end

	end

end

-- ============================================================

-- getRootPart yang robust

-- ============================================================

local function getRootPart(model)

	if model:IsA("BasePart") then return model end

	local handle = model:FindFirstChild("Handle", true)

	if handle and handle:IsA("BasePart") then

		return handle

	end

	if model.PrimaryPart then

		return model.PrimaryPart

	end

	local bestPart   = nil

	local bestVolume = -1

	for _, obj in ipairs(model:GetDescendants()) do

		if obj:IsA("BasePart") then

			local s = obj.Size

			local v = s.X * s.Y * s.Z

			if v > bestVolume then

				bestVolume = v

				bestPart   = obj

			end

		end

	end

	if bestPart then

		warn(string.format(

			"[LOOT] getRootPart: '%s' tidak punya Handle/PrimaryPart, pakai '%s' (vol=%.3f)",

			model.Name, bestPart.Name, bestVolume

			))

	end

	return bestPart

end

local function getTorso(character)

	return character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso")

end

local function getAttachPart(character, partName)

	if partName == "Torso" then

		return character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso")

	end

	if partName == "Head" then

		return character:FindFirstChild("Head")

	end

	return character:FindFirstChild(partName)

end

-- ============================================================

-- prepareEquipmentModel

-- ============================================================

local function prepareEquipmentModel(model)

	local rootPart = getRootPart(model)

	if not rootPart then

		warn("[EQUIP] prepareEquipmentModel: tidak ada BasePart di", model.Name)

		return nil

	end

	if model:IsA("Model") then

		model.PrimaryPart = rootPart

	end

	for _, obj in ipairs(model:GetDescendants()) do

		if obj:IsA("BaseScript") then

			obj.Disabled = true

		end

	end

	rootPart.Anchored   = false

	rootPart.CanCollide = false

	rootPart.CanTouch   = false

	rootPart.CanQuery   = false

	rootPart.Massless   = true

	for _, obj in ipairs(model:GetDescendants()) do

		if obj:IsA("BasePart") then

			obj.Anchored   = false

			obj.CanCollide = false

			obj.CanTouch   = false

			obj.CanQuery   = false

			obj.Massless   = true

		end

	end

	for _, obj in ipairs(model:GetDescendants()) do

		if obj:IsA("BasePart") and obj ~= rootPart then

			for _, w in ipairs(rootPart:GetChildren()) do

				if w:IsA("WeldConstraint") and w.Part1 == obj then

					w:Destroy()

				end

			end

			local weld      = Instance.new("WeldConstraint")

			weld.Name       = "InternalWeld"

			weld.Part0      = rootPart

			weld.Part1      = obj

			weld.Parent     = rootPart

		end

	end

	return rootPart

end

-- ============================================================

-- VEST SYSTEM

-- ============================================================

local function getVestTemplate(level)

	level = math.clamp(level or 1, 1, 3)

	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")

	if not assetsFolder then warn("[VEST] Assets tidak ditemukan") return nil end

	local itemFolder = assetsFolder:FindFirstChild("Item")

	if not itemFolder then warn("[VEST] Assets > Item tidak ditemukan") return nil end

	local vestFolder = itemFolder:FindFirstChild("Vest")

	if not vestFolder then warn("[VEST] Assets > Item > Vest tidak ditemukan") return nil end

	local vestName = VEST_NAMES[level]

	local vest = vestFolder:FindFirstChild(vestName)

	if not vest then warn("[VEST] Model tidak ditemukan:", vestName) return nil end

	return vest

end

local function applyVestStats(character, level)

	level = math.clamp(level or 1, 1, 3)

	local stats = VEST_STATS[level]

	if not stats then return end

	character:SetAttribute("ArmorLevel",          level)

	character:SetAttribute("Armor",               stats.MaxArmor)

	character:SetAttribute("MaxArmor",            stats.MaxArmor)

	character:SetAttribute("VestDamageReduction", stats.DamageReduction)

	character:SetAttribute("ArmorBroken",         false)

	print("[VEST] Stats applied:", character.Name, "Lv", level, "Armor", stats.MaxArmor)

end

local function equipVest(player, level)

	local character = player.Character

	if not character then return end

	local torso = getTorso(character)

	if not torso then warn("[VEST] Torso tidak ditemukan:", character.Name) return end

	level = math.clamp(level or 1, 1, 3)

	local old = character:FindFirstChild(EQUIPPED_VEST_NAME)

	if old then old:Destroy() end

	local vestTemplate = getVestTemplate(level)

	if not vestTemplate then return end

	local vestClone      = vestTemplate:Clone()

	vestClone.Name       = EQUIPPED_VEST_NAME

	vestClone.Parent     = character

	local rootPart = prepareEquipmentModel(vestClone)

	if not rootPart then

		vestClone:Destroy()

		return

	end

	if vestClone:IsA("Model") then

		vestClone:PivotTo(torso.CFrame * VEST_C0)

	else

		vestClone.CFrame = torso.CFrame * VEST_C0

	end

	local weld      = Instance.new("WeldConstraint")

	weld.Name       = "VestTorsoWeld"

	weld.Part0      = torso

	weld.Part1      = rootPart

	weld.Parent     = rootPart

	applyVestStats(character, level)

	print("[VEST] Vest Lv" .. tostring(level) .. " dipasang ke", player.Name)

end

-- ============================================================

-- EQUIPMENT SYSTEM (Helm, Tas)

-- ============================================================

local function getEquipmentTemplate(itemType, level)

	local config = EQUIPMENT_CONFIG[itemType]

	if not config then return nil end

	level = math.clamp(level or 1, 1, 3)

	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")

	if not assetsFolder then return nil end

	local itemFolder = assetsFolder:FindFirstChild("Item")

	if not itemFolder then return nil end

	local folder = itemFolder:FindFirstChild(config.folder)

	if not folder then

		warn("[EQUIP] Folder tidak ditemukan:", config.folder)

		return nil

	end

	local modelName = config.names[level]

	local template  = folder:FindFirstChild(modelName)

	if not template then

		warn("[EQUIP] Model tidak ditemukan:", itemType, modelName)

		return nil

	end

	return template

end

local function equipEquipment(player, itemType, level)

	local config = EQUIPMENT_CONFIG[itemType]

	if not config then return end

	local character = player.Character

	if not character then return end

	local attachPart = getAttachPart(character, config.attachPart)

	if not attachPart then

		warn("[EQUIP] AttachPart tidak ditemukan:", config.attachPart, "untuk", player.Name)

		return

	end

	level = math.clamp(level or 1, 1, 3)

	local old = character:FindFirstChild(config.equippedName)

	if old then old:Destroy() end

	local template = getEquipmentTemplate(itemType, level)

	if not template then

		warn("[EQUIP] Tidak ada template untuk", itemType, "level", level)

		return

	end

	local clone      = template:Clone()

	clone.Name       = config.equippedName

	clone.Parent     = character

	local rootPart = prepareEquipmentModel(clone)

	if not rootPart then

		warn("[EQUIP] rootPart nil setelah prepare:", itemType, level)

		clone:Destroy()

		return

	end

	local scaleVal = config.scale or 1

	if clone:IsA("Model") and scaleVal ~= 1 then

		local ok, err = pcall(function() clone:ScaleTo(scaleVal) end)

		if not ok then

			warn("[EQUIP] ScaleTo gagal:", err)

		end

		rootPart = getRootPart(clone)

		if not rootPart then

			warn("[EQUIP] rootPart hilang setelah ScaleTo:", itemType)

			clone:Destroy()

			return

		end

		clone.PrimaryPart = rootPart

	end

	local targetCF = attachPart.CFrame * config.c0

	if clone:IsA("Model") then

		local ok, err = pcall(function() clone:PivotTo(targetCF) end)

		if not ok then

			warn("[EQUIP] PivotTo gagal, fallback manual CFrame:", err)

			rootPart.CFrame = targetCF

		end

	else

		clone.CFrame = targetCF

	end

	local attachWeld      = Instance.new("WeldConstraint")

	attachWeld.Name       = itemType .. "AttachWeld"

	attachWeld.Part0      = attachPart

	attachWeld.Part1      = rootPart

	attachWeld.Parent     = rootPart

	print(string.format("[EQUIP] %s pakai %s Lv%d (root: %s)", player.Name, itemType, level, rootPart.Name))

end

-- ============================================================

-- [FIX v8] UNEQUIP WEAPON DARI KARAKTER (SERVER SIDE)
-- Fungsi ini wajib dipanggil sebelum drop weapon agar:
-- 1. Tool / Model senjata dihapus dari Character
-- 2. Tool / Model senjata dihapus dari Backpack
-- 3. Animasi pegang senjata ikut hilang
-- ============================================================

local function unequipWeaponFromCharacter(player, weaponName)
	if not weaponName then return end
	local character = player.Character

	-- 1. PAKSA Humanoid untuk Unequip terlebih dahulu agar animasi tangan kembali normal
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:UnequipTools()
	end

	-- 2. Hapus senjata dari Backpack (StarterGear / Backpack)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, item in ipairs(backpack:GetChildren()) do
			if (item:IsA("Tool") or item:IsA("Model")) and item.Name == weaponName then
				item:Destroy()
				print("[UNEQUIP] Hapus", weaponName, "dari Backpack")
			end
		end
	end

	-- 3. Hapus senjata dari Character (jaga-jaga jika masih menempel secara fisik)
	if character then
		for _, item in ipairs(character:GetChildren()) do
			if (item:IsA("Tool") or item:IsA("Model")) and item.Name == weaponName then
				item:Destroy()
				print("[UNEQUIP] Hapus", weaponName, "dari Character")
			end
		end
	end
end
-- ============================================================

-- BINDABLE / REMOTE ACCESS

-- ============================================================

getInvFunc.OnInvoke = function(player)

	return getInventory(player)

end

upgradeItemFunc.OnInvoke = function(player, itemName, scrap, cloth, electronic)

	local inv  = getInventory(player)

	local mats = inv.materials

	if itemName == "Ammo" then return false, "Ammo tidak bisa di-upgrade" end

	if inv.items[itemName] == nil then return false, "Item tidak dikenal: " .. tostring(itemName) end

	if mats.ScrapMetal < scrap or mats.Cloth < cloth or mats.Electronic < electronic then

		return false, "Material tidak cukup"

	end

	local currentLevel = inv.items[itemName]

	if currentLevel == nil or currentLevel < 0 then return false, "Belum punya " .. tostring(itemName) end

	if currentLevel >= 3 then return false, tostring(itemName) .. " sudah max level" end

	mats.ScrapMetal -= scrap

	mats.Cloth      -= cloth

	mats.Electronic -= electronic

	inv.items[itemName] = currentLevel + 1

	if itemName == "Vest" then

		equipVest(player, inv.items.Vest)

	elseif itemName == "Helm" then

		equipEquipment(player, "Helm", inv.items.Helm)

	elseif itemName == "Tas" then

		equipEquipment(player, "Tas", inv.items.Tas)

	end

	syncInventory(player)

	return true, tostring(itemName) .. " naik ke Level " .. tostring(currentLevel + 1)

end

reloadAmmoFunc.OnServerInvoke = function(player, ammoType, neededAmmo)

	local inv = getInventory(player)

	ensureAmmoData(inv)

	if not AMMO_CONFIG[ammoType] then

		warn("[RELOAD] Ammo type tidak dikenal:", ammoType)

		return 0, 0

	end

	neededAmmo    = math.clamp(math.floor(tonumber(neededAmmo) or 0), 0, 999)

	local available = inv.ammo[ammoType] or 0

	if available <= 0 or neededAmmo <= 0 then

		syncInventory(player)

		return 0, available

	end

	local loaded = math.min(neededAmmo, available)

	inv.ammo[ammoType] = available - loaded

	inv.items.Ammo     = getTotalAmmo(inv)

	syncInventory(player)

	print("[RELOAD]", player.Name, ammoType, "loaded:", loaded, "remaining:", inv.ammo[ammoType])

	return loaded, inv.ammo[ammoType]

end

-- ============================================================

-- AMMO MODEL

-- ============================================================

local function buildAmmoModel(position)

	local model = Instance.new("Model")

	model.Name  = "LootModel"

	local box = makePart(model, Vector3.new(1, 0.55, 0.7), Color3.fromRGB(90,75,45), Enum.Material.Wood)

	box.Name     = "AmmoBox"

	box.Position = position + Vector3.new(0, 0.28, 0)

	local lid = makePart(model, Vector3.new(1.05, 0.12, 0.75), Color3.fromRGB(70,58,35), Enum.Material.Wood)

	lid.Name     = "AmmoLid"

	lid.Position = position + Vector3.new(0, 0.58, 0)

	for i = -1, 1 do

		local bullet = makePart(model, Vector3.new(0.13,0.28,0.13), Color3.fromRGB(230,190,70), Enum.Material.Metal, Enum.PartType.Cylinder)

		bullet.Name     = "AmmoBullet"

		bullet.Position = position + Vector3.new(i * 0.22, 0.75, 0)

	end

	local label = makePart(model, Vector3.new(0.45,0.25,0.04), Color3.fromRGB(180,50,40), Enum.Material.SmoothPlastic)

	label.Name     = "AmmoLabel"

	label.Position = position + Vector3.new(0, 0.28, 0.37)

	model.PrimaryPart = box

	return model

end

local function applyAmmoVisual(model, ammoType)

	local ammoInfo = AMMO_CONFIG[ammoType]

	if not ammoInfo then return end

	local mainColor = ammoInfo.color or Color3.fromRGB(255,255,255)

	for _, obj in ipairs(model:GetDescendants()) do

		if obj:IsA("BasePart") then

			if obj.Name == "AmmoBox" then

				obj.Color    = mainColor

				obj.Material = Enum.Material.Metal

			elseif obj.Name == "AmmoLid" then

				obj.Color    = mainColor:Lerp(Color3.fromRGB(0,0,0), 0.25)

				obj.Material = Enum.Material.Metal

			elseif obj.Name == "AmmoLabel" then

				obj.Color    = mainColor

				obj.Material = Enum.Material.Neon

			elseif obj.Name == "AmmoBullet" then

				obj.Color    = Color3.fromRGB(230,190,70)

				obj.Material = Enum.Material.Metal

			end

		end

	end

end

-- ============================================================

-- MATERIAL MODELS

-- ============================================================

local function buildScrapModel(position)

	local model = Instance.new("Model")

	model.Name  = "LootModel"

	for i = 1, 3 do

		local scrap = makePart(model,

			Vector3.new(math.random(5,9)/10, 0.15, math.random(5,9)/10),

			Color3.fromRGB(120+math.random(-20,20), 120, 130),

			Enum.Material.CorrodedMetal

		)

		scrap.Position    = position + Vector3.new(math.random(-4,4)/10, 0.1+i*0.13, math.random(-4,4)/10)

		scrap.Orientation = Vector3.new(0, math.random(0,360), math.random(-10,10))

		if i == 1 then model.PrimaryPart = scrap end

	end

	return model

end

local function buildClothModel(position)

	local model = Instance.new("Model")

	model.Name  = "LootModel"

	local roll  = makePart(model, Vector3.new(0.9,0.5,0.5), Color3.fromRGB(180,160,130), Enum.Material.Fabric, Enum.PartType.Cylinder)

	roll.Position    = position + Vector3.new(0, 0.25, 0)

	roll.Orientation = Vector3.new(0, 0, 90)

	model.PrimaryPart = roll

	return model

end

local function buildElectronicModel(position)

	local model = Instance.new("Model")

	model.Name  = "LootModel"

	local board = makePart(model, Vector3.new(0.9,0.12,0.7), Color3.fromRGB(40,120,80), Enum.Material.SmoothPlastic)

	board.Position = position + Vector3.new(0, 0.15, 0)

	for _ = 1, 4 do

		local chip = makePart(model, Vector3.new(0.15,0.15,0.15), Color3.fromRGB(30,30,35), Enum.Material.Metal)

		chip.Position = position + Vector3.new(math.random(-3,3)/10, 0.28, math.random(-25,25)/100)

	end

	model.PrimaryPart = board

	return model

end

-- ============================================================

-- LOOT FOLDER

-- ============================================================

local lootFolder = workspace:FindFirstChild("LootDrops")

if lootFolder then lootFolder:Destroy() end

lootFolder        = Instance.new("Folder")

lootFolder.Name   = "LootDrops"

lootFolder.Parent = workspace

-- ============================================================

-- CREATE MATERIAL DROP

-- ============================================================

local MATERIAL_BUILDERS = {

	ScrapMetal = buildScrapModel,

	Cloth      = buildClothModel,

	Electronic = buildElectronicModel,

}

local function createMaterialDrop(position, materialType)

	local builder = MATERIAL_BUILDERS[materialType]

	if not builder then return end

	local model        = builder(position)

	model.Name         = "LootMat_" .. materialType

	model.Parent       = lootFolder

	local prompt       = Instance.new("ProximityPrompt")

	prompt.ActionText  = "Ambil " .. materialType

	prompt.ObjectText  = "Material"

	prompt.HoldDuration = 0

	prompt.MaxActivationDistance = 6

	prompt.RequiresLineOfSight   = false

	prompt.KeyboardKeyCode       = Enum.KeyCode.E

	prompt.Parent = model.PrimaryPart

	prompt.Triggered:Connect(function(player)

		if not model or not model.Parent then return end

		local inv    = getInventory(player)

		local amount = math.random(1, 3)

		local currentWeight, maxCapacity = getInventoryCapacity(inv)

		if currentWeight + amount * ITEM_WEIGHT.Material > maxCapacity then

			warn("[CAPACITY]", player.Name, "tas penuh (material)")

			return

		end

		inv.materials[materialType] += amount

		syncInventory(player)

		model:Destroy()

		print("[MATERIAL]", player.Name, "ambil", materialType, "+", amount)

	end)

end

-- ============================================================

-- CREATE ITEM DROP

-- ============================================================

local ITEM_BUILDERS = { Ammo = buildAmmoModel }

local function rollEquipmentLevel()

	local r = math.random()

	if r < 0.65 then return 1

	elseif r < 0.90 then return 2

	else return 3 end

end

local function prepareGroundItemModel(model)

	local rootPart = getRootPart(model)

	if rootPart and model:IsA("Model") then

		model.PrimaryPart = rootPart

	end

	for _, obj in ipairs(model:GetDescendants()) do

		if obj:IsA("BaseScript") then

			obj.Disabled = true

		elseif obj:IsA("BasePart") then

			obj.Anchored   = true

			obj.CanCollide = false

			obj.CanTouch   = false

			obj.CanQuery   = false

			obj.Massless   = true

		end

	end

	return rootPart

end

local function createEquipmentItemDrop(position, itemType)

	local config   = EQUIPMENT_CONFIG[itemType]

	if not config then return nil end

	local level    = rollEquipmentLevel()

	local template = getEquipmentTemplate(itemType, level)

	if not template then return nil end

	local model    = template:Clone()

	model.Name     = "LootItem_" .. itemType

	model.Parent   = lootFolder

	local rootPart = prepareGroundItemModel(model)

	if model:IsA("Model") then

		local gs = config.groundScale or config.scale or 1

		if gs ~= 1 then pcall(function() model:ScaleTo(gs) end) end

		rootPart = getRootPart(model)

		if rootPart then model.PrimaryPart = rootPart end

	end

	local cf = CFrame.new(position + Vector3.new(0, 0.5, 0))

		* CFrame.Angles(0, math.rad(math.random(0,360)), 0)

	if model:IsA("Model") and model.PrimaryPart then

		model:PivotTo(cf)

	elseif rootPart then

		rootPart.CFrame = cf

	end

	local interactPart            = Instance.new("Part")

	interactPart.Name             = "InteractPart"

	interactPart.Size             = Vector3.new(4, 2, 4)

	interactPart.Transparency     = 1

	interactPart.Anchored         = true

	interactPart.CanCollide       = false

	interactPart.CanTouch         = false

	interactPart.CanQuery         = false

	interactPart.Position         = position + Vector3.new(0, 0.5, 0)

	interactPart.Parent           = model

	local light           = Instance.new("PointLight")

	light.Color           = Color3.fromRGB(255, 240, 200)

	light.Range           = 4

	light.Brightness      = 0.5

	light.Parent          = interactPart

	local prompt                       = Instance.new("ProximityPrompt")

	prompt.ActionText                  = "Ambil " .. itemType .. " Lv" .. tostring(level)

	prompt.ObjectText                  = itemType

	prompt.HoldDuration                = 0

	prompt.MaxActivationDistance       = 6

	prompt.RequiresLineOfSight         = false

	prompt.KeyboardKeyCode             = Enum.KeyCode.E

	prompt.Parent                      = interactPart

	model:SetAttribute("ItemType",  itemType)

	model:SetAttribute("ItemLevel", level)

	return model, prompt

end

local function createItemDrop(position, itemType)

	if itemType == "Helm" or itemType == "Vest" or itemType == "Tas" then

		local model, prompt = createEquipmentItemDrop(position, itemType)

		if not model or not prompt then

			warn("[ITEM] Gagal membuat drop:", itemType)

			return

		end

		prompt.Triggered:Connect(function(player)

			if not model or not model.Parent then return end

			local inv          = getInventory(player)

			local level        = model:GetAttribute("ItemLevel") or 1

			local currentLevel = inv.items[itemType] or -1

			if currentLevel < level then inv.items[itemType] = level end

			if itemType == "Vest" then

				equipVest(player, inv.items.Vest)

			else

				equipEquipment(player, itemType, inv.items[itemType])

			end

			syncInventory(player)

			model:Destroy()

			print("[ITEM]", player.Name, "ambil", itemType, "Lv", inv.items[itemType])

		end)

		return

	end

	local builder = ITEM_BUILDERS[itemType]

	if not builder then return end

	local model    = builder(position)

	model.Name     = "LootItem_" .. itemType

	model.Parent   = lootFolder

	local light           = Instance.new("PointLight")

	light.Color           = Color3.fromRGB(255, 240, 200)

	light.Range           = 4

	light.Brightness      = 0.5

	light.Parent          = model.PrimaryPart

	local prompt                       = Instance.new("ProximityPrompt")

	prompt.ActionText                  = "Ambil " .. itemType

	prompt.ObjectText                  = "Item"

	prompt.HoldDuration                = 0

	prompt.MaxActivationDistance       = 6

	prompt.RequiresLineOfSight         = false

	prompt.KeyboardKeyCode             = Enum.KeyCode.E

	prompt.Parent                      = model.PrimaryPart

	if itemType == "Ammo" then

		local ammoType = AMMO_RANDOM_POOL[math.random(1, #AMMO_RANDOM_POOL)]

		local ammoInfo = AMMO_CONFIG[ammoType]

		local amount   = math.random(ammoInfo.min, ammoInfo.max)

		model:SetAttribute("AmmoType",   ammoType)

		model:SetAttribute("AmmoAmount", amount)

		applyAmmoVisual(model, ammoType)

		light.Color       = ammoInfo.color or Color3.fromRGB(255, 240, 200)

		prompt.ActionText = "Ambil +" .. amount .. " " .. ammoInfo.label

		prompt.ObjectText = "Ammo"

	end

	prompt.Triggered:Connect(function(player)

		if not model or not model.Parent then return end

		local inv = getInventory(player)

		if itemType == "Ammo" then

			ensureAmmoData(inv)

			local ammoType = model:GetAttribute("AmmoType")

			if not ammoType or not AMMO_CONFIG[ammoType] then

				ammoType = AMMO_RANDOM_POOL[math.random(1, #AMMO_RANDOM_POOL)]

			end

			local ammoInfo       = AMMO_CONFIG[ammoType]

			local amountOnGround = model:GetAttribute("AmmoAmount") or math.random(ammoInfo.min, ammoInfo.max)

			local currentWeight, maxCapacity = getInventoryCapacity(inv)

			local availableSpace = maxCapacity - currentWeight

			if availableSpace <= 0 then

				warn("[CAPACITY]", player.Name, "tas penuh (ammo)")

				return

			end

			local maxCanCarry  = math.floor(availableSpace / ITEM_WEIGHT.Ammo)

			local amountTaken  = math.min(amountOnGround, maxCanCarry)

			if amountTaken <= 0 then return end

			inv.ammo[ammoType] = (inv.ammo[ammoType] or 0) + amountTaken

			inv.items.Ammo     = getTotalAmmo(inv)

			if amountTaken < amountOnGround then

				local leftOver = amountOnGround - amountTaken

				model:SetAttribute("AmmoAmount", leftOver)

				prompt.ActionText = "Ambil +" .. leftOver .. " " .. ammoInfo.label

				syncInventory(player)

				print("[AMMO]", player.Name, "ambil sebagian:", amountTaken, ammoInfo.label, "sisa:", leftOver)

				return

			end

			syncInventory(player)

			model:Destroy()

			print("[AMMO]", player.Name, "ambil", amountTaken, ammoInfo.label, "total:", inv.ammo[ammoType])

		end

	end)

end

-- ============================================================

-- CREATE WEAPON DROP

-- ============================================================

local function setupGroundWeapon(object)

	disableScripts(object)

	for _, d in ipairs(object:GetDescendants()) do

		if d:IsA("BasePart") then

			d.Anchored = true; d.CanCollide = false; d.CanTouch = false; d.CanQuery = false; d.Massless = true

		end

	end

	if object:IsA("BasePart") then

		object.Anchored = true; object.CanCollide = false; object.CanTouch = false; object.CanQuery = false; object.Massless = true

	end

end

local function getFirstBasePart(object)

	if object:IsA("BasePart") then return object end

	return object:FindFirstChildWhichIsA("BasePart", true)

end

local function moveAllPartsByFirstPart(object, targetCFrame)

	local firstPart = getFirstBasePart(object)

	if not firstPart then return end

	local delta = targetCFrame * firstPart.CFrame:Inverse()

	for _, d in ipairs(object:GetDescendants()) do

		if d:IsA("BasePart") then d.CFrame = delta * d.CFrame end

	end

	if object:IsA("BasePart") then object.CFrame = targetCFrame end

end

local function createWeaponDrop(position, weaponAsset, categoryName, slotKey)

	local groundModel      = weaponAsset:Clone()

	groundModel.Name       = "LootWeapon_" .. slotKey

	groundModel.Parent     = lootFolder

	setupGroundWeapon(groundModel)

	local targetCFrame = CFrame.new(position + Vector3.new(0, 0.5, 0))

		* CFrame.Angles(math.rad(math.random(-8,8)), math.rad(math.random(0,360)), math.rad(math.random(-8,8)))

	if groundModel:IsA("Model") then groundModel:PivotTo(targetCFrame)

	elseif groundModel:IsA("BasePart") then groundModel.CFrame = targetCFrame

	else moveAllPartsByFirstPart(groundModel, targetCFrame) end

	local interactPart            = Instance.new("Part")

	interactPart.Name             = "InteractPart"

	interactPart.Size             = INTERACT_PART_SIZE

	interactPart.Transparency     = 1

	interactPart.Anchored         = true

	interactPart.CanCollide       = false

	interactPart.CanQuery         = false

	interactPart.CanTouch         = false

	interactPart.CastShadow       = false

	interactPart.Position         = position + Vector3.new(0, 0.5, 0)

	interactPart.Parent           = groundModel

	local glowColor        = (slotKey == "sidearm") and GLOW_SIDEARM or GLOW_PRIMARY

	local light            = Instance.new("PointLight")

	light.Color            = glowColor

	light.Range            = 5

	light.Brightness       = 0.7

	light.Parent           = interactPart

	local prompt                       = Instance.new("ProximityPrompt")

	local slotLabel                    = (slotKey == "sidearm") and "SIDEARM" or "SENJATA"

	prompt.ActionText                  = "Ambil [" .. slotLabel .. "]"

	prompt.ObjectText                  = weaponAsset.Name

	prompt.HoldDuration                = 0

	prompt.MaxActivationDistance       = WEAPON_PICKUP_DISTANCE

	prompt.RequiresLineOfSight         = false

	prompt.KeyboardKeyCode             = Enum.KeyCode.E

	prompt.Parent                      = interactPart

	groundModel:SetAttribute("WeaponName",     weaponAsset.Name)

	groundModel:SetAttribute("WeaponCategory", categoryName)

	groundModel:SetAttribute("WeaponSlot",     slotKey)

	return groundModel, prompt

end

-- ============================================================

-- EQUIP / DROP WEAPON

-- ============================================================

local function equipWeapon(player, weaponAsset, categoryName, slotKey)

	local pw   = getWeapons(player)

	pw[slotKey] = { name=weaponAsset.Name, category=categoryName, asset=weaponAsset }

	syncWeapons(player)

	player:SetAttribute("SelectedWeaponId",   weaponAsset.Name)

	player:SetAttribute("SelectedWeaponSlot", slotKey)

	print(string.format("[LOOT] %s ambil [%s] %s", player.Name, slotKey, weaponAsset.Name))

end

-- [FIX v8] dropWeapon — sekarang unequip dari karakter SEBELUM spawn di tanah

local function dropWeapon(player, slotKey)

	local pw   = getWeapons(player)

	local data = pw[slotKey]

	if not data then return end

	-- [FIX] Hapus senjata dari karakter/backpack player dulu

	unequipWeaponFromCharacter(player, data.name)

	-- Clear weapon data dari server state DULU sebelum spawn drop
	pw[slotKey] = nil

	if player:GetAttribute("SelectedWeaponSlot") == slotKey then

		player:SetAttribute("SelectedWeaponId",   "")

		player:SetAttribute("SelectedWeaponSlot", "")

	end

	-- [FIX] Sync ke client SEBELUM spawn (supaya UI update segera)
	syncWeapons(player)

	-- Sekarang spawn di tanah
	local hrp  = player.Character and player.Character:FindFirstChild("HumanoidRootPart")

	local pos  = hrp and hrp.Position + Vector3.new(math.random(-3,3), 0, math.random(-3,3)) or Vector3.new(0, 5, 0)

	local groundModel, prompt = createWeaponDrop(pos, data.asset, data.category, slotKey)

	if not groundModel or not prompt then return end

	prompt.Triggered:Connect(function(triggerPlayer)

		if not groundModel or not groundModel.Parent then return end

		local tpw = getWeapons(triggerPlayer)

		if tpw[slotKey] then dropWeapon(triggerPlayer, slotKey) end

		groundModel:Destroy()

		equipWeapon(triggerPlayer, data.asset, data.category, slotKey)

	end)

end

local function handleWeaponPickup(player, groundModel)

	if not groundModel or not groundModel.Parent then return end

	local weaponName   = groundModel:GetAttribute("WeaponName")

	local categoryName = groundModel:GetAttribute("WeaponCategory")

	local slotKey      = groundModel:GetAttribute("WeaponSlot")

	if not weaponName or not categoryName or not slotKey then return end

	local assetList  = weaponAssets[categoryName]

	local weaponAsset = nil

	if assetList then

		for _, asset in ipairs(assetList) do

			if asset.Name == weaponName then weaponAsset = asset break end

		end

	end

	if not weaponAsset then warn("[LOOT] Asset tidak ditemukan:", weaponName) return end

	local pw = getWeapons(player)

	if slotKey == "sidearm" then

		if pw.sidearm then dropWeapon(player, "sidearm") end

		groundModel:Destroy()

		equipWeapon(player, weaponAsset, categoryName, "sidearm")

		return

	end

	if not pw.slot1 then

		groundModel:Destroy()

		equipWeapon(player, weaponAsset, categoryName, "slot1")

	elseif not pw.slot2 then

		groundModel:Destroy()

		equipWeapon(player, weaponAsset, categoryName, "slot2")

	else

		dropWeapon(player, "slot2")

		groundModel:Destroy()

		equipWeapon(player, weaponAsset, categoryName, "slot2")

	end

end

-- ============================================================

-- SPAWN WEAPON AT SPOT

-- ============================================================

local function spawnWeaponAtSpot(position, tier)

	if math.random() > (WEAPON_SPAWN_CHANCE[tier] or 0.5) then return end

	local countCfg    = WEAPON_COUNT_PER_TIER[tier] or {min=1,max=1}

	local weaponCount = math.random(countCfg.min, countCfg.max)

	for _ = 1, weaponCount do

		local slotWeight  = WEAPON_SLOT_WEIGHT[tier] or {primary_weight=0.6}

		local isSidearm   = math.random() > slotWeight.primary_weight

		local categoryPool, slotKey

		if isSidearm then

			categoryPool = SIDEARM_POOL[tier]; slotKey = "sidearm"

		else

			categoryPool = PRIMARY_POOL[tier];  slotKey = "slot1"

		end

		local categoryName = randomFrom(categoryPool)

		if categoryName then

			local assetList = weaponAssets[categoryName]

			if assetList and #assetList > 0 then

				local weaponAsset = randomFrom(assetList)

				local offset      = Vector3.new(math.random(-WEAPON_SCATTER,WEAPON_SCATTER), 0, math.random(-WEAPON_SCATTER,WEAPON_SCATTER))

				local gm, prompt  = createWeaponDrop(position + offset, weaponAsset, categoryName, slotKey)

				if gm and prompt then

					prompt.Triggered:Connect(function(player) handleWeaponPickup(player, gm) end)

				end

			end

		end

	end

end

-- ============================================================

-- SPAWN LOOT AT POSITION

-- ============================================================

local function spawnLootAtPosition(position, tier)

	local materialConfig = MATERIAL_SPAWN[tier]

	local itemConfig     = ITEM_SPAWN_CHANCE[tier]

	if not materialConfig or not itemConfig then return end

	for materialType, config in pairs(materialConfig) do

		local count = math.random(config.min, config.max)

		for _ = 1, count do

			local offset = Vector3.new(math.random(-8,8), 0, math.random(-8,8))

			createMaterialDrop(position + offset, materialType)

		end

	end

	for itemType, chance in pairs(itemConfig) do

		if itemType ~= "Ammo" and math.random() < chance then

			local offset = Vector3.new(math.random(-6,6), 0, math.random(-6,6))

			createItemDrop(position + offset, itemType)

		end

	end

	local ammoCfg = AMMO_PACKS_PER_TIER[tier]

	if ammoCfg then

		local ammoCount = math.random(ammoCfg.min, ammoCfg.max)

		for _ = 1, ammoCount do

			local offset = Vector3.new(math.random(-9,9), 0, math.random(-9,9))

			createItemDrop(position + offset, "Ammo")

		end

	end

	spawnWeaponAtSpot(position, tier)

end

-- ============================================================

-- SPAWN ALL LOOT

-- ============================================================

local function spawnAllLoot()

	local pubgMap = workspace:FindFirstChild("PUBGMap")

	if not pubgMap then warn("[LOOT] Workspace > PUBGMap tidak ditemukan") return end

	local spots = {}

	for _, object in ipairs(pubgMap:GetDescendants()) do

		if object:IsA("BasePart") then

			local name = object.Name

			local pos  = object.Position

			local dist = math.sqrt(pos.X^2 + pos.Z^2)

			local tier = nil

			if   string.find(name, "IW_Floor")  then tier = "high"

			elseif string.find(name, "RM_Floor1") then tier = "medium"

			elseif string.find(name, "RS_Floor")  then tier = (dist > MAP_HALF*0.5) and "high" or "medium"

			elseif string.find(name, "GH_Floor")  then tier = "medium"

			elseif string.find(name, "SK_Floor")  then tier = "low"

			end

			if tier then table.insert(spots, {pos=pos, tier=tier}) end

		end

	end

	print(string.format("[LOOT] %d loot spots", #spots))

	for _, spot in ipairs(spots) do spawnLootAtPosition(spot.pos, spot.tier) end

	print(string.format("[LOOT] Spawn selesai — %d item di tanah", #lootFolder:GetChildren()))

end

-- ============================================================

-- PLAYER EVENTS

-- ============================================================

Players.PlayerAdded:Connect(function(player)
	initInventory(player)
	giveDemoRocketAmmo(player)

	player.CharacterAdded:Connect(function()

		task.wait(2)

		local inv = getInventory(player)

		syncInventory(player)

		syncWeapons(player)

		if inv.items.Helm and inv.items.Helm >= 1 then equipEquipment(player, "Helm", inv.items.Helm) end

		if inv.items.Vest and inv.items.Vest >= 1 then equipVest(player, inv.items.Vest) end

		if inv.items.Tas  and inv.items.Tas  >= 1 then equipEquipment(player, "Tas",  inv.items.Tas) end

	end)

end)

Players.PlayerRemoving:Connect(function(player)

	playerInventory[player] = nil

	playerWeapons[player]   = nil

end)


-- ============================================================
-- START
-- ============================================================
math.randomseed(os.time())
print("===========================================")
print("[LOOT SYSTEM v8 - DROP FIX]")
print("===========================================")

-- Bungkus proses loading dengan task.spawn agar script tidak ter-pause
task.spawn(function()
	collectWeaponAssets()
	task.wait(6)
	spawnAllLoot()
end)

for _, player in ipairs(Players:GetPlayers()) do
	initInventory(player)
	syncInventory(player)
	syncWeapons(player)
	local inv = getInventory(player)
	if player.Character then
		if inv.items.Helm and inv.items.Helm >= 1 then equipEquipment(player, "Helm", inv.items.Helm) end
		if inv.items.Vest and inv.items.Vest >= 1 then equipVest(player, inv.items.Vest) end
		if inv.items.Tas  and inv.items.Tas  >= 1 then equipEquipment(player, "Tas",  inv.items.Tas) end
	end
end
print("[LOOT SYSTEM] Siap!")

-- ============================================================

--  DROP ITEM HANDLER (DropItemEvent)
--  [FIX v8] Tambah handler "Ammo" dan perbaiki flow "Weapon"
-- ============================================================

local EQUIPPED_NAMES = {

	Helm = "EquippedHelmet",

	Vest = "EquippedVest",

	Tas  = "EquippedTas",

}

local function spawnEquipmentDropAtLevel(position, itemType, level)

	local template = getEquipmentTemplate(itemType, level)

	if not template then

		template = getEquipmentTemplate(itemType, 1)

	end

	if not template then

		warn("[DROP] Template tidak ditemukan untuk", itemType, "Lv", level)

		return nil, nil

	end

	local model    = template:Clone()

	model.Name     = "LootItem_" .. itemType

	model.Parent   = lootFolder

	local rootPart = prepareGroundItemModel(model)

	local config   = EQUIPMENT_CONFIG[itemType]

	if model:IsA("Model") and config then

		local gs = config.groundScale or config.scale or 1

		if gs ~= 1 then pcall(function() model:ScaleTo(gs) end) end

		rootPart = getRootPart(model)

		if rootPart then model.PrimaryPart = rootPart end

	end

	local cf = CFrame.new(position + Vector3.new(0, 0.5, 0))

		* CFrame.Angles(0, math.rad(math.random(0, 360)), 0)

	if model:IsA("Model") and model.PrimaryPart then

		model:PivotTo(cf)

	elseif rootPart then

		rootPart.CFrame = cf

	end

	local interactPart            = Instance.new("Part")

	interactPart.Name             = "InteractPart"

	interactPart.Size             = Vector3.new(4, 2, 4)

	interactPart.Transparency     = 1

	interactPart.Anchored         = true

	interactPart.CanCollide       = false

	interactPart.CanTouch         = false

	interactPart.CanQuery         = false

	interactPart.Position         = position + Vector3.new(0, 0.5, 0)

	interactPart.Parent           = model

	local light           = Instance.new("PointLight")

	light.Color           = Color3.fromRGB(255, 240, 200)

	light.Range           = 4

	light.Brightness      = 0.5

	light.Parent          = interactPart

	local prompt                       = Instance.new("ProximityPrompt")

	prompt.ActionText                  = "Ambil " .. itemType .. " Lv" .. tostring(level)

	prompt.ObjectText                  = itemType

	prompt.HoldDuration                = 0

	prompt.MaxActivationDistance       = 6

	prompt.RequiresLineOfSight         = false

	prompt.KeyboardKeyCode             = Enum.KeyCode.E

	prompt.Parent                      = interactPart

	model:SetAttribute("ItemType",  itemType)

	model:SetAttribute("ItemLevel", level)

	return model, prompt

end

-- [FIX v8] Fungsi spawn ammo di tanah saat di-drop
local function spawnAmmoDropOnGround(position, ammoType, amount)

	if not AMMO_CONFIG[ammoType] then return end

	local model    = buildAmmoModel(position)

	model.Name     = "LootItem_Ammo"

	model.Parent   = lootFolder

	applyAmmoVisual(model, ammoType)

	model:SetAttribute("AmmoType",   ammoType)

	model:SetAttribute("AmmoAmount", amount)

	local ammoInfo = AMMO_CONFIG[ammoType]

	local light           = Instance.new("PointLight")

	light.Color           = ammoInfo.color or Color3.fromRGB(255, 240, 200)

	light.Range           = 4

	light.Brightness      = 0.5

	light.Parent          = model.PrimaryPart

	local prompt                       = Instance.new("ProximityPrompt")

	prompt.ActionText                  = "Ambil +" .. amount .. " " .. ammoInfo.label

	prompt.ObjectText                  = "Ammo"

	prompt.HoldDuration                = 0

	prompt.MaxActivationDistance       = 6

	prompt.RequiresLineOfSight         = false

	prompt.KeyboardKeyCode             = Enum.KeyCode.E

	prompt.Parent                      = model.PrimaryPart

	prompt.Triggered:Connect(function(triggerPlayer)

		if not model or not model.Parent then return end

		local tInv = getInventory(triggerPlayer)

		ensureAmmoData(tInv)

		local amountOnGround = model:GetAttribute("AmmoAmount") or 0

		if amountOnGround <= 0 then model:Destroy() return end

		local currentWeight, maxCapacity = getInventoryCapacity(tInv)

		local availableSpace = maxCapacity - currentWeight

		if availableSpace <= 0 then

			warn("[CAPACITY]", triggerPlayer.Name, "tas penuh (ammo pickup)")

			return

		end

		local maxCanCarry = math.floor(availableSpace / ITEM_WEIGHT.Ammo)

		local amountTaken = math.min(amountOnGround, maxCanCarry)

		if amountTaken <= 0 then return end

		tInv.ammo[ammoType] = (tInv.ammo[ammoType] or 0) + amountTaken

		tInv.items.Ammo     = getTotalAmmo(tInv)

		if amountTaken < amountOnGround then

			local leftOver = amountOnGround - amountTaken

			model:SetAttribute("AmmoAmount", leftOver)

			prompt.ActionText = "Ambil +" .. leftOver .. " " .. ammoInfo.label

			syncInventory(triggerPlayer)

			return

		end

		syncInventory(triggerPlayer)

		model:Destroy()

		print("[AMMO PICKUP]", triggerPlayer.Name, "ambil", amountTaken, ammoInfo.label)

	end)

end

dropItemEvent.OnServerEvent:Connect(function(player, category, key, amount)

	if not player or not player.Parent then return end

	local inv       = getInventory(player)

	local pw        = getWeapons(player)

	local character = player.Character

	local hrp       = character and character:FindFirstChild("HumanoidRootPart")

	if not hrp then return end

	local lookVector = hrp.CFrame.LookVector

	local pos = hrp.Position

		+ Vector3.new(math.random(-1,1), 0, math.random(-1,1))

		+ lookVector * 2.5

	-- ──────────────────────────────────────

	--  EQUIPMENT: Helm, Vest, Tas

	-- ──────────────────────────────────────

	if category == "Equipment" then

		local level = inv.items[key] or -1

		if level < 1 then return end

		local equippedName = EQUIPPED_NAMES[key]

		if equippedName then

			local equippedModel = character:FindFirstChild(equippedName)

			if equippedModel then equippedModel:Destroy() end

		end

		if key == "Vest" then

			character:SetAttribute("Armor",              0)

			character:SetAttribute("MaxArmor",           0)

			character:SetAttribute("ArmorLevel",         0)

			character:SetAttribute("VestDamageReduction", 0)

			character:SetAttribute("ArmorBroken",        false)

		end

		inv.items[key] = -1

		syncInventory(player)

		local model, prompt = spawnEquipmentDropAtLevel(pos, key, level)

		if model and prompt then

			prompt.Triggered:Connect(function(triggerPlayer)

				if not model or not model.Parent then return end

				local tInv       = getInventory(triggerPlayer)

				local dropLevel  = model:GetAttribute("ItemLevel") or 1

				local currLevel  = tInv.items[key] or -1

				if currLevel < dropLevel then tInv.items[key] = dropLevel end

				if key == "Vest" then

					equipVest(triggerPlayer, tInv.items.Vest)

				else

					equipEquipment(triggerPlayer, key, tInv.items[key])

				end

				syncInventory(triggerPlayer)

				model:Destroy()

				print(string.format("[DROP] %s ambil %s Lv%d dari tanah", triggerPlayer.Name, key, dropLevel))

			end)

		end

		print(string.format("[DROP] %s drop %s Lv%d", player.Name, key, level))

		-- ──────────────────────────────────────

		--  WEAPON: slot1, slot2, sidearm

		--  [FIX v8] dropWeapon sudah handle unequip dari karakter

		-- ──────────────────────────────────────

	elseif category == "Weapon" then

		if not pw[key] then

			print("[DROP] Weapon slot", key, "kosong, tidak ada yang di-drop")

			return

		end

		dropWeapon(player, key)

		print(string.format("[DROP] %s drop weapon slot [%s]", player.Name, key))

		-- ──────────────────────────────────────

		--  MATERIAL: ScrapMetal, Cloth, Electronic

		-- ──────────────────────────────────────

	elseif category == "Material" then

		local mats      = inv.materials or {}

		local matAmount = mats[key] or 0

		if matAmount <= 0 then return end

		inv.materials[key] = 0

		syncInventory(player)

		createMaterialDrop(pos, key)

		print(string.format("[DROP] %s drop %s ×%d", player.Name, key, matAmount))

		-- ──────────────────────────────────────

		--  [FIX v8] AMMO: drop semua ammo dari tipe tertentu
		--  key = ammoType (e.g. "Ammo9mm", "Ammo556", dll)
		--  Jika key == "All", drop semua jenis ammo sekaligus
		-- ──────────────────────────────────────

	elseif category == "Ammo" then

		ensureAmmoData(inv)

		if key == "All" then

			-- Drop semua jenis ammo
			for ammoType, ammoAmount in pairs(inv.ammo) do

				if ammoAmount > 0 and AMMO_CONFIG[ammoType] then

					local dropPos = pos + Vector3.new(math.random(-2,2), 0, math.random(-2,2))

					spawnAmmoDropOnGround(dropPos, ammoType, ammoAmount)

					inv.ammo[ammoType] = 0

					print(string.format("[DROP] %s drop %s ×%d", player.Name, ammoType, ammoAmount))

				end

			end

		elseif AMMO_CONFIG[key] then

			-- Drop satu jenis ammo tertentu
			local ammoAmount = inv.ammo[key] or 0

			if ammoAmount <= 0 then return end

			inv.ammo[key] = 0

			spawnAmmoDropOnGround(pos, key, ammoAmount)

			print(string.format("[DROP] %s drop %s ×%d", player.Name, key, ammoAmount))

		else

			warn("[DROP] Ammo type tidak dikenal:", key)

			return

		end

		inv.items.Ammo = getTotalAmmo(inv)

		syncInventory(player)

	end

end)

print("[DROP HANDLER] ✓ DropItemEvent siap (v8 — drop weapon + ammo fix)")
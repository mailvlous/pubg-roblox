--[[
=============================================================
  CRAFTING SYSTEM v2 (Server) — LEVEL UPGRADE BERTAHAP
  
  - Item drop di tanah = Level 0
  - Craft = upgrade level pakai material (Lv0→1→2→3)
  - HARUS bertahap, tidak bisa skip
  - Setiap meja assign 1 item random per match
  
  Recipe upgrade (makin tinggi level makin mahal):
  Level    Helm           Vest           Tas            Ammo
  0→1   2S,1C          3S,2C          1S,3C          2S,1E
  1→2   3S,2C          4S,3C          2S,4C          3S,2E
  2→3   5S,3C          6S,4C          3S,6C          4S,3E
  (S=Scrap, C=Cloth, E=Electronic)
  
  PLACE INI DI: ServerScriptService
  NAMA SCRIPT: CraftingSystem
=============================================================
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ============================================================
--  RECIPE PER LEVEL
-- ============================================================
-- [item][targetLevel] = { scrap, cloth, electronic }
local RECIPES = {
	Helm = {
		[2] = { scrap = 3, cloth = 2, electronic = 0 },
		[3] = { scrap = 5, cloth = 3, electronic = 0 },
		icon = "⛑️",
		displayName = "Helm",
		effectPerLevel = { 10, 20, 35 },  -- armor head per level
		descTemplate = "Pelindung kepala (+%d armor)",
	},
	Vest = {
		[2] = { scrap = 4, cloth = 3, electronic = 0 },
		[3] = { scrap = 6, cloth = 4, electronic = 0 },
		icon = "🦺",
		displayName = "Vest",
		effectPerLevel = { 20, 40, 70 },  -- armor body per level
		descTemplate = "Pelindung badan (+%d armor)",
	},
	Tas = {
		[2] = { scrap = 2, cloth = 4, electronic = 0 },
		[3] = { scrap = 3, cloth = 6, electronic = 0 },
		icon = "🎒",
		displayName = "Tas",
		effectPerLevel = { 3, 6, 10 },  -- inventory slots per level
		descTemplate = "Tambah slot inventory (+%d)",
	},
	Ammo = {
		[2] = { scrap = 3, cloth = 0, electronic = 2 },
		[3] = { scrap = 4, cloth = 0, electronic = 3 },
		icon = "🔫",
		displayName = "Ammo Boost",
		effectPerLevel = { 10, 20, 35 },  -- damage boost per level
		descTemplate = "Damage peluru (+%d dmg)",
	},
}

local ITEM_LIST = { "Helm", "Vest", "Tas", "Ammo" }

-- ============================================================
--  REMOTE EVENTS
-- ============================================================
local function ensureRemote(name, className)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing then return existing end
	local obj = Instance.new(className)
	obj.Name = name
	obj.Parent = ReplicatedStorage
	return obj
end

local openCraftingEvent = ensureRemote("OpenCrafting", "RemoteEvent")
local craftRequestEvent = ensureRemote("CraftRequest", "RemoteEvent")
local craftResultEvent = ensureRemote("CraftResult", "RemoteEvent")

-- Functions dari LootSystem
local getInvFunc = ReplicatedStorage:WaitForChild("GetInventory")
local upgradeItemFunc = ReplicatedStorage:WaitForChild("UpgradeItem")

-- ============================================================
--  ASSIGN ITEM KE MEJA (random per match)
-- ============================================================
local tableAssignments = {}

local function setupCraftTable(craftTable, itemName)
	local oldPrompt = craftTable:FindFirstChild("CraftPrompt")
	if oldPrompt then oldPrompt:Destroy() end

	local recipe = RECIPES[itemName]

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "CraftPrompt"
	prompt.ActionText = "Upgrade " .. recipe.displayName
	prompt.ObjectText = "Meja " .. recipe.displayName
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = craftTable

	prompt.Triggered:Connect(function(player)
		-- Kirim info meja ke client untuk buka UI
		local inv = getInvFunc:Invoke(player)
		local currentLevel = inv.items[itemName] or -1

		openCraftingEvent:FireClient(player, {
			item = itemName,
			displayName = recipe.displayName,
			icon = recipe.icon,
			currentLevel = currentLevel,
			recipes = {
				[1] = recipe[1],
				[2] = recipe[2],
				[3] = recipe[3],
			},
			effectPerLevel = recipe.effectPerLevel,
			descTemplate = recipe.descTemplate,
		})
	end)
end

local function assignItemsToTables()
	local craftTables = {}
	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("BasePart") and string.find(obj.Name, "CraftTable_Body") then
			table.insert(craftTables, obj)
		end
	end

	print(string.format("[CRAFT] %d meja crafting ditemukan", #craftTables))

	-- Shuffle
	local shuffled = {}
	for _, item in ipairs(ITEM_LIST) do table.insert(shuffled, item) end
	for i = #shuffled, 2, -1 do
		local j = math.random(i)
		shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
	end

	for i, craftTable in ipairs(craftTables) do
		local itemIndex = ((i - 1) % #ITEM_LIST) + 1
		local assignedItem = shuffled[itemIndex]
		tableAssignments[craftTable] = assignedItem
		print(string.format("[CRAFT] Meja %d → %s", i, assignedItem))
		setupCraftTable(craftTable, assignedItem)
	end
end

-- ============================================================
--  HANDLE CRAFT REQUEST
-- ============================================================
craftRequestEvent.OnServerEvent:Connect(function(player, itemName)
	local recipe = RECIPES[itemName]
	if not recipe then
		craftResultEvent:FireClient(player, false, "Item tidak valid")
		return
	end

	-- Cek level saat ini
	local inv = getInvFunc:Invoke(player)
	local currentLevel = inv.items[itemName]

	if currentLevel == nil or currentLevel < 0 then
		craftResultEvent:FireClient(player, false, 
			"Cari " .. recipe.displayName .. " di tanah dulu!")
		return
	end

	if currentLevel >= 3 then
		craftResultEvent:FireClient(player, false, 
			recipe.displayName .. " sudah Level MAX (3)")
		return
	end

	-- Target level = current + 1 (bertahap)
	local targetLevel = currentLevel + 1
	local cost = recipe[targetLevel]

	-- Upgrade (consume material + naik level)
	local success, message = upgradeItemFunc:Invoke(player, itemName,
		cost.scrap, cost.cloth, cost.electronic)

	if success then
		-- Apply effect
		applyItemEffect(player, itemName, targetLevel, recipe)
		craftResultEvent:FireClient(player, true, message)
		print(string.format("[CRAFT] %s upgrade %s ke Lv%d", 
			player.Name, itemName, targetLevel))
	else
		craftResultEvent:FireClient(player, false, message)
	end
end)

-- ============================================================
--  APPLY EFFECT
-- ============================================================
function applyItemEffect(player, itemName, level, recipe)
	local char = player.Character
	if not char then return end
	local humanoid = char:FindFirstChildOfClass("Humanoid")

	local effectValue = recipe.effectPerLevel[level]
	-- Selisih dari level sebelumnya
	local prevValue = level > 1 and recipe.effectPerLevel[level - 1] or 0
	local delta = effectValue - prevValue

	if itemName == "Helm" or itemName == "Vest" then
		if humanoid then
			humanoid.MaxHealth = humanoid.MaxHealth + delta
			humanoid.Health = humanoid.Health + delta
		end
	elseif itemName == "Tas" then
		player:SetAttribute("ExtraInventorySlots", effectValue)
	elseif itemName == "Ammo" then
		player:SetAttribute("AmmoDamageBoost", effectValue)
	end
end

-- ============================================================
--  START
-- ============================================================
math.randomseed(tick())

print("===========================================")
print("[CRAFTING SYSTEM v2] Level upgrade bertahap")
print("===========================================")

task.wait(7)
assignItemsToTables()

print("[CRAFTING] Siap! Item upgrade Lv0→1→2→3 (bertahap)")
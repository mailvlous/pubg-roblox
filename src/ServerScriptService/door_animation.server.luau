--[[
=============================================================
  INTERACTIVE DOORS v3 — DETECT Door_Leaf*
  
  Fix: Detect SEMUA part yang nama-nya mengandung "Door_Leaf"
  (termasuk Door_Leaf.001, Door_Leaf.002, dll)
=============================================================
]]

local TweenService = game:GetService("TweenService")

local OPEN_ANGLE     = 90
local ANIM_DURATION  = 0.6
local DISTANCE       = 10

local doorStates = {}

-- ============================================================
--  CEK APAKAH NAMA PART INI ADALAH PINTU
-- ============================================================
local function isDoorPart(name)
	-- Match "Door_Leaf", "Door_Leaf.001", "Door_Leaf.002", dll
	return string.find(name, "Door_Leaf") ~= nil
end

-- ============================================================
--  TOGGLE PINTU
-- ============================================================
local function toggleDoor(doorPart, player)
	local state = doorStates[doorPart]
	if not state then return end
	if state.isAnimating then return end

	state.isAnimating = true
	state.isOpen = not state.isOpen

	local size = doorPart.Size
	local hingeOffset = CFrame.new(-size.X / 2, 0, 0)

	local targetCFrame
	if state.isOpen then
		targetCFrame = state.originalCFrame 
			* hingeOffset 
			* CFrame.Angles(0, math.rad(OPEN_ANGLE), 0)
			* hingeOffset:Inverse()
	else
		targetCFrame = state.originalCFrame
	end

	local tween = TweenService:Create(
		doorPart,
		TweenInfo.new(ANIM_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = targetCFrame }
	)
	tween:Play()
	tween.Completed:Connect(function()
		state.isAnimating = false
	end)

	local action = state.isOpen and "BUKA" or "TUTUP"
	print(string.format("[DOOR] %s %s oleh %s", action, doorPart.Name, player.Name))
end

-- ============================================================
--  SETUP 1 PINTU
-- ============================================================
local function setupDoor(doorPart)
	if doorStates[doorPart] then return end

	doorStates[doorPart] = {
		isOpen = false,
		isAnimating = false,
		originalCFrame = doorPart.CFrame,
	}

	doorPart.Anchored = true
	doorPart.CanCollide = true

	-- Hapus ProximityPrompt lama kalau ada
	for _, child in ipairs(doorPart:GetChildren()) do
		if child:IsA("ProximityPrompt") then
			child:Destroy()
		end
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Buka/Tutup"
	prompt.ObjectText = "Pintu"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.Parent = doorPart

	prompt.Triggered:Connect(function(player)
		toggleDoor(doorPart, player)
	end)
end

-- ============================================================
--  SCAN
-- ============================================================
local function scanAndSetup()
	local count = 0
	local sample = {}
	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("BasePart") and isDoorPart(obj.Name) then
			setupDoor(obj)
			count = count + 1
			if #sample < 5 then
				table.insert(sample, obj.Name)
			end
		end
	end
	return count, sample
end

-- ============================================================
--  MAIN
-- ============================================================
print("===========================================")
print("[DOOR v3] Memulai setup pintu...")
print("===========================================")

-- Scan 1
local count, sample = scanAndSetup()
print(string.format("[DOOR] Scan #1: %d pintu ditemukan", count))
for _, name in ipairs(sample) do
	print("  Contoh nama: " .. name)
end

-- Scan 2 setelah delay
task.wait(5)
local count2, _ = scanAndSetup()
print(string.format("[DOOR] Scan #2: total %d pintu", count2))

-- Scan 3 (kalau ada yang load lambat)
task.wait(5)
local count3, _ = scanAndSetup()
print(string.format("[DOOR] Scan #3: total %d pintu", count3))

-- Listener untuk pintu baru
workspace.DescendantAdded:Connect(function(obj)
	if obj:IsA("BasePart") and isDoorPart(obj.Name) then
		task.wait(0.5)
		setupDoor(obj)
	end
end)

print("===========================================")
print(string.format("[DOOR v3] SELESAI! Total %d pintu siap", count3))
print("Cara pakai: dekati pintu, tekan E")
print("===========================================")
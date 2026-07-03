local ReplicatedStorage = game:GetService("ReplicatedStorage")

local animRig = workspace:WaitForChild("HoldRifle_R6")

local weaponModel = ReplicatedStorage
	:WaitForChild("Assets")
	:WaitForChild("Weapon")
	:WaitForChild("Rifle")
	:WaitForChild("AssaultRifle2_1")

local WEAPON_C0 = CFrame.new(0, -0.85, -0.65) * CFrame.Angles(
	math.rad(0),
	math.rad(-90),
	math.rad(0)
)

local function findHandle(model)
	for _, obj in ipairs(model:GetDescendants()) do
		if obj:IsA("BasePart") and obj.Name == "Handle" then
			return obj
		end
	end
	return nil
end

local function prepareWeapon(model)
	local handle = findHandle(model)
	if not handle then
		warn("Handle tidak ditemukan")
		return nil
	end

	for _, obj in ipairs(model:GetDescendants()) do
		if obj:IsA("BasePart") then
			obj.Anchored = false
			obj.CanCollide = false
			obj.CanTouch = false
			obj.CanQuery = false
			obj.Massless = true

			if obj ~= handle then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = handle
				weld.Part1 = obj
				weld.Parent = handle
			end
		end
	end

	return handle
end

local oldWeapon = animRig:FindFirstChild("EquippedWeapon")
if oldWeapon then
	oldWeapon:Destroy()
end

local rightArm = animRig:WaitForChild("Right Arm")

local weaponClone = weaponModel:Clone()
weaponClone.Name = "EquippedWeapon"
weaponClone.Parent = animRig

local handle = prepareWeapon(weaponClone)
if not handle then return end

handle.CFrame = rightArm.CFrame

local oldMotor = rightArm:FindFirstChild("WeaponMotor")
if oldMotor then
	oldMotor:Destroy()
end

local motor = Instance.new("Motor6D")
motor.Name = "WeaponMotor"
motor.Part0 = rightArm
motor.Part1 = handle
motor.C0 = WEAPON_C0
motor.C1 = CFrame.new()
motor.Parent = rightArm

print("Weapon attached to AnimRig using same WeaponController C0")
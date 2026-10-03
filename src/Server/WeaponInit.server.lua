-- ============================================================
--  WeaponInit (Server Script)
--  Place inside: ServerScriptService
--
--  Connects held weapon Tools to WeaponManager. Weapon Tools themselves are
--  built from Modules/Items/Defs/Weapons by ItemTools (stamped with the
--  WeaponId attribute), so there is nothing to register here.
-- ============================================================

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local WeaponManager = require(ServerScriptService:WaitForChild("WeaponManager")) :: any

-- ===================== WEAPON EQUIP / UNEQUIP TRACKING =====================
-- A weapon is "equipped" for combat while its Tool is held in the character.
local function setupCharacterToolTracking(player, character)
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			local weaponId = child:GetAttribute("WeaponId")
			if weaponId and WeaponManager.GetEquipped(player) ~= weaponId then
				WeaponManager.EquipWeapon(player, weaponId)
			end
		end
	end)

	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			local weaponId = child:GetAttribute("WeaponId")
			if weaponId and WeaponManager.GetEquipped(player) == weaponId then
				WeaponManager.UnequipWeapon(player)
			end
		end
	end)
end

local function onPlayerAdded(player)
	if player.Character then
		setupCharacterToolTracking(player, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		setupCharacterToolTracking(player, character)
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

print("[WeaponInit] Loaded ✓ (use /give <weaponId> to test)")

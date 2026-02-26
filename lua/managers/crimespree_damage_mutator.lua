-- Crime Spree Roguelike - Enemy Damage Mutator (v4)
-- Hook on MutatorsManager:modify_value - same pipeline as vanilla mutators
-- Called INSIDE damage_bullet/melee/explosion/fire

if not RequiredScript then
	return
end

-- Guard against double-loading
if _G.CSR_DamageMutatorV4Loaded then
	return
end
_G.CSR_DamageMutatorV4Loaded = true



if not MutatorsManager then
	return
end

local original_modify_value = MutatorsManager.modify_value

function MutatorsManager:modify_value(id, value, ...)
	-- Run the original first so vanilla mutators apply before ours
	local result = original_modify_value(self, id, value, ...)

	-- Only scale incoming player damage
	if id == "PlayerDamage:TakeDamageBullet"
	or id == "PlayerDamage:TakeDamageMelee"
	or id == "PlayerDamage:TakeDamageExplosion"
	or id == "PlayerDamage:TakeDamageFire" then
		-- Guard: only apply during an active Crime Spree
		if managers.crime_spree and managers.crime_spree:is_active() then
			local _, dmg_bonus = CSR_GetTotalHPDamageBonus()

			if dmg_bonus and dmg_bonus > 0 and type(result) == "number" then
				result = result * (1 + dmg_bonus)
			end
		end
	end

	return result
end


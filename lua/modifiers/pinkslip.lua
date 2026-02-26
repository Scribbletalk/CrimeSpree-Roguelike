-- PINK SLIP - Kill to Heal
-- Killing an enemy restores health
-- 1 stack = +5 HP, each additional stack = +2.5 HP

if not RequiredScript then
	return
end



ModifierPinkSlip = ModifierPinkSlip or class(CSRBaseModifier)
ModifierPinkSlip.desc_id = "csr_pink_slip_desc"

-- Count how many Pink Slip items player has
local function get_pink_slip_stacks()
	if not managers.crime_spree or not managers.crime_spree:is_active() then
		return 0
	end
	local count = 0
	for _, mod in ipairs(managers.crime_spree:active_modifiers() or {}) do
		if mod.id and string.find(mod.id, "player_pink_slip_", 1, true) == 1 then
			count = count + 1
		end
	end
	return count
end

-- Kill handler
local function on_kill(self, attack_data)
	-- Check that the killer is the local player
	if not attack_data or not attack_data.attacker_unit then return end
	if not attack_data.attacker_unit:base() then return end
	if not attack_data.attacker_unit:base().is_local_player then return end

	-- Check that the enemy just died
	if not self._dead then return end

	-- Guard against multiple triggers on the same enemy
	if self._csr_pinkslip_processed then return end
	self._csr_pinkslip_processed = true

	local stacks = get_pink_slip_stacks()
	if stacks <= 0 then return end

	-- Calculate heal amount from global constants (base_modifier.lua)
	local base_heal  = _G.CSR_ItemConstants and _G.CSR_ItemConstants.pink_slip_base_heal  or 5
	local extra_heal = _G.CSR_ItemConstants and _G.CSR_ItemConstants.pink_slip_extra_heal or 2.5
	local heal_amount = base_heal + (stacks - 1) * extra_heal

	-- Restore HP
	-- Internal HP units are ~5x smaller than displayed (UI multiplies by stats_present_multiplier)
	local player_unit = managers.player:player_unit()
	if not player_unit or not alive(player_unit) then return end
	local dmg = player_unit:character_damage()
	if not dmg then return end

	local display_scale = tweak_data.gui and tweak_data.gui.stats_present_multiplier or 5
	local heal_internal = heal_amount / display_scale

	local current_hp = dmg:get_real_health()
	dmg:set_health(current_hp + heal_internal)
end

-- Hooks on all damage types
if CopDamage then
	Hooks:PostHook(CopDamage, "damage_bullet", "CSR_PinkSlip_Bullet", function(self, attack_data)
		on_kill(self, attack_data)
	end)

	if CopDamage.damage_melee then
		Hooks:PostHook(CopDamage, "damage_melee", "CSR_PinkSlip_Melee", function(self, attack_data)
			on_kill(self, attack_data)
		end)
	end

	if CopDamage.damage_explosion then
		Hooks:PostHook(CopDamage, "damage_explosion", "CSR_PinkSlip_Explosion", function(self, attack_data)
			on_kill(self, attack_data)
		end)
	end

	if CopDamage.damage_dot then
		Hooks:PostHook(CopDamage, "damage_dot", "CSR_PinkSlip_Dot", function(self, attack_data)
			on_kill(self, attack_data)
		end)
	end

else
end


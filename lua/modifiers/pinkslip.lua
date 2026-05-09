-- PINK SLIP - Kill to Heal
-- Killing an enemy restores health
-- 1 stack = 1% of max HP + 4 flat HP, each additional stack = +6 flat HP

if not RequiredScript then
	return
end

ModifierPinkSlip = ModifierPinkSlip or class(CSRBaseModifier)
ModifierPinkSlip.desc_id = "csr_pink_slip_desc"

-- Count how many Pink Slip items player has
local function get_pink_slip_stacks()
	return CSR_CountStacks("player_pink_slip_")
end

-- Kill handler
local function on_kill(self, attack_data)
	if not managers.crime_spree or not managers.crime_spree:is_active() then
		return
	end
	-- Check that the killer is the local player
	if not attack_data or not attack_data.attacker_unit then
		return
	end
	if not attack_data.attacker_unit:base() then
		return
	end
	if not attack_data.attacker_unit:base().is_local_player then
		return
	end

	-- Check that the enemy just died
	if not self._dead then
		return
	end

	-- Guard against multiple triggers on the same enemy
	if self._csr_pinkslip_processed then
		return
	end
	self._csr_pinkslip_processed = true

	local stacks = get_pink_slip_stacks()
	if stacks <= 0 then
		return
	end

	-- Block healing if setting is enabled (Berserker/Frenzy builds)
	if CSR_Settings and CSR_Settings.values.block_item_healing then
		return
	end

	-- Restore HP
	-- Internal HP units are ~5x smaller than displayed (UI multiplies by stats_present_multiplier)
	local player_unit = managers.player:player_unit()
	if not player_unit or not alive(player_unit) then
		return
	end
	local dmg = player_unit:character_damage()
	if not dmg then
		return
	end

	-- Calculate heal amount from global constants (base_modifier.lua)
	local C = _G.CSR_ItemConstants or {}
	local base_percent = C.pink_slip_base_percent or 0.01
	local base_flat = C.pink_slip_base_flat or 4
	local extra_heal = C.pink_slip_extra_heal or 6

	local display_scale = tweak_data.gui and tweak_data.gui.stats_present_multiplier or 5
	local max_hp_display = dmg:_max_health() * display_scale
	local heal_amount = max_hp_display * base_percent + base_flat + (stacks - 1) * extra_heal
	local heal_internal = heal_amount / display_scale

	local current_hp = dmg:get_real_health()
	local target_hp = current_hp + heal_internal
	log(
		string.format(
			"[CSR][DPDiag][PinkSlip] kill heal: stacks=%d current_hp=%.3f heal_internal=%.3f target=%.3f max_hp=%.3f current_armor=%.3f",
			stacks,
			current_hp,
			heal_internal,
			target_hp,
			dmg:_max_health(),
			dmg.get_real_armor and dmg:get_real_armor() or -1
		)
	)
	dmg:set_health(target_hp)
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

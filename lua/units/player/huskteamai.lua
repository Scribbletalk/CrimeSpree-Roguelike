-- Crime Spree Roguelike - Bot HP/Damage Buffs
-- Apply passive bonuses to bots (HP and Damage only)

if not RequiredScript then
	return
end



-- Hook on bot spawn - apply buffs
Hooks:PostHook(HuskTeamAIInventory, "post_init", "CSR_ApplyBotBuffs", function(self)
	if not managers.crime_spree or not managers.crime_spree:is_active() then
		return
	end

	local unit = self._unit
	if not alive(unit) then
		return
	end

	-- Get current Crime Spree level
	local spree_level = managers.crime_spree:spree_level() or 0
	if spree_level <= 0 then
		return
	end

	-- Passive progression scales with level
	local progression_tiers = spree_level
	if progression_tiers <= 0 then
		return
	end


	-- === HP BUFF (slower than player) ===
	-- Player: +0.06% per level, Bots: +0.024% per level (2.5x slower)
	local hp_bonus = 0.00024 * progression_tiers  -- 0.024% per level

	local damage_ext = unit:character_damage()
	if damage_ext and damage_ext._HEALTH_INIT then
		local base_hp = 230  -- Bot base health

		-- Save original value on first spawn
		if not damage_ext._CSR_ORIGINAL_BOT_HEALTH then
			damage_ext._CSR_ORIGINAL_BOT_HEALTH = damage_ext._HEALTH_INIT
		end

		-- Calculate bonus from bot skills
		local bot_skill_bonus = (damage_ext._CSR_ORIGINAL_BOT_HEALTH / base_hp) - 1.0

		-- Combine skill bonus and passive bonus additively
		local combined_bonus = bot_skill_bonus + hp_bonus
		local combined_multiplier = math.max(0.01, 1.0 + combined_bonus)

		-- Apply new max HP
		local new_max_hp = base_hp * combined_multiplier
		damage_ext._HEALTH_INIT = new_max_hp
		damage_ext._health = new_max_hp  -- Fill HP to new max

		        ", passive_bonus=" .. string.format("%.0f%%", hp_bonus * 100) ..
		        ", new_max=" .. string.format("%.1f", new_max_hp))
	end

	-- === DAMAGE BUFF ===
	-- Same as player: +0.05% per level
	local damage_bonus = 0.0005 * progression_tiers

	-- Store damage bonus in global table (used by bot weapon hook)
	if not _G.CSR_BotDamageBuffs then
		_G.CSR_BotDamageBuffs = {}
	end
	_G.CSR_BotDamageBuffs[tostring(unit:key())] = damage_bonus

end)


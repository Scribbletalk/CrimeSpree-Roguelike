-- VIKLUND'S VINYL - Chain Damage
-- Dealing damage chains 20% to 2 nearby enemies (700cm / ~7m radius).
-- Wave chance: min(100%, (stacks + 2 - wave_num) × 50%)
-- Chain stops when chance reaches 0.
-- Example: 1 stack → wave 1 = 100%, wave 2 = 50%, wave 3 = 0% (stop)
--           2 stacks → wave 1 = 100%, wave 2 = 100%, wave 3 = 50%, wave 4 = 0% (stop)

if not RequiredScript then
	return
end



ModifierViklundVinyl = ModifierViklundVinyl or class(CSRBaseModifier)
ModifierViklundVinyl.desc_id = "csr_viklund_vinyl_desc"

local CHAIN_RADIUS    = 700   -- centimeters (~7 meters)
local CHAIN_COUNT     = 2     -- enemies hit per wave
local CHAIN_DMG_PCT   = 0.20  -- 20% of original damage
local CHAIN_SPEC_MULT = 0.25  -- specials take 25% of chain damage (armor simulation)

-- Special enemies that normally have armor/high resistance.
-- Bulldozers use "tank" as their tweak_table prefix (e.g. "tank", "tank_skull", "tank_medic").
local SPECIAL_SUBSTRINGS = {"taser", "cloaker", "tank", "captain", "sniper", "shield", "marshal"}

local function is_special_enemy(unit)
	if not unit or not unit:base() then return false end
	local td = unit:base()._tweak_table
	if type(td) ~= "string" then return false end
	for _, s in ipairs(SPECIAL_SUBSTRINGS) do
		if td:find(s) then return true end
	end
	return false
end

local CHAIN_DUMMY_BODY_NAME = Idstring("chain_dummy")

-- Fake col_ray so vanilla copdamage.lua doesn't crash on nil access.
-- body returns a dummy Idstring not in any armor table → armor check is skipped.
local function make_fake_col_ray(unit)
	return {
		ray      = Vector3(0, 0, -1),
		position = unit:movement():m_pos(),
		normal   = math_up,
		unit     = unit,
		distance = 0,
		body     = { name = function() return CHAIN_DUMMY_BODY_NAME end },
	}
end

local ELECTRIC_EFFECT_DURATION = 0.6  -- seconds before effect is killed

-- Pending effects: {fx, kill_at}. Processed in on_damage (combat = frequent) and
-- on the death of the target unit via clbk_death hook.
_G.CSR_VinylEffectQueue  = _G.CSR_VinylEffectQueue  or {}
-- Directly hit units: excluded from all chains until 0.15s has passed.
-- Prevents multi-hit melee from chaining back into its own targets.
_G.CSR_VinylDirectHits   = _G.CSR_VinylDirectHits   or {}
_G.CSR_VinylDirectExpiry = _G.CSR_VinylDirectExpiry  or 0

local function flush_vinyl_effects()
	local now = Application:time()
	-- Clear direct-hit list after 0.15s (covers multi-hit melee window)
	if now > _G.CSR_VinylDirectExpiry then
		_G.CSR_VinylDirectHits = {}
	end
	if #_G.CSR_VinylEffectQueue == 0 then return end
	local i = 1
	while i <= #_G.CSR_VinylEffectQueue do
		local entry = _G.CSR_VinylEffectQueue[i]
		if now >= entry.kill_at then
			pcall(function() World:effect_manager():fade_kill(entry.fx) end)
			table.remove(_G.CSR_VinylEffectQueue, i)
		else
			i = i + 1
		end
	end
end

local function spawn_electric_effect(unit)
	if not alive(unit) or not unit:movement() then return end
	local ok, err = pcall(function()
		local spine = unit:get_object(Idstring("Spine1"))
		if not spine then return end
		local effect = World:effect_manager():spawn({
			effect = Idstring("effects/payday2/particles/character/taser_hittarget"),
			parent = spine,
		})
		if effect then
			table.insert(_G.CSR_VinylEffectQueue, {
				fx      = effect,
				kill_at = Application:time() + ELECTRIC_EFFECT_DURATION,
			})
		end
	end)
	if not ok then
	end
end

-- Squared distance between two Vector3 positions
local function pos_dist_sq(p1, p2)
	local dx = p1.x - p2.x
	local dy = p1.y - p2.y
	local dz = p1.z - p2.z
	return dx * dx + dy * dy + dz * dz
end

-- Anti-recursion guard: chain damage calls damage_bullet again, this prevents looping
_G.CSR_ViklundChaining = false

local function run_chain(original_damage, attacker_unit, weapon_unit, initial_target, stacks)
	-- For melee attacks weapon_unit is nil; vanilla damage_bullet crashes on nil weapon_unit.
	-- Fall back to the attacker's currently equipped weapon unit.
	if not weapon_unit and attacker_unit then
		pcall(function()
			weapon_unit = attacker_unit:inventory():equipped_unit()
		end)
	end

	local enemy_mask = managers.slot:get_mask("enemies")
	local hit_units  = {}
	hit_units[initial_target] = true
	local wave     = { initial_target }
	local chain_dmg = original_damage * CHAIN_DMG_PCT
	local wave_num  = 0

	while true do
		wave_num = wave_num + 1

		-- chance = min(1.0, (stacks + 2 - wave_num) * 0.5)
		local chance_raw = (stacks + 2 - wave_num) * 0.5
		if chance_raw <= 0 then
			break
		end
		local chance = math.min(1.0, chance_raw)

		if math.random() > chance then
			break
		end

		-- Collect all valid candidates near any unit in the current wave
		local candidates = {}
		for _, source in ipairs(wave) do
			if alive(source) and source:movement() then
				local src_pos = source:movement():m_pos()
				local nearby = World:find_units_quick("sphere", src_pos, CHAIN_RADIUS, enemy_mask)
				for _, unit in ipairs(nearby) do
					if alive(unit) and not hit_units[unit] and not _G.CSR_VinylDirectHits[unit] then
						local dmg = unit:character_damage()
						if dmg and not dmg:dead() and unit:movement() then
							candidates[unit] = true
						end
					end
				end
			end
		end

		-- Sort candidates by minimum distance to any wave unit, pick closest CHAIN_COUNT
		local sorted = {}
		for unit, _ in pairs(candidates) do
			local min_d = math.huge
			for _, src in ipairs(wave) do
				if alive(src) and src:movement() then
					local d = pos_dist_sq(src:movement():m_pos(), unit:movement():m_pos())
					if d < min_d then min_d = d end
				end
			end
			table.insert(sorted, { unit = unit, dist = min_d })
		end
		table.sort(sorted, function(a, b) return a.dist < b.dist end)

		local next_wave = {}
		for i = 1, math.min(CHAIN_COUNT, #sorted) do
			table.insert(next_wave, sorted[i].unit)
		end

		if #next_wave == 0 then
			break
		end

		-- Deal chain damage to next wave
		for _, unit in ipairs(next_wave) do
			hit_units[unit] = true
			local cdmg = unit:character_damage()
			if cdmg and not cdmg:dead() then
				-- Specials (dozers, shields, etc.) resist chain — simulate armor by reducing damage
				local target_dmg = is_special_enemy(unit) and (chain_dmg * CHAIN_SPEC_MULT) or chain_dmg
				cdmg:damage_bullet({
					damage        = target_dmg,
					attacker_unit = attacker_unit,
					weapon_unit   = weapon_unit,
					col_ray       = make_fake_col_ray(unit),
				})
				spawn_electric_effect(unit)
			end
		end

		wave = next_wave
	end
end

-- Process effect queue every frame via PlayerDamage:update (same pattern as dearestpossession)
Hooks:PostHook(PlayerDamage, "update", "CSR_ViklundVinyl_EffectFlush", function(self, unit, t, dt)
	flush_vinyl_effects()
end)

local function on_damage(self, attack_data)
	if _G.CSR_ViklundChaining then return end
	if not CSR_ActiveBuffs or not CSR_ActiveBuffs.viklund_vinyl then return end
	if not attack_data or not attack_data.damage or attack_data.damage <= 0 then return end
	if not attack_data.attacker_unit then return end
	if not attack_data.attacker_unit:base() then return end
	if not attack_data.attacker_unit:base().is_local_player then return end

	local stacks = CSR_ActiveBuffs.viklund_vinyl

	-- Mark this unit as directly hit so it's excluded from chain candidates
	_G.CSR_VinylDirectHits[self._unit] = true
	_G.CSR_VinylDirectExpiry = Application:time() + 0.15

	_G.CSR_ViklundChaining = true
	local ok, err = pcall(run_chain,
		attack_data.damage,
		attack_data.attacker_unit,
		attack_data.weapon_unit,
		self._unit,
		stacks
	)
	_G.CSR_ViklundChaining = false

	if not ok then
	end
end

Hooks:PostHook(CopDamage, "damage_bullet", "CSR_ViklundVinyl_Bullet", on_damage)
Hooks:PostHook(CopDamage, "damage_melee",  "CSR_ViklundVinyl_Melee",  on_damage)


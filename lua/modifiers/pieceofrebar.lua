-- PIECE OF REBAR - First hit bonus
-- Deals bonus damage on the first hit against each enemy unit
-- 1 stack = +15%, each additional stack adds +10% (formula: 5% + stacks × 10%)

if not RequiredScript then
	return
end

-- Modifier class
ModifierPieceOfRebar = ModifierPieceOfRebar or class(CSRBaseModifier)
ModifierPieceOfRebar.desc_id = "csr_piece_of_rebar_desc"

-- Global table tracking which enemy units have already been hit this life
_G.CSR_Rebar_Hit = _G.CSR_Rebar_Hit or {}

-- Count how many Piece of Rebar stacks the player has
local function get_rebar_stacks()
	return CSR_CountStacks("player_rebar_")
end

-- Bonus multiplier: base + stacks × extra  →  1 stack = +15%, 2 = +25%, 3 = +35%
local function get_rebar_bonus(stacks)
	local C = _G.CSR_ItemConstants or {}
	local base = C.rebar_base_bonus or 0.15
	local extra = C.rebar_extra_bonus or 0.10
	return base + (stacks - 1) * extra
end

-- Safely get a unique string key for the enemy unit
local function get_unit_key(cop_damage)
	local ok, key = pcall(function()
		if cop_damage._unit and alive(cop_damage._unit) then
			return tostring(cop_damage._unit:key())
		end
	end)
	return ok and key or nil
end

-- Check if the attacker is the local player. Without this, the PreHook fires
-- for ANY attacker — bots, remote peers, even environment damage — and on the
-- host (who resolves damage authoritatively) that means bots' first hits get
-- the player's Rebar bonus. The "already hit" flag is also shared across
-- attackers, so a bot's first hit consumes the buff for the player too.
local function is_local_player_attack(attack_data)
	if not attack_data or not attack_data.attacker_unit then
		return false
	end
	local ok, result = pcall(function()
		if not alive(attack_data.attacker_unit) then
			return false
		end
		local base = attack_data.attacker_unit:base()
		if not base then
			return false
		end
		return base.is_local_player == true
	end)
	return ok and result or false
end

-- Apply the first-hit bonus if this enemy hasn't been hit yet
local function apply_rebar_bonus(self, attack_data)
	if not managers.crime_spree or not managers.crime_spree:is_active() then
		return
	end
	if not attack_data or not attack_data.damage then
		return
	end
	if not is_local_player_attack(attack_data) then
		return
	end

	local stacks = get_rebar_stacks()
	if stacks <= 0 then
		return
	end

	local key = get_unit_key(self)
	if not key then
		return
	end

	if not _G.CSR_Rebar_Hit[key] then
		_G.CSR_Rebar_Hit[key] = true
		local bonus = get_rebar_bonus(stacks)
		attack_data.damage = attack_data.damage * (1 + bonus)
	end
end

-- Install hooks on CopDamage using PreHook to play nicely with other mods
if CopDamage then
	-- Guns
	Hooks:PreHook(CopDamage, "damage_bullet", "CSR_Rebar_Bullet", function(self, attack_data)
		apply_rebar_bonus(self, attack_data)
	end)

	-- Melee
	if CopDamage.damage_melee then
		Hooks:PreHook(CopDamage, "damage_melee", "CSR_Rebar_Melee", function(self, attack_data)
			apply_rebar_bonus(self, attack_data)
		end)
	end

	-- Fire / gas (DoT)
	if CopDamage.damage_dot then
		Hooks:PreHook(CopDamage, "damage_dot", "CSR_Rebar_Dot", function(self, attack_data)
			apply_rebar_bonus(self, attack_data)
		end)
	end

	-- Explosions (mines, grenade launchers, turrets)
	if CopDamage.damage_explosion then
		Hooks:PreHook(CopDamage, "damage_explosion", "CSR_Rebar_Explosion", function(self, attack_data)
			apply_rebar_bonus(self, attack_data)
		end)
	end

	-- Clear the hit record when the enemy dies so their corpse doesn't take up memory
	Hooks:PostHook(CopDamage, "clbk_death", "CSR_Rebar_Death", function(self)
		local key = get_unit_key(self)
		if key then
			_G.CSR_Rebar_Hit[key] = nil
		end
	end)
end

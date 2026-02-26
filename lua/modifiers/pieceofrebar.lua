-- PIECE OF REBAR - First hit bonus
-- Deals bonus damage on the first hit against each enemy unit
-- 1 stack = +20%, each additional stack adds +10% (formula: (stacks+1) × 10%)

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
	if not managers.crime_spree or not managers.crime_spree:is_active() then
		return 0
	end
	local count = 0
	for _, mod in ipairs(managers.crime_spree:active_modifiers() or {}) do
		if mod.id and string.find(mod.id, "player_rebar_", 1, true) == 1 then
			count = count + 1
		end
	end
	return count
end

-- Bonus multiplier: (stacks + 1) × 0.1  →  1 stack = +20%, 2 = +30%, 3 = +40%
local function get_rebar_bonus(stacks)
	return (stacks + 1) * 0.1
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

-- Apply the first-hit bonus if this enemy hasn't been hit yet
local function apply_rebar_bonus(self, attack_data)
	if not attack_data or not attack_data.damage then return end

	local stacks = get_rebar_stacks()
	if stacks <= 0 then return end

	local key = get_unit_key(self)
	if not key then return end

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

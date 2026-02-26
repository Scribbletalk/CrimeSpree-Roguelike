-- EQUALIZER - Special enemy damage boost, normal enemy damage reduction
-- Specials: taser, cloaker, medic, dozer, captain, sniper, shield, marshal
-- Formula: specials × (1 + 0.5 × stacks), normals math.max(1, dmg × (1 - 0.5 × stacks))

if not RequiredScript then
	return
end



ModifierEqualizer = ModifierEqualizer or class(CSRBaseModifier)
ModifierEqualizer.desc_id = "csr_equalizer_desc"

-- Keywords that identify special enemies via substring match on the unit's tweak table name
local SPECIAL_KEYWORDS = {
	"taser",
	"cloaker",
	"tank",     -- all bulldozer variants: "tank", "tank_skull", "tank_medic", etc.
	"captain",
	"sniper",
	"shield",
	"marshal",
}

-- Get the unit's tweak table name (string) safely
local function get_tweak_name(cop_damage)
	local ok, result = pcall(function()
		if not cop_damage._unit then return nil end
		if not alive(cop_damage._unit) then return nil end
		local base = cop_damage._unit:base()
		if not base then return nil end
		local tt = base._tweak_table
		if type(tt) == "string" then return tt end
		-- If it's a table (some engine versions), try to get a name field
		if type(tt) == "table" then return tt._name or tt.name or nil end
		return nil
	end)
	return ok and result or nil
end

-- Determine if the unit is a special enemy
local function is_special_unit(cop_damage)
	local name = get_tweak_name(cop_damage)
	if not name then return false end
	for _, keyword in ipairs(SPECIAL_KEYWORDS) do
		if string.find(name, keyword, 1, true) then
			return true
		end
	end
	return false
end

-- Check if the attacker is the local player
local function is_local_player_attack(attack_data)
	if not attack_data or not attack_data.attacker_unit then return false end
	local ok, result = pcall(function()
		if not alive(attack_data.attacker_unit) then return false end
		local base = attack_data.attacker_unit:base()
		if not base then return false end
		return base.is_local_player == true
	end)
	return ok and result or false
end

-- Apply equalizer modifier to damage
local function apply_equalizer(self, attack_data)
	if not CSR_ActiveBuffs or not CSR_ActiveBuffs.equalizer then return end
	if not attack_data or not attack_data.damage then return end
	if not is_local_player_attack(attack_data) then return end

	local stacks = CSR_ActiveBuffs.equalizer
	if is_special_unit(self) then
		attack_data.damage = attack_data.damage * (1 + 0.5 * stacks)
	else
		attack_data.damage = math.max(1, attack_data.damage * (1 - 0.5 * stacks))
	end
end

-- Install hooks on CopDamage using PreHook to play nicely with other mods
if CopDamage then

	-- Guns
	Hooks:PreHook(CopDamage, "damage_bullet", "CSR_Equalizer_Bullet", function(self, attack_data)
		apply_equalizer(self, attack_data)
	end)

	-- Melee
	if CopDamage.damage_melee then
		Hooks:PreHook(CopDamage, "damage_melee", "CSR_Equalizer_Melee", function(self, attack_data)
			apply_equalizer(self, attack_data)
		end)
	end

	-- Fire / gas (DoT)
	if CopDamage.damage_dot then
		Hooks:PreHook(CopDamage, "damage_dot", "CSR_Equalizer_Dot", function(self, attack_data)
			apply_equalizer(self, attack_data)
		end)
	end

	-- Explosions (mines, grenade launchers, turrets)
	if CopDamage.damage_explosion then
		Hooks:PreHook(CopDamage, "damage_explosion", "CSR_Equalizer_Explosion", function(self, attack_data)
			apply_equalizer(self, attack_data)
		end)
	end

end

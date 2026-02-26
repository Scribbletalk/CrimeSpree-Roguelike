-- CSRBaseModifier - fully standalone base class for all mod modifiers
-- Does NOT inherit from any vanilla class
-- Implements the minimal interface expected by CrimeSpreeManager:
--   :new(data)            → instance creation (provided by PD2 class())
--   :init(data)           → data initialization
--   :modify_value(id, value) → hook for modifying game values
--   :destroy()            → cleanup on removal

CSRBaseModifier = CSRBaseModifier or class()

CSRBaseModifier.desc_id = "csr_base_modifier"
CSRBaseModifier.icon = ""

function CSRBaseModifier:init(data)
	self._data = data
end

function CSRBaseModifier:modify_value(id, value)
	return value
end

function CSRBaseModifier:value()
	if self._data and self._data[self.default_value] then
		local val = self._data[self.default_value]
		if type(val) == "table" then
			return val[1] or 0
		end
		return val
	end
	return 0
end

function CSRBaseModifier:destroy()
end

-- === ITEM BALANCE CONSTANTS ===
-- Change values here — logbook descriptions will update automatically
_G.CSR_ItemConstants = {
	-- DOG TAGS (Common)
	dog_tags_hp_bonus         = 0.10,  -- +10% Max HP per stack

	-- DUCT TAPE (Common)
	duct_tape_speed_bonus     = 0.05,  -- +5% Interaction Speed per stack

	-- ESCAPE PLAN (Common)
	escape_plan_cap         = 0.50,  -- Movement speed cap: 50%
	escape_plan_k_num       = 3,     -- Hyperbolic formula: k = k_num / k_den
	escape_plan_k_den       = 47,    -- First stack ≈ 3%

	-- WORN BAND-AID (Common)
	worn_bandaid_regen        = 5,     -- HP regen per stack every N seconds
	worn_bandaid_interval     = 10,    -- Regen interval (seconds)

	-- EVIDENCE ROUNDS / AP ROUNDS (Uncommon)
	ap_rounds_damage_bonus    = 0.05,  -- +5% to ALL damage per stack

	-- FALCOGINI KEYS (Uncommon)
	car_keys_k_den            = 19,    -- Hyperbolic formula: k = 1/k_den, first stack ≈ 5%

	-- WOLF'S TOOLBOX (Uncommon)
	wolfs_toolbox_normal      = 0.1,   -- -0.1s from drill/saw timer per normal enemy per stack
	wolfs_toolbox_special     = 1.0,   -- -1s from drill/saw timer per special enemy per stack

	-- BONNIE'S LUCKY CHIP (Rare)
	bonnie_chip_chance        = 0.05,  -- 5% instakill chance per stack (independent rolls)
	bonnie_chip_cooldown      = 1.5,   -- Instakill cooldown (seconds)

	-- PLUSH SHARK (Rare)
	plush_shark_invuln_base   = 10,    -- Base invulnerability duration (seconds)
	plush_shark_invuln_extra  = 20,    -- +N seconds per additional stack

	-- DOZER GUIDE (Contraband)
	dozer_armor_bonus         = 0.50,  -- +50% Armor per stack
	dozer_damage_bonus        = 0.05,  -- +5% Damage per stack
	dozer_speed_penalty       = 0.15,  -- -15% Speed per stack
	dozer_speed_min           = 0.40,  -- Minimum movement speed (cap)
	dozer_dodge_penalty       = 5,     -- -5 Dodge per stack

	-- GLASS PISTOL (Contraband) — multiplicative stacking!
	glass_pistol_dmg_per_stack  = 1.5,  -- ×1.5 damage per stack (multiplicative)
	glass_pistol_div_per_stack  = 2,    -- ÷2 HP and Armor per stack

	-- PIECE OF REBAR (Uncommon)
	rebar_base_bonus          = 0.20,  -- +20% damage on first hit (1 stack)
	rebar_extra_bonus         = 0.10,  -- +10% per each additional stack

	-- OVERKILL RUSH (Uncommon) - Kill Streak: Fire Rate + Reload Speed
	overkill_rush_first_bonus  = 0.02,  -- 2% for the first kill in the streak (per item stack)
	overkill_rush_extra_bonus  = 0.01,  -- +1% per each subsequent kill (per item stack)
	overkill_rush_max_stacks   = 4,     -- max kill streak stacks
	overkill_rush_duration     = 4.0,   -- seconds before streak resets

	-- PINK SLIP (Uncommon) - Kill to Heal
	pink_slip_base_heal       = 5,     -- HP healed per kill for the first item stack
	pink_slip_extra_heal      = 2.5,   -- +HP per kill for each additional item stack
}

log("[CSR] CSRBaseModifier loaded — standalone base class")

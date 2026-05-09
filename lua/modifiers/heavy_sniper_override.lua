-- HEAVY SNIPER MODIFIER REWORK (6.0.2 / refined 6.0.4):
-- Repurposes vanilla ModifierHeavySniper from "swap Heavy SWATs for ZEAL Heavy
-- Snipers" into "+N marksmen per marshal squad, shield count fixed at 1".
--
-- Mechanism (per stack, N = data.amount):
--   * Group size (`amount[1]` and `amount[2]`) += N → groups spawn N more units.
--   * Shield entry's `amount_max` clamped to 1. Vanilla's spawn loop
--     (groupaistatebesiege.lua:_spawn_in_group) does an amount_min pass first
--     (1 shield + 1 marksman) and then fills remaining slots by freq-weighted
--     random. With amount_max=1, the engine removes shield from the random pool
--     the instant its single slot is allocated → every additional slot is a
--     marksman. Bumping freq is no longer needed.
--   * `max_nr_simultaneous_groups` is NOT touched — that would multiply shields too.
-- Net result: per-group = exactly 1 shield + (1 + N) marksmen, shield count
-- stays at the vanilla baseline regardless of stacks.
--
-- Why repurpose instead of replace: the vanilla modifier id "csr_heavy_sniper"
-- is already in tweakdata/crimespree.lua and may exist in saved CS runs. Reusing
-- the class keeps save compatibility — only the data shape and behavior change.

if not RequiredScript then
	return
end

if not ModifierHeavySniper then
	return
end

-- Stop swapping spawning units. The new behavior lives entirely in init/destroy
-- via tweak_data mutation; modify_value is no longer needed.
local function csr_modify_value(_self, _id, value)
	return value
end

local function _get_marshal_squad()
	local groups = tweak_data and tweak_data.group_ai and tweak_data.group_ai.enemy_spawn_groups
	return groups and groups.marshal_squad or nil
end

local function _apply_marshal_buff(self)
	local amount = (self._data and self._data.amount) or 0
	if amount <= 0 then
		return
	end
	local squad = _get_marshal_squad()
	if not squad then
		log("[CSR HeavySniper] no marshal_squad on this difficulty/level — modifier inert")
		return
	end

	-- Group size: add N to both min and max so groups deterministically spawn
	-- (vanilla_size + N) units rather than a random range.
	if squad.amount then
		if squad.amount[1] then
			self._csr_orig_amount_min = squad.amount[1]
			squad.amount[1] = self._csr_orig_amount_min + amount
		end
		if squad.amount[2] then
			self._csr_orig_amount_max = squad.amount[2]
			squad.amount[2] = self._csr_orig_amount_max + amount
		end
	end

	-- Cap shield count at 1 per group. The vanilla spawn loop's freq-weighted
	-- random pass would otherwise add extra shields ~1/(N+1+1) of the time
	-- (groupaistatebesiege.lua:_spawn_in_group). Setting amount_max = 1 makes
	-- the engine drop shield from the pool the moment its first slot is filled.
	if squad.spawn then
		for _, entry in ipairs(squad.spawn) do
			if entry.unit == "marshal_shield" then
				self._csr_orig_shield_amount_max = entry.amount_max
				entry.amount_max = 1
				self._csr_shield_entry = entry
				break
			end
		end
		if not self._csr_shield_entry then
			log("[CSR HeavySniper] no marshal_shield entry in marshal_squad.spawn — shield cap skipped")
		end
	end

	self._csr_applied = true
	log(
		"[CSR HeavySniper] marshal_squad bumped: amount "
			.. tostring(self._csr_orig_amount_min)
			.. "-"
			.. tostring(self._csr_orig_amount_max)
			.. " -> "
			.. tostring(squad.amount and squad.amount[1])
			.. "-"
			.. tostring(squad.amount and squad.amount[2])
			.. ", shield amount_max "
			.. tostring(self._csr_orig_shield_amount_max)
			.. " -> "
			.. tostring(self._csr_shield_entry and self._csr_shield_entry.amount_max)
	)
end

local function _restore_marshal_buff(self)
	if not self._csr_applied then
		return
	end
	local squad = _get_marshal_squad()
	if squad and squad.amount then
		if self._csr_orig_amount_min then
			squad.amount[1] = self._csr_orig_amount_min
		end
		if self._csr_orig_amount_max then
			squad.amount[2] = self._csr_orig_amount_max
		end
	end
	if self._csr_shield_entry then
		self._csr_shield_entry.amount_max = self._csr_orig_shield_amount_max
	end
	self._csr_applied = false
end

-- Default value lookup uses the new "amount" key.
ModifierHeavySniper.default_value = "amount"

-- Replace modify_value on the class itself so any existing or future instance
-- skips the unit-swap logic.
ModifierHeavySniper.modify_value = csr_modify_value

Hooks:PostHook(ModifierHeavySniper, "init", "CSR_HeavySniperMarshalRework_init", function(self)
	self.modify_value = csr_modify_value
	_apply_marshal_buff(self)
end)

Hooks:PreHook(ModifierHeavySniper, "destroy", "CSR_HeavySniperMarshalRework_destroy", function(self)
	_restore_marshal_buff(self)
end)

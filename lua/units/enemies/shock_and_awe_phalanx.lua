-- Shock And Awe: Phalanx Minion Knockback Fix + Spawn Cap
-- Makes phalanx_minion units spawned via the CSR Shield Phalanx modifier
-- vulnerable to Shock And Awe knockback, while Captain Winters' own
-- formation shields remain immune (they guard him standing still).
-- Also enforces a spawn cap: Normal=2, all other difficulties=4.
--
-- How it works:
--   1. Enable shield_knocked in tweakdata for phalanx_minion (globally).
--   2. Track which phalanx_minion were spawned by the group AI spawn system
--      (i.e. via the CSR modifier) vs by mission scripts (Captain Winters).
--   3. Override is_immune_to_shield_knockback() so only Winters' phalanx
--      are immune; CSR modifier phalanx get knocked back normally.
--   4. Override _spawn_in_group to count living phalanx from self._police
--      and block shield groups when at the difficulty-based limit.
--   5. Track deaths via CopDamage:clbk_death to keep the counter accurate.

if not RequiredScript then return end


-- ============================================================
-- CharacterTweakData — enable shield_knocked for phalanx_minion
-- ============================================================
if RequiredScript == "lib/tweak_data/charactertweakdata" then

	Hooks:PostHook(CharacterTweakData, "init", "CSR_ShockAwe_TweakData", function(self)
		if self.phalanx_minion and self.phalanx_minion.damage then
			self.phalanx_minion.damage.shield_knocked = true
		end
	end)

end


-- ============================================================
-- GroupAIStateBase — reset tracking table and counter on new heist
-- ============================================================
if RequiredScript == "lib/managers/group_ai_states/groupaistatebase" then

	Hooks:PostHook(GroupAIStateBase, "on_simulation_started", "CSR_ShockAwe_SimStart", function(self)
		_G.CSR_ModifierPhalanxUnits = {}
		_G.CSR_ModifierPhalanxCount = 0
	end)

end


-- ============================================================
-- GroupAIStateBesiege — flag active during group spawning + spawn cap fix
-- ============================================================
if RequiredScript == "lib/managers/group_ai_states/groupaistatebesiege" then

	-- Set flag before group spawning so CopBrain:init can detect modifier-spawned phalanx.
	-- Captain Winters' shields are spawned via mission element scripts — they never go
	-- through _perform_group_spawning, so their CopBrain:init fires without the flag.
	Hooks:PreHook(GroupAIStateBesiege, "_perform_group_spawning", "CSR_ShockAwe_SpawnPre", function(self)
		_G.CSR_InGroupSpawning = true
	end)

	Hooks:PostHook(GroupAIStateBesiege, "_perform_group_spawning", "CSR_ShockAwe_SpawnPost", function(self)
		_G.CSR_InGroupSpawning = false
	end)

	-- Direct phalanx spawn cap via _spawn_in_group override.
	--
	-- The vanilla cap mechanism (_special_units["shield"] + special_unit_spawn_limits)
	-- does not work reliably for phalanx_minion in Crime Spree — exact root cause unknown
	-- (units may not register in _special_units, or the count may be stale).
	--
	-- Fix: override _spawn_in_group to count living phalanx_minion directly from
	-- self._police (the group AI's master table of all registered enemies).
	-- When at the shield limit, block any spawn group that contains CS_shield or
	-- FBI_shield entries (these are phalanx_minion clones after ModifierShieldPhalanx:init).
	--
	-- Performance: _spawn_in_group is called at most once per frame per task type
	-- (assault, recon, reenforce), and _police iteration is fast even with 200+ entries.

	local function count_living_phalanx(gstate)
		local count = 0
		if not gstate._police then return 0 end
		for _, u_data in pairs(gstate._police) do
			local unit = u_data.unit
			if unit and alive(unit) then
				local base = unit:base()
				if base and base._tweak_table == "phalanx_minion" then
					count = count + 1
				end
			end
		end
		return count
	end

	local function group_has_shield_entry(spawn_group_type)
		local desc = tweak_data.group_ai.enemy_spawn_groups[spawn_group_type]
		if not desc or not desc.spawn then return false end
		for _, entry in ipairs(desc.spawn) do
			if entry.unit then
				if entry.unit == "CS_shield" or entry.unit == "FBI_shield" then
					return true
				end
			else
				-- Nested entry list (used by _extract_group_desc_structure)
				for _, sub in ipairs(entry) do
					if sub.unit and (sub.unit == "CS_shield" or sub.unit == "FBI_shield") then
						return true
					end
				end
			end
		end
		return false
	end

	local orig_spawn_in_group = GroupAIStateBesiege._spawn_in_group
	function GroupAIStateBesiege:_spawn_in_group(spawn_group, spawn_group_type, grp_objective, ai_task)
		local phalanx_count = count_living_phalanx(self)
		if phalanx_count > 0 and group_has_shield_entry(spawn_group_type) then
			local limit = tweak_data.group_ai.special_unit_spawn_limits
				and tweak_data.group_ai.special_unit_spawn_limits.shield or 4
			if phalanx_count >= limit then
				spawn_group.delay_t = self._t + 10
				return nil
			end
		end
		return orig_spawn_in_group(self, spawn_group, spawn_group_type, grp_objective, ai_task)
	end

end


-- ============================================================
-- CopBrain — register modifier-spawned phalanx and increment count
-- ============================================================
if RequiredScript == "lib/units/enemies/copbrain" then

	Hooks:PostHook(CopBrain, "init", "CSR_ShockAwe_CopBrainInit", function(self)
		if not _G.CSR_InGroupSpawning then return end

		local unit = self._unit
		if not unit then return end
		if not alive(unit) then return end

		local base = unit:base()
		if base and base._tweak_table == "phalanx_minion" then
			if not _G.CSR_ModifierPhalanxUnits then
				_G.CSR_ModifierPhalanxUnits = {}
			end
			_G.CSR_ModifierPhalanxUnits[unit:key()] = true
			_G.CSR_ModifierPhalanxCount = (_G.CSR_ModifierPhalanxCount or 0) + 1
		end
	end)

end


-- ============================================================
-- CopDamage — knockback immunity override + death tracking
-- ============================================================
if RequiredScript == "lib/units/enemies/cop/copdamage" then

	local orig_immune = CopDamage.is_immune_to_shield_knockback

	function CopDamage:is_immune_to_shield_knockback()
		local unit = self._unit
		if unit and alive(unit) then
			local base = unit:base()
			if base and base._tweak_table == "phalanx_minion" then
				-- CSR modifier phalanx: allow knockback
				if _G.CSR_ModifierPhalanxUnits and _G.CSR_ModifierPhalanxUnits[unit:key()] then
					return false
				end
				-- Captain Winters' phalanx: keep immune
				return true
			end
		end
		if orig_immune then
			return orig_immune(self)
		end
		return false
	end

	-- When a CSR phalanx dies, remove it from tracking and decrement count.
	-- This keeps the spawn cap check accurate across multiple assault waves.
	Hooks:PostHook(CopDamage, "clbk_death", "CSR_PhalanxSpawnCap_Death", function(self)
		local unit = self._unit
		if not unit then return end
		local base = unit:base()
		if not base or base._tweak_table ~= "phalanx_minion" then return end
		local key = unit:key()
		if _G.CSR_ModifierPhalanxUnits and _G.CSR_ModifierPhalanxUnits[key] then
			_G.CSR_ModifierPhalanxUnits[key] = nil
			_G.CSR_ModifierPhalanxCount = math.max(0, (_G.CSR_ModifierPhalanxCount or 0) - 1)
		end
	end)

end



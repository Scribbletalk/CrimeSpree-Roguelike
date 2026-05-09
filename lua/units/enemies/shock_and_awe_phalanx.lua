-- Shock And Awe: Phalanx Minion Knockback + Spawn Cap
--
-- Allows Shock And Awe melee knockback on ALL phalanx_minion units
-- when the Phalanx Formation modifier is active (including Winters' escort).
--
-- Also enforces a phalanx spawn cap via _spawn_in_group override.

if not RequiredScript then
	return
end

local function is_phalanx_formation_active()
	if not managers.crime_spree or not managers.crime_spree:is_active() then
		return false
	end
	local mods = managers.crime_spree:active_modifiers() or {}
	for _, m in ipairs(mods) do
		if m.id and string.find(m.id, "csr_shield_phalanx", 1, true) then
			return true
		end
	end
	return false
end

-- ============================================================
-- CopDamage — runtime knockback, conditional on modifier + not escort
-- ============================================================
if RequiredScript == "lib/units/enemies/cop/copdamage" then
	-- Override is_immune_to_shield_knockback so playerstandard sets attack_data.shield_knock.
	-- Without this, playerstandard never marks the hit as a shield_knock attempt and
	-- damage_melee never receives the flag, making the PreHook below unreachable.
	local orig_is_immune = CopDamage.is_immune_to_shield_knockback
	function CopDamage:is_immune_to_shield_knockback()
		local base = self._unit and self._unit:base()
		if base and base._tweak_table == "phalanx_minion" then
			if is_phalanx_formation_active() then
				return false
			end
		end
		return orig_is_immune(self)
	end

	-- Temporarily set shield_knocked = true so damage_melee resolves result_type as "shield_knock".
	-- Vanilla phalanx_minion has shield_knocked = false in tweakdata; we patch it per-hit only.
	Hooks:PreHook(CopDamage, "damage_melee", "CSR_PhalanxKnock_Pre", function(self, attack_data)
		self._csr_phalanx_knock = false

		if not attack_data or not attack_data.shield_knock then
			return
		end

		local base = self._unit and self._unit:base()
		if not base or base._tweak_table ~= "phalanx_minion" then
			return
		end

		if not is_phalanx_formation_active() then
			return
		end

		self._csr_phalanx_knock = true
		-- Temporarily allow knockback for this hit
		self._csr_saved_shield_knocked = self._char_tweak.damage.shield_knocked
		self._csr_saved_immune_knockback = self._char_tweak.damage.immune_to_knockback
		self._char_tweak.damage.shield_knocked = true
		self._char_tweak.damage.immune_to_knockback = false
	end)

	Hooks:PostHook(CopDamage, "damage_melee", "CSR_PhalanxKnock_Post", function(self)
		if not self._csr_phalanx_knock then
			return
		end
		self._csr_phalanx_knock = false
		if self._csr_saved_shield_knocked ~= nil then
			self._char_tweak.damage.shield_knocked = self._csr_saved_shield_knocked
			self._csr_saved_shield_knocked = nil
		end
		if self._csr_saved_immune_knockback ~= nil then
			self._char_tweak.damage.immune_to_knockback = self._csr_saved_immune_knockback
			self._csr_saved_immune_knockback = nil
		end
	end)
end

-- ============================================================
-- GroupAIStateBesiege — phalanx spawn cap
-- ============================================================
if RequiredScript == "lib/managers/group_ai_states/groupaistatebesiege" then
	local function count_living_phalanx(gstate)
		local count = 0
		if not gstate._police then
			return 0
		end
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
		if not desc or not desc.spawn then
			return false
		end
		for _, entry in ipairs(desc.spawn) do
			if entry.unit then
				if entry.unit == "CS_shield" or entry.unit == "FBI_shield" then
					return true
				end
			else
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
					and tweak_data.group_ai.special_unit_spawn_limits.shield
				or 4
			if phalanx_count >= limit then
				spawn_group.delay_t = self._t + 10
				return nil
			end
		end
		return orig_spawn_in_group(self, spawn_group, spawn_group_type, grp_objective, ai_task)
	end
end

-- ============================================================
-- PlayerStandard — guard intimidation lookup against nil crash
-- ============================================================
if RequiredScript == "lib/units/beings/player/states/playerstandard" then
	if PlayerStandard and PlayerStandard._get_unit_intimidation_action then
		local orig_get_intimidation = PlayerStandard._get_unit_intimidation_action
		function PlayerStandard:_get_unit_intimidation_action(unit, ...)
			-- phalanx_minion has no intimidation data — skip lookup to avoid pairs(nil) crash
			-- unit can be a boolean value in some call paths, so check type first
			if type(unit) == "userdata" and unit:base() and unit:base()._tweak_table == "phalanx_minion" then
				return nil
			end
			return orig_get_intimidation(self, unit, ...)
		end
	end
end

-- ============================================================
-- NewNPCRaycastWeaponBase — bot bullets pierce phalanx_minion shields when
-- (a) Phalanx Formation modifier is active AND
-- (b) the bot has the vanilla "Piercing" Crew Ability equipped, which sets
--     `_is_team_ai` + `_has_ap_rounds` via `set_team_ai_ap_rounds(true)`.
-- Vanilla `_fire_raycast` already does AP shoot-through for normal shields
-- (newnpcraycastweaponbase.lua:603-654), but the queued follow-up raycast
-- starts only 5 units past the shield position and apparently re-hits
-- phalanx_minion shields (Winters escort). We pre-empt that by scanning
-- the bullet path and adding any phalanx shield units to `ignore_units`,
-- so the original raycast skips them entirely.
-- ============================================================
if RequiredScript == "lib/units/weapons/newnpcraycastweaponbase" then
	local function bot_can_pierce_phalanx(weap_base)
		if not weap_base or not weap_base._is_team_ai or not weap_base._has_ap_rounds then
			return false
		end
		return is_phalanx_formation_active()
	end

	Hooks:PreHook(
		NewNPCRaycastWeaponBase,
		"_fire_raycast",
		"CSR_BotPiercePhalanx_Pre",
		function(self, user_unit, from_pos, direction)
			self._csr_phalanx_pierce_active = false
			if not bot_can_pierce_phalanx(self) then
				return
			end
			if not from_pos or not direction then
				return
			end
			local shield_mask = RaycastWeaponBase.shield_mask
			if not shield_mask then
				return
			end

			-- Scan the bullet path for phalanx_minion shield units and add them to ignore_units.
			-- Single raycast_all + linear scan; cheap because phalanx encounters are rare.
			local to = from_pos + direction * 20000
			local hits = World:raycast_all(
				"ray",
				from_pos,
				to,
				"slot_mask",
				self._bullet_slotmask,
				"ignore_unit",
				self._setup.ignore_units
			)
			if not hits or #hits == 0 then
				return
			end

			local extra_ignores = nil
			for _, hit in ipairs(hits) do
				local hu = hit.unit
				if alive(hu) and hu:in_slot(shield_mask) then
					local parent = hu:parent()
					if alive(parent) and parent:base() and parent:base()._tweak_table == "phalanx_minion" then
						extra_ignores = extra_ignores or {}
						table.insert(extra_ignores, hu)
					end
				end
			end

			if not extra_ignores then
				return
			end

			-- Save and replace ignore_units. Restored in PostHook so we don't leak the
			-- shield-skip flag into subsequent shots from the same bot weapon.
			self._csr_phalanx_pierce_active = true
			self._csr_phalanx_pierce_orig = self._setup.ignore_units
			local merged = {}
			if self._csr_phalanx_pierce_orig then
				for _, u in ipairs(self._csr_phalanx_pierce_orig) do
					table.insert(merged, u)
				end
			end
			for _, u in ipairs(extra_ignores) do
				table.insert(merged, u)
			end
			self._setup.ignore_units = merged
		end
	)

	Hooks:PostHook(NewNPCRaycastWeaponBase, "_fire_raycast", "CSR_BotPiercePhalanx_Post", function(self)
		if not self._csr_phalanx_pierce_active then
			return
		end
		self._setup.ignore_units = self._csr_phalanx_pierce_orig
		self._csr_phalanx_pierce_orig = nil
		self._csr_phalanx_pierce_active = false
	end)
end

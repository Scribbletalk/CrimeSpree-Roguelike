-- Phalanx Formation (loud modifier) -- all Shields become Captain Winters' Shields.
if not (_G.CSR and _G.CSR.register_modifier) then
	return
end

-- True only while a CSR heist with this modifier active is running. CSR runs the STANDARD
-- gamemode, so gate on managers.csr:in_csr_heist() (crime_spree:is_active() is always false here).
local function is_phalanx_formation_active()
	local mgr = managers and managers.csr
	if not (mgr and mgr.in_csr_heist and mgr:in_csr_heist() and mgr.active_modifiers) then
		return false
	end
	for _, e in ipairs(mgr:active_modifiers("loud")) do
		if e.id == "shield_phalanx" then
			return true
		end
	end
	return false
end

_G.CSR.register_modifier({
	id = "shield_phalanx",
	category = "loud",
	loc = "menu_cs_modifier_shield_phalanx",
	icon = "crime_spree_shield_phalanx",
	class = "ModifierShieldPhalanx",
	data = {},
	hooks = {
		-- Bot bullets pierce phalanx_minion (Winters escort) shields when the bot has the vanilla
		-- "Piercing" Crew Ability (sets _is_team_ai + _has_ap_rounds). Vanilla AP shoot-through in
		-- _fire_raycast re-hits phalanx shields on its queued follow-up raycast, so we pre-scan the
		-- bullet path and add any phalanx shield units to ignore_units; restored in PostHook so the
		-- skip never leaks into the next shot from the same bot weapon.
		["lib/units/weapons/newnpcraycastweaponbase"] = function()
			if _G._CSR_PHALANX_BOT_PIERCE_HOOKED then
				return
			end
			_G._CSR_PHALANX_BOT_PIERCE_HOOKED = true

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

					-- Save and replace ignore_units; restored in PostHook.
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
		end,

		-- Shock & Awe melee knockback works on phalanx_minion (incl. Winters escort) while this modifier
		-- is active. Vanilla phalanx_minion is knock-immune (shield_knocked=false, immune_to_knockback), so
		-- flip is_immune_to_shield_knockback => playerstandard marks the hit as a shield_knock attempt, then
		-- patch the tweak per-hit in damage_melee so result_type resolves to "shield_knock". Host-only (enemy
		-- damage runs on its owner). Restored in PostHook so the flip never leaks to other hits.
		["lib/units/enemies/cop/copdamage"] = function()
			if _G._CSR_PHALANX_KNOCK_HOOKED then
				return
			end
			_G._CSR_PHALANX_KNOCK_HOOKED = true

			local orig_is_immune = CopDamage.is_immune_to_shield_knockback
			function CopDamage:is_immune_to_shield_knockback()
				local base = self._unit and self._unit:base()
				if base and base._tweak_table == "phalanx_minion" and is_phalanx_formation_active() then
					return false
				end
				return orig_is_immune(self)
			end

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
				-- Temporarily allow knockback for this hit so damage_melee resolves "shield_knock".
				self._csr_phalanx_knock = true
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
		end,

		-- Phalanx spawn cap. The modifier reskins CS_shield/FBI_shield to Winters minions, but the vanilla
		-- special-unit cap can fail to count phalanx_minion, so shields spawn unbounded. Re-enforce it: block
		-- _spawn_in_group when living phalanx_minion >= the shield limit and the group spawns shields. Gated on
		-- is_phalanx_formation_active() so the _police scan is skipped on every spawn outside a phalanx heist.
		-- Host-only (besiege spawn logic runs on host).
		["lib/managers/group_ai_states/groupaistatebesiege"] = function()
			if _G._CSR_PHALANX_SPAWNCAP_HOOKED then
				return
			end
			_G._CSR_PHALANX_SPAWNCAP_HOOKED = true

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
				if is_phalanx_formation_active() then
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
				end
				return orig_spawn_in_group(self, spawn_group, spawn_group_type, grp_objective, ai_task)
			end
		end,
	},
})

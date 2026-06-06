-- Marshal Reinforcements (loud) — additional US Marshal Marksmen per squad.
-- Repurposes vanilla ModifierHeavySniper: skips the ZEAL Heavy Sniper unit swap and
-- instead bumps marshal_squad amount and caps shields at 1 per group so every extra
-- slot spawns a marksman. See csr_modifier_file_pattern.md (heavy_sniper repurpose).
if not (_G.CSR and _G.CSR.register_modifier) then
	return
end

local AMOUNT = 2

_G.CSR.register_modifier({
	id = "heavy_sniper",
	category = "loud",
	loc = "menu_cs_modifier_heavy_sniper",
	icon = "crime_spree_heavy_sniper",
	class = "ModifierHeavySniper",
	data = { amount = { AMOUNT, "add" } },
	loc_macros = { n = AMOUNT },

	hooks = {
		["lib/modifiers/modifierheavysniper"] = function()
			if _G._CSR_HEAVY_SNIPER_HOOKED then
				return
			end
			_G._CSR_HEAVY_SNIPER_HOOKED = true

			-- Accumulate `amount` instead of vanilla `spawn_chance`.
			ModifierHeavySniper.default_value = "amount"

			-- Skip the vanilla ZEAL-sniper unit swap.
			local function no_modify_value(_self, _id, value)
				return value
			end
			ModifierHeavySniper.modify_value = no_modify_value

			local function _get_marshal_squad()
				local groups = tweak_data and tweak_data.group_ai and tweak_data.group_ai.enemy_spawn_groups
				return groups and groups.marshal_squad or nil
			end

			local function _apply(self)
				local amount = self._data and self._data.amount or 0
				if amount <= 0 then
					return
				end
				local squad = _get_marshal_squad()
				if not squad then
					log("[CSR HeavySniper] no marshal_squad on this level/difficulty -- modifier inert")
					return
				end
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
				-- Cap shields at 1; _spawn_in_group decrements amount_max to remove the
				-- entry, so extra slots go to marksmen. Vanilla amount_max is nil — restoring
				-- to nil correctly removes the field.
				if squad.spawn then
					for _, entry in ipairs(squad.spawn) do
						if entry.unit == "marshal_shield" then
							self._csr_orig_shield_amount_max = entry.amount_max
							entry.amount_max = 1
							self._csr_shield_entry = entry
							break
						end
					end
				end
				self._csr_applied = true
			end

			local function _restore(self)
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

			Hooks:PostHook(ModifierHeavySniper, "init", "CSR_HeavySniperMarshal_Init", function(self)
				self.modify_value = no_modify_value
				_apply(self)
			end)

			Hooks:PreHook(ModifierHeavySniper, "destroy", "CSR_HeavySniperMarshal_Destroy", function(self)
				_restore(self)
			end)
		end,
	},
})

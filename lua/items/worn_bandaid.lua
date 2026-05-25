-- Worn Band-Aid (common) -- regenerates a % of max HP every N seconds.
--
-- Per-item-file model (see cup_of_joe.lua). Text fields are localization keys.

if not (_G.CSR and _G.CSR.register_item) then
	return
end

_G.CSR.register_item({
	type = "worn_bandaid",
	rarity = "common",
	name = "csr_logbook_worn_bandaid_name",
	desc = "csr_item_worn_bandaid_desc",
	full_desc = "csr_logbook_worn_bandaid_effect",
	notes = "csr_logbook_worn_bandaid_notes",
	icon = "csr_worn_bandaid",
	icon_scale = 1.0,

	hooks = {
		-- Heal-over-time on PlayerDamage:update (local player only -- husks use
		-- HuskPlayerDamage). Hyperbolic stacking: regen_pct = max_pct*stacks /
		-- (stacks + k) where k = (max_pct - first_pct)/first_pct, so it equals
		-- first_pct at 1 stack and asymptotes to max_pct. first_pct/max_pct/interval
		-- mirror the 6.2 constants (worn_bandaid_first_pct 0.02 / _max_pct 0.20 /
		-- _interval 5). Per-instance timer; reset when unowned so a re-pick can't
		-- fire a partial cycle.
		["lib/units/beings/player/playerdamage"] = function()
			if _G._CSR_WORN_BANDAID_HOOKED then
				return
			end
			_G._CSR_WORN_BANDAID_HOOKED = true
			local FIRST_PCT, MAX_PCT, INTERVAL = 0.02, 0.20, 5
			local K = (MAX_PCT - FIRST_PCT) / FIRST_PCT
			Hooks:PostHook(PlayerDamage, "update", "CSR_WornBandaid_Regen", function(self, unit, t, dt)
				local mgr = managers.csr
				if not (mgr and mgr.is_run_active and mgr:is_run_active()) then
					return
				end
				local stacks = mgr:owned("worn_bandaid")
				if stacks <= 0 then
					self._csr_bandaid_timer = 0
					return
				end
				if self:is_downed() or self:dead() then
					return
				end
				local timer = (self._csr_bandaid_timer or 0) + dt
				if timer < INTERVAL then
					self._csr_bandaid_timer = timer
					return
				end
				self._csr_bandaid_timer = timer - INTERVAL
				local max_hp = self:_max_health()
				local pct = MAX_PCT * stacks / (stacks + K)
				local heal = max_hp * pct
				if heal > 0 then
					self:set_health(self:get_real_health() + heal)
					if mgr:debug_enabled() then
						mgr:debug_log(string.format("worn_bandaid tick +%.1f HP (stacks=%d)", heal, stacks))
					end
				end
			end)
		end,
	},
})

-- Escape Plan (common) -- movement speed, diminishing returns (hyperbolic).
--
-- Per-item-file model (see cup_of_joe.lua). Text fields are localization keys.

if not (_G.CSR and _G.CSR.register_item) then
	return
end

_G.CSR.register_item({
	type = "escape_plan",
	rarity = "common",
	name = "csr_logbook_escape_plan_name",
	desc = "csr_item_escape_plan_desc",
	full_desc = "csr_logbook_escape_plan_effect",
	notes = "csr_logbook_escape_plan_notes",
	icon = "csr_escape_plan",
	icon_scale = 1.0,

	hooks = {
		-- Multiply PlayerStandard:_get_max_walk_speed by (1 + bonus), where
		-- bonus = cap*(1 - 1/(1 + (k_num/k_den)*stacks)) -- ~3% at 1 stack,
		-- asymptotes to 50%. cap/k_num/k_den mirror the 6.2 constants
		-- (escape_plan_cap 0.50 / _k_num 3 / _k_den 47). Return-value method ->
		-- raw chain wrap; _G guard stops a double-wrap.
		["lib/units/beings/player/states/playerstandard"] = function()
			if _G._CSR_ESCAPE_PLAN_HOOKED then
				return
			end
			_G._CSR_ESCAPE_PLAN_HOOKED = true
			local orig = PlayerStandard._get_max_walk_speed
			if not orig then
				return
			end
			function PlayerStandard:_get_max_walk_speed(t, force_run)
				local speed = orig(self, t, force_run)
				if type(speed) ~= "number" then
					return speed
				end
				local mgr = managers.csr
				if not (mgr and mgr.is_run_active and mgr:is_run_active()) then
					return speed
				end
				local stacks = mgr:owned("escape_plan")
				if stacks <= 0 then
					return speed
				end
				local k = 3 / 47
				local bonus = 0.50 * (1 - 1 / (1 + k * stacks))
				return speed * (1 + bonus)
			end
		end,
	},
})

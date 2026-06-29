-- Escape Plan (common) — hyperbolic movement-speed bonus.
-- bonus = 0.5*(1 - 1/(1 + (3/47)*stacks)). ~3% at 1 stack, asymptotes to 50%.

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

	-- Heister panel: same hyperbolic walk-speed bonus as the _get_max_walk_speed hook below.
	stat_preview = function(count)
		local k = 3 / 47
		return { movement = 1 + 0.50 * (1 - 1 / (1 + k * count)) }
	end,

	hooks = {
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
				if not (mgr and mgr.in_csr_heist and mgr:in_csr_heist()) then
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

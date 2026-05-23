-- Duct Tape (common) -- +10% interaction speed per copy owned.
--
-- Per-item-file model (see cup_of_joe.lua). Text fields are localization keys.

if not (_G.CSR and _G.CSR.register_item) then
	return
end

_G.CSR.register_item({
	type = "duct_tape",
	rarity = "common",
	name = "logbook_duct_tape_name",
	desc = "item_duct_tape_desc",
	full_desc = "logbook_duct_tape_effect",
	notes = "logbook_duct_tape_notes",
	icon = "duct_tape",

	hooks = {
		-- Divide BaseInteractionExt:_get_timer by (1 + 0.10*owned) -- linear CSR
		-- stacking, multiplicative with vanilla upgrade multipliers. "revive" and
		-- "free" interactions are excluded (mirrored from 6.x). Return-value method
		-- -> raw chain wrap; _G guard stops a double-wrap. Mirrors the 6.2 constant
		-- duct_tape_speed_bonus (0.10).
		["lib/units/interactions/interactionext"] = function()
			if _G._CSR_DUCT_TAPE_HOOKED then
				return
			end
			_G._CSR_DUCT_TAPE_HOOKED = true
			local orig = BaseInteractionExt._get_timer
			if not orig then
				return
			end
			function BaseInteractionExt:_get_timer()
				local t = orig(self)
				if type(t) ~= "number" then
					return t
				end
				local tid = self.tweak_data
				if tid == "revive" or tid == "free" then
					return t
				end
				local mgr = managers.csr
				if not (mgr and mgr.is_run_active and mgr:is_run_active()) then
					return t
				end
				local bonus = 0.10 * mgr:owned("duct_tape")
				if bonus <= 0 then
					return t
				end
				return t / (1 + bonus)
			end
		end,
	},
})

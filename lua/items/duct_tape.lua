-- Duct Tape (common) — +10%/stack interaction speed. Skips "revive" and "free".

if not (_G.CSR and _G.CSR.register_item) then
	return
end

local SPEED_BONUS = 0.10

_G.CSR.register_item({
	type = "duct_tape",
	rarity = "common",
	name = "csr_logbook_duct_tape_name",
	desc = "csr_item_duct_tape_desc",
	full_desc = "csr_logbook_duct_tape_effect",
	notes = "csr_logbook_duct_tape_notes",
	icon = "csr_duct_tape",
	icon_scale = 1.0,
	loc_macros = { pct = string.format("%g", SPEED_BONUS * 100) },

	hooks = {
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
				if not (mgr and mgr.in_csr_heist and mgr:in_csr_heist()) then
					return t
				end
				local bonus = SPEED_BONUS * mgr:owned("duct_tape")
				if bonus <= 0 then
					return t
				end
				return t / (1 + bonus)
			end
		end,
	},
})

-- Registers the "csr_copier" interaction tweak used by the in-world copier prop.
-- Referenced from the unit file via the `tweak_data` var on the interaction
-- extension, and read by CrimeSpreeCopierInteractionExt at interact time.
--
-- Deliberately NO upgrade_timer_multiplier: the subclass overrides _get_timer
-- to pin the hold at tweak_data.timer unconditionally, but omitting the field
-- is belt-and-braces in case a future base-class change bypasses the override.

if not InteractionTweakData then
	return
end

-- Yellow contour palette deferred to LocalizationManagerPostInit (see
-- scrapper_interaction.lua for the full write-up — TweakData:init PostHook
-- doesn't work here because the InteractionTweakData class file is required
-- BEFORE the TweakData class itself is declared, so `TweakData` is nil when
-- our script body executes). Idempotent with the matching block in
-- scrapper_interaction.lua.
Hooks:Add("LocalizationManagerPostInit", "CSR_RegisterYellowContourPaletteCopier", function()
	if tweak_data and tweak_data.contour and not tweak_data.contour.csr_yellow_interactable then
		tweak_data.contour.csr_yellow_interactable = {
			standard_color = Vector3(1, 0.85, 0),
			selected_color = Vector3(1, 1, 0.4),
		}
	end
end)

Hooks:PostHook(InteractionTweakData, "init", "CSR_CopierInteractionTweak", function(self)
	self.csr_copier = {
		icon = "equipment_missing",
		text_id = "csr_interact_copier",
		action_text_id = "csr_interact_copier_action",
		blocked_hint = "csr_copier_no_item",
		timer = 0.5,
		interact_distance = 250,
		-- Yellow contour, gated on distance by copier_spawner.lua's per-frame
		-- proximity hook (only rendered when the player is within
		-- CSR_PROX_RANGE — see PROX_RANGE constant there).
		contour = "csr_yellow_interactable",
		-- Electronic keyboard-typing cues, reused from the vanilla hack/ipad
		-- interactions (see interactiontweakdata.lua `hack_suburbia` et al.).
		-- Fits the copy-machine prop better than the bag-rustle set.
		sound_start = "bar_keyboard",
		sound_interupt = "bar_keyboard_cancel",
		sound_done = "bar_keyboard_finished",
	}
end)

-- Registers the "csr_scrapper" interaction tweak used by the in-world
-- evidence-shredder scrapper prop (scrapper_spawner.lua). Mirrors the csr_copier
-- tweak file; the subclass pins the timer in _get_timer so
-- upgrade_timer_multiplier / Toolset Expert never speed it up.

if not InteractionTweakData then
	return
end

-- Yellow contour palette deferred to LocalizationManagerPostInit (TweakData is
-- nil when this script body runs; see copier_interaction.lua for the full
-- write-up). Idempotent with copier_interaction.lua -- same key, different hook
-- id, first to run registers it.
Hooks:Add("LocalizationManagerPostInit", "CSR_RegisterYellowContourPalette", function()
	if tweak_data and tweak_data.contour and not tweak_data.contour.csr_yellow_interactable then
		tweak_data.contour.csr_yellow_interactable = {
			standard_color = Vector3(1, 0.85, 0),
			selected_color = Vector3(1, 1, 0.4),
		}
	end
end)

Hooks:PostHook(InteractionTweakData, "init", "CSR_ScrapperInteractionTweak", function(self)
	self.csr_scrapper = {
		icon = "equipment_missing",
		text_id = "csr_interact_scrapper",
		action_text_id = "csr_interact_scrapper_action",
		blocked_hint = "csr_scrapper_no_items",
		timer = 0.5,
		interact_distance = 250,
		sound_start = "bar_keyboard",
		sound_interupt = "bar_keyboard_cancel",
		sound_done = "bar_keyboard_finished",
		-- Yellow contour, gated on distance by scrapper_spawner.lua's per-frame
		-- proximity hook (only rendered when within CSR_PROX_RANGE there).
		contour = "csr_yellow_interactable",
	}
end)

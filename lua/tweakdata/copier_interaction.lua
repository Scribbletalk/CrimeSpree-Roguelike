-- Interaction tweak for the in-world printer prop (csr_copier).

if not InteractionTweakData then
	return
end

-- TweakData is nil at script-load (InteractionTweakData loads before it), so palette registration is deferred. Idempotent with scrapper_interaction.lua.
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
		-- Proximity-gated by copier_spawner.lua (only shown within CSR_PROX_RANGE).
		contour = "csr_yellow_interactable",
		-- Keyboard sounds fit the prop better than bag-rustle cues.
		sound_start = "bar_keyboard",
		sound_interupt = "bar_keyboard_cancel",
		sound_done = "bar_keyboard_finished",
	}
end)

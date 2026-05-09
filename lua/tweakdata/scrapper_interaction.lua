-- Registers the "csr_scrapper" interaction tweak used by the in-world
-- evidence-shredder scrapper prop (scrapper_spawner.lua). Mirrors the
-- csr_copier tweak file structure; subclass pins the timer in _get_timer
-- so upgrade_timer_multiplier / Toolset Expert never speed it up.

if not InteractionTweakData then
	return
end

-- Palette registration deferred to LocalizationManagerPostInit:
-- vanilla tweakdata.lua creates `self.interaction` at line ~763 but only assigns
-- `self.contour = { ... }` at line ~1513, so we can't register from inside
-- InteractionTweakData:init (contour table doesn't exist yet there). Hooking
-- TweakData:init from this file also fails: tweakdata.lua requires the
-- InteractionTweakData class file at line 29, BEFORE TweakData itself is
-- declared at line 54 — so when our script body runs, the global `TweakData`
-- is still nil. LocalizationManagerPostInit fires after the entire tweak_data
-- table is built, so both globals are guaranteed populated.
--
-- If skipped, downstream consumers (vanilla set_contour, plus third-party
-- wrappers like Clientsided Uppers's interactionext.lua hook) crash with
-- "attempt to index a nil value" the moment a unit referencing
-- contour = "csr_yellow_interactable" is spawned. Idempotent:
-- copier_interaction.lua registers the same key under a different hook id.
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
		-- Yellow contour, gated on distance by scrapper_spawner.lua's
		-- per-frame proximity hook (the contour is only rendered when the
		-- player is within CSR_PROX_RANGE — see PROX_RANGE constant there).
		contour = "csr_yellow_interactable",
	}
end)

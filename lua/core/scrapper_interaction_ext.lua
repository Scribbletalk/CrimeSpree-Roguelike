-- CrimeSpreeScrapperInteractionExt
-- ---------------------------------------------------------------------------
-- Interaction extension for the in-world evidence-shredder scrapper prop
-- (scrapper_spawner.lua). Modeled on copier_interaction_ext.lua. On hold-
-- complete, opens an item-pick dialog (lua/menu/scrapper_menu.lua).
--
-- Note: the asset is INJECTED via supermod.xml, so attaching this extension
-- in the .unit XML hijacks every shredder instance in the global asset DB,
-- including any vanilla-placed ones. The _is_csr_owned gate below prevents
-- us from showing a hover prompt on those vanilla shredders.

if not RequiredScript then
	return
end

if not UseInteractionExt then
	return
end

CrimeSpreeScrapperInteractionExt = CrimeSpreeScrapperInteractionExt or class(UseInteractionExt)

-- Keep the interaction live after a successful use so the player can scrap
-- multiple items without re-aiming.
CrimeSpreeScrapperInteractionExt.keep_active_after_interaction = true

-- A scrapper unit is "ours" only if it lives in the debug-spawn registry. The
-- scrapper has no auto-spawn flow yet (parity with the copier comes later);
-- until then this is the only path that puts the prop in the world.
function CrimeSpreeScrapperInteractionExt:_is_csr_owned()
	local list = _G.CSR_DebugSpawnedUnits
	if not list then
		return false
	end
	for _, u in ipairs(list) do
		if alive(u) and u == self._unit then
			return true
		end
	end
	return false
end

function CrimeSpreeScrapperInteractionExt:can_select(player, locator)
	if not self:_is_csr_owned() then
		return false
	end
	return CrimeSpreeScrapperInteractionExt.super.can_select(self, player, locator)
end

function CrimeSpreeScrapperInteractionExt:_interact_blocked(player)
	if not self:_is_csr_owned() then
		return true
	end
	if not (managers.crime_spree and (managers.crime_spree:is_active() or managers.crime_spree:in_progress())) then
		return true
	end
	-- Animation lock: scrapper_menu.lua:play_scrapper_anim stamps a "busy
	-- until" timestamp here when an item is scrapped, so the player can't
	-- re-trigger the interaction while the shredder animation is mid-play.
	local busy = _G.CSR_ScrapperBusyUntil and _G.CSR_ScrapperBusyUntil[self._unit:key()]
	if busy then
		local now = (Application and Application:time()) or 0
		if now < busy then
			return true
		end
	end
	-- Empty-item case is intentionally NOT a block: silently hiding the prompt
	-- when items=0 makes the scrapper feel broken. Let the prompt show, let
	-- the hold complete, and let the menu's own "No items to scrap" hint
	-- (in CSR_ScrapperMenu_Open) give the player feedback.
	return false
end

function CrimeSpreeScrapperInteractionExt:interact(player)
	-- Mirror vanilla's own can_interact gate so we don't run when the hold
	-- completes against stale state (item vanished between start and finish).
	if not self:can_interact(player) then
		return
	end
	-- Do NOT call CrimeSpreeScrapperInteractionExt.super.interact: vanilla
	-- UseInteractionExt:interact runs the unit's "interact" sequence on
	-- hold-complete (interactionext.lua:901-905), which on this prop plays
	-- the shredder animation. We want the animation gated to actual item
	-- pick (scrapper_menu.lua:on_pick), not the F-hold itself. Inline the
	-- two pieces from UseInteractionExt we still need:
	--   - BaseInteractionExt:interact's "sound_done" post-event (so the
	--     keyboard 'finished' SFX plays at hold completion)
	--   - remove_interact() to hide the prompt while the menu is up
	-- Network sync, equipment consume, sound_event, and run_sequence_simple
	-- are all intentionally dropped — local-only debug prop, no animation
	-- here.
	self._tweak_data_at_interact_start = nil
	self:_post_event(player, "sound_done")
	self:remove_interact()
	-- remove_interact alone isn't enough: with keep_active_after_interaction
	-- = true the unit stays in managers.interaction's active set, so vanilla's
	-- per-frame raycast re-shows the "Hold F to use scrapper" prompt the
	-- moment we let the menu draw. set_active(false) drops it from that set
	-- entirely; close_menu() calls set_active(true) to restore selectability
	-- once the player closes the menu.
	if self.set_active then
		pcall(function()
			self:set_active(false)
		end)
	end

	local open_fn = _G.CSR_ScrapperMenu_Open
	if open_fn then
		pcall(open_fn, self._unit)
	end

	-- super.interact called remove_interact() which hid the HUD prompt. Since
	-- keep_active_after_interaction = true the unit stays selected, so call
	-- update_show_interact directly to re-show "Hold [F] to use scrapper".
	if self._is_selected and alive(self._unit) then
		local local_player = managers.player and managers.player:player_unit()
		if player and local_player and player == local_player then
			self:update_show_interact(player)
		end
	end
end

-- Single chokepoint for ALL contour writes on CSR scrappers. Mirrors the
-- pattern in copier_interaction_ext.lua. Vanilla's selected/unselect call
-- set_contour with no opacity arg whenever the player aims at or away from
-- the prop — Clientsided Uppers's wrapper turns that into opacity=1, fighting
-- our prox hook's opacity=0 write. Forcing opacity to 0 here when the unit
-- is out-of-prox-range (CSR_ScrapperProxState in scrapper_spawner.lua) makes
-- every set_contour call obey the prox state regardless of caller.
function CrimeSpreeScrapperInteractionExt:set_contour(color, opacity)
	-- Map-placed shredders share this extension via supermod.xml DB injection.
	-- They're not in CSR_ScrapperProxState, so the prox-range gate below misses
	-- them and the yellow contour leaks onto vanilla props. Force opacity=0 first.
	if not self:_is_csr_owned() then
		opacity = 0
	elseif _G.CSR_ScrapperProxState and _G.CSR_ScrapperProxState[self._unit] == false then
		opacity = 0
	end
	CrimeSpreeScrapperInteractionExt.super.set_contour(self, color, opacity)
end

function CrimeSpreeScrapperInteractionExt:_get_timer()
	return self._tweak_data.timer or 0.5
end

function CrimeSpreeScrapperInteractionExt:interact_interupt(player, complete)
	CrimeSpreeScrapperInteractionExt.super.interact_interupt(self, player, complete)
	if self._is_selected and alive(self._unit) then
		local local_player = managers.player and managers.player:player_unit()
		if player and local_player and player == local_player then
			self:update_show_interact(player)
		end
	end
end

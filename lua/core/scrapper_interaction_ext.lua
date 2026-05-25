-- CrimeSpreeScrapperInteractionExt
-- ---------------------------------------------------------------------------
-- Interaction extension for the in-world evidence-shredder scrapper prop
-- (scrapper_spawner.lua). Modeled on copier_interaction_ext.lua. On hold-
-- complete, opens an item-pick dialog (lua/menu/scrapper_menu.lua).
--
-- The asset is INJECTED via supermod.xml, so attaching this extension in the
-- .unit XML hijacks every shredder instance in the global asset DB, including
-- vanilla-placed ones. The _is_csr_owned gate prevents a hover prompt on those.

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

-- A scrapper unit is "ours" only if it lives in the debug-spawn registry
-- (CSR_DebugSpawnedUnits, populated by scrapper_spawner.lua for both auto- and
-- debug-spawns). Map-placed vanilla shredders are not in it -> not interactable.
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
	-- Only usable inside a CSR run. is_run_active() is the item-hook convention
	-- (always true in the alpha stub); _is_csr_owned already ensures this is a
	-- CSR-spawned shredder, so this is belt-and-braces.
	local mgr = managers.csr
	if mgr and mgr.is_run_active and not mgr:is_run_active() then
		return true
	end
	-- Animation lock: scrapper_menu.lua:play_scrapper_anim stamps a "busy until"
	-- timestamp here when an item is scrapped, so the player can't re-trigger the
	-- interaction while the shredder animation is mid-play.
	local busy = _G.CSR_ScrapperBusyUntil and _G.CSR_ScrapperBusyUntil[self._unit:key()]
	if busy then
		local now = (Application and Application:time()) or 0
		if now < busy then
			return true
		end
	end
	-- Empty-item case is intentionally NOT a block: silently hiding the prompt
	-- when items=0 makes the scrapper feel broken. Let the prompt show, let the
	-- hold complete, and let the menu's own "No items to scrap" message give the
	-- player feedback.
	return false
end

function CrimeSpreeScrapperInteractionExt:interact(player)
	-- Mirror vanilla's own can_interact gate so we don't run when the hold
	-- completes against stale state (item vanished between start and finish).
	if not self:can_interact(player) then
		return
	end
	-- Do NOT call super.interact: vanilla UseInteractionExt:interact runs the
	-- unit's "interact" sequence on hold-complete, which on this prop plays the
	-- shredder animation. We want that animation gated to the actual item pick
	-- (scrapper_menu.lua:on_pick), not the F-hold itself. Inline the two pieces
	-- we still need: the "sound_done" post-event (keyboard 'finished' SFX) and
	-- remove_interact() to hide the prompt while the menu is up.
	self._tweak_data_at_interact_start = nil
	self:_post_event(player, "sound_done")
	self:remove_interact()
	-- remove_interact alone isn't enough: with keep_active_after_interaction =
	-- true the unit stays in managers.interaction's active set, so vanilla's
	-- per-frame raycast re-shows the prompt the moment the menu draws.
	-- set_active(false) drops it; close_menu() calls set_active(true) to restore.
	if self.set_active then
		pcall(function()
			self:set_active(false)
		end)
	end

	local open_fn = _G.CSR_ScrapperMenu_Open
	if open_fn then
		pcall(open_fn, self._unit)
	end

	if self._is_selected and alive(self._unit) then
		local local_player = managers.player and managers.player:player_unit()
		if player and local_player and player == local_player then
			self:update_show_interact(player)
		end
	end
end

-- Single chokepoint for ALL contour writes on CSR scrappers (mirrors
-- copier_interaction_ext.lua). Forces opacity 0 for non-CSR shredders and for
-- out-of-prox-range units so the yellow contour obeys the prox state regardless
-- of which code path (vanilla selected/unselect, Clientsided Uppers) calls it.
function CrimeSpreeScrapperInteractionExt:set_contour(color, opacity)
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

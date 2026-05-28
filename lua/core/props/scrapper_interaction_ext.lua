-- Interaction extension for the in-world evidence shredder. Attached via
-- supermod.xml to pex_prop_evidence_shredder.unit. Arch + MP notes in
-- csr_in_world_props_architecture.md.

if not RequiredScript then
	return
end

if not UseInteractionExt then
	return
end

CrimeSpreeScrapperInteractionExt = CrimeSpreeScrapperInteractionExt or class(UseInteractionExt)

CrimeSpreeScrapperInteractionExt.keep_active_after_interaction = true

-- A scrapper unit is "ours" only if it's in CSR_DebugSpawnedUnits. Map-placed
-- vanilla shredders aren't, so they stay inert.
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
	local mgr = managers.csr
	if mgr and mgr.is_run_active and not mgr:is_run_active() then
		return true
	end
	-- scrapper_menu.lua stamps a "busy until" timestamp here while the shred anim
	-- is mid-play, so the player can't re-trigger the interaction.
	local busy = _G.CSR_ScrapperBusyUntil and _G.CSR_ScrapperBusyUntil[self._unit:key()]
	if busy then
		local now = (Application and Application:time()) or 0
		if now < busy then
			return true
		end
	end
	-- Empty inventory is deliberately NOT a block — let the menu surface "No items
	-- to scrap" rather than silently hiding the prompt (which feels broken).
	return false
end

function CrimeSpreeScrapperInteractionExt:interact(player)
	if not self:can_interact(player) then
		return
	end
	-- Don't call super.interact: it runs the "interact" sequence (shred animation)
	-- on hold-complete. We want that animation gated to the actual item pick in
	-- scrapper_menu:on_pick. Inline the two side effects we still need.
	self._tweak_data_at_interact_start = nil
	self:_post_event(player, "sound_done")
	self:remove_interact()
	-- remove_interact alone isn't enough with keep_active_after_interaction = true;
	-- vanilla's per-frame raycast re-shows the prompt the moment the menu draws.
	-- set_active(false) drops us from managers.interaction's active set;
	-- scrapper_menu.close_menu restores it.
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

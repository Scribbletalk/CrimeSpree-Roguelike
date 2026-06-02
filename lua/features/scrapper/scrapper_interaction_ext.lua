-- Interaction extension for the CSR in-world evidence shredder unit.

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
	-- Busy flag stamped by scrapper_menu.lua during the shred animation.
	local busy = _G.CSR_ScrapperBusyUntil and _G.CSR_ScrapperBusyUntil[self._unit:key()]
	if busy then
		local now = (Application and Application:time()) or 0
		if now < busy then
			return true
		end
	end
	-- Empty inventory is not a block; the menu surfaces the "nothing to scrap" message.
	return false
end

function CrimeSpreeScrapperInteractionExt:interact(player)
	if not self:can_interact(player) then
		return
	end
	-- Skip super.interact — the shred animation must fire from scrapper_menu:on_pick, not here.
	self._tweak_data_at_interact_start = nil
	self:_post_event(player, "sound_done")
	self:remove_interact()
	-- set_active(false) suppresses the re-shown prompt; scrapper_menu.close_menu restores it.
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

-- Interaction extension for the in-world printer. Attached via supermod.xml
-- to off_prop_copy_machine_smuggle.unit. Arch + MP notes in
-- csr_in_world_props_architecture.md.

if not RequiredScript then
	return
end

-- Two hook entries (mod.txt): interactionext + hudinteraction. Whichever fires
-- first installs its half; a once-flag prevents double-install.
if HUDInteraction and not _G._CSR_HoverPromptHookInstalled then
	_G._CSR_HoverPromptHookInstalled = true
	-- Reset the hover-prompt text to white on every show_interact. Vanilla never
	-- resets it, so our red "blocked" tint would bleed onto the next interactable.
	Hooks:PostHook(HUDInteraction, "show_interact", "CSR_ResetHoverPromptColor", function(self, data)
		if not (self._hud_panel and self._child_name_text) then
			return
		end
		local text_obj = self._hud_panel:child(self._child_name_text)
		if text_obj then
			text_obj:set_color(Color.white)
		end
	end)
end

-- Bail until the other hook entry brings UseInteractionExt up.
if not UseInteractionExt then
	return
end

CrimeSpreeCopierInteractionExt = CrimeSpreeCopierInteractionExt or class(UseInteractionExt)

-- Stay live after a successful hold so the printer can be used again.
CrimeSpreeCopierInteractionExt.keep_active_after_interaction = true

-- supermod.xml injects this extension onto every off_prop_copy_machine_smuggle
-- in the DB, including vanilla map-placed ones. _is_csr_owned filters those out.
function CrimeSpreeCopierInteractionExt:_is_csr_owned()
	local finder = _G.CSR_FindCopierByUnit
	return finder and finder(self._unit) ~= nil
end

function CrimeSpreeCopierInteractionExt:can_select(player, locator)
	if not self:_is_csr_owned() then
		return false
	end
	return CrimeSpreeCopierInteractionExt.super.can_select(self, player, locator)
end

function CrimeSpreeCopierInteractionExt:_interact_blocked(player)
	local finder = _G.CSR_FindCopierByUnit
	if not finder then
		return false
	end
	local copier = finder(self._unit)
	if not copier then
		return true
	end

	if copier.cycling then
		return true
	end

	-- Blocked when the local player owns no same-tier item to sacrifice.
	local has_fn = _G.CSR_CopierHasSacrifice
	if not has_fn then
		return false
	end
	if not has_fn(copier.tier) then
		return true
	end

	return false
end

function CrimeSpreeCopierInteractionExt:interact(player)
	-- Mirror vanilla's can_interact gate so a hold that completes against stale
	-- state (item vanished between start and finish) bails before delegating.
	if not self:can_interact(player) then
		return
	end
	CrimeSpreeCopierInteractionExt.super.interact(self, player)

	local finder = _G.CSR_FindCopierByUnit
	local use_fn = _G.CSR_UseCopier
	if finder and use_fn then
		local copier = finder(self._unit)
		if copier then
			use_fn(copier)
		end
	end
	-- super.interact called remove_interact(); re-show the prompt directly so the
	-- copier keeps its hover state (set_text_dirty is unreliable across frames).
	if self._is_selected and alive(self._unit) then
		local local_player = managers.player and managers.player:player_unit()
		if player and local_player and player == local_player then
			self:update_show_interact(player)
		end
	end
end

-- Single chokepoint for all contour writes — forces opacity=0 for vanilla map-
-- placed copiers and for out-of-prox-range units, defeating Clientsided Uppers's
-- wrapper which fights our prox state.
function CrimeSpreeCopierInteractionExt:set_contour(color, opacity)
	if not self:_is_csr_owned() then
		opacity = 0
	elseif _G.CSR_CopierProxState and _G.CSR_CopierProxState[self._unit] == false then
		opacity = 0
	end
	CrimeSpreeCopierInteractionExt.super.set_contour(self, color, opacity)
end

function CrimeSpreeCopierInteractionExt:_get_timer()
	-- Fallback mirrors tweak_data.interaction.csr_copier.timer. Keep in sync.
	return self._tweak_data.timer or 0.5
end

function CrimeSpreeCopierInteractionExt:interact_interupt(player, complete)
	CrimeSpreeCopierInteractionExt.super.interact_interupt(self, player, complete)
	-- Force a prompt refresh so "Hold F" reappears after a release-before-finish.
	if self._is_selected and alive(self._unit) then
		local local_player = managers.player and managers.player:player_unit()
		if player and local_player and player == local_player then
			self:update_show_interact(player)
		end
	end
end

-- Tint the hover prompt red while blocked. Pairs with the show_interact reset
-- PostHook above: super's call chain leaves text white, we re-tint here.
local BLOCKED_PROMPT_COLOR = Color(1, 1, 0.2, 0.2)

function CrimeSpreeCopierInteractionExt:update_show_interact(player, locator)
	CrimeSpreeCopierInteractionExt.super.update_show_interact(self, player, locator)
	if not self:_interact_blocked(player) then
		return
	end
	-- Only tint when THIS copier is the active interaction target — otherwise red
	-- bleeds onto another prompt while keep_active_after_interaction keeps us in the pool.
	if not (managers.interaction and managers.interaction:active_unit() == self._unit) then
		return
	end
	local hud = managers.hud and managers.hud._hud_interaction
	if not (hud and hud._hud_panel and hud._child_name_text) then
		return
	end
	local text_obj = hud._hud_panel:child(hud._child_name_text)
	if text_obj then
		text_obj:set_color(BLOCKED_PROMPT_COLOR)
	end
end

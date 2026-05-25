-- CrimeSpreeCopierInteractionExt
-- ---------------------------------------------------------------------------
-- Interaction extension for the in-world printer/copier (copier_spawner.lua).
-- Referenced from off_prop_copy_machine_smuggle.unit as:
--   <extension name="interaction" class="CrimeSpreeCopierInteractionExt">
--     <var name="tweak_data" value="csr_copier" />
--   </extension>
--
-- Overrides:
--   _interact_blocked — return true when the player has no same-tier sacrifice
--                       or when the copier is mid-cycle (so the red blocked
--                       hint "No matching-tier item to exchange" appears).
--   interact          — on hold completion, delegate to CSR_UseCopier, which
--                       runs the sacrifice / offer / lid-anim flow.
--   _get_timer        — pin the hold to tweak_data.timer (0.5s) regardless of
--                       crew_interact / upgrade_timer_multiplier / infamy / toolset.

if not RequiredScript then
	return
end

-- Loaded by TWO hook entries (mod.txt) so we run regardless of which subsystem
-- class is defined first:
--   - lib/units/interactions/interactionext  -> UseInteractionExt is up, build subclass
--   - lib/managers/hud/hudinteraction        -> HUDInteraction is up, install PostHook
-- The HUDInteraction PostHook runs UNCONDITIONALLY of UseInteractionExt so the
-- early-return below (when UseInteractionExt is nil) doesn't skip it. A once-flag
-- prevents double-install if both hooks fire.

if HUDInteraction and not _G._CSR_HoverPromptHookInstalled then
	_G._CSR_HoverPromptHookInstalled = true
	-- Reset the hover-prompt text color to white on EVERY show_interact call. Our
	-- subclass below re-tints to red AFTER super's call chain has fired
	-- show_interact, so the order is: reset white -> (subclass) re-tint red if
	-- blocked, else stays white. Without this reset, a red tint bleeds onto the
	-- NEXT interactable the player looks at (vanilla never resets this color).
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

-- From here down requires UseInteractionExt. When loaded via the hudinteraction
-- hook the class isn't up yet -- bail cleanly; the interactionext hook re-loads us.
if not UseInteractionExt then
	return
end

CrimeSpreeCopierInteractionExt = CrimeSpreeCopierInteractionExt or class(UseInteractionExt)

-- Keep the interaction active after a successful hold-to-use so the printer can
-- be used again. Without this, UseInteractionExt:interact calls set_active(false)
-- after a successful use, permanently hiding the prompt on that copier.
CrimeSpreeCopierInteractionExt.keep_active_after_interaction = true

-- Map-placed vanilla copiers must NOT be interactable. supermod.xml injects this
-- extension onto every off_prop_copy_machine_smuggle in the DB, including props
-- baked into heist levels. Gate the whole funnel on "this unit is one of ours"
-- so only CSR-spawned copiers show the outline + hover prompt.
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
		-- Not one of ours -- belt-and-braces in case can_select is bypassed.
		return true
	end

	if copier.cycling then
		return true
	end

	-- Blocked when the local player owns no item of the offer's tier to sacrifice.
	-- CSR_CopierHasSacrifice (copier_spawner.lua) reads managers.csr ownership.
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
	-- Mirror vanilla UseInteractionExt:interact's can_interact gate so that if the
	-- hold completes against stale state (item vanished between timer start and
	-- completion) both super and our CSR_UseCopier delegate skip together.
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
	-- super.interact called remove_interact() which hid the HUD prompt. Since
	-- keep_active_after_interaction = true the copier stays selected, so nothing
	-- else re-shows the prompt. Re-show it directly for the local player.
	if self._is_selected and alive(self._unit) then
		local local_player = managers.player and managers.player:player_unit()
		if player and local_player and player == local_player then
			self:update_show_interact(player)
		end
	end
end

-- Single chokepoint for ALL contour writes on CSR copiers. Vanilla's
-- selected/unselect call set_contour with no opacity arg; Clientsided Uppers's
-- wrapper turns that into opacity=1 whenever the player aims at/away from the
-- prop, fighting our prox hook's opacity=0 write. Forcing opacity to 0 here when
-- the unit is marked out-of-range (CSR_CopierProxState) makes every set_contour
-- call obey the prox state regardless of caller.
function CrimeSpreeCopierInteractionExt:set_contour(color, opacity)
	-- Map-placed copiers share this extension via DB injection; they aren't in
	-- CSR_CopierProxState, so force opacity=0 so the yellow contour never leaks.
	if not self:_is_csr_owned() then
		opacity = 0
	elseif _G.CSR_CopierProxState and _G.CSR_CopierProxState[self._unit] == false then
		opacity = 0
	end
	CrimeSpreeCopierInteractionExt.super.set_contour(self, color, opacity)
end

function CrimeSpreeCopierInteractionExt:_get_timer()
	-- Fallback 0.5 mirrors tweak_data.interaction.csr_copier.timer; only hit if
	-- the csr_copier tweak entry is somehow missing. Keep them in sync.
	return self._tweak_data.timer or 0.5
end

function CrimeSpreeCopierInteractionExt:interact_interupt(player, complete)
	CrimeSpreeCopierInteractionExt.super.interact_interupt(self, player, complete)
	-- On release before completion the "release [F] to cancel" text can linger if
	-- the text_dirty flag is lost across frames. Force a prompt refresh so the
	-- normal "Hold F" text reappears.
	if self._is_selected and alive(self._unit) then
		local local_player = managers.player and managers.player:player_unit()
		if player and local_player and player == local_player then
			self:update_show_interact(player)
		end
	end
end

-- Tint the on-screen hover prompt RED while the printer is blocked, so the player
-- can tell at a glance there's nothing to sacrifice. Pairs with the show_interact
-- reset PostHook at the top: super's update_show_interact eventually calls
-- show_interact (resets white), then we re-tint red here.
local BLOCKED_PROMPT_COLOR = Color(1, 1, 0.2, 0.2) -- alpha, r, g, b -> bright red

function CrimeSpreeCopierInteractionExt:update_show_interact(player, locator)
	CrimeSpreeCopierInteractionExt.super.update_show_interact(self, player, locator)
	if not self:_interact_blocked(player) then
		return -- super's call chain already left the text white via the reset PostHook
	end
	-- Only tint red when this copier is the currently-displayed interaction target.
	-- With keep_active_after_interaction = true the unit stays in the pool after
	-- use, so update_show_interact can fire while another interactable is active --
	-- skip the tint to avoid bleeding red onto that prompt.
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

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
--                       runs the existing sacrifice / offer / lid-anim flow.
--   _get_timer        — pin the hold to tweak_data.timer (0.5s) regardless of
--                       crew_interact, upgrade_timer_multiplier, infamy level
--                       interaction bonus, or toolset_value (Toolset Expert).

if not RequiredScript then
	return
end

-- This file is loaded by TWO hook entries (mod.txt) so we run regardless of
-- which subsystem class is defined first:
--   - lib/units/interactions/interactionext  → UseInteractionExt is up, build subclass
--   - lib/managers/hud/hudinteraction        → HUDInteraction is up, install PostHook
-- The HUDInteraction PostHook block runs UNCONDITIONALLY of UseInteractionExt
-- so the early-return below (when UseInteractionExt is nil) doesn't skip it.
-- A once-flag prevents double-installation if both hooks fire and HUDInteraction
-- happened to also be loaded by the time the first hook fired.

if HUDInteraction and not _G._CSR_HoverPromptHookInstalled then
	_G._CSR_HoverPromptHookInstalled = true
	-- Reset the hover-prompt text color to white on EVERY show_interact call.
	-- Our subclass below re-tints to red AFTER super's call chain has fired
	-- show_interact, so the order is: reset white → (subclass) re-tint red if
	-- blocked, otherwise stays white. Without this reset, a red tint would
	-- bleed across to the NEXT interactable the player looked at, because
	-- vanilla never sets nor resets the color of this text element.
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

-- From here down requires UseInteractionExt. When this file is loaded via the
-- hudinteraction hook, the class definition isn't up yet — bail cleanly. The
-- interactionext hook will re-load us once that class is available.
if not UseInteractionExt then
	return
end

CrimeSpreeCopierInteractionExt = CrimeSpreeCopierInteractionExt or class(UseInteractionExt)

-- Keep the interaction active after a successful hold-to-use so the printer
-- can be used again (another exchange with another item). Without this flag,
-- UseInteractionExt:interact calls self:set_active(false) after a successful
-- use, permanently hiding the prompt on that copier unit.
CrimeSpreeCopierInteractionExt.keep_active_after_interaction = true

-- Map-placed vanilla copiers must NOT be interactable. Our supermod.xml
-- injects this extension onto every instance of off_prop_copy_machine_smuggle
-- in the game DB, including props already baked into heist levels. Gate the
-- whole interaction funnel on "this unit is one of ours" so only CSR-spawned
-- copiers show the outline + hover prompt. CSR_Copiers is populated on both
-- host and clients (clients fill it in _spawn_copier via CSR_HandleCopierSpawn),
-- so this check is MP-safe.
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
		-- Not one of ours — belt-and-braces in case can_select is bypassed.
		return true
	end

	if copier.cycling then
		return true
	end

	local owned_fn = _G.CSR_GetOwnedItemsByRarity
	if not owned_fn then
		return false
	end
	local owned = owned_fn(copier.tier)
	if not owned or #owned == 0 then
		return true
	end

	return false
end

function CrimeSpreeCopierInteractionExt:interact(player)
	-- Mirror vanilla UseInteractionExt:interact's own can_interact gate so that
	-- if the hold completes against stale state (e.g. item vanished between
	-- timer start and completion) both super and our CSR_UseCopier delegate
	-- skip together, instead of super bailing silently while we proceed.
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
	-- super.interact called remove_interact() which hid the HUD prompt.
	-- Since keep_active_after_interaction = true the copier stays selected, so
	-- nothing else re-shows the prompt. Call update_show_interact directly for
	-- the local player; it re-shows "Hold [F] to use printer" (red while cycling).
	if self._is_selected and alive(self._unit) then
		local local_player = managers.player and managers.player:player_unit()
		if player and local_player and player == local_player then
			self:update_show_interact(player)
		end
	end
end

-- Single chokepoint for ALL contour writes on CSR copiers. Vanilla's
-- selected/unselect (interactionext.lua:274/344) call set_contour with no
-- opacity arg — Clientsided Uppers's wrapper turns that into opacity=1
-- whenever the player aims at or away from the prop, fighting our prox hook's
-- opacity=0 write. Forcing opacity to 0 here when the unit is marked out-of-
-- range (CSR_CopierProxState in copier_spawner.lua) makes every set_contour
-- call obey the prox state regardless of caller. The original opacity is left
-- intact when in-range so vanilla's selected/aim highlighting still works.
function CrimeSpreeCopierInteractionExt:set_contour(color, opacity)
	-- Map-placed copiers share this extension via supermod.xml DB injection.
	-- They're not in CSR_CopierProxState, so the prox-range gate below misses
	-- them and the yellow contour leaks onto vanilla props. Force opacity=0 first.
	if not self:_is_csr_owned() then
		opacity = 0
	elseif _G.CSR_CopierProxState and _G.CSR_CopierProxState[self._unit] == false then
		opacity = 0
	end
	CrimeSpreeCopierInteractionExt.super.set_contour(self, color, opacity)
end

function CrimeSpreeCopierInteractionExt:_get_timer()
	-- Fallback 0.5 mirrors tweak_data.interaction.csr_copier.timer; only ever
	-- hit if the csr_copier tweak entry is somehow missing. Keep them in sync.
	return self._tweak_data.timer or 0.5
end

function CrimeSpreeCopierInteractionExt:interact_interupt(player, complete)
	CrimeSpreeCopierInteractionExt.super.interact_interupt(self, player, complete)
	-- When the player releases the hold before completion, the "release [F] to
	-- cancel" text lingers because the text_dirty mechanism can lose the flag if
	-- the unit briefly drops out of active_unit between frames.  Force a prompt
	-- refresh immediately so the normal "Hold F" text reappears.
	if self._is_selected and alive(self._unit) then
		local local_player = managers.player and managers.player:player_unit()
		if player and local_player and player == local_player then
			self:update_show_interact(player)
		end
	end
end

-- Tint the on-screen hover prompt RED while the printer is blocked, so the
-- player can tell at a glance there's nothing to sacrifice instead of having
-- to walk up and press F to discover it. Pairs with the show_interact reset
-- PostHook at the top of this file: super's update_show_interact eventually
-- calls show_interact which resets to white, then we re-tint red here.
local BLOCKED_PROMPT_COLOR = Color(1, 1, 0.2, 0.2) -- alpha, r, g, b → bright red

function CrimeSpreeCopierInteractionExt:update_show_interact(player, locator)
	CrimeSpreeCopierInteractionExt.super.update_show_interact(self, player, locator)
	if not self:_interact_blocked(player) then
		return -- super's call chain already left the text white via the reset PostHook
	end
	-- Only tint red when this copier is the currently-displayed interaction target.
	-- With keep_active_after_interaction = true the unit stays in the interaction
	-- pool after use, so update_show_interact can fire while another interactable
	-- is the active unit -- skip the tint to avoid bleeding red onto that prompt.
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

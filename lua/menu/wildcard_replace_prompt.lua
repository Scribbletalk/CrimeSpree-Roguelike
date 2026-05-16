-- Wildcard replace-confirm prompt + main-menu finalize override.
--
-- Wildcards are carry-1: picking a new one when the player already owns a
-- different wildcard must remove the old one. To avoid silent data loss,
-- every popup finalize for a wildcard runs through a confirmation modal.
--
-- Storage-layer cleanup (CSR_AddItem removing any existing wildcard when a
-- new wildcard is added) lives in player_items_store.lua and is the
-- defensive backstop. This module only owns the user-visible prompt; the
-- two paths agree on the final state so the data layer stays consistent
-- even if a future code path bypasses this prompt (scrapper, sync, late-
-- join catchup, debug menu, etc).
--
-- Two finalize entry points:
--   * Main-menu CrimeSpreeModifiersMenuComponent:_on_finalize_modifier
--     (hooked here via Hooks:OverrideFunction).
--   * Briefing-screen comp instance has its own _on_finalize_modifier set
--     per-instance in briefing_select_item.lua; that file calls
--     _G.CSR_PromptWildcardReplace directly.

if not RequiredScript then
	return
end

-- Find the registry def for a full item id like "player_turron_1" or a
-- selection-popup modifier id like "player_turron_0". Returns nil if the id
-- doesn't map to a registry entry.
local function find_item_def(full_id)
	if not full_id then
		return nil
	end
	local prefix_with_underscore = full_id:match("^(.+_)%d+$")
	if not prefix_with_underscore then
		return nil
	end
	local key = prefix_with_underscore:sub(1, -2)
	return _G.CSR_ITEM_BY_PREFIX and _G.CSR_ITEM_BY_PREFIX[key]
end

-- Localized display name for an item def. Falls back to UPPERCASED type so a
-- missing loc key never crashes the modal — readable, just unprettified.
local function display_name(item_def)
	if not item_def or not item_def.type then
		return "?"
	end
	local key = "csr_logbook_" .. item_def.type .. "_name"
	if managers.localization and managers.localization:exists(key) then
		return managers.localization:text(key)
	end
	return tostring(item_def.type):upper()
end

-- Public: full item id (e.g. "player_turron_1") of the local player's
-- currently-owned wildcard, or nil if none.
function _G.CSR_FindOwnedWildcardId()
	if not _G.CSR_GetLocalItems or not _G.CSR_ITEM_BY_PREFIX then
		return nil
	end
	local items = CSR_GetLocalItems()
	if not items then
		return nil
	end
	for _, it in ipairs(items) do
		local def = find_item_def(it.id)
		if def and def.rarity == "wildcard" then
			return it.id
		end
	end
	return nil
end

-- Public: if the player owns a DIFFERENT wildcard than the one represented by
-- `new_modifier_id`, show a confirmation modal. On YES, call on_confirm. On
-- NO, do nothing (popup stays open per user choice). If no replacement is
-- needed (new item isn't a wildcard, or no wildcard owned, or same prefix),
-- on_confirm is called immediately.
function _G.CSR_PromptWildcardReplace(new_modifier_id, on_confirm)
	if type(on_confirm) ~= "function" then
		return
	end
	local new_def = find_item_def(new_modifier_id)
	if not new_def or new_def.rarity ~= "wildcard" then
		on_confirm()
		return
	end
	local old_id = CSR_FindOwnedWildcardId()
	if not old_id then
		on_confirm()
		return
	end
	local old_def = find_item_def(old_id)
	-- Same prefix = vanilla dedupe will handle it / it's a no-op; skip modal.
	if old_def and old_def.id_prefix == new_def.id_prefix then
		on_confirm()
		return
	end
	if not managers.system_menu or not managers.localization then
		on_confirm()
		return
	end
	local dialog_data = {
		title = managers.localization:text("csr_wildcard_replace_title"),
		text = managers.localization:text("csr_wildcard_replace_text", {
			OLD = display_name(old_def),
			NEW = display_name(new_def),
		}),
		id = "csr_wildcard_replace_confirm",
	}
	local yes_button = {
		text = managers.localization:text("dialog_yes"),
		callback_func = function()
			on_confirm()
		end,
	}
	local no_button = {
		text = managers.localization:text("dialog_no"),
		cancel_button = true,
	}
	dialog_data.button_list = { yes_button, no_button }
	managers.system_menu:show(dialog_data)
end

-- Main-menu path: gate the vanilla finalize via the prompt. BLT-managed
-- override with captured original — same pattern briefing_select_item.lua
-- uses for MissionBriefingGui input methods, NOT a raw `local _orig = …`
-- override (that would destroy other mods' hooks per Critical Rule #1).
if CrimeSpreeModifiersMenuComponent and not _G._CSR_WILDCARD_FINALIZE_OVERRIDE then
	_G._CSR_WILDCARD_FINALIZE_OVERRIDE = true

	local _orig_finalize = Hooks:GetFunction(CrimeSpreeModifiersMenuComponent, "_on_finalize_modifier")
		or CrimeSpreeModifiersMenuComponent._on_finalize_modifier

	Hooks:OverrideFunction(CrimeSpreeModifiersMenuComponent, "_on_finalize_modifier", function(self)
		if not self or not self._selected_modifier then
			return _orig_finalize(self)
		end
		local data = self._selected_modifier.data and self._selected_modifier:data()
		local mod_id = data and data.id
		if not mod_id then
			return _orig_finalize(self)
		end
		CSR_PromptWildcardReplace(mod_id, function()
			_orig_finalize(self)
		end)
	end)
end

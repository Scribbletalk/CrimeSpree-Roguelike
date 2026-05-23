-- Cup of Joe (common) -- +10% max stamina per copy owned.
--
-- Per-item-file model: the whole item -- passport (metadata) AND behavior --
-- lives in this one self-contained file. Auto-discovered + executed by
-- extension_api.lua (no mod.txt entry). The file CALLS register_item itself
-- (PD2's dofile does not return chunk values), exactly as an addon would.
-- `hooks` maps an engine script path to a function run once, the moment that
-- script loads (its class is guaranteed to exist by then).
--
-- Text fields (name/desc/full_desc/notes) are LOCALIZATION KEYS, not literals:
-- the string lives in loc/<lang>.json so the game shows it in the current
-- language. english.json owns English; a future russian.json owns Russian; no
-- item-file change is needed to add a language.

if not (_G.CSR and _G.CSR.register_item) then
	return
end

_G.CSR.register_item({
	type = "cup_of_joe",
	rarity = "common",
	name = "csr_logbook_cup_of_joe_name",
	desc = "csr_item_cup_of_joe_desc",
	full_desc = "csr_logbook_cup_of_joe_effect",
	notes = "csr_logbook_cup_of_joe_notes",
	icon = "csr_cup_of_joe",

	hooks = {
		-- +10% to PlayerManager:stamina_multiplier per copy owned. It RETURNS a
		-- value (PostHook can't carry that), so a raw chain wrap per the CSR
		-- return-value convention; the _G guard stops a double-wrap. Mirrors the
		-- 6.2 constant cup_of_joe_per_stack (0.10).
		["lib/managers/playermanager"] = function()
			if _G._CSR_CUP_OF_JOE_HOOKED then
				return
			end
			_G._CSR_CUP_OF_JOE_HOOKED = true
			local orig = PlayerManager.stamina_multiplier
			function PlayerManager:stamina_multiplier()
				local v = orig(self)
				local mgr = managers.csr
				-- Only inside a CSR run, and only the local player's owned stacks.
				if not (mgr and mgr.is_run_active and mgr:is_run_active()) then
					return v
				end
				return v + 0.10 * mgr:owned("cup_of_joe")
			end
		end,
	},
})

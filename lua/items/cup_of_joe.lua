-- Cup of Joe (common) -- +10% max stamina per copy owned.
--
-- First item on the per-item-file model: the whole item -- passport (metadata)
-- AND behavior -- lives in this one file. Auto-discovered + executed by
-- csr_extension_api.lua (no mod.txt entry needed). The file CALLS register_item
-- itself (PD2's dofile does not return chunk values), exactly as an addon would
-- from its own mod. `hooks` maps an engine script path to a function run once,
-- the moment that script loads (its class is guaranteed to exist by then).

if not (_G.CSR and _G.CSR.register_item) then
	return
end

_G.CSR.register_item({
	-- Passport: appears in the menu, drop pool, inventory, save, with this icon.
	type = "cup_of_joe",
	rarity = "common",
	name = "CUP OF JOE",
	desc = "Increases your max stamina.", -- short card/selection text (Rule #15)
	full_desc = "Increases maximum stamina by {g}10%{/} (+10% per stack, linear).", -- Logbook
	notes = "- Total stolen: 1 artifact, 3 assault rifles, a set of samurai armor, a server... and a cup of Joe.\n- Sorry, a cup of Joe?\n- A cup of Joe.\n- ...\n- So where's Joe, exactly?\n- Not funny.\n- No, seriously. Where's Joe?\n- Oh, that Joe. He's right over there. Crying about his favorite mug being stolen.",
	icon = "csr_cup_of_joe",

	hooks = {
		-- +10% to PlayerManager:stamina_multiplier per copy owned. It RETURNS a
		-- value (PostHook can't carry that), so a raw chain wrap per the CSR
		-- return-value convention; the _G guard stops a double-wrap if this ever
		-- runs twice. Mirrors the 6.2 constant cup_of_joe_per_stack (0.10).
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

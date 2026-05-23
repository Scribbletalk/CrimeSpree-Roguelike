-- Piece of Rebar (common) -- the first hit on each enemy deals bonus damage.
--
-- Per-item-file model (see cup_of_joe.lua). Text fields are localization keys.
--
-- PreHook on the four CopDamage damage_* paths: the FIRST time the local player
-- damages a given enemy, that hit's attack_data.damage is multiplied by
-- (1 + base_bonus + (stacks-1)*extra_bonus). A per-enemy flag (cop._csr_rebar_hit)
-- makes it once-per-unit; it rides on the CopDamage instance (GC'd with the unit).
--
-- MP: amplifying attack_data.damage inside a PreHook on the ATTACKER's local
-- damage_* call routes the higher damage through vanilla's own networking (the
-- proven Bonnie's Chip path). The is_local_player gate means each peer amplifies
-- only its own first-hits, and the host never re-amplifies a client's hit.
-- Values mirror the 6.2 register line (base_bonus 0.15 / extra_bonus 0.10).

if not (_G.CSR and _G.CSR.register_item) then
	return
end

local BASE_BONUS = 0.15
local EXTRA_BONUS = 0.10

local function rebar_apply_first_hit(cop, attack_data)
	local mgr = managers and managers.csr
	if not mgr or not mgr.is_run_active or not mgr:is_run_active() then
		return
	end
	if not attack_data or not attack_data.damage then
		return
	end
	-- Local-player attacker only (the host resolves bots' / remote peers' damage
	-- too; without this their first hit would consume the buff and mis-scale it).
	local au = attack_data.attacker_unit
	if not au or not au:base() or au:base().is_local_player ~= true then
		return
	end
	if cop._csr_rebar_hit then
		return
	end
	local stacks = mgr:owned("rebar")
	if stacks <= 0 then
		return
	end
	local bonus = BASE_BONUS + (stacks - 1) * EXTRA_BONUS
	cop._csr_rebar_hit = true
	attack_data.damage = attack_data.damage * (1 + bonus)
	if mgr:debug_enabled() then
		mgr:debug_log(string.format("rebar first-hit +%.0f%% damage", bonus * 100))
	end
end

_G.CSR.register_item({
	type = "rebar",
	rarity = "common",
	name = "logbook_rebar_name",
	desc = "item_rebar_desc",
	full_desc = "logbook_rebar_effect",
	notes = "logbook_rebar_notes",
	icon = "rebar",

	hooks = {
		["lib/units/enemies/cop/copdamage"] = function()
			if _G._CSR_REBAR_HOOKED then
				return
			end
			_G._CSR_REBAR_HOOKED = true
			Hooks:PreHook(CopDamage, "damage_bullet", "CSR_Rebar_Bullet", rebar_apply_first_hit)
			if CopDamage.damage_melee then
				Hooks:PreHook(CopDamage, "damage_melee", "CSR_Rebar_Melee", rebar_apply_first_hit)
			end
			if CopDamage.damage_dot then
				Hooks:PreHook(CopDamage, "damage_dot", "CSR_Rebar_Dot", rebar_apply_first_hit)
			end
			if CopDamage.damage_explosion then
				Hooks:PreHook(CopDamage, "damage_explosion", "CSR_Rebar_Explosion", rebar_apply_first_hit)
			end
		end,
	},
})

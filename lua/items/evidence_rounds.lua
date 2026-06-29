-- Evidence Rounds (uncommon) — +10%/stack to bullet-weapon damage and sentry turrets.
-- "Bullets" = any primary/secondary firearm plus bows/crossbows (their arrows resolve to
-- CopDamage:damage_bullet via InstantBulletBase). Explosions, throwables, melee and fire/DOT
-- are intentionally NOT covered — those are reserved for separate future items.

if not (_G.CSR and _G.CSR.register_item) then
	return
end

local PER_STACK = 0.10

-- Amplify the local player's bullet-class hits. Target-side scaling on CopDamage, gated on
-- attacker == local player (Rebar/Equalizer pattern; see csr_damage_amplification_pattern.md).
-- Guns, bows and crossbows all funnel through damage_bullet, so one hook covers them uniformly.
local function apply_bullet_bonus(_, attack_data)
	if not attack_data or not attack_data.damage or attack_data.damage <= 0 then
		return
	end
	local au = attack_data.attacker_unit
	if not au or not alive(au) or not au:base() or au:base().is_local_player ~= true then
		return
	end
	local mgr = managers and managers.csr
	if not (mgr and mgr.in_csr_heist and mgr:in_csr_heist()) then
		return
	end
	local stacks = mgr:owned("evidence_rounds")
	if stacks > 0 then
		attack_data.damage = attack_data.damage * (1 + PER_STACK * stacks)
	end
end

_G.CSR.register_item({
	type = "evidence_rounds",
	rarity = "uncommon",
	name = "csr_logbook_evidence_rounds_name",
	desc = "csr_item_evidence_rounds_desc",
	full_desc = "csr_logbook_evidence_rounds_effect",
	notes = "csr_logbook_evidence_rounds_notes",
	icon = "csr_evidence_rounds",
	icon_scale = 0.9,
	loc_macros = {
		per_stack_pct = string.format("%g", PER_STACK * 100),
	},

	-- Heister panel: +PER_STACK/stack ranged (bullet/sentry) damage only; melee, throwables,
	-- explosions and fire/DOT are intentionally NOT buffed, so they are not declared here.
	stat_preview = function(count)
		return { damage_ranged = 1 + PER_STACK * count }
	end,

	hooks = {
		["lib/units/enemies/cop/copdamage"] = function()
			if _G._CSR_EVIDENCE_ROUNDS_BULLET_HOOKED then
				return
			end
			_G._CSR_EVIDENCE_ROUNDS_BULLET_HOOKED = true
			Hooks:PreHook(CopDamage, "damage_bullet", "CSR_EvidenceRounds_Bullet", apply_bullet_bonus)
		end,

		-- Sentry turrets fire via InstantBulletBase with user_unit = the sentry unit, not the player,
		-- so they bypass the is_local_player bullet hook. Scale the sentry's own per-shot damage
		-- instead, gated on its owner (self._owner = setup_data.user_unit) being the local player.
		["lib/units/weapons/sentrygunweapon"] = function()
			if _G._CSR_EVIDENCE_ROUNDS_SENTRY_HOOKED then
				return
			end
			_G._CSR_EVIDENCE_ROUNDS_SENTRY_HOOKED = true
			local orig = SentryGunWeapon._apply_dmg_mul
			if not orig then
				return
			end
			function SentryGunWeapon:_apply_dmg_mul(damage, col_ray, from_pos)
				local result = orig(self, damage, col_ray, from_pos)
				if type(result) ~= "number" then
					return result
				end
				local owner = self._owner
				if not (owner and alive(owner) and owner:base() and owner:base().is_local_player == true) then
					return result
				end
				local mgr = managers and managers.csr
				if not (mgr and mgr.in_csr_heist and mgr:in_csr_heist()) then
					return result
				end
				local stacks = mgr:owned("evidence_rounds")
				if stacks > 0 then
					result = result * (1 + PER_STACK * stacks)
				end
				return result
			end
		end,
	},
})

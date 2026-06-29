-- Bonnie's Lucky Chip (rare) — each bullet hit has a small chance to instakill.
-- Amplification pattern: amplify damage so vanilla damage_bullet lands the kill
-- (routes through MP networking — never :die() on a client).
-- See csr_damage_amplification_pattern.md.

if not (_G.CSR and _G.CSR.register_item) then
	return
end

local CHANCE = 0.10
local COOLDOWN = 1.5

-- Full-boss enemies are immune to the instakill (fought normally instead).
-- biker_boss=The Biker Heist d2, deep_boss=Crude Awakening, triad_boss=Mountain Master;
-- hector/chavez/mobster/drug_lord = their respective heist bosses; captain=Captain Winters (any heist).
local BOSS_TWEAKS = {
	biker_boss = true,
	deep_boss = true,
	triad_boss = true,
	triad_boss_no_armor = true,
	hector_boss = true,
	hector_boss_no_armor = true,
	chavez_boss = true,
	mobster_boss = true,
	drug_lord_boss = true,
	drug_lord_boss_stealth = true,
	captain = true,
}

local last_roll = nil

local function bonnie_try_proc(cop, attack_data)
	local mgr = managers and managers.csr
	if not mgr or not mgr.in_csr_heist or not mgr:in_csr_heist() then
		return false
	end
	local au = attack_data and attack_data.attacker_unit
	if not au or not au:base() or au:base().is_local_player ~= true then
		return false
	end
	if not cop._unit or not alive(cop._unit) or cop._dead or cop._converted then
		return false
	end
	-- Civilians, npc_*, and full-boss enemies are excluded.
	local base = cop._unit:base()
	local tweak_table = (base and base._tweak_table) or ""
	local is_npc = type(tweak_table) == "string" and tweak_table:sub(1, 4) == "npc_"
	if CopDamage.is_civilian(tweak_table) or is_npc or BOSS_TWEAKS[tweak_table] then
		return false
	end
	local stacks = mgr:owned("bonnie_chip")
	if stacks <= 0 then
		return false
	end
	local game = TimerManager and TimerManager:game()
	local now = game and game:time()
	if not now then
		return false
	end
	if last_roll and now - last_roll < COOLDOWN then
		return false
	end
	-- Arm cooldown on every eligible attempt (win OR lose) so high-RPM weapons can't spam rolls.
	last_roll = now
	local total_chance = 1 - (1 - CHANCE) ^ stacks
	if math.random() > total_chance then
		return false
	end
	-- Exceed current health; vanilla clamps applied damage internally.
	attack_data.damage = (cop._health or 1) * 10
	if mgr:debug_enabled() then
		mgr:debug_log("bonnie_chip INSTAKILL proc")
	end
	return true
end

-- 2D flat playback to the local killer only (positional 3D never worked reliably).
-- Proc is gated to the local player, so this only fires for whoever landed the kill.
local function bonnie_play_kill_sound()
	if _G.CSR and _G.CSR.play_sound then
		_G.CSR.play_sound("bonnie_chip", { volume = 0.5 })
	end
end

_G.CSR.register_item({
	type = "bonnie_chip",
	rarity = "rare",
	name = "csr_logbook_bonnie_chip_name",
	desc = "csr_item_bonnie_chip_desc",
	full_desc = "csr_logbook_bonnie_chip_effect",
	notes = "csr_logbook_bonnie_chip_notes",
	icon = "csr_bonnie_chip",
	icon_scale = 1.05,
	loc_macros = {
		chance_pct = string.format("%g", CHANCE * 100),
		cooldown = COOLDOWN,
	},

	hooks = {
		["lib/units/enemies/cop/copdamage"] = function()
			if _G._CSR_BONNIE_CHIP_HOOKED then
				return
			end
			_G._CSR_BONNIE_CHIP_HOOKED = true

			-- PreHook flags + amplifies; PostHook plays the sound after vanilla confirms the kill.
			Hooks:PreHook(CopDamage, "damage_bullet", "CSR_BonnieChip_Pre", function(cop, attack_data)
				if bonnie_try_proc(cop, attack_data) then
					cop._csr_chip_proc = true
				end
			end)
			Hooks:PostHook(CopDamage, "damage_bullet", "CSR_BonnieChip_Post", function(cop, attack_data)
				if cop._csr_chip_proc and cop._dead then
					bonnie_play_kill_sound()
				end
				cop._csr_chip_proc = nil
			end)
		end,
	},
})

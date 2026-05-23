-- Bonnie's Lucky Chip (rare) -- each bullet hit has a small chance to instakill.
--
-- Per-item-file model (see cup_of_joe.lua). Text fields are localization keys.
--
-- PreHook on CopDamage:damage_bullet: against a valid enemy, off cooldown, roll
-- 1-(1-chance)^stacks; on a win, AMPLIFY the attack's damage so the ORIGINAL
-- damage_bullet lands the kill itself. That routes the death through vanilla MP
-- networking (a client RPCs the host, the host syncs the death back); a local
-- self:die() on a client would desync. The cooldown is armed on EVERY eligible
-- attempt (win or lose) so high-RPM weapons can't spam rolls.
--
-- On a confirmed proc-kill the dead enemy's position plays a chip clip and the
-- position is broadcast so nearby peers hear it. Values mirror the 6.2 register
-- line (chance 0.10 / cooldown 1.5).

if not (_G.CSR and _G.CSR.register_item) then
	return
end

local CHANCE = 0.10
local COOLDOWN = 1.5
local BONNIE_CHIP_RPC = "CSR_ChipKill"

-- Single-item cooldown timestamp (game time of the last roll attempt).
local last_roll = nil

local function bonnie_try_proc(cop, attack_data)
	local mgr = managers and managers.csr
	if not mgr or not mgr.is_run_active or not mgr:is_run_active() then
		return false
	end
	local au = attack_data and attack_data.attacker_unit
	if not au or not au:base() or au:base().is_local_player ~= true then
		return false
	end
	-- Target must be a live, non-converted enemy.
	if not cop._unit or not alive(cop._unit) or cop._dead or cop._converted then
		return false
	end
	-- Skip civilians and scripted NPCs (npc_*) -- instakill is enemy-only.
	local base = cop._unit:base()
	local tweak_table = (base and base._tweak_table) or ""
	local is_npc = type(tweak_table) == "string" and tweak_table:sub(1, 4) == "npc_"
	if CopDamage.is_civilian(tweak_table) or is_npc then
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
	last_roll = now -- arm on every eligible attempt
	local total_chance = 1 - (1 - CHANCE) ^ stacks
	if math.random() > total_chance then
		return false
	end
	-- Amplify so the original damage_bullet kills the enemy (vanilla clamps the
	-- applied damage to self._health internally, so just exceed current health).
	attack_data.damage = (cop._health or 1) * 10
	if mgr:debug_enabled() then
		mgr:debug_log("bonnie_chip INSTAKILL proc")
	end
	return true
end

local function bonnie_play_chip_at(pos)
	if pos and _G.CSR and _G.CSR.play_sound then
		_G.CSR.play_sound("bonnie_chip", { position = pos, volume = 0.7 })
	end
end

local function bonnie_play_kill_sound(dead_unit)
	if not (dead_unit and alive(dead_unit)) then
		return
	end
	local pos = dead_unit:position()
	bonnie_play_chip_at(pos)
	-- Broadcast the spot so other peers hear the kill. GetNumberOfPeers gates out
	-- the solo case (no peers -> skip the work + log entirely).
	if LuaNetworking and LuaNetworking.GetNumberOfPeers and LuaNetworking:GetNumberOfPeers() > 0 then
		local payload = string.format("%.2f,%.2f,%.2f", pos.x, pos.y, pos.z)
		pcall(function()
			LuaNetworking:SendToPeers(BONNIE_CHIP_RPC, payload)
		end)
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

	hooks = {
		["lib/units/enemies/cop/copdamage"] = function()
			if _G._CSR_BONNIE_CHIP_HOOKED then
				return
			end
			_G._CSR_BONNIE_CHIP_HOOKED = true

			-- PreHook flags the proc (and amplifies damage); PostHook plays the
			-- sound only once vanilla has confirmed the kill landed (cop._dead).
			Hooks:PreHook(CopDamage, "damage_bullet", "CSR_BonnieChip_Pre", function(cop, attack_data)
				if bonnie_try_proc(cop, attack_data) then
					cop._csr_chip_proc = true
				end
			end)
			Hooks:PostHook(CopDamage, "damage_bullet", "CSR_BonnieChip_Post", function(cop, attack_data)
				if cop._csr_chip_proc and cop._dead then
					bonnie_play_kill_sound(cop._unit)
				end
				cop._csr_chip_proc = nil
			end)

			-- A peer's broadcast chip-kill: play it locally at the sent position.
			Hooks:Add("NetworkReceivedData", "CSR_BonnieChip_NetKill", function(sender, id, data)
				if id ~= BONNIE_CHIP_RPC then
					return
				end
				local x, y, z = tostring(data):match("([^,]+),([^,]+),([^,]+)")
				x, y, z = tonumber(x), tonumber(y), tonumber(z)
				if x and y and z then
					bonnie_play_chip_at(Vector3(x, y, z))
				end
			end)
		end,
	},
})

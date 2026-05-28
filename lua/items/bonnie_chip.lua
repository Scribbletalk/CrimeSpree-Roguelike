-- Bonnie's Lucky Chip (rare) — each bullet hit has a small chance to instakill.
-- Amplification pattern: amplify damage so vanilla damage_bullet lands the kill
-- (routes through MP networking — never :die() on a client).
-- See csr_damage_amplification_pattern.md.

if not (_G.CSR and _G.CSR.register_item) then
	return
end

local CHANCE = 0.10
local COOLDOWN = 1.5
local BONNIE_CHIP_RPC = "CSR_ChipKill"

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
	if not cop._unit or not alive(cop._unit) or cop._dead or cop._converted then
		return false
	end
	-- Civilians and npc_* are excluded.
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
	-- Broadcast the kill spot so other peers hear it too.
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
	icon_scale = 1.05,

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
					bonnie_play_kill_sound(cop._unit)
				end
				cop._csr_chip_proc = nil
			end)

			-- Peer's broadcast chip-kill — play locally at the sent position.
			if _G.CSR_MP and _G.CSR_MP.register_handler then
				_G.CSR_MP.register_handler(BONNIE_CHIP_RPC, function(sender, data)
					local x, y, z = tostring(data):match("([^,]+),([^,]+),([^,]+)")
					x, y, z = tonumber(x), tonumber(y), tonumber(z)
					if x and y and z then
						bonnie_play_chip_at(Vector3(x, y, z))
					end
				end)
			end
		end,
	},
})

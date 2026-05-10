-- FAMILIAR FRIEND - Wildcard active item
-- "Spike Nova": on key press, deal a 360° AoE around the player.
-- Carry-1 wildcard. Activation gated by cooldown; SFX/VFX wired but empty
-- until assets ship (TODO marker below). Stealth-blocked.

if not RequiredScript then
	return
end

ModifierFamiliarFriend = ModifierFamiliarFriend or class(CSRBaseModifier)
ModifierFamiliarFriend.desc_id = "csr_familiar_friend_desc"
ModifierFamiliarFriend.icon = "csr_familiar_friend"

local C = _G.CSR_ItemConstants or {}
local function const(key, default)
	-- Re-read each call so live tweaks via base_modifier.lua reload pick up.
	local t = _G.CSR_ItemConstants or {}
	if t[key] ~= nil then
		return t[key]
	end
	return default
end

local math_up = math.UP or Vector3(0, 0, 1)

-- Per-player cooldown end timestamp. Resets on spawn / new heist via spawned_player.
_G.CSR_FamiliarFriend = _G.CSR_FamiliarFriend or {
	cooldown_end = 0,
}

local function fire_hud_buff_event(name, duration)
	if CSR_VHUDPlusEvent then
		pcall(CSR_VHUDPlusEvent, "timed_buff", "activate", name, {
			t = TimerManager:game():time(),
			duration = duration,
		})
	end
	if CSR_WFHudEvent then
		pcall(CSR_WFHudEvent, "activate", name, { duration = duration })
	end
	if CSR_PocoHudEvent then
		pcall(CSR_PocoHudEvent, "activate", name, { duration = duration })
	end
end

local function pos_dist(p1, p2)
	local dx = p1.x - p2.x
	local dy = p1.y - p2.y
	local dz = p1.z - p2.z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function has_line_of_sight(geometry_mask, from_pos, to_pos)
	if not geometry_mask then
		return true
	end
	local blocked = false
	pcall(function()
		blocked = World:raycast("ray", from_pos, to_pos, "slot_mask", geometry_mask) ~= nil
	end)
	return not blocked
end

-- Mirrors deadmanstrigger's fake col_ray (vanilla damage_bullet dereferences body).
local function make_fake_col_ray(unit)
	local pos = Vector3(0, 0, 0)
	if unit:movement() and unit:movement().m_pos then
		mvector3.set(pos, unit:movement():m_pos())
	elseif unit:position() then
		mvector3.set(pos, unit:position())
	end
	local body = unit:body(0)
	return {
		ray = Vector3(0, 0, -1),
		position = pos,
		normal = math_up,
		unit = unit,
		distance = 0,
		body = body,
	}
end

-- Apply the actual Spike Nova damage. Called after the charge wind-up.
-- Re-validates state because the player may have died/cuffed/left whisper mode
-- during the 0.6s wind-up.
local function fire_spike_nova(player_unit)
	if not alive(player_unit) then
		return
	end
	-- Stealth gate (re-check): whisper might have re-engaged during charge.
	if managers.groupai and managers.groupai:state() and managers.groupai:state():whisper_mode() then
		return
	end
	local cdmg_self = player_unit:character_damage()
	if cdmg_self then
		if cdmg_self.dead and cdmg_self:dead() then
			return
		end
		if cdmg_self.bleed_out and cdmg_self:bleed_out() then
			return
		end
		if cdmg_self.arrested and cdmg_self:arrested() then
			return
		end
	end

	local move = player_unit:movement()
	if not move then
		return
	end
	local player_pos = move:m_pos()

	local radius = const("familiar_friend_radius", 600)
	local base_damage = const("familiar_friend_damage", 2000)
	local level_pct = const("familiar_friend_level_pct", 0.0035)
	local cs_level = (managers.crime_spree and managers.crime_spree:spree_level()) or 0
	-- Display HP units → internal units (×5). Additive linear rank scaling
	-- (mirrors how vanilla enemy HP scales): base * (1 + rank * pct).
	local max_damage = base_damage * (1 + cs_level * level_pct) * 5

	-- Attack SFX (random pick from gup_attack_1..5), 3D-attached to the player.
	if _G.CSR_PlaySound then
		pcall(_G.CSR_PlaySound, "gup_attack", { unit = player_unit })
	end

	-- TODO: VFX — placeholder. Once a particle effect ships, fire it here.

	local weapon_unit = nil
	pcall(function()
		weapon_unit = player_unit:inventory():equipped_unit()
	end)

	local attacker_pos = Vector3(0, 0, 0)
	pcall(function()
		mvector3.set(attacker_pos, player_pos)
	end)

	local geometry_mask = nil
	pcall(function()
		geometry_mask = managers.slot:get_mask("world_geometry")
	end)
	local player_check_pos = player_pos + Vector3(0, 0, 80)

	local enemy_mask = managers.slot:get_mask("enemies")
	local enemies = World:find_units_quick("sphere", player_pos, radius, enemy_mask)

	for _, unit in ipairs(enemies) do
		if alive(unit) and unit:movement() then
			local cdmg = unit:character_damage()
			if cdmg and not cdmg:dead() then
				local unit_pos = unit:movement():m_pos() + Vector3(0, 0, 80)
				if has_line_of_sight(geometry_mask, player_check_pos, unit_pos) then
					local dist = pos_dist(player_pos, unit:movement():m_pos())
					local falloff = math.max(0, 1 - dist / radius)
					local dmg = max_damage * falloff
					if dmg > 0 then
						local was_dead = cdmg:dead()
						local col_ray = make_fake_col_ray(unit)
						if col_ray.body then
							local ok = pcall(function()
								cdmg:damage_bullet({
									damage = dmg,
									attacker_unit = player_unit,
									weapon_unit = weapon_unit,
									variant = "bullet",
									col_ray = col_ray,
									origin = attacker_pos,
								})
							end)
							-- Same zombie-enemy guard as DMT: if pcall failed after die() but
							-- before _on_damage_received, force the death event.
							if not ok and not was_dead and alive(unit) and cdmg._dead then
								pcall(function()
									cdmg:_on_damage_received({
										attacker_unit = player_unit,
										variant = "bullet",
										result = { type = "death", variant = "bullet" },
									})
								end)
							end
						end
					end
				end
			end
		end
	end
end

-- Cooldown-ready chime. Fired by DelayedCalls when the cooldown finishes.
-- Suppressed if the player has left the heist or no longer owns the item.
local function play_cooldown_ready()
	if not _G.CSR_PlaySound then
		return
	end
	if not (managers and managers.crime_spree and managers.crime_spree:is_active()) then
		return
	end
	-- End-screen: is_active() stays true through victoryscreen/gameoverscreen.
	if game_state_machine then
		local state = game_state_machine:current_state_name()
		if state == "victoryscreen" or state == "gameoverscreen" then
			return
		end
	end
	if not _G.CSR_CountStacks or CSR_CountStacks("player_familiar_friend_") <= 0 then
		return
	end
	-- 2D so the player always hears it regardless of camera position.
	pcall(_G.CSR_PlaySound, "gup_cooldown")
end

local function activate_spike_nova(player_unit)
	-- Stealth gate: detonating during whisper would instantly break it.
	if managers.groupai and managers.groupai:state() and managers.groupai:state():whisper_mode() then
		return
	end

	-- Cooldown gate.
	local now = TimerManager:game():time()
	if now < (_G.CSR_FamiliarFriend.cooldown_end or 0) then
		return
	end

	if not player_unit:movement() then
		return
	end

	local cooldown = const("familiar_friend_cooldown", 60)
	local charge_delay = const("familiar_friend_charge_delay", 0.6)

	_G.CSR_FamiliarFriend.cooldown_end = now + cooldown
	fire_hud_buff_event("csr_familiar_friend_cd", cooldown)

	-- Charge SFX plays immediately on key press as the wind-up. The actual
	-- nova fires after `charge_delay` seconds to match the audio.
	if _G.CSR_PlaySound then
		pcall(_G.CSR_PlaySound, "gup_charge", { unit = player_unit })
	end

	DelayedCalls:Add("CSR_FamiliarFriend_Fire", charge_delay, function()
		fire_spike_nova(player_unit)
	end)

	-- Schedule the cooldown-ready chime to match the cooldown end timestamp.
	DelayedCalls:Add("CSR_FamiliarFriend_CooldownReady", cooldown, play_cooldown_ready)
end

if PlayerManager and not _G._CSR_FAMILIAR_FRIEND_HOOKED then
	_G._CSR_FAMILIAR_FRIEND_HOOKED = true

	-- Reset cooldown on spawn (per-heist).
	Hooks:PostHook(PlayerManager, "spawned_player", "CSR_FamiliarFriendInit", function(self)
		_G.CSR_FamiliarFriend.cooldown_end = 0
	end)

	-- Register with the wildcard dispatcher. Guarded so reloads don't re-register.
	if _G.CSR_RegisterWildcardActive then
		_G.CSR_RegisterWildcardActive("player_familiar_friend_", activate_spike_nova)
	end
end

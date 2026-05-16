-- Bonnie's Lucky Chip - Instant Kill Mechanic
-- Chance to instantly kill an enemy on hit

if not RequiredScript then
	return
end

-- Sound buffers are loaded centrally by lua/core/sound_preloader.lua
-- and played via _G.CSR_PlaySound below.

-- ==========================================
-- INSTAKILL MECHANIC
-- ==========================================

-- Read constants per-call so debug-menu retuning takes effect without a game
-- restart, matching the pattern in dearestpossession.lua / deadmanstrigger.lua /
-- equalizer.lua / plush_shark_guardian.lua. Caching at file-load was a bug:
-- if this file ever loads before base_modifier.lua defines _G.CSR_ItemConstants
-- (load-order-dependent), the fallbacks would bake in permanently.
local last_instakill_time = 0

-- Count Bonnie's Lucky Chip stacks
local function count_bonnie_chips()
	return CSR_CountStacks("player_bonnie_chip_")
end

-- Clean up stale UnitSource from previous heist so stop()/close() on a dead unit
-- doesn't produce an audio glitch at the start of heist 2+.
Hooks:PostHook(PlayerDamage, "init", "CSR_BonnieChip_CleanupSound", function(self)
	if _G._csr_chip_sound_source then
		pcall(function()
			if not _G._csr_chip_sound_source:is_closed() then
				_G._csr_chip_sound_source:stop()
				_G._csr_chip_sound_source:close()
			end
		end)
		_G._csr_chip_sound_source = nil
	end
end)

-- PreHook: roll instakill, amplify attack_data.damage so vanilla damage_bullet
-- handles the kill. Previous PostHook called self:die() locally on clients,
-- but the host's master copy never knew, leaving the enemy alive everywhere
-- except the proccing client. Amplifying damage in a PreHook lets the kill
-- flow through vanilla networking (client RPCs the host, host syncs the death
-- back to all peers).
local function bonnie_chip_try_proc(self, attack_data)
	if not managers.crime_spree or not managers.crime_spree:is_active() then
		return false
	end
	if not attack_data or not attack_data.attacker_unit or not attack_data.attacker_unit:base() then
		return false
	end
	if not attack_data.attacker_unit:base().is_local_player then
		return false
	end

	local chip_count = count_bonnie_chips()
	if chip_count == 0 then
		return false
	end

	if not self._unit or not alive(self._unit) or self._dead then
		return false
	end
	if self._converted then
		return false
	end

	local tweak_table = self._unit:base() and self._unit:base()._tweak_table or ""
	local is_npc = type(tweak_table) == "string" and tweak_table:sub(1, 4) == "npc_"
	if CopDamage.is_civilian(tweak_table) or is_npc then
		return false
	end

	local C = _G.CSR_ItemConstants or {}
	local chance = C.bonnie_chip_chance or 0.10
	local cooldown = C.bonnie_chip_cooldown or 1.5

	local current_time = TimerManager:game():time()
	if current_time - last_instakill_time < cooldown then
		return false
	end

	-- Start cooldown on EVERY attempt — prevents minigun spam
	last_instakill_time = current_time

	if CSR_VHUDPlusEvent then
		CSR_VHUDPlusEvent("timed_buff", "activate", "csr_bonnie_chip_cd", {
			t = current_time,
			duration = cooldown,
		})
	end
	if CSR_WFHudEvent then
		CSR_WFHudEvent("activate", "bonnie_chip_cd", { duration = cooldown })
	end
	if CSR_PocoHudEvent then
		CSR_PocoHudEvent("activate", "bonnie_chip_cd", { duration = cooldown })
	end

	-- Roll: 1 - (1 - chance)^stacks (independent rolls per chip)
	local total_chance = 1 - math.pow(1 - chance, chip_count)
	if math.random() > total_chance then
		return false
	end

	-- Amplify damage so the original damage_bullet kills the enemy.
	-- Vanilla clamps damage to self._health internally.
	attack_data.damage = (self._health or 1) * 10
	return true
end

local function bonnie_chip_play_kill_sound(dead_unit, attack_data)
	if not _G.CSR_PlaySound then
		return
	end
	local player_unit = attack_data and attack_data.attacker_unit
	if not (player_unit and alive(player_unit)) then
		return
	end
	if not (dead_unit and alive(dead_unit)) then
		return
	end
	-- Position-based source at the dead enemy's body. Manual quadratic
	-- attenuation via falloff_max_distance — silent at 30 m and beyond,
	-- full volume at the source. (SuperBLT's XAudio set_min/max_distance
	-- API is a no-op in the current C++ build — verified 2026-05-13 with
	-- diagnostic logging on chip kills at 8.79-37.46 m, sound played at
	-- full volume regardless of min_distance value.) Source position still
	-- provides stereo panning via OpenAL even without distance attenuation.
	-- cleanup_old kills the prior proc's source — fixes back-to-back
	-- minigun proc layering.
	local pos = dead_unit:position()
	local user_vol = (_G.CSR_Settings and _G.CSR_Settings.values and _G.CSR_Settings.values.bonnie_chip_sound_volume)
		or 1.0

	_G._csr_chip_sound_source = _G.CSR_PlaySound("bonnie_chip", {
		position = pos,
		falloff_db_per_meter = 1,
		volume = user_vol * 0.75,
		cleanup_old = _G._csr_chip_sound_source,
	})

	-- MP sync: broadcast position so other peers hear the chip kill at the
	-- same spot. Each receiver picks its own random variant locally.
	if LuaNetworking and _G.CSR_MP and CSR_MP.is_mp_session and CSR_MP.MSG and CSR_MP.MSG.CHIP_KILL then
		local payload = string.format("%.2f,%.2f,%.2f", pos.x, pos.y, pos.z)
		pcall(function()
			LuaNetworking:SendToPeers(CSR_MP.MSG.CHIP_KILL, payload)
		end)
	end
end

Hooks:PreHook(CopDamage, "damage_bullet", "CSR_BonnieChip_Pre", function(self, attack_data)
	if bonnie_chip_try_proc(self, attack_data) then
		self._csr_chip_proc = attack_data
	end
end)

Hooks:PostHook(CopDamage, "damage_bullet", "CSR_BonnieChip_Post", function(self, attack_data)
	if self._csr_chip_proc and self._dead then
		bonnie_chip_play_kill_sound(self._unit, self._csr_chip_proc)
	end
	self._csr_chip_proc = nil
end)

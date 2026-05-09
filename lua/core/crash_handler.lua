-- Crime Spree Roguelike - General Crash Handler
-- Wraps unsafe spawn functions with pcall protection.
-- Reports the likely source mod in chat when a crash is prevented.
--
-- NOTE: This file is hooked at TWO points in mod.txt:
--   1. lib/setups/setup           -> wraps safe_spawn_unit (global function)
--   2. lib/managers/missionmanager -> wraps ElementSpawnEnemyDummy:on_executed
--                                    AND ElementSpawnEnemyDummy:produce
-- Each section is guarded so it only runs once and only when the target exists.
--
-- Direct function override is used intentionally — Hooks:PostHook cannot
-- prevent execution of the original function, which is required for crash prevention.

-- Parse debug.traceback() to find which mod triggered the crash
local function get_source_mod(tb)
	if not tb then
		return "unknown"
	end
	for line in tb:gmatch("[^\n]+") do
		local mod_name = line:match("mods/([^/]+)/")
		if
			mod_name
			and mod_name ~= "CrimeSpree-Roguelike"
			and mod_name ~= "base"
			and mod_name ~= "logs"
			and mod_name ~= "saves"
		then
			return mod_name
		end
	end
	return "unknown"
end

-- Show a warning in game chat (each unique message only once per heist)
_G.CSR_CrashWarnShown = _G.CSR_CrashWarnShown or {}

local function chat_warn(message)
	if _G.CSR_CrashWarnShown[message] then
		return
	end
	_G.CSR_CrashWarnShown[message] = true

	DelayedCalls:Add("CSR_CrashHandler_" .. tostring(math.random(100000)), 0.5, function()
		if managers and managers.chat then
			managers.chat:_receive_message(1, "[CSR]", message, tweak_data.system_chat_color)
		end
	end)
end

-- Reset shown warnings each heist (this file re-runs on lib/setups/setup)
_G.CSR_CrashWarnShown = {}

---------------------------------------------------------------------------
-- Part 1: safe_spawn_unit guard (global function, available after lib/setups/setup)
-- Prevents crash when a mod tries to spawn a unit that isn't loaded.
---------------------------------------------------------------------------
if safe_spawn_unit and not _G.CSR_SpawnGuardInstalled then
	_G.CSR_SpawnGuardInstalled = true
	local _orig_safe_spawn = safe_spawn_unit

	function safe_spawn_unit(unit_name, ...)
		if not unit_name then
			return _orig_safe_spawn(unit_name, ...)
		end

		local ok, unit_ids = pcall(function()
			return unit_name:id()
		end)
		if not ok or not unit_ids then
			return _orig_safe_spawn(unit_name, ...)
		end

		if not PackageManager:has(Idstring("unit"), unit_ids) then
			local name_str = tostring(unit_name) or "unknown"
			local source = get_source_mod(debug.traceback())
			log("[CSR/CrashHandler] Blocked spawn of unloaded unit: " .. name_str .. " (source: " .. source .. ")")
			chat_warn("Prevented crash: unloaded unit — mod: " .. source)
			return nil
		end

		return _orig_safe_spawn(unit_name, ...)
	end
end

---------------------------------------------------------------------------
-- Part 2: ElementSpawnEnemyDummy guard (available after lib/managers/missionmanager)
-- Wraps produce() in pcall so a nil-unit result doesn't crash the game.
---------------------------------------------------------------------------
if ElementSpawnEnemyDummy and not _G.CSR_ProduceGuardInstalled then
	_G.CSR_ProduceGuardInstalled = true
	local _orig_on_executed = ElementSpawnEnemyDummy.on_executed

	function ElementSpawnEnemyDummy:on_executed(instigator)
		if not self._values.enabled then
			return
		end

		if not managers.groupai:state():is_AI_enabled() and not Application:editor() then
			return
		end

		local ok, unit = pcall(self.produce, self)

		if not ok then
			local source = get_source_mod(debug.traceback())
			log("[CSR/CrashHandler] produce() error: " .. tostring(unit) .. " (source: " .. source .. ")")
			chat_warn("Prevented crash in enemy spawn — mod: " .. source)
			return
		end

		if not unit then
			log("[CSR/CrashHandler] produce() returned nil — spawn skipped")
			return
		end

		ElementSpawnEnemyDummy.super.on_executed(self, unit)
	end
end

---------------------------------------------------------------------------
-- Part 3: ElementSpawnEnemyDummy:produce guard
-- Some mods (e.g. LIES MWS) call produce() directly instead of going
-- through on_executed(). If safe_spawn_unit returns nil (blocked by Part 1
-- or by vanilla), produce() will crash on unit:brain(). Wrap in pcall.
---------------------------------------------------------------------------
if ElementSpawnEnemyDummy and not _G.CSR_ProduceDirectGuardInstalled then
	_G.CSR_ProduceDirectGuardInstalled = true
	local _orig_produce = ElementSpawnEnemyDummy.produce

	function ElementSpawnEnemyDummy:produce(params)
		local ok, result = pcall(_orig_produce, self, params)

		if not ok then
			local source = get_source_mod(debug.traceback())
			log("[CSR/CrashHandler] produce() crashed: " .. tostring(result) .. " (source: " .. source .. ")")
			chat_warn("Prevented crash in produce() — mod: " .. source)
			return nil
		end

		return result
	end
end

---------------------------------------------------------------------------
-- Part 4: CopLogicAttack._upd_aim guard
-- LIES MWS overrides _upd_aim and at line 938 dereferences
-- focus_enemy.nav_tracker:nav_segment(). When the tracked enemy unit has
-- been freed, nav_tracker is a dangling userdata pointer → engine access
-- violation (crash_report_2026_04_12_10_10.txt).
--
-- Pre-validate that data.unit and the focus enemy unit are still alive.
-- If the enemy is gone, clear the stale attention_obj and skip this frame
-- — the cop will re-acquire a target next tick. Final pcall is a fallback
-- for Lua errors (cannot catch C-side access violations, but covers any
-- nil dereference before the engine call happens).
---------------------------------------------------------------------------
-- Re-wraps on every hook invocation if our wrapper has been clobbered by
-- another mod (identity check on _G.CSR_UpdAimGuardFn). LIES MWS replaces
-- CopLogicAttack._upd_aim entirely, so a one-shot wrap would be lost.
if CopLogicAttack and CopLogicAttack._upd_aim and CopLogicAttack._upd_aim ~= _G.CSR_UpdAimGuardFn then
	local _orig_upd_aim = CopLogicAttack._upd_aim

	local function guarded_upd_aim(data, my_data)
		if not data or not data.unit or not alive(data.unit) then
			return
		end

		local focus = my_data and my_data.attention_obj
		if focus and focus.unit and not alive(focus.unit) then
			my_data.attention_obj = nil
			return
		end

		local ok, err = pcall(_orig_upd_aim, data, my_data)
		if not ok then
			local source = get_source_mod(debug.traceback())
			log("[CSR/CrashHandler] _upd_aim error: " .. tostring(err) .. " (source: " .. source .. ")")
			chat_warn("Prevented crash in _upd_aim — mod: " .. source)
		end
	end

	_G.CSR_UpdAimGuardFn = guarded_upd_aim
	CopLogicAttack._upd_aim = guarded_upd_aim
end

---------------------------------------------------------------------------
-- Part 5: CopBrain:set_logic guard
-- LIES MWS's coplogictravel:update() calls CopLogicBase._exit() which in
-- turn calls brain:set_logic(name). If `name` is not a valid logic key,
-- `self._logics[name]` is nil and `logic.enter(...)` crashes at
-- copbrain.lua:542 (crash_report_2026_04_12_10_42.txt).
--
-- Skip the transition if the target logic doesn't exist — the cop stays
-- in its current logic and will re-evaluate next tick.
---------------------------------------------------------------------------
-- Re-wraps on every hook invocation if our wrapper has been clobbered by
-- another mod (identity check on _G.CSR_SetLogicGuardFn). This file is hooked
-- on lib/setups/setup, lib/managers/missionmanager, AND lib/units/enemies/cop/copbrain
-- so the guard is installed whichever file loads CopBrain first.
if CopBrain and CopBrain.set_logic and CopBrain.set_logic ~= _G.CSR_SetLogicGuardFn then
	local _orig_set_logic = CopBrain.set_logic

	local function guarded_set_logic(self, name, enter_params)
		if not self._logics or not self._logics[name] then
			local source = get_source_mod(debug.traceback())
			log(
				"[CSR/CrashHandler] set_logic: unknown logic '"
					.. tostring(name)
					.. "' (source: "
					.. source
					.. ") — skipped"
			)
			chat_warn("Prevented crash: unknown AI logic — mod: " .. source)
			return
		end

		local ok, err = pcall(_orig_set_logic, self, name, enter_params)
		if not ok then
			local source = get_source_mod(debug.traceback())
			log(
				"[CSR/CrashHandler] set_logic error: "
					.. tostring(err)
					.. " (name: "
					.. tostring(name)
					.. ", source: "
					.. source
					.. ")"
			)
			chat_warn("Prevented crash in set_logic — mod: " .. source)
		end
	end

	_G.CSR_SetLogicGuardFn = guarded_set_logic
	CopBrain.set_logic = guarded_set_logic
end

---------------------------------------------------------------------------
-- Part 6: CopBrain:check_upd_aim guard (LIES MWS-injected method)
-- LIES adds CopBrain:check_upd_aim which calls its replacement of
-- CopLogicAttack._upd_aim. When invoked from the team-AI update path
-- (teamaimovement -> copmovement._upd_actions -> LIES copmovement
-- extension -> check_upd_aim -> _upd_aim), a freed focus unit causes an
-- engine access violation at coplogicattack.lua:938
-- (crash_report_2026_04_15_11_22.txt).
--
-- LIES' check_upd_aim calls its OWN internal reference to _upd_aim, so the
-- Part 4 pre-validation never runs on this path. pcall can't catch engine
-- access violations (crash_report_2026_04_15_16_24.txt), so the only way
-- to prevent the crash is to validate the focus enemy BEFORE handing off
-- to LIES. If the attention_obj's unit has been freed, clear it and skip
-- the call — the cop re-acquires a target next tick.
---------------------------------------------------------------------------
if CopBrain and CopBrain.check_upd_aim and CopBrain.check_upd_aim ~= _G.CSR_CheckUpdAimGuardFn then
	local _orig_check_upd_aim = CopBrain.check_upd_aim

	local function guarded_check_upd_aim(self, ...)
		-- Pre-validation: brain itself + its logic_data + its focus enemy
		if not self then
			return
		end
		local data = self._logic_data
		if not data or not data.unit or not alive(data.unit) then
			return
		end
		local my_data = data.internal_data
		if my_data then
			local focus = my_data.attention_obj
			if focus and focus.unit and not alive(focus.unit) then
				my_data.attention_obj = nil
				return
			end
		end

		local ok, err = pcall(_orig_check_upd_aim, self, ...)
		if not ok then
			local source = get_source_mod(debug.traceback())
			log("[CSR/CrashHandler] check_upd_aim error: " .. tostring(err) .. " (source: " .. source .. ")")
			chat_warn("Prevented crash in check_upd_aim — mod: " .. source)
		end
	end

	_G.CSR_CheckUpdAimGuardFn = guarded_check_upd_aim
	CopBrain.check_upd_aim = guarded_check_upd_aim
end

---------------------------------------------------------------------------
-- Part 7: HopLib NameProvider:init guard
-- NameProvider:init iterates `tweak_data.character.weap_ids` with pairs()
-- and does `"_" .. w`, expecting every value to be a string. If any mod
-- stamps a non-string key/value into weap_ids (or the list is otherwise
-- corrupted), HopLib crashes the game on the first damage event
-- (crash_report_2026_04_21_16_40.txt — original cause was CSR itself
-- stamping __CSR_CAPS_SAVED into non-enemy sibling tables; fixed at the
-- source in remove_damage_cap.lua, this guard is defense-in-depth against
-- other mods doing similar pollution).
--
-- Wraps the init in pcall. If it fails, log + warn. NameProvider remains
-- partially initialized (localization lookups return nil/fallback) but
-- the game doesn't crash.
---------------------------------------------------------------------------
if NameProvider and NameProvider.init and not _G.CSR_NameProviderGuardInstalled then
	_G.CSR_NameProviderGuardInstalled = true
	local _orig_np_init = NameProvider.init

	function NameProvider:init(...)
		local ok, err = pcall(_orig_np_init, self, ...)
		if not ok then
			local source = get_source_mod(debug.traceback())
			log("[CSR/CrashHandler] NameProvider:init error: " .. tostring(err) .. " (source: " .. source .. ")")
			chat_warn("Prevented crash in HopLib NameProvider — tweak_data contaminated, source: " .. source)
		end
	end
end

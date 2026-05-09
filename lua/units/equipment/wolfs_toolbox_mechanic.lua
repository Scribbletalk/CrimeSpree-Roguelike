-- Wolf's Toolbox Mechanic - Drill/Saw timer reduction on kills
-- Always triggers (no RNG), different values for normal/special enemies
-- Formula: Normal -0.2s base + -0.1s per stack, Special -1s base + -0.5s per stack
-- Does NOT affect jammed drills

if not RequiredScript then
	return
end

-- === GLOBAL VARIABLES ===
CSR_WolfsToolbox = CSR_WolfsToolbox
	or {
		stacks = 0, -- Number of Wolf's Toolbox stacks
		active_equipment = {}, -- Table of active drills/saws: {unit = {is_active, equipment_type}}
	}

-- === STACK COUNTING ON SPAWN ===
Hooks:PostHook(PlayerManager, "spawned_player", "CSR_WolfsToolboxInit", function(self)
	-- Reset state
	CSR_WolfsToolbox.active_equipment = {}

	-- Check Crime Spree
	if not managers.crime_spree or not managers.crime_spree:is_active() then
		CSR_WolfsToolbox.stacks = 0
		return
	end

	-- Count Wolf's Toolbox stacks
	local toolbox_stacks = CSR_CountStacks("player_wolfs_toolbox_")
	local stacks = toolbox_stacks

	-- Update global variables
	CSR_WolfsToolbox.stacks = stacks

	if stacks > 0 then
	else
	end
end)

-- Saw-based timed interactions (No Mercy teddy-bear saw, apartment saws, etc.).
-- These are InteractionExt timers, not TimerGui devices, so they need a separate path.
local CSR_WOLFS_TOOLBOX_SAW_INTERACTIONS = {
	hospital_saw = true,
	hospital_saw_jammed = true,
	apartment_saw = true,
	apartment_saw_jammed = true,
	secret_stash_saw = true,
	secret_stash_saw_jammed = true,
	gen_pku_saw = true,
	gen_pku_saw_axis = true,
	gen_int_saw = true,
	gen_int_saw_jammed = true,
}

local function get_local_saw_interaction_state()
	local player = managers.player and managers.player:player_unit()
	if not alive(player) then
		return nil
	end
	local movement = player:movement()
	local state = movement and movement:current_state()
	if not state or not state._interact_expire_t then
		return nil
	end
	local params = state._interact_params
	if not params or not params.tweak_data then
		return nil
	end
	if not CSR_WOLFS_TOOLBOX_SAW_INTERACTIONS[params.tweak_data] then
		return nil
	end
	return state
end

local function compute_reduction_seconds(is_special)
	local C = _G.CSR_ItemConstants or {}
	local normal_reduction = (C.wolfs_toolbox_normal_base or 0.2)
		+ ((CSR_WolfsToolbox.stacks - 1) * (C.wolfs_toolbox_normal_extra or 0.1))
	local special_reduction = (C.wolfs_toolbox_special_base or 1.0)
		+ ((CSR_WolfsToolbox.stacks - 1) * (C.wolfs_toolbox_special_extra or 0.5))
	return is_special and special_reduction or normal_reduction
end

function CSR_WolfsToolbox.reduce_local_saw_interaction(is_special)
	local state = get_local_saw_interaction_state()
	if not state then
		return false
	end
	local reduction = compute_reduction_seconds(is_special)
	state._interact_expire_t = math.max(0, state._interact_expire_t - reduction)
	return true
end

-- === KILL TRACKING ===
-- Hook on enemy death (same as bonnie_instakill.lua)
Hooks:PostHook(CopDamage, "die", "CSR_WolfsToolboxKillTracking", function(self, attack_data)
	-- Check if mechanic is active
	if CSR_WolfsToolbox.stacks == 0 then
		return
	end

	-- Check if damage is from player
	if not attack_data or not attack_data.attacker_unit or not attack_data.attacker_unit:base() then
		return
	end

	if not attack_data.attacker_unit:base().is_local_player then
		return
	end

	-- Check if there's active equipment (drill/saw)
	local has_active_equipment = false
	for unit, data in pairs(CSR_WolfsToolbox.active_equipment) do
		if alive(unit) and data.is_active then
			has_active_equipment = true
			break
		end
	end

	local is_doing_saw_interaction = get_local_saw_interaction_state() ~= nil

	if not has_active_equipment and not is_doing_saw_interaction then
		return
	end

	-- === MECHANIC: Always triggers, different values for normal/special ===
	-- Check if enemy is special unit
	local is_special = false
	if self._unit and self._unit:base() then
		local char_tweak = self._char_tweak
		-- Check enemy category (tank, shield, taser, medic, spooc, etc.)
		if char_tweak and char_tweak.priority_shout then
			is_special = true
		end
	end

	-- Saw interactions are locally owned — reduce directly on every peer.
	if is_doing_saw_interaction then
		CSR_WolfsToolbox.reduce_local_saw_interaction(is_special)
	end

	if not has_active_equipment then
		return
	end

	-- Multiplayer client: send kill event to host so it can apply reduction authoritatively.
	-- Drill timers are host-owned; modifying them locally on a client causes desync.
	local is_mp = _G.CSR_MP and CSR_MP.is_multiplayer and CSR_MP.is_multiplayer()
	if is_mp and CSR_MP.is_client and CSR_MP.is_client() then
		LuaNetworking:SendToPeer(1, "CSR_WolfKill", is_special and "1" or "0")
		return
	end

	-- Host or singleplayer: apply reduction directly
	CSR_WolfsToolbox.apply_reduction(is_special)
end)

-- Shared helper: reduce all active drill/saw timers
-- Called both locally (host/SP) and from the network handler (host receiving client kills)
function CSR_WolfsToolbox.apply_reduction(is_special)
	local C = _G.CSR_ItemConstants or {}
	local normal_reduction = (C.wolfs_toolbox_normal_base or 0.2)
		+ ((CSR_WolfsToolbox.stacks - 1) * (C.wolfs_toolbox_normal_extra or 0.1))
	local special_reduction = (C.wolfs_toolbox_special_base or 1.0)
		+ ((CSR_WolfsToolbox.stacks - 1) * (C.wolfs_toolbox_special_extra or 0.5))
	local reduction_seconds = is_special and special_reduction or normal_reduction

	for unit, data in pairs(CSR_WolfsToolbox.active_equipment) do
		if alive(unit) and data.is_active then
			-- Skip jammed drills
			local base = unit:base()
			if base and base._jammed then
				goto continue
			end

			local timer_gui = unit:timer_gui()
			if timer_gui and timer_gui._current_timer and timer_gui._current_timer > 0 then
				timer_gui._current_timer = math.max(0, timer_gui._current_timer - reduction_seconds)
			end

			::continue::
		end
	end
end

-- Host receives kill event from a client: apply timer reduction on behalf of that client
Hooks:Add("NetworkReceivedData", "CSR_WolfsToolboxNetKill", function(sender, id, data)
	if id ~= "CSR_WolfKill" then
		return
	end
	if not (_G.CSR_MP and CSR_MP.is_host and CSR_MP.is_host()) then
		return
	end
	if CSR_WolfsToolbox.stacks == 0 then
		return
	end

	local is_special = (data == "1")
	CSR_WolfsToolbox.apply_reduction(is_special)
end)

-- === TRACKING ACTIVE DRILLS/SAWS ===
-- Hook on TimerGui:_start to register active devices
Hooks:PostHook(TimerGui, "_start", "CSR_WolfsToolboxTimerStart", function(self, timer)
	local unit = self._unit
	if not unit or not alive(unit) then
		return
	end
	local base = unit:base()

	-- Debug trace: fires regardless of stacks so we can verify whether things
	-- like the First World Bank overdrill actually hit TimerGui:_start at all.
	local debug_on = _G.CSR_Settings and _G.CSR_Settings.values and _G.CSR_Settings.values.debug_mode
	if debug_on then
		local name_str = "<unknown>"
		pcall(function()
			name_str = tostring(unit:name())
		end)
		local is_drill_flag = base and base.is_drill or false
		local is_saw_flag = base and base.is_saw or false
		local is_hack_flag = base and base.is_hacking_device or false
		log(
			string.format(
				"[CSR WolfsToolbox] TimerGui:_start | unit=%s | is_drill=%s is_saw=%s is_hacking=%s | timer=%s",
				name_str,
				tostring(is_drill_flag),
				tostring(is_saw_flag),
				tostring(is_hack_flag),
				tostring(timer)
			)
		)
	end

	-- Check if mechanic is active
	if CSR_WolfsToolbox.stacks == 0 then
		return
	end

	-- Check equipment type
	if not base then
		return
	end

	-- Filter only drills and saws (NOT thermite, NOT hacking)
	local is_valid_equipment = false
	local equipment_type = "unknown"

	-- is_drill and is_saw are BOOLEAN properties, NOT functions
	if base.is_drill then
		is_valid_equipment = true
		equipment_type = "drill"
	elseif base.is_saw then
		is_valid_equipment = true
		equipment_type = "saw"
	elseif not base.is_hacking_device and unit:timer_gui() then
		-- Fallback: if unit has a timer but isn't explicitly drill/saw/hacking,
		-- still treat it as valid (catches overdrill and other special drills)
		is_valid_equipment = true
		equipment_type = "drill"
	end

	if debug_on then
		if is_valid_equipment then
			log("[CSR WolfsToolbox] Registered as " .. equipment_type)
		else
			log("[CSR WolfsToolbox] NOT registered (no matching flag / was hacking device)")
		end
	end

	if not is_valid_equipment then
		return
	end

	-- Register as active device
	CSR_WolfsToolbox.active_equipment[unit] = {
		is_active = true,
		equipment_type = equipment_type,
	}
end)

-- Hook on TimerGui:done to remove finished devices
Hooks:PostHook(TimerGui, "done", "CSR_WolfsToolboxTimerDone", function(self)
	local unit = self._unit
	if unit and CSR_WolfsToolbox.active_equipment[unit] then
		local equipment_type = CSR_WolfsToolbox.active_equipment[unit].equipment_type
		CSR_WolfsToolbox.active_equipment[unit] = nil
	end
end)

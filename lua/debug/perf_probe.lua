-- TEMPORARY perf diagnostic v3: catches the real freezes via WALL-CLOCK timing.
-- Game-time dt pauses during native streaming stalls, so v1/v2 missed them. TimerManager:wall()
-- keeps running, so wall_dt reveals the true stall duration. On a stall we log which enemy TYPE
-- first appeared that frame (prime suspect: first-spawn unit streaming from disk).
-- Runs on its own flag (not CSR_DEBUG). Read-only, in-heist only. Remove once cause is found.

if not RequiredScript then
	return
end

if _G._CSR_PERF_PROBE_HOOKED then
	return
end
_G._CSR_PERF_PROBE_HOOKED = true

_G.CSR_PERF = true -- master switch; set false to silence

local STALL_MS = 200 -- wall-clock frame longer than this == a freeze worth attributing
local HB_PERIOD = 5.0 -- heartbeat period (wall seconds)

local wall_prev = nil
local hb_prev = nil
local peak_heap = 0
local seen_types = {} -- tweak_table -> true, dedupes "first time this enemy type appeared"

-- Scan live enemies; return list of types appearing for the first time EVER this frame.
local function new_enemy_types()
	local em = managers and managers.enemy
	if not (em and em.all_enemies) then
		return nil, 0
	end
	local fresh, n = nil, 0
	for _, u_data in pairs(em:all_enemies()) do
		n = n + 1
		local unit = u_data and u_data.unit
		local base = alive(unit) and unit:base()
		local tt = base and base._tweak_table
		if tt and not seen_types[tt] then
			seen_types[tt] = true
			fresh = fresh or {}
			fresh[#fresh + 1] = tt
		end
	end
	return fresh, n
end

Hooks:Add("GameSetupUpdate", "CSR_PerfProbe", function(_t, dt)
	if not _G.CSR_PERF then
		return
	end
	local mgr = managers and managers.csr
	if not (mgr and mgr.in_csr_heist and mgr:in_csr_heist()) then
		return
	end

	local wall = TimerManager:wall():time()
	local wall_dt = wall_prev and (wall - wall_prev) or 0
	wall_prev = wall

	local fresh, enemies = new_enemy_types()
	local heap = collectgarbage("count")
	if heap > peak_heap then
		peak_heap = heap
	end

	if wall_dt * 1000 > STALL_MS then
		local rank = (mgr.host_rank and mgr:host_rank()) or 0
		log(
			string.format(
				"[CSR][PERF] STALL wall=%.0fms game=%.0fms heap=%.1fMB enemies=%d rank=%d new_types={%s}",
				wall_dt * 1000,
				(tonumber(dt) or 0) * 1000,
				heap / 1024,
				enemies,
				rank,
				fresh and table.concat(fresh, ",") or "none"
			)
		)
	end

	if not hb_prev then
		hb_prev = wall
	elseif wall - hb_prev >= HB_PERIOD then
		hb_prev = wall
		local rank = (mgr.host_rank and mgr:host_rank()) or 0
		log(
			string.format(
				"[CSR][PERF] hb heap=%.1fMB peak=%.1fMB enemies=%d types_seen=%d rank=%d",
				heap / 1024,
				peak_heap / 1024,
				enemies,
				(function()
					local c = 0
					for _ in pairs(seen_types) do
						c = c + 1
					end
					return c
				end)(),
				rank
			)
		)
	end
end)

csr_log("[CSR] debug/perf_probe.lua loaded (TEMP freeze diagnostic v3 wall-clock)")

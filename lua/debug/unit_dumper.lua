-- Unit Dumper: logs all units spawned on a map for optimization analysis.
-- Hooks into WorldDefinition:make_unit to capture unit_id, name, and type.
-- Output: mods/saves/unit_dump_<level_id>.txt
--
-- HOW TO USE:
-- 1. Add hook to mod.txt: { "hook_id": "core/lib/utils/dev/tools/coredebugger", "script_path": "lua/debug/unit_dumper.lua" }
--    OR just dofile this from an existing hook
-- 2. Load any heist
-- 3. Check mods/saves/unit_dump_<level_id>.txt
--
-- NOT hooked by default — enable manually when needed.

if not RequiredScript then
	return
end

-- Only run if explicitly enabled
if not _G.CSR_DUMP_UNITS then
	return
end

local _dumped = {}
local _dump_count = 0
local _level_id = "unknown"

-- Hook make_unit to capture every unit created during level load
local orig_make_unit = WorldDefinition.make_unit
function WorldDefinition:make_unit(data, ...)
	local unit_id = data.unit_id
	local unit_name = data.name or "?"

	-- Capture level ID on first call
	if _dump_count == 0 then
		_level_id = Global.level_data and Global.level_data.level_id or "unknown"
	end

	-- Record unit info
	_dump_count = _dump_count + 1
	_dumped[_dump_count] = {
		id = unit_id,
		name = tostring(unit_name),
	}

	return orig_make_unit(self, data, ...)
end

-- Write dump after level finishes loading
Hooks:PostHook(WorldDefinition, "create", "CSR_UnitDump_Write", function(self, layer)
	if layer ~= "all" and layer ~= "statics" then
		return
	end
	if _dump_count == 0 then
		return
	end

	-- Categorize units
	local lights = {}
	local effects = {}
	local shadows = {}
	local props = {}
	local other = {}

	for _, entry in ipairs(_dumped) do
		local name = entry.name:lower()
		if name:find("light") or name:find("lamp") or name:find("neon") or name:find("glow") or name:find("flare") then
			table.insert(lights, entry)
		elseif
			name:find("effect")
			or name:find("particle")
			or name:find("smoke")
			or name:find("fire")
			or name:find("steam")
			or name:find("fog")
			or name:find("rain")
			or name:find("dust")
			or name:find("spark")
		then
			table.insert(effects, entry)
		elseif name:find("shadow") or name:find("occluder") then
			table.insert(shadows, entry)
		elseif
			name:find("prop")
			or name:find("debris")
			or name:find("trash")
			or name:find("decal")
			or name:find("detail")
			or name:find("clutter")
		then
			table.insert(props, entry)
		else
			table.insert(other, entry)
		end
	end

	-- Write to file
	local path = SavePath .. "unit_dump_" .. _level_id .. ".txt"
	local f = io.open(path, "w")
	if not f then
		log("[CSR UnitDumper] Failed to write to " .. path)
		return
	end

	f:write("=== UNIT DUMP: " .. _level_id .. " ===\n")
	f:write("Total units: " .. _dump_count .. "\n")
	f:write(
		"Lights: " .. #lights .. " | Effects: " .. #effects .. " | Props: " .. #props .. " | Other: " .. #other .. "\n"
	)
	f:write("\n")

	-- Write lights first (most impactful for FPS)
	f:write("=== LIGHTS (" .. #lights .. ") ===\n")
	for _, entry in ipairs(lights) do
		f:write(string.format("  [%d] %s\n", entry.id, entry.name))
	end

	f:write("\n=== EFFECTS (" .. #effects .. ") ===\n")
	for _, entry in ipairs(effects) do
		f:write(string.format("  [%d] %s\n", entry.id, entry.name))
	end

	f:write("\n=== PROPS/DEBRIS (" .. #props .. ") ===\n")
	for _, entry in ipairs(props) do
		f:write(string.format("  [%d] %s\n", entry.id, entry.name))
	end

	f:write("\n=== OTHER (" .. #other .. ") ===\n")
	for _, entry in ipairs(other) do
		f:write(string.format("  [%d] %s\n", entry.id, entry.name))
	end

	f:close()
	log("[CSR UnitDumper] Wrote " .. _dump_count .. " units to " .. path)
end)

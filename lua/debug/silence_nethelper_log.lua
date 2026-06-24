-- TEMP: silence SuperBLT's per-packet "[NetworkHelper]" INFO spam during MP testing.
-- Wraps BLT:Log to drop only those lines; everything else passes through.
-- DELETE this file and its mod.txt entries when MP testing is done.

if _G._CSR_SILENCE_NETHELPER then
	return
end

if not (_G.BLT and BLT.Log) then
	return
end

_G._CSR_SILENCE_NETHELPER = true

local orig_log = BLT.Log
function BLT:Log(level, ...)
	local first = ...
	if type(first) == "string" and first:find("[NetworkHelper]", 1, true) == 1 then
		return
	end
	return orig_log(self, level, ...)
end

-- TEMP testing aid: silence SuperBLT's per-packet "[NetworkHelper] <name>: GNAP/CSR_.../..." INFO
-- spam. mods/base req/core/Networking.lua logs EVERY SendToPeers/SendToPeer at LogLevel.INFO; the
-- aloe_leaf AURA_PULSE heartbeat fans one such line per heal tick, flooding the log during MP tests.
-- Wraps BLT:Log to drop ONLY lines prefixed "[NetworkHelper]"; every other log passes through.
-- DELETE this file and its two mod.txt entries when MP testing is done.

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

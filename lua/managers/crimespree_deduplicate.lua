-- Crime Spree Roguelike - Duplicate Modifier Diagnostic
-- Vanilla select_modifier has a broken duplicate check (compares string to table entries).
-- Our code generates unique IDs so duplicates shouldn't happen, but log a warning if they do.

if not RequiredScript then
	return
end

Hooks:PostHook(CrimeSpreeManager, "select_modifier", "CSR_DeduplicateDiag", function(self, modifier_id)
	if not modifier_id or not self._global or not self._global.modifiers then
		return
	end

	-- Count how many times this ID appears
	local count = 0
	for _, mod in ipairs(self._global.modifiers) do
		if mod.id == modifier_id then
			count = count + 1
		end
	end

	if count > 1 then
		log("[CSR Dedup] WARNING: duplicate modifier detected: " .. tostring(modifier_id) .. " (count=" .. count .. ")")
	end
end)

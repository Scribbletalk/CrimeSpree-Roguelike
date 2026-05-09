-- Crime Spree Roguelike - HP/DMG Scaling System
-- Enemies gain bonus HP (+0.3%) and DMG (+0.4%) per Crime Spree level
-- Instead of many small modifiers - one virtual modifier with combined totals

if not RequiredScript then
	return
end

-- Global function to get HP/DMG bonuses based on current level
-- Called from the UI filter and enemy hooks
function CSR_GetTotalHPDamageBonus()
	if not managers.crime_spree or not managers.crime_spree:is_active() then
		return 0, 0
	end

	-- In multiplayer, use host's rank (server_spree_level returns CSR_MP_HostRank for clients)
	local level = managers.crime_spree:server_spree_level() or 0

	local hp_bonus = level * 0.003 -- +0.3% HP per level  (15% per 50 ranks)
	local dmg_bonus = level * 0.004 -- +0.4% DMG per level (20% per 50 ranks)

	-- PRINTER COST (incoming damage): additive to rank bonus, no cap.
	-- Counter is per-local-peer; each client scales its own damage only.
	-- Use CSR_LocalPeerId (handles offline fallback) instead of session:local_peer().
	local C = _G.CSR_ItemConstants or {}
	local per_use = C.printer_damage_taken_per_use or 0.004
	if _G.CSR_PrinterUses then
		local peer_id = (CSR_LocalPeerId and CSR_LocalPeerId()) or 1
		local uses = _G.CSR_PrinterUses[peer_id] or 0
		if uses > 0 then
			dmg_bonus = dmg_bonus + uses * per_use
		end
	end

	return hp_bonus, dmg_bonus
end

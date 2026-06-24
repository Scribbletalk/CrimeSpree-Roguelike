-- CSR lobby integration: host advertises in the Crime Spree browser; client blocks vanilla gamemode flip.
-- See pd2_crime_spree_lobby_attr_dual_effect.md for why crime_spree attr has a dual side-effect.

if not RequiredScript then
	return
end

if _G._CSR_CRIMENET_LOBBY_HOOKED then
	return
end
_G._CSR_CRIMENET_LOBBY_HOOKED = true

Hooks:PostHook(
	CrimeSpreeManager,
	"apply_matchmake_attributes",
	"CSR_AdvertiseLobbyAsCrimeSpree",
	function(self, lobby_attributes)
		if managers.csr and managers.csr:is_active() then
			-- crime_spree>=0 puts the lobby in the Crime Spree browser; value shows as the spree level.
			lobby_attributes.crime_spree = managers.csr:rank()
			-- crime_spree_mission: without it an in-progress server shows "unknown heist" in the browser.
			local mission_id = managers.csr:current_mission()
			if mission_id then
				lobby_attributes.crime_spree_mission = mission_id
			end
			-- csr_mod marker: tells a joining client this is a CSR lobby, not vanilla Crime Spree.
			lobby_attributes.csr_mod = 1
		end
	end
)

-- CLIENT: suppress enable_crime_spree_gamemode() for CSR lobbies so the client stays on STANDARD.
-- Vanilla CS lobbies (no csr_mod) still activate normally.
local _csr_orig_enable_cs_gamemode = CrimeSpreeManager.enable_crime_spree_gamemode
function CrimeSpreeManager:enable_crime_spree_gamemode()
	local mm = managers.network and managers.network.matchmake
	local lobby_data = mm and mm.get_lobby_data and mm:get_lobby_data()
	if lobby_data and lobby_data.csr_mod then
		csr_log("[CSR] crimenet_lobby: CSR lobby join -> staying on standard gamemode (CSR reroute handles it)")
		return
	end
	return _csr_orig_enable_cs_gamemode(self)
end

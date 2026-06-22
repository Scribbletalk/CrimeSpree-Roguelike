-- CSR lobby <-> Crime.Net integration (host advertise + client join guard).
--
-- HOST: CSR runs the STANDARD gamemode, so vanilla apply_matchmake_attributes marks the lobby
-- crime_spree=-1 (shows as a normal job). Override to the CSR rank so the lobby lands in the
-- Crime Spree browser category (browser reads crime_spree>=0), and tag it csr_mod=1 so a joining
-- CSR client can tell a CSR lobby apart from a real vanilla Crime Spree lobby.
-- Host-only by construction: set_attributes only sends the host's own lobby data.
--
-- CLIENT: joining ANY crime_spree>=0 lobby makes vanilla matchmaking call enable_crime_spree_gamemode()
-- (networkmatchmakingsteam.lua:883), flipping the client to the vanilla Crime Spree gamemode -- which
-- breaks CSR (it stays STANDARD and reroutes via the chat tunnel). Suppress that activation for CSR
-- lobbies (csr_mod set) so the client stays on standard and CSR's reroute handles the lobby.

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
			-- crime_spree>=0 categorises the lobby as Crime Spree; value shows as the spree level.
			lobby_attributes.crime_spree = managers.csr:rank()
			-- crime_spree_mission = the picked mission's string id. The Crime.Net browser resolves the
			-- heist NAME from this via managers.crime_spree:get_mission(id) once the host is in-mission
			-- (server state > in_lobby); without it an in-progress CSR server shows "unknown heist".
			-- Mirrors vanilla apply_matchmake_attributes (round-trips as a named key like crime_spree).
			local mission_id = managers.csr:current_mission()
			if mission_id then
				lobby_attributes.crime_spree_mission = mission_id
			end
			-- CSR-lobby marker. Round-trips to the client's get_lobby_data() (same as crime_spree);
			-- lets a joining client distinguish a CSR lobby from a real vanilla Crime Spree lobby.
			lobby_attributes.csr_mod = 1
		end
	end
)

-- CLIENT join guard: keep the client on STANDARD when joining a CSR lobby (csr_mod marker present),
-- so vanilla's join-time enable_crime_spree_gamemode() can't flip it into vanilla Crime Spree.
-- A real vanilla CS lobby (crime_spree>=0 but no csr_mod) still activates normally.
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

-- Force-create CrimeSpreeMissionEndOptions for CSR multiplayer clients.
-- Vanilla returns early because is_active() is false for clients.
-- Must hook on menucomponentmanager (where MenuComponentManager is defined).

if not RequiredScript then
	return
end

Hooks:PostHook(
	MenuComponentManager,
	"create_crime_spree_mission_end_gui",
	"CSR_ForceClientEndScreen",
	function(self, node)
		if self._crime_spree_mission_end then
			return
		end
		if not (_G.CSR_MP and CSR_MP.is_client and CSR_MP.is_client()) then
			return
		end
		if not node or not alive(self._ws) or not alive(self._fullscreen_ws) then
			return
		end

		log("[CSR EndScreen] force-creating component for client")
		self._crime_spree_mission_end = CrimeSpreeMissionEndOptions:new(self._ws, self._fullscreen_ws, node)
		self:register_component("crime_spree_mission_end", self._crime_spree_mission_end, -1)
	end
)

-- Crime Spree Roguelike - HoloUI Compatibility for MissionBriefingGui

if not _G.Holo then
	return
end

-- Ready button reposition: HoloUI hides _ready_tick_box and anchors _ready_button
-- to a fixed bottom-right position (Holo/Hooks/Menu/MissionBriefingGUI.lua:30-47).
-- Our SELECT ITEM text swap in briefing_select_item.lua resizes the button and
-- re-snaps it to the invisible tick_box, leaving it floating mid-screen.
-- briefing_select_item.lua calls this override when present.
function CSR_BriefingReadyButtonReposition(briefing)
	if not briefing or not briefing._ready_button or not alive(briefing._ready_button) then
		return
	end
	if not briefing._panel or not alive(briefing._panel) then
		return
	end
	briefing._ready_button:set_right(briefing._panel:w() - 8)
	local is_skirmish = managers.skirmish and managers.skirmish:is_skirmish()
	briefing._ready_button:set_bottom(briefing._panel:h() + (is_skirmish and 45 or 105))
end

-- Briefing-screen lobby code reposition.
-- MissionBriefingGui:init creates its OWN LobbyCodeMenuComponent at self._lobby_code_text
-- (missionbriefinggui.lua:3828) and places it at (600, 80) during Crime Spree.
-- Under HoloUI the briefing layout shifts and that position overlaps the CSR tab
-- description panel. Move it to top-right, below the Safehouse Raid counter.
if MissionBriefingGui then
	Hooks:PostHook(MissionBriefingGui, "init", "CSR_HoloUI_LobbyCodeReposition", function(self)
		if not self._lobby_code_text then
			return
		end
		local panel = self._lobby_code_text:panel()
		if not panel or not alive(panel) then
			return
		end
		-- Keep vanilla CS x (600), move y up near the top edge of the screen.
		panel:set_top(35)
	end)
end

log("[CSR] HoloUI briefing compat loaded")

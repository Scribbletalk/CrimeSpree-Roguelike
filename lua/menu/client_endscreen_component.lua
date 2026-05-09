-- Crime Spree Roguelike - End screen: host waiting status
-- Client SELECT ITEM / AUTO-FILL / green READY are in ready_system.lua.
-- This file handles host "waiting for others" status on the end screen.

if not RequiredScript then
	return
end

local function CSR_log(msg)
	if _G.CSR_Settings and _G.CSR_Settings.values and _G.CSR_Settings.values.debug_mode then
		log("[CSR EndScreen] " .. tostring(msg))
	end
end

-- Track which peers have finished item selection (host-side)
_G.CSR_PeersItemsDone = _G.CSR_PeersItemsDone or {}

-- Count connected non-host peers and how many have finished selecting
local function csr_peer_count_and_ready()
	local session = managers.network and managers.network:session()
	if not session then
		return 0, 0
	end

	local connected = {}
	for _, peer in pairs(session:peers() or {}) do
		if peer then
			connected[peer:id()] = true
		end
	end

	for pid, _ in pairs(_G.CSR_PeersItemsDone) do
		if not connected[pid] then
			_G.CSR_PeersItemsDone[pid] = nil
		end
	end

	local total = 0
	local ready = 0
	for pid, _ in pairs(connected) do
		total = total + 1
		if _G.CSR_PeersItemsDone[pid] then
			ready = ready + 1
		end
	end

	return total, ready
end

-- Refresh helper
function _G.CSR_RefreshEndScreenComponent()
	local mcm = managers.menu_component
	if not mcm or not mcm._crime_spree_mission_end then
		return
	end
	local node = mcm._crime_spree_mission_end._node
	if not node then
		return
	end
	mcm:close_crime_spree_mission_end_gui(node)
	mcm:create_crime_spree_mission_end_gui(node)
end

-- Network handler: client reports item selection status to host
Hooks:Add("NetworkReceivedData", "CSR_ItemsDoneHandler", function(sender, id, data)
	if id ~= "CSR_ItemsDone" then
		return
	end
	if not (_G.CSR_MP and CSR_MP.is_host and CSR_MP.is_host()) then
		return
	end

	local peer_id = tonumber(sender)
	if not peer_id then
		return
	end

	local done = data == "1"
	_G.CSR_PeersItemsDone[peer_id] = done or nil
	CSR_log("Peer " .. peer_id .. " items_done=" .. tostring(done))

	-- Live-update host status text
	local total, ready = csr_peer_count_and_ready()
	local all_ready = ready >= total and total > 0

	if _G.CSR_HostWaitingText and alive(_G.CSR_HostWaitingText) then
		if all_ready then
			_G.CSR_HostWaitingText:set_text(managers.localization:to_upper_text("csr_all_players_ready"))
			_G.CSR_HostWaitingText:set_color(Color(1, 0.2, 0.8, 0.2))
		else
			_G.CSR_HostWaitingText:set_text(managers.localization:to_upper_text("csr_waiting_for_others"))
			_G.CSR_HostWaitingText:set_color(Color(1, 0.6, 0.6, 0.6))
		end
	end

	if _G.CSR_HostCountText and alive(_G.CSR_HostCountText) then
		local count_str = ready .. "/" .. total .. " " .. managers.localization:to_upper_text("csr_ready")
		_G.CSR_HostCountText:set_text(count_str)
		_G.CSR_HostCountText:set_color(all_ready and Color(1, 0.2, 0.8, 0.2) or Color(1, 0.6, 0.6, 0.6))
	end
end)

----------------------------------------------
-- Host: waiting status above vanilla buttons
----------------------------------------------
Hooks:PostHook(CrimeSpreeMissionEndOptions, "_setup", "CSR_EndScreenSetup", function(self)
	if not (_G.CSR_MP and CSR_MP.is_host and CSR_MP.is_host()) then
		return
	end

	local bp = self._button_panel
	if not bp or not alive(bp) then
		return
	end

	local host_done = MenuCallbackHandler.show_crime_spree_start and MenuCallbackHandler:show_crime_spree_start()
	if not host_done then
		return
	end

	local total, ready = csr_peer_count_and_ready()
	if total <= 0 then
		return
	end

	local top_y = bp:h()
	for _, btn in ipairs(self._buttons or {}) do
		if btn.panel and alive(btn:panel()) then
			top_y = math.min(top_y, btn:panel():y())
		end
	end

	local all_ready = ready >= total
	local med_font = tweak_data.menu.pd2_medium_font
	local med_size = tweak_data.menu.pd2_medium_font_size

	local count_str = ready .. "/" .. total .. " " .. managers.localization:to_upper_text("csr_ready")
	local count_color = all_ready and Color(1, 0.2, 0.8, 0.2) or Color(1, 0.6, 0.6, 0.6)

	local count_text = bp:text({
		text = count_str,
		font = med_font,
		font_size = med_size,
		color = count_color,
		blend_mode = "add",
		align = "right",
		w = bp:w(),
		layer = 1,
	})
	local _, _, cw, ch = count_text:text_rect()
	count_text:set_size(cw, ch)
	count_text:set_right(bp:right())
	count_text:set_bottom(top_y - 16)

	local wait_color = all_ready and Color(1, 0.2, 0.8, 0.2) or Color(1, 0.6, 0.6, 0.6)
	local wait_str = all_ready and managers.localization:to_upper_text("csr_all_players_ready")
		or managers.localization:to_upper_text("csr_waiting_for_others")

	local wait_text = bp:text({
		text = wait_str,
		font = med_font,
		font_size = med_size * 0.85,
		color = wait_color,
		align = "right",
		w = bp:w(),
		layer = 1,
	})
	local _, _, ww, wh = wait_text:text_rect()
	wait_text:set_size(ww, wh)
	wait_text:set_right(bp:right())
	wait_text:set_bottom(count_text:y() - 4)

	_G.CSR_HostWaitingText = wait_text
	_G.CSR_HostCountText = count_text

	CSR_log("host status: " .. ready .. "/" .. total .. " ready")
end)

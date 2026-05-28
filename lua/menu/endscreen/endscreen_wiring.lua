-- Swap vanilla StageEndScreenGui for CSRStageEndScreenGui on CSR heists.
-- HUD-side swap lives in endscreen_hud_wiring.lua (split for load order:
-- HUDManager isn't defined at this hook point — see csr_vanilla_intercepts.md).

if not RequiredScript then
	return
end

local function csr_endscreen_active()
	if not managers or not managers.job then
		return false
	end
	if managers.job:current_job_id() ~= "crime_spree" then
		return false
	end
	if managers.crime_spree and managers.crime_spree:is_active() then
		return false
	end
	return true
end

Hooks:OverrideFunction(MenuComponentManager, "create_stage_endscreen_gui", function(self)
	if not self._stage_endscreen_gui then
		-- Guest case: clients lose current_job == "crime_spree" earlier than host;
		-- is_guesting() (host_seed) is the reliable signal there.
		local is_csr = csr_endscreen_active()
			or (managers.csr and managers.csr.is_guesting and managers.csr:is_guesting())
		if is_csr and CSRStageEndScreenGui then
			self._stage_endscreen_gui = CSRStageEndScreenGui:new(self._ws, self._fullscreen_ws)
			csr_log("[CSR] wiring: stage endscreen built from CSRStageEndScreenGui")
		else
			self._stage_endscreen_gui = StageEndScreenGui:new(self._ws, self._fullscreen_ws)
		end
	end

	game_state_machine:current_state():set_continue_button_text()
	self._stage_endscreen_gui:show()

	if self._endscreen_predata then
		if self._endscreen_predata.cash_summary then
			self:show_endscreen_cash_summary()
		end

		if self._endscreen_predata.stats then
			self:feed_endscreen_statistics(self._endscreen_predata.stats)
		end

		if self._endscreen_predata.continue then
			self:set_endscreen_continue_button_text(
				self._endscreen_predata.continue[1],
				self._endscreen_predata.continue[2]
			)
		end

		self._endscreen_predata = nil
	end
end)

csr_log("[CSR] endscreen_wiring.lua loaded")

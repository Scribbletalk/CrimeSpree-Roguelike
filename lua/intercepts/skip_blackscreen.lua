-- Auto-skip the heist intro blackscreen when the "skip_blackscreen" preference is on (host only).
-- Hooks IngameWaitingForPlayersState:update; gates on in_csr_heist() (CSR runs the STANDARD
-- gamemode, so crime_spree:is_active() is always false here).

if not RequiredScript then
	return
end

Hooks:PostHook(IngameWaitingForPlayersState, "update", "CSR_AutoSkipBlackscreen", function(self, t, dt)
	local mgr = managers and managers.csr
	if not (mgr and mgr.in_csr_heist and mgr:in_csr_heist()) then
		return
	end

	-- CLIENT SAFETY (setting-independent): a synced skip can leave guests stuck on a perma
	-- blackscreen when vanilla's are_all_peer_assets_loaded() hangs. Force the fade after 3s.
	if not Network:is_server() and self._skipped and self._delay_start_t then
		if not self._csr_skip_timeout then
			self._csr_skip_timeout = t + 3
		elseif t > self._csr_skip_timeout then
			self._csr_skip_timeout = nil
			self._delay_start_t = nil
			if managers.hud and managers.hud.blackscreen_fade_out_mid_text then
				managers.hud:blackscreen_fade_out_mid_text()
			end
			csr_log("[CSR] Client blackscreen safety timeout -- forcing fade")
		end
	end

	if mgr:setting("skip_blackscreen") ~= true then
		return
	end

	-- Host-only skip; only once audio started, skip prompt is up, and not already skipped.
	if not Network:is_server() then
		return
	end
	if not self._audio_started or self._skipped then
		return
	end
	if not self._skip_promt_shown then
		return
	end

	if managers.hud and managers.hud.blackscreen_skip_circle_done then
		managers.hud:blackscreen_skip_circle_done()
	end
	if self._skip then
		self:_skip()
	end
end)

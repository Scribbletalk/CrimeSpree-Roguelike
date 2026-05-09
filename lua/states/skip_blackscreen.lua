-- Crime Spree Roguelike - Auto-skip heist intro blackscreen
-- Hooks into IngameWaitingForPlayersState to instantly skip the briefing

if not RequiredScript then
	return
end

-- Safe hook via BLT (won't crash if the hooked function doesn't exist)
Hooks:PostHook(IngameWaitingForPlayersState, "update", "CSR_AutoSkipBlackscreen", function(self, t, dt)
	-- CS-only: bail out for vanilla heists. is_active() checks the current
	-- gamemode, so it stays false during a normal heist even if a CS run is
	-- mid-flight. (in_progress() would not — it persists across heists.)
	local cs = managers.crime_spree
	if not cs or not cs:is_active() then
		return
	end

	-- === CLIENT SAFETY: force fade after 3s if stuck on blackscreen after skip ===
	-- Vanilla bug: are_all_peer_assets_loaded() can hang, leaving clients on perma blackscreen.
	if not Network:is_server() and self._skipped and self._delay_start_t then
		if not self._csr_skip_timeout then
			self._csr_skip_timeout = t + 3
		elseif t > self._csr_skip_timeout then
			self._csr_skip_timeout = nil
			self._delay_start_t = nil
			if managers.hud and managers.hud.blackscreen_fade_out_mid_text then
				managers.hud:blackscreen_fade_out_mid_text()
			end
			log("[CSR] Client blackscreen safety timeout — forcing fade")
		end
	end

	-- Only auto-skip if setting is enabled
	if not CSR_Settings or not CSR_Settings:IsSkipBlackscreen() then
		return
	end

	-- Only host can skip
	if not Network:is_server() then
		return
	end

	-- Must have audio started and not already skipped
	if not self._audio_started or self._skipped then
		return
	end

	-- Wait for skip prompt to be available (peers done streaming)
	if not self._skip_promt_shown then
		return
	end

	-- Auto-skip immediately
	if managers.hud and managers.hud.blackscreen_skip_circle_done then
		managers.hud:blackscreen_skip_circle_done()
	end

	if self._skip then
		self:_skip()
	end
end)

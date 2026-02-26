-- Crime Spree Roguelike - Auto-skip heist intro blackscreen
-- Hooks into IngameWaitingForPlayersState to instantly skip the briefing

if not RequiredScript then
	return
end

-- Safe hook via BLT (won't crash if the hooked function doesn't exist)
Hooks:PostHook(IngameWaitingForPlayersState, "update", "CSR_AutoSkipBlackscreen", function(self, t, dt)
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

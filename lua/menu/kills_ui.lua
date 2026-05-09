-- Crime Spree Roguelike - Kills UI (fade-out fix only)
-- Kill bonus display removed. This file only contains the fade-out fix
-- for the last CSR bonus label in the vanilla animation system.

if not RequiredScript then
	return
end

-- Vanilla _update_gain_calculate does NOT call fade_out on the label of the LAST bonus entry.
-- We PostHook _update_gain_calculate to add the missing fade_out with the exact same timing
-- vanilla would use. We replicate vanilla's timing loop to compute the correct delay,
-- then queue one more animate(fade_out) coroutine on the last label.
-- Since animate() queues coroutines (not replaces), this runs alongside vanilla's coroutines.
-- NOTE: _update_gain_calculate is called EVERY FRAME by vanilla. Run only once.
Hooks:PostHook(CrimeSpreeResultTabItem, "_update_gain_calculate", "CSR_FadeOutLastLabel", function(self)
	if self._csr_fadeout_done then
		return
	end
	if not self._csr_gain_done then
		return
	end
	self._csr_fadeout_done = true
	if not self._levels or not self._levels.bonuses then
		return
	end
	if not self:success() then
		return
	end

	local bonuses = self._levels.bonuses
	local n = #bonuses
	if n < 1 then
		return
	end

	local last = bonuses[n]
	if not last or not last[1] then
		return
	end

	-- Only fade out our CSR labels, not vanilla labels
	local ok, name = pcall(function()
		return last[1]:name()
	end)
	if not ok or (name ~= "csr_bags_label" and name ~= "csr_rank_label") then
		return
	end

	-- Replicate vanilla timing constants
	local fade_t = 0.5
	local count_bonus_t = 0.75
	local t = 0.5 -- initial gain fade_in offset

	for i, bonus in ipairs(bonuses) do
		t = t + 0.25
		if bonus[2] then
			t = t + fade_t + 0.5
		end
		t = t + count_bonus_t + 1
		-- This is the t value where vanilla schedules fade_outs
		if i == n then
			last[1]:animate(callback(self, self, "fade_out"), fade_t * 0.66, t)
		end
		t = t + 0.4
	end
end)

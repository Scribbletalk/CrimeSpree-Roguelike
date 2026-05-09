-- Crime Spree Roguelike - Fade out all bonus labels on mission end screen
-- Vanilla keeps the last bonus label (e.g. "Mission Complete") visible forever.
-- This override makes all bonus labels fade out, leaving just the gain number.
-- NOTE: vanilla calls _update_gain_calculate EVERY FRAME from an animate coroutine.

local key = ModPath .. "\t" .. RequiredScript
if _G[key] then
	return
else
	_G[key] = true
end

local function CSR_log(msg)
	if _G.CSR_Settings and _G.CSR_Settings.values and _G.CSR_Settings.values.debug_mode then
		log("[CSR StageEnd] " .. tostring(msg))
	end
end

if not CrimeSpreeResultTabItem then
	CSR_log("CrimeSpreeResultTabItem not found, skipping")
	return
end

-- Check if any popup is blocking the rank animation
local function _csr_popups_blocking()
	return _G.CSR_ForcedModsPending or _G.CSR_ForcedModsNotificationInstance
end

-- Actual rank animation logic (runs once when popups are cleared)
function CrimeSpreeResultTabItem:_csr_run_gain_animation()
	local t = 0
	local fade_t = 0.5
	local count_t = 1.5
	local count_bonus_t = 0.75
	local gain_amt = 0

	self._levels.gain:animate(callback(self, self, "fade_in"), 0.5, t)

	t = t + 0.5

	for i, bonus in ipairs(self._levels.bonuses) do
		bonus[1]:animate(callback(self, self, "fade_in"), fade_t, t)

		t = t + 0.25

		if bonus[2] then
			bonus[2]:animate(callback(self, self, "fade_in"), fade_t, t)

			t = t + fade_t + 0.5

			self._levels.gain:animate(
				callback(self, self, "count_text"),
				"+",
				gain_amt,
				gain_amt + bonus[3],
				count_bonus_t,
				t
			)

			gain_amt = gain_amt + bonus[3]
		end

		t = t + count_bonus_t + 1

		if self:success() then
			-- All bonuses fade out (vanilla skips the last one)
			bonus[1]:animate(callback(self, self, "fade_out"), fade_t * 0.66, t)

			if bonus[2] then
				bonus[2]:animate(callback(self, self, "fade_out"), fade_t * 0.66, t)
			end

			t = t + 0.4
		end
	end

	self:_advance_stage(t)
end

-- Called EVERY FRAME by vanilla animate coroutine.
-- Wait for popups to close, then run animation exactly once.
function CrimeSpreeResultTabItem:_update_gain_calculate(t, dt)
	-- Already ran animation — nothing to do
	if self._csr_gain_done then
		return
	end

	-- Popups still open — skip this frame
	if _csr_popups_blocking() then
		self._csr_gain_waiting = true
		return
	end

	-- Popups cleared — run animation once
	self._csr_gain_done = true
	_G.CSR_GainAnimDeferred = false

	if self._csr_gain_waiting then
		CSR_log("Popups closed, starting gain animation")
	end

	self:_csr_run_gain_animation()
end

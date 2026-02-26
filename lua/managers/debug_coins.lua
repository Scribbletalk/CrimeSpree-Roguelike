-- Crime Spree Roguelike - Debug: Free Continental Coins
-- In debug mode, all continental coin spending is automatically refunded

if not RequiredScript then
	return
end

local function CSR_log(msg)
	if _G.CSR_Settings and _G.CSR_Settings.debug_mode then
		log("[CSR Debug Coins] " .. tostring(msg))
	end
end

-- Guard: skip if debug mode is not enabled
if not CSR_DEBUG_MODE then
	CSR_log("Debug mode is off, skipping coin hook")
	return
end

CSR_log("Debug mode: continental coins are automatically refunded!")

-- Hook on the continental coin deduction function - refund coins immediately
if CustomSafehouseManager then
	local original_deduct = CustomSafehouseManager.deduct

	function CustomSafehouseManager:deduct(amount, ...)
		CSR_log("Attempting to deduct " .. tostring(amount) .. " coins")

		-- Call the original function (coins are deducted)
		local result = original_deduct(self, amount, ...)

		-- Immediately refund the amount
		if amount and amount > 0 then
			self:award(amount)
			CSR_log("Refunded " .. amount .. " coins (debug mode)")
			CSR_log("Balance: " .. self:total())
		end

		return result
	end

	CSR_log("Hook on CustomSafehouseManager:deduct installed")
end

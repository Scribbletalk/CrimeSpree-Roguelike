-- Open callback for Gage Services (Black Market). Triggered from the CSR lobby
-- sidebar (missions_menu.lua csr_open_shop).

if not RequiredScript then
	return
end

if not MenuCallbackHandler then
	csr_log("[CSR Shop] black_market_button: early return (MenuCallbackHandler missing)")
	return
end

csr_log("[CSR Shop] black_market_button.lua loaded; CSR_OpenBlackMarket registered")

MenuCallbackHandler.CSR_OpenBlackMarket = function(this, item)
	csr_log("[CSR Shop] CSR_OpenBlackMarket fired -> open_node(black_market_screen)")

	local ok, err = pcall(function()
		managers.menu:open_node("black_market_screen")
	end)

	if not ok then
		log("[CSR Shop] ERROR open_node(black_market_screen) failed: " .. tostring(err))
	end
end

-- Crime Spree Roguelike - Gage Services open callback.
-- Opened from the CSR lobby sidebar "Black Market" row (missions_menu.lua ->
-- csr_open_shop -> this). Registers the callback only; the screen itself is
-- black_market_screen (node_register + component_register + black_market_menu.lua).
-- Mirrors logbook_button.lua.

if not RequiredScript then
	return
end

if not MenuCallbackHandler then
	log("[CSR Shop] black_market_button: early return (MenuCallbackHandler missing)")
	return
end

log("[CSR Shop] black_market_button.lua loaded; CSR_OpenBlackMarket registered")

MenuCallbackHandler.CSR_OpenBlackMarket = function(this, item)
	log("[CSR Shop] CSR_OpenBlackMarket fired -> open_node(black_market_screen)")

	local ok, err = pcall(function()
		managers.menu:open_node("black_market_screen")
	end)

	if not ok then
		log("[CSR Shop] ERROR open_node(black_market_screen) failed: " .. tostring(err))
	end
end

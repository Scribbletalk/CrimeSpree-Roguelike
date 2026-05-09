-- Crime Spree Roguelike — Gage Tokens
-- Per-peer wallet lives in _G.CSR_PlayerItems[peer_id].tokens (already declared
-- in player_items_store.lua). Host-only earned counter lives in
-- _G.CSR_HostTokensEarned. Both are persisted by autosave + cleared on CS reset.

CSR_TokensManager = CSR_TokensManager or {}

local function CSR_log(msg)
	if _G.CSR_Settings and _G.CSR_Settings.values and _G.CSR_Settings.values.debug_mode then
		log("[CSR TOK] " .. tostring(msg))
	end
end

-- Price by rarity (string -> int tokens). Wildcard intentionally absent until
-- Wildcards are introduced; pricing TBD at that point.
CSR_TokensManager.PRICE = {
	common = 10,
	uncommon = 20,
	rare = 40,
}

function CSR_TokensManager.local_peer_id()
	return (CSR_LocalPeerId and CSR_LocalPeerId()) or 1
end

function CSR_TokensManager.get_wallet(peer_id)
	peer_id = peer_id or CSR_TokensManager.local_peer_id()
	local pdata = _G.CSR_PlayerItems and _G.CSR_PlayerItems[peer_id]
	return (pdata and pdata.tokens) or 0
end

function CSR_TokensManager.set_wallet(peer_id, value)
	peer_id = peer_id or CSR_TokensManager.local_peer_id()
	_G.CSR_PlayerItems = _G.CSR_PlayerItems or {}
	local pdata = _G.CSR_PlayerItems[peer_id]
	if not pdata then
		-- Auto-create a placeholder record. Catch-up grants can fire before the
		-- joiner has called CSR_InitLocalPlayer or before host has synced PLAYER_ITEMS;
		-- silently dropping the wallet write here used to leave joiners with 0 tokens.
		log("[CSR TOK] set_wallet: auto-creating placeholder pdata for peer=" .. tostring(peer_id))
		_G.CSR_PlayerItems[peer_id] = {
			items = {},
			name = "Player " .. tostring(peer_id),
			rank = 0,
			difficulty = _G.CSR_CurrentDifficulty or "overkill",
			tokens = 0,
		}
		pdata = _G.CSR_PlayerItems[peer_id]
	end
	pdata.tokens = math.max(0, math.floor(value))
end

function CSR_TokensManager.credit(peer_id, amount)
	if amount <= 0 then
		return
	end
	CSR_TokensManager.set_wallet(peer_id, CSR_TokensManager.get_wallet(peer_id) + amount)
end

function CSR_TokensManager.debit(peer_id, amount)
	if amount <= 0 then
		return false
	end
	local cur = CSR_TokensManager.get_wallet(peer_id)
	if cur < amount then
		return false
	end
	CSR_TokensManager.set_wallet(peer_id, cur - amount)
	return true
end

-- Host-only monotonic counter, mirrored to all peers. Used for late-join catchup.
function CSR_TokensManager.get_host_earned()
	return _G.CSR_HostTokensEarned or 0
end

function CSR_TokensManager.add_host_earned(amount)
	if amount <= 0 then
		return
	end
	_G.CSR_HostTokensEarned = (_G.CSR_HostTokensEarned or 0) + amount
end

function CSR_TokensManager.set_host_earned(value)
	_G.CSR_HostTokensEarned = math.max(0, math.floor(value))
end

function CSR_TokensManager.price_for_rarity(rarity)
	return CSR_TokensManager.PRICE[rarity] or math.huge
end

CSR_log("loaded")

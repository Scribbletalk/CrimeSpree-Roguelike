-- CSR contract difficulty selector — injects a vanilla-style difficulty
-- multichoice into the Crime Spree contract node's button list, above ACCEPT
-- (matches the vanilla contract menu: TEAM AI / DIFFICULTY / ONE DOWN / ACCEPT).
--
-- WHICH initiator: the SP node (crimenet_crime_spree_contract_singleplayer) and
-- the MP-host node (crimenet_crime_spree_contract_host) use DIFFERENT modifiers
-- (diagnostic 2026-05-21: SP runs MenuCrimeNetContractInitiator; wrapping that
-- alone left the host node selector-less online). So we wrap BOTH contract
-- initiators and recognise the CS contract by data.job_id == "crime_spree" OR a
-- known node name. add_difficulty_item is idempotent, so a node that runs both
-- initiators only gets one item. The client JOIN node is excluded (host picks
-- difficulty; clients receive it via lobby sync).
--
-- Mouse vs keyboard: MenuRenderer:input_focus()=false for these nodes disables
-- KEYBOARD navigation but NOT mouse -- the player changes difficulty by CLICKING
-- the < > arrows (see pd2_cs_contract_node_input_focus.md).
--
-- Why a raw wrap (not Hooks:PostHook): modify_node returns a deep_clone'd node we
-- must mutate; a PostHook can't reach the return value. Documented CSR
-- return-value-hook exception to Critical Rule #1 (cf. sidesatchel / hippocraticoath).
-- Hooked at BOTH lib/managers/menumanager (defines MenuCrimeNetContractInitiator)
-- AND lib/managers/menu/crimespreecontractmenucomponent (defines
-- MenuCrimeNetCrimeSpreeContractInitiator) so both are present when we wrap; the
-- per-initiator guard keeps re-runs idempotent.

if not RequiredScript then
	return
end

local CSR_CONTRACT_NODES = {
	crimenet_crime_spree_contract_host = true,
	crimenet_crime_spree_contract_singleplayer = true,
}

-- Client join node: never gets a difficulty selector (host-authoritative).
local CSR_EXCLUDE_NODES = {
	crimenet_contract_crime_spree_join = true,
}

-- tweak_data.difficulties[1] == "easy" is excluded; the CSR ladder is the 7
-- entries Normal .. Death Sentence (indices 2..8).
local FIRST_DIFFICULTY_INDEX = 2

local function build_difficulty_options()
	local options = {
		type = "MenuItemMultiChoice",
	}
	local diffs = tweak_data.difficulties
	local name_ids = tweak_data.difficulty_name_ids

	for i = FIRST_DIFFICULTY_INDEX, #diffs do
		local diff = diffs[i]

		options[#options + 1] = {
			_meta = "option",
			value = i,
			text_id = (name_ids and name_ids[diff]) or diff,
		}
	end

	return options
end

local function add_difficulty_item(node)
	if node:item("csr_contract_difficulty") then
		return
	end

	local params = {
		name = "csr_contract_difficulty",
		text_id = "csr_contract_difficulty",
		callback = "change_csr_contract_difficulty",
	}
	local item = node:create_item(build_difficulty_options(), params)

	-- Pre-select the run's current / remembered difficulty (set_value does not
	-- fire the callback, so the popup's own _setup paints the initial read-out).
	local diff = (managers.csr and managers.csr:difficulty()) or tweak_data.crime_spree.base_difficulty
	item:set_value(tweak_data:difficulty_to_index(diff) or tweak_data.crime_spree.base_difficulty_index)

	-- Lock the selector once a run is in progress: difficulty is chosen when a run
	-- STARTS and stays fixed for its duration. Re-opening the contract on an active
	-- run shows the locked difficulty greyed out (set_enabled is vanilla's disable,
	-- menumanager.lua:6189). The change callback also guards on is_active().
	if managers.csr and managers.csr:is_active() then
		item:set_enabled(false)
	end

	-- Place it just above ACCEPT CONTRACT so it reads like a vanilla contract.
	local accept_index = nil

	for idx, it in ipairs(node:items()) do
		if it:parameters().name == "accept_contract" then
			accept_index = idx

			break
		end
	end

	if accept_index then
		node:insert_item(item, accept_index)
	else
		node:add_item(item)
	end
end

-- A node is the CSR contract if its job is crime_spree OR its name is one of the
-- CS contract nodes -- but never the client join node. job_id covers SP + MP-host
-- even if the host node name differs from what we expect.
local function is_csr_contract(node, data)
	local nm = (node and node.parameters) and node:parameters().name or nil

	if nm and CSR_EXCLUDE_NODES[nm] then
		return false
	end

	if data and data.job_id == "crime_spree" then
		return true
	end

	return nm ~= nil and CSR_CONTRACT_NODES[nm] == true
end

-- Wrap one initiator's modify_node to inject the difficulty item on the finalized
-- CS contract node. Re-wrap-safe via a per-initiator guard global.
local function install_wrap(cls, label, guard_key)
	if not (cls and cls.modify_node) or cls.modify_node == _G[guard_key] then
		return
	end

	local _orig_modify_node = cls.modify_node

	local function wrapped(self, original_node, data)
		local node = _orig_modify_node(self, original_node, data)

		if node and is_csr_contract(node, data) then
			-- Rare (per CS-contract-open) diagnostic: which initiator built it +
			-- the node name + job. Kept per feedback_keep_rare_event_logs.
			local nm = node.parameters and node:parameters().name

			log(
				"[CSR] csr_contract_difficulty: "
					.. label
					.. " built CS node '"
					.. tostring(nm)
					.. "' (job="
					.. tostring(data and data.job_id)
					.. ")"
			)

			-- Defensive pcall: a bug here must degrade to "no difficulty item",
			-- never break the (shared) contract node build.
			local ok, err = pcall(add_difficulty_item, node)

			if not ok then
				log("[CSR] csr_contract_difficulty: add_difficulty_item failed -> " .. tostring(err))
			end
		end

		return node
	end

	_G[guard_key] = wrapped
	cls.modify_node = wrapped
end

install_wrap(MenuCrimeNetContractInitiator, "MenuCrimeNetContractInitiator", "_CSR_DIFF_WRAP_REGULAR")
install_wrap(MenuCrimeNetCrimeSpreeContractInitiator, "MenuCrimeNetCrimeSpreeContractInitiator", "_CSR_DIFF_WRAP_CS")

log("[CSR] contract_difficulty.lua loaded")

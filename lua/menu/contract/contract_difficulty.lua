-- Injects a difficulty multichoice into the CSR contract node above ACCEPT.
-- Wraps BOTH initiators (SP uses MenuCrimeNetContractInitiator, MP-host uses
-- MenuCrimeNetCrimeSpreeContractInitiator) and recognises the contract by job_id
-- or node name. Client join node excluded (host-authoritative).
-- Mouse-only: nav focus is disabled but mouse click on < > arrows works.

if not RequiredScript then
	return
end

local CSR_CONTRACT_NODES = {
	crimenet_crime_spree_contract_host = true,
	crimenet_crime_spree_contract_singleplayer = true,
}

local CSR_EXCLUDE_NODES = {
	crimenet_contract_crime_spree_join = true,
}

-- CSR ladder = Normal .. Death Sentence (indices 2..8; "easy" at 1 excluded).
local FIRST_DIFFICULTY_INDEX = 2

local function build_difficulty_options()
	local options = { type = "MenuItemMultiChoice" }
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

local function add_csr_contract_items(node)
	if node:item("csr_contract_difficulty") then
		return
	end

	local diff_item = node:create_item(build_difficulty_options(), {
		name = "csr_contract_difficulty",
		text_id = "csr_contract_difficulty",
		callback = "change_csr_contract_difficulty",
	})

	-- Pre-select remembered difficulty; set_value doesn't fire the callback.
	local diff = (managers.csr and managers.csr:difficulty()) or tweak_data.crime_spree.base_difficulty
	diff_item:set_value(tweak_data:difficulty_to_index(diff) or tweak_data.crime_spree.base_difficulty_index)

	local spree_active = managers.csr and managers.csr:is_active()

	-- Lock once a run is active — difficulty is chosen at run start and stays fixed.
	if spree_active then
		diff_item:set_enabled(false)
	end

	-- "Start a new spree" — always enabled; shows confirm dialog when a run is already active.
	local start_item = node:create_item({}, {
		name = "csr_start_new_spree",
		text_id = "csr_start_new_spree",
		callback = "start_new_csr_spree",
		align = "right",
	})

	-- "Continue current spree" — grayed when no run is active.
	local continue_item = node:create_item({}, {
		name = "csr_continue_spree",
		text_id = "csr_continue_spree",
		callback = "accept_csr_contract",
		align = "right",
	})
	continue_item:set_enabled(spree_active == true)

	-- Find the vanilla accept button position, then insert our items before it and hide it.
	local accept_index = nil
	for idx, it in ipairs(node:items()) do
		if it:parameters().name == "accept_contract" then
			accept_index = idx
			break
		end
	end

	if accept_index then
		-- Insert order: diff → continue → start_new, then hide vanilla accept.
		node:insert_item(diff_item, accept_index)
		node:insert_item(continue_item, accept_index + 1)
		node:insert_item(start_item, accept_index + 2)
		node:item("accept_contract"):set_visible(false)
	else
		node:add_item(diff_item)
		node:add_item(start_item)
		node:add_item(continue_item)
	end
end

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

-- Per-initiator wrap with a _G guard so re-runs are idempotent.
local function install_wrap(cls, label, guard_key)
	if not (cls and cls.modify_node) or cls.modify_node == _G[guard_key] then
		return
	end

	local _orig_modify_node = cls.modify_node

	local function wrapped(self, original_node, data)
		local node = _orig_modify_node(self, original_node, data)

		if node and is_csr_contract(node, data) then
			local nm = node.parameters and node:parameters().name

			csr_log(
				"[CSR] csr_contract_difficulty: "
					.. label
					.. " built CS node '"
					.. tostring(nm)
					.. "' (job="
					.. tostring(data and data.job_id)
					.. ")"
			)

			-- Defensive pcall: a bug here must not break the shared contract node build.
			local ok, err = pcall(add_csr_contract_items, node)
			if not ok then
				log("[CSR] csr_contract_difficulty: add_csr_contract_items failed -> " .. tostring(err))
			end
		end

		return node
	end

	_G[guard_key] = wrapped
	cls.modify_node = wrapped
end

install_wrap(MenuCrimeNetContractInitiator, "MenuCrimeNetContractInitiator", "_CSR_DIFF_WRAP_REGULAR")
install_wrap(MenuCrimeNetCrimeSpreeContractInitiator, "MenuCrimeNetCrimeSpreeContractInitiator", "_CSR_DIFF_WRAP_CS")

csr_log("[CSR] contract_difficulty.lua loaded")

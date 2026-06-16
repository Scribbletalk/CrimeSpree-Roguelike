-- Item-discovery progress for the Logbook UI. JSON-persisted at SavePath.

if not RequiredScript then
	return
end

local function CSR_log(msg)
	if _G.CSR_DEBUG then
		log(msg)
	end
end

CSR_LogbookProgress = CSR_LogbookProgress or class()

function CSR_LogbookProgress:init()
	self._save_path = SavePath .. "crime_spree_roguelike_logbook.json"
	self._unlocked_items = {}
	self._new_items = {}
	self._seen_this_run = {}
	self:load()
end

-- Older saves used pre-rename keys (health/damage/car_keys). Migrate to current
-- ids so players don't lose unlock progress.
local LOGBOOK_TYPE_REMAP = {
	health = "dog_tags",
	damage = "evidence_rounds",
	car_keys = "falcogini_keys",
}

function CSR_LogbookProgress:load()
	local file = io.open(self._save_path, "r")
	if file then
		local content = file:read("*all")
		file:close()

		local success, data = pcall(json.decode, content)
		if success and data then
			self._unlocked_items = data.unlocked_items or {}
			self._new_items = data.new_items or {}
			self._seen_this_run = data.seen_this_run or {}
			for _, tbl in ipairs({ self._unlocked_items, self._new_items, self._seen_this_run }) do
				for old_key, new_key in pairs(LOGBOOK_TYPE_REMAP) do
					if tbl[old_key] and not tbl[new_key] then
						tbl[new_key] = tbl[old_key]
					end
					tbl[old_key] = nil
				end
			end
			CSR_log(
				"[CSR Logbook] Loaded: "
					.. table.size(self._unlocked_items)
					.. " unlocked, "
					.. table.size(self._new_items)
					.. " new"
			)
		else
			log("[CSR Logbook] JSON parse error, starting fresh")
			self._unlocked_items = {}
			self._new_items = {}
			self._seen_this_run = {}
		end
	else
		log("[CSR Logbook] Progress file not found, starting fresh")
		self._unlocked_items = {}
		self._new_items = {}
		self._seen_this_run = {}
	end
end

function CSR_LogbookProgress:save()
	local data = {
		unlocked_items = self._unlocked_items,
		new_items = self._new_items,
		seen_this_run = self._seen_this_run,
	}

	local file = io.open(self._save_path, "w+")
	if file then
		file:write(json.encode(data))
		file:close()
		CSR_log("[CSR Logbook] Progress saved")
		return true
	else
		log("[CSR Logbook] ERROR: Failed to save progress")
		return false
	end
end

function CSR_LogbookProgress:is_unlocked(item_id)
	return self._unlocked_items[item_id] == true
end

function CSR_LogbookProgress:mark_seen(item_id)
	if not self._seen_this_run[item_id] then
		self._seen_this_run[item_id] = true
		self:save()
		CSR_log("[CSR Logbook] Marked as seen: " .. tostring(item_id))
	end
end

-- Called at run end (end_run): promote everything seen this run to unlocked.
function CSR_LogbookProgress:unlock_seen()
	local had_seen = next(self._seen_this_run) ~= nil
	for item_id, _ in pairs(self._seen_this_run) do
		if not self._unlocked_items[item_id] then
			self._unlocked_items[item_id] = true
			self._new_items[item_id] = true
			CSR_log("[CSR Logbook] New item unlocked: " .. tostring(item_id))
		end
	end
	self._seen_this_run = {}
	if had_seen then
		self:save()
	end
end

function CSR_LogbookProgress:has_new()
	return next(self._new_items) ~= nil
end

function CSR_LogbookProgress:clear_new()
	if next(self._new_items) ~= nil then
		self._new_items = {}
		self:save()
	end
end

-- Legacy direct unlock — kept for back-compat with old callers.
function CSR_LogbookProgress:unlock_item(item_id)
	if not self:is_unlocked(item_id) then
		self._unlocked_items[item_id] = true
		self:save()
		CSR_log("[CSR Logbook] Item unlocked (legacy): " .. tostring(item_id))
		return true
	end
	return false
end

function CSR_LogbookProgress:get_unlocked_items()
	return self._unlocked_items
end

function CSR_LogbookProgress:reset()
	self._unlocked_items = {}
	self._new_items = {}
	self._seen_this_run = {}
	self:save()
	CSR_log("[CSR Logbook] Progress reset")
end

if not _G.CSR_Logbook then
	_G.CSR_Logbook = CSR_LogbookProgress:new()
	CSR_log("[CSR Logbook] System initialized")
end

csr_log("[CSR Logbook] logbook_progress.lua loaded")

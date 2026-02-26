-- Crime Spree Roguelike - Logbook Progress System
-- Tracks and saves item discovery progress

if not RequiredScript then
	return
end

CSR_LogbookProgress = CSR_LogbookProgress or class()

function CSR_LogbookProgress:init()
	self._save_path = SavePath .. "crime_spree_roguelike_logbook.json"
	self._unlocked_items = {}
	self._new_items = {}
	self._seen_this_run = {}
	self:load()
end

-- Load progress from disk
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
			log("[CSR Logbook] Loaded: " .. table.size(self._unlocked_items) .. " unlocked, " .. table.size(self._new_items) .. " new")
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

-- Save progress to disk
function CSR_LogbookProgress:save()
	local data = {
		unlocked_items = self._unlocked_items,
		new_items = self._new_items,
		seen_this_run = self._seen_this_run
	}

	local file = io.open(self._save_path, "w+")
	if file then
		file:write(json.encode(data))
		file:close()
		log("[CSR Logbook] Progress saved")
		return true
	else
		log("[CSR Logbook] ERROR: Failed to save progress")
		return false
	end
end

-- Check whether an item is unlocked
function CSR_LogbookProgress:is_unlocked(item_id)
	return self._unlocked_items[item_id] == true
end

-- Mark an item as seen during the current run
function CSR_LogbookProgress:mark_seen(item_id)
	if not self._seen_this_run[item_id] then
		self._seen_this_run[item_id] = true
		self:save()
		log("[CSR Logbook] Marked as seen: " .. tostring(item_id))
	end
end

-- Unlock all items seen this run (called when a new run starts)
function CSR_LogbookProgress:unlock_seen()
	local had_seen = next(self._seen_this_run) ~= nil
	for item_id, _ in pairs(self._seen_this_run) do
		if not self._unlocked_items[item_id] then
			self._unlocked_items[item_id] = true
			self._new_items[item_id] = true
			log("[CSR Logbook] New item unlocked: " .. tostring(item_id))
		end
	end
	self._seen_this_run = {}
	-- Save if there were any seen items (needed to clear seen_this_run)
	if had_seen then
		self:save()
	end
end

-- Check whether there are any newly unlocked items not yet viewed in the logbook
function CSR_LogbookProgress:has_new()
	return next(self._new_items) ~= nil
end

-- Clear the new-items flag (called when the logbook is opened)
function CSR_LogbookProgress:clear_new()
	if next(self._new_items) ~= nil then
		self._new_items = {}
		self:save()
	end
end

-- Unlock an item directly (legacy method, kept for backwards compatibility)
function CSR_LogbookProgress:unlock_item(item_id)
	if not self:is_unlocked(item_id) then
		self._unlocked_items[item_id] = true
		self:save()
		log("[CSR Logbook] Item unlocked (legacy): " .. tostring(item_id))
		return true  -- first unlock
	end
	return false  -- already unlocked
end

-- Get the full list of unlocked items
function CSR_LogbookProgress:get_unlocked_items()
	return self._unlocked_items
end

-- Reset all progress (debug only)
function CSR_LogbookProgress:reset()
	self._unlocked_items = {}
	self._new_items = {}
	self._seen_this_run = {}
	self:save()
	log("[CSR Logbook] Progress reset")
end

-- Initialize the global singleton instance
if not _G.CSR_Logbook then
	_G.CSR_Logbook = CSR_LogbookProgress:new()
	log("[CSR Logbook] System initialized")
end

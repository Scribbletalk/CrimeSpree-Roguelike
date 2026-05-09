-- Crime Spree Roguelike - HALF-A-GLASS pickup hook
-- On Gage package pickup by local player:
--   - Instantly refills 15% of max ammo for primary and secondary
--   - Increases max ammo by 2% (first stack) + 1% per additional stack for the rest of the mission
-- While active: Gage packages within 3 meters show a contour outline.

if not RequiredScript then
	return
end

local function CSR_log(msg)
	if _G.CSR_Settings and _G.CSR_Settings.values and _G.CSR_Settings.values.debug_mode then
		log("[CSR HalfAGlass] " .. tostring(msg))
	end
end

-- Returns number of half_a_glass stacks the local player has, or 0
local function get_stacks()
	local hag_stacks = CSR_CountStacks("player_half_a_glass_")
	return hag_stacks
end

-- Track original (base) max ammo per weapon slot and total pickups
_G.CSR_HalfAGlass_BaseAmmo = _G.CSR_HalfAGlass_BaseAmmo or {}
_G.CSR_HalfAGlass_Pickups = _G.CSR_HalfAGlass_Pickups or 0

-- Applies ammo bonus to both primary and secondary weapons
-- Bonus is always calculated from original max ammo, not current
local function apply_ammo_bonus(stacks)
	local player_unit = managers.player and managers.player:player_unit()
	if not player_unit then
		return
	end

	local inventory = player_unit:inventory()
	if not inventory then
		return
	end

	_G.CSR_HalfAGlass_Pickups = _G.CSR_HalfAGlass_Pickups + 1
	local pickups = _G.CSR_HalfAGlass_Pickups

	for i = 1, 2 do
		pcall(function()
			local weapon_unit = inventory:unit_by_selection(i)
			if not weapon_unit or not alive(weapon_unit) then
				return
			end
			local base = weapon_unit:base()
			if not base then
				return
			end

			local C = _G.CSR_ItemConstants or {}

			-- Capture original max ammo on first pickup
			if not _G.CSR_HalfAGlass_BaseAmmo[i] then
				_G.CSR_HalfAGlass_BaseAmmo[i] = base:get_ammo_max()
			end
			local base_max = _G.CSR_HalfAGlass_BaseAmmo[i]
			if not base_max or base_max <= 0 then
				return
			end

			-- Total bonus = base_max * pct * number_of_pickups (always from original)
			local pct = (C.half_a_glass_max_ammo_first or 0.04) + (stacks - 1) * (C.half_a_glass_max_ammo_extra or 0.02)
			local total_bonus = math.ceil(base_max * pct * pickups)
			local new_max = base_max + total_bonus
			base:set_ammo_max(new_max)
			CSR_log(
				"Weapon slot " .. i .. ": base=" .. base_max .. " new_max=" .. new_max .. " (pickups=" .. pickups .. ")"
			)

			-- Instantly add 15% of the NEW max ammo to the pool
			local refill = math.ceil(new_max * (C.half_a_glass_refill or 0.15))
			base:add_ammo_to_pool(refill, i)
			CSR_log("Weapon slot " .. i .. ": refilled " .. refill .. " ammo")

			-- Apply the same bonus to an underbarrel weapon if one is attached.
			-- Underbarrels are gadgets with their own WeaponAmmo instance; the
			-- main weapon's set_ammo_max / add_ammo_to_pool don't touch them.
			if managers.weapon_factory and base._parts then
				local ub_part = managers.weapon_factory:get_part_from_weapon_by_type("underbarrel", base._parts)
				if ub_part and ub_part.unit and alive(ub_part.unit) then
					local ub_base = ub_part.unit:base()
					if ub_base and ub_base.ammo_base then
						local ub_ammo = ub_base:ammo_base()
						if ub_ammo then
							local ub_key = "ub_" .. i
							if not _G.CSR_HalfAGlass_BaseAmmo[ub_key] then
								_G.CSR_HalfAGlass_BaseAmmo[ub_key] = ub_ammo:get_ammo_max()
							end
							local ub_base_max = _G.CSR_HalfAGlass_BaseAmmo[ub_key]
							if ub_base_max and ub_base_max > 0 then
								local ub_new_max = ub_base_max + math.ceil(ub_base_max * pct * pickups)
								ub_ammo:set_ammo_max(ub_new_max)
								local ub_refill = math.ceil(ub_new_max * (C.half_a_glass_refill or 0.15))
								ub_ammo:set_ammo_total(math.min(ub_ammo:get_ammo_total() + ub_refill, ub_new_max))
								CSR_log(
									"Weapon slot "
										.. i
										.. " underbarrel: new_max="
										.. ub_new_max
										.. " refilled="
										.. ub_refill
								)
							end
						end
					end
				end
			end
		end)
	end
end

-- == CONTOUR SYSTEM ==
-- Tracks live Gage package units and shows a contour outline when the local
-- player is within 3 meters (300 cm).  Requires CONTOUR in the material
-- render_template, provided by our material_config files registered via
-- DB:create_entry in seed_manager.lua (only when Half-a-Glass is in inventory).

_G.CSR_GagePackages = _G.CSR_GagePackages or {}

local CONTOUR_RADIUS = 300 -- 3 meters (300 cm)
local CONTOUR_RADIUS_SQ = CONTOUR_RADIUS * CONTOUR_RADIUS
local CONTOUR_CHECK_INTERVAL = 0.1 -- seconds between distance checks
local IDS_MATERIAL = Idstring("material")
local IDS_CONTOUR_OPACITY = Idstring("contour_opacity")
local IDS_CONTOUR_COLOR = Idstring("contour_color")

-- Unit objects are C++ userdata — we cannot attach Lua fields to them directly.
-- Use separate tables keyed by unit:key() to store per-package state.
local _pkg_materials = {} -- [key] = material list (nil = not yet cached)
local _pkg_visible = {} -- [key] = true if contour is currently shown

-- Cache ALL materials on the unit without filtering (ContourExt does the same).
-- Returns the material list. An empty list means materials weren't ready yet.
local function cache_materials(pkg_unit)
	local key = pkg_unit:key()
	local mats = {}
	_pkg_materials[key] = mats
	pcall(function()
		for _, m in ipairs(pkg_unit:get_objects_by_type(IDS_MATERIAL)) do
			table.insert(mats, m)
		end
	end)
	return mats
end

local function set_contour_opacity(pkg_unit, opacity)
	local mats = _pkg_materials[pkg_unit:key()] or {}
	for _, m in ipairs(mats) do
		pcall(function()
			m:set_variable(IDS_CONTOUR_OPACITY, opacity)
		end)
	end
end

-- Fade is done via contour_color RGB, not contour_opacity (which is binary).
-- Fading Contour mod confirmed: multiplying color RGB by a ratio gives smooth fade.
local function set_contour_color(pkg_unit, ratio)
	local mats = _pkg_materials[pkg_unit:key()] or {}
	local color = Vector3(ratio, ratio, ratio)
	for _, m in ipairs(mats) do
		pcall(function()
			m:set_variable(IDS_CONTOUR_COLOR, color)
		end)
	end
end

local function remove_package_contour(pkg_unit)
	local key = pkg_unit:key()
	-- No early-return guard: InteractionExt may have set opacity=1 during init
	-- (before our PostHook could block it), and we must always enforce opacity=0.
	set_contour_opacity(pkg_unit, 0)
	_pkg_visible[key] = false
end

if GageAssignmentBase then
	-- Register each Gage package unit as it spawns and force our CONTOUR material.
	-- DB:create_entry alone is unreliable — the engine may have loaded the vanilla
	-- material from a bundle cache before our override registered.  Calling
	-- set_material_config forces the unit to reload from the (now overridden) DB,
	-- guaranteeing the CONTOUR render_template is present.
	Hooks:PostHook(GageAssignmentBase, "init", "CSR_HalfAGlass_TrackPackage", function(self)
		if not self._unit or not alive(self._unit) then
			return
		end

		-- Guard: only run during active Crime Spree.
		-- Non-CS outline suppression is handled in the GageAssignmentInteractionExt:init
		-- PostHook below, which fires AFTER BaseInteractionExt:init → set_active(true).
		-- Doing it here (base ext) is too early — the interaction ext hasn't run yet.
		if not managers.crime_spree or not managers.crime_spree:is_active() then
			return
		end

		-- For known gage paths, force-load our DB CONTOUR material so interact._materials
		-- is populated even if the engine bundled a non-CONTOUR version.
		if _G.CSR_HalfAGlass_MaterialRegistered then
			pcall(function()
				self._unit:set_material_config(self._unit:name(), true)
			end)
		end

		-- Set up tracking with whatever CONTOUR-capable materials the unit has.
		-- Works for our DB material on known gage paths AND for custom gage package
		-- models that already include their own CONTOUR shader.
		local interact = self._unit:interaction()
		pcall(function()
			if interact then
				interact._contour_override = true
				if interact.refresh_material then
					interact:refresh_material()
				end
			end
		end)

		local key = self._unit:key()
		-- Prefer interact._materials (vanilla's own CONTOUR-filtered list) so we only
		-- set variables on materials that actually support them.  Fall back to
		-- cache_materials if the interaction ext isn't available.
		if interact and interact._materials and #interact._materials > 0 then
			_pkg_materials[key] = interact._materials
		else
			cache_materials(self._unit)
		end
		set_contour_opacity(self._unit, 0)

		_G.CSR_GagePackages[key] = self._unit
	end)

	-- Unregister and strip contour when a package is picked up.
	Hooks:PostHook(GageAssignmentBase, "_pickup", "CSR_HalfAGlass_UntrackPickup", function(self, unit)
		if not managers.crime_spree or not managers.crime_spree:is_active() then
			return
		end
		-- Ammo bonus for the picking CLIENT only.
		-- The host (for all pickups) and non-picking clients are handled in the
		-- sync_pickup PostHook below, which is not called on the picking client.
		if Network:is_client() and unit and alive(unit) then
			local is_local = false
			pcall(function()
				is_local = unit:base().is_local_player == true
			end)
			if is_local then
				local stacks = get_stacks()
				if stacks > 0 then
					CSR_log("Package picked up by local client! stacks=" .. stacks)
					apply_ammo_bonus(stacks)
				end
			end
		end

		-- Remove from tracker (all clients, so contour is cleaned up for everyone).
		if self._unit and alive(self._unit) then
			local key = self._unit:key()
			remove_package_contour(self._unit)
			_G.CSR_GagePackages[key] = nil
			_pkg_materials[key] = nil
			_pkg_visible[key] = nil
		end
	end)

	-- Ammo bonus for host (any pickup) and non-picking clients (any pickup).
	-- self._picked_up is set inside sync_pickup only if the pickup was valid;
	-- if it was skipped (not an assignment / already picked up), we bail out.
	Hooks:PostHook(GageAssignmentBase, "sync_pickup", "CSR_HalfAGlass_SyncPickupBonus", function(self, peer)
		if not self._picked_up then
			return
		end
		if not managers.crime_spree or not managers.crime_spree:is_active() then
			return
		end
		local stacks = get_stacks()
		if stacks > 0 then
			CSR_log("sync_pickup: applying ammo bonus, stacks=" .. stacks)
			apply_ammo_bonus(stacks)
		end
	end)
end

-- Suppress the interactable orange outline on gage packages in non-CS heists.
-- Must hook the INTERACTION ext (not GageAssignmentBase) because the outline is
-- painted by BaseInteractionExt:init → set_active(true), which runs as part of
-- GageAssignmentInteractionExt.super.init — so our PostHook is guaranteed to fire
-- AFTER the outline is set and we can safely undo it.
-- In CS, sets _contour_override so our proximity update loop owns contour_opacity.
if GageAssignmentInteractionExt then
	Hooks:PostHook(GageAssignmentInteractionExt, "init", "CSR_HalfAGlass_InteractionExtInit", function(self)
		if not self._unit or not alive(self._unit) then
			return
		end

		if not managers.crime_spree or not managers.crime_spree:is_active() then
			-- super.init already called set_active(true) which:
			--   remove_occlusion → set_skip_occlusion(true)  (renders the outline)
			--   set_contour(..., 1) → contour_opacity=1       (sets the color)
			-- Reverse both now.
			self._contour_override = true
			for _, m in ipairs(self._materials or {}) do
				pcall(function()
					m:set_variable(IDS_CONTOUR_OPACITY, 0)
				end)
			end
			pcall(function()
				managers.occlusion:add_occlusion(self._unit)
			end)
		else
			-- CS: block future set_contour calls so the proximity update loop
			-- can control contour_opacity without the interaction ext fighting it.
			self._contour_override = true
		end
	end)
end

-- Distance check: runs every CONTOUR_CHECK_INTERVAL seconds while in a mission.
-- Adds or removes the contour preset based on player proximity.
Hooks:PostHook(PlayerDamage, "update", "CSR_HalfAGlass_ContourUpdate", function(self, unit, t, dt)
	-- Only relevant when the buff is active.
	if not CSR_ActiveBuffs or not CSR_ActiveBuffs.half_a_glass then
		-- If buff was removed mid-mission, clear any lingering contours.
		if _G.CSR_GagePackages then
			for key, pkg_unit in pairs(_G.CSR_GagePackages) do
				if alive(pkg_unit) then
					remove_package_contour(pkg_unit)
				end
			end
		end
		return
	end

	-- Throttle checks to avoid per-frame overhead.
	self._csr_hag_contour_timer = (self._csr_hag_contour_timer or 0) + dt
	if self._csr_hag_contour_timer < CONTOUR_CHECK_INTERVAL then
		return
	end
	self._csr_hag_contour_timer = 0

	local player_unit = managers.player and managers.player:player_unit()
	if not player_unit then
		return
	end

	local px = player_unit:position()

	for key, pkg_unit in pairs(_G.CSR_GagePackages) do
		if not alive(pkg_unit) then
			_G.CSR_GagePackages[key] = nil
			_pkg_materials[key] = nil
			_pkg_visible[key] = nil
		else
			pcall(function()
				-- If init cached an empty material list (materials not ready yet),
				-- retry now — by this point the engine has compiled the materials.
				local mats = _pkg_materials[key]
				if mats and #mats == 0 then
					mats = cache_materials(pkg_unit)
					-- Force-hide immediately after re-caching so contour doesn't flash.
					for _, m in ipairs(mats) do
						pcall(function()
							m:set_variable(IDS_CONTOUR_OPACITY, 0)
						end)
					end
					_pkg_visible[key] = false
				end

				local pp = pkg_unit:position()
				local dx = pp.x - px.x
				local dy = pp.y - px.y
				local dz = pp.z - px.z
				local dist_sq = dx * dx + dy * dy + dz * dz

				if dist_sq <= CONTOUR_RADIUS_SQ then
					-- Fade via contour_color intensity (not opacity — that's binary).
					-- sqrt curve: brighter sooner, smoother feel (same as Fading Contour mod).
					local ratio = math.sqrt(1 - math.sqrt(dist_sq) / CONTOUR_RADIUS)
					set_contour_opacity(pkg_unit, 1)
					set_contour_color(pkg_unit, ratio)
					_pkg_visible[key] = true
				else
					set_contour_opacity(pkg_unit, 0)
					_pkg_visible[key] = false
				end
			end)
		end
	end
end)

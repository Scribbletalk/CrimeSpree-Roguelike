-- Registers the csr_ff_arrow projectile entries used by Familiar Friend.
-- Custom unit (no AmmoClip) prevents players picking up VFX arrows; see pd2_custom_projectile_needs_local_unit_no_sync.md.
-- Mutates already-populated tweak_data globals directly (PostHook on init fires too late).

if not RequiredScript then
	return
end

local req = string.lower(RequiredScript)

if req == "lib/tweak_data/tweakdata" then
	-- ArrowBase:_setup_from_tweak_data reads tweak_data.projectiles[entry]; missing = nil crash.
	if tweak_data and tweak_data.projectiles and not tweak_data.projectiles.csr_ff_arrow then
		tweak_data.projectiles.csr_ff_arrow = {
			damage = 50,
			launch_speed = 3500,
			adjust_z = 0,
			mass_look_up_modifier = 1,
			name_id = "csr_ff_arrow",
			push_at_body_index = 0,
		}
	end

	-- ProjectileBase.throw_projectile reads unit/local_unit from blackmarket.projectiles.
	-- local_unit has no sync="spawn" network tag; server unit native-AVs on clients.
	if tweak_data and tweak_data.blackmarket and tweak_data.blackmarket.projectiles then
		if not tweak_data.blackmarket.projectiles.csr_ff_arrow then
			tweak_data.blackmarket.projectiles.csr_ff_arrow = {
				unit = "units/payday2_csr/wildcards/ff_arrow/ff_arrow",
				local_unit = "units/payday2_csr/wildcards/ff_arrow/ff_arrow_local",
				no_cheat_count = true,
				impact_detonation = true,
				client_authoritative = true,
			}
		end
		-- MP sync: get_index_from_projectile_id walks this list.
		if tweak_data.blackmarket._projectiles_index then
			local already = false
			for _, name in ipairs(tweak_data.blackmarket._projectiles_index) do
				if name == "csr_ff_arrow" then
					already = true
					break
				end
			end
			if not already then
				table.insert(tweak_data.blackmarket._projectiles_index, "csr_ff_arrow")
			end
		end
	end
end

if req == "lib/units/weapons/projectiles/arrowbase" then
	Hooks:PostHook(ArrowBase, "init", "CSR_FFArrow_ScheduleDespawn", function(self, unit)
		if self._tweak_projectile_entry ~= "csr_ff_arrow" then
			return
		end
		local arrow_unit = unit
		local key = tostring(arrow_unit:key())
		DelayedCalls:Add("CSR_FF_DespawnArrow_" .. key, 8.0, function()
			if alive(arrow_unit) then
				pcall(function()
					World:delete_unit(arrow_unit)
				end)
			end
		end)
	end)
end

if req == "lib/units/contourext" then
	-- Suppress any contour HUD mods add to ff_arrow. ContourExt stays on the unit
	-- for material init, but the arrow must never render an outline.
	Hooks:PostHook(
		ContourExt,
		"add",
		"CSR_FFArrow_SuppressContour",
		function(self, type, sync, multiplier, override_color, is_element)
			local unit = self._unit
			if not alive(unit) then
				return
			end
			local base = unit:base()
			local entry = base and base._tweak_projectile_entry
			if entry == "csr_ff_arrow" then
				pcall(function()
					self:clear_all()
				end)
			end
		end
	)
end

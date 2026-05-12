-- Registers the csr_ff_arrow custom projectile entry used by Familiar Friend.
-- Clone of ecp_arrow but pointing at our own .unit which lacks AmmoClip
-- (pickup) — fixes the player picking up our VFX arrows. Slot=1 + no AmmoClip
-- also keeps throwable-outline HUDs from finding our arrows. Also schedules
-- auto-despawn so stuck arrows don't litter the world after corpses despawn.
--
-- Hooked at two load points (see mod.txt):
--   lib/tweak_data/tweakdata                       → register entries AFTER
--                                                    tweak_data = TweakData:new()
--                                                    has finished populating
--   lib/units/weapons/projectiles/arrowbase        → auto-despawn on init
--
-- IMPORTANT: do NOT try to PostHook TweakData:init or BlackMarketTweakData:_init_projectiles
-- from a regular ("post") hook — by the time the hook file runs, init has
-- already executed and the PostHook will never fire. Instead, mutate the
-- already-populated globals directly.

if not RequiredScript then
	return
end

local req = string.lower(RequiredScript)

if req == "lib/tweak_data/tweakdata" then
	-- tweak_data global is fully populated by line 3746 of tweakdata.lua
	-- (`tweak_data = TweakData:new()`). Our post-hook runs after that.

	-- Required by ArrowBase:_setup_from_tweak_data — reads damage / launch_speed
	-- from tweak_data.projectiles[self._tweak_projectile_entry]. Missing entry
	-- → nil deref on arrowbase.lua:14 → FATAL ERROR per spawn.
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

	-- Required by ProjectileBase.throw_projectile — reads unit / local_unit
	-- from tweak_data.blackmarket.projectiles[projectile_type].
	if tweak_data and tweak_data.blackmarket and tweak_data.blackmarket.projectiles then
		if not tweak_data.blackmarket.projectiles.csr_ff_arrow then
			tweak_data.blackmarket.projectiles.csr_ff_arrow = {
				unit = "units/payday2_csr/wildcards/ff_arrow/ff_arrow",
				local_unit = "units/payday2_csr/wildcards/ff_arrow/ff_arrow",
				no_cheat_count = true,
				impact_detonation = true,
				client_authoritative = true,
			}
		end
		-- Required by MP sync (get_index_from_projectile_id walks this list).
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
	-- Proactive contour suppression: if any HUD mod (WolfHUD/VHUDPlus/PocoHud
	-- throwable-outline systems) tries to add a contour to our ff_arrow unit,
	-- immediately revert it. clear_all wipes any contour state regardless of
	-- which "type" was added. ContourExt is kept on the unit for material
	-- init (the arrow's render template needs the contour material slot),
	-- but no actual outline should ever render.
	--
	-- Diagnostic logs are scoped to our entry only (no global spam). If the
	-- user reports "contour still visible" but no log appears, the hook isn't
	-- firing for our arrows — the contour is being added through a path that
	-- bypasses ContourExt:add (e.g. a direct material override).
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
				local ok, err = pcall(function()
					self:clear_all()
				end)
				log(
					"[CSR FF] suppressed contour on csr_ff_arrow, contour_type="
						.. tostring(type)
						.. " ok="
						.. tostring(ok)
						.. " err="
						.. tostring(err)
				)
			end
		end
	)
end

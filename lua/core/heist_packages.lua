-- CSR heist asset/enemy package loader.
--
-- ROOT CAUSE of the "most heists crash on enemy spawn" bug (native access
-- violation in ElementSpawnEnemyDummy:produce -> safe_spawn_unit): a heist's
-- scripted enemy units live in its JOB package. GameSetup:load_packages loads
-- that job package, but ONLY inside a block gated on
-- `Global.game_settings.gamemode == "crime_spree"` (gamesetup.lua:404). Vanilla
-- Crime Spree enables that gamemode; CSR deliberately does NOT (it would flip
-- vanilla managers.crime_spree:is_active() true and leak vanilla-CS behaviour --
-- feedback_csr_only_no_vanilla_leak). So under CSR the heist runs in the
-- "standard" gamemode, that block is skipped, the job package never loads, the
-- level geometry loads fine (level_package, from level_id) but the scripted
-- enemy units are absent -> the first timed/random ElementSpawnEnemyDummy spawn
-- hits an unloaded unit and the game access-violates.
--
-- FIX: replicate that exact block in a PostHook, gated on the temporary
-- "crime_spree" JOB (the run-scoped CSR signal) instead of the gamemode -- so the
-- enemy package loads without re-enabling the CS gamemode. Appends to the same
-- self._loaded_job_packages list GameSetup:unload_packages drains
-- (gamesetup.lua:500), so the package is freed on level exit like vanilla's.
--
-- No-leak: gated on Global.job_manager.current_job.job_id == "crime_spree". A
-- NORMAL heist (real job id) is skipped; vanilla CS (same job id, but the
-- gamemode block already loaded the package) re-scans and finds everything
-- loaded -> no-op. Only a CSR heist (crime_spree job + standard gamemode) gets
-- the otherwise-missing package loaded. NetworkGameSetup inherits load_packages
-- from GameSetup, so this one hook covers SP + MP host/client.

if not RequiredScript then
	return
end

if GameSetup and not _G._CSR_HEIST_PACKAGES_HOOKED then
	_G._CSR_HEIST_PACKAGES_HOOKED = true

	Hooks:PostHook(GameSetup, "load_packages", "CSR_LoadHeistJobPackages", function(self)
		local jm = Global and Global.job_manager
		local cur = jm and jm.current_job
		if not cur or cur.job_id ~= "crime_spree" then
			return
		end
		local level_id = Global.level_data and Global.level_data.level_id
		if not level_id then
			return
		end
		local jobs = tweak_data and tweak_data.narrative and tweak_data.narrative.jobs
		if not jobs then
			return
		end

		self._loaded_job_packages = self._loaded_job_packages or {}
		local loaded, matched = 0, 0
		-- Find every job whose chain contains the level being loaded and load its
		-- package -- the real heist's job (e.g. "branchbank") carries the scripted
		-- enemy units. The crime_spree temp job also matches but its package is
		-- nil/minimal; loading it (if any) is harmless. Verbose per-job logging (rare
		-- event -- once per level load, CSR path only) so a missing-package crash can
		-- be diagnosed: it shows whether ANY job matched the level and the fate of each
		-- package (loaded / already-loaded / missing).
		for job_id, data in pairs(jobs) do
			for _, level_data in ipairs(data.chain or {}) do
				if level_data.level_id == level_id then
					matched = matched + 1
					local package = data.package
					if not package then
						log("[CSR] heist_packages: job '" .. tostring(job_id) .. "' matches but has NO package")
					elseif not PackageManager:package_exists(package) then
						log(
							"[CSR] heist_packages: job '"
								.. tostring(job_id)
								.. "' package '"
								.. tostring(package)
								.. "' does NOT exist"
						)
					elseif PackageManager:loaded(package) then
						log(
							"[CSR] heist_packages: job '"
								.. tostring(job_id)
								.. "' package '"
								.. tostring(package)
								.. "' already loaded"
						)
					elseif not table.contains(self._loaded_job_packages, package) then
						table.insert(self._loaded_job_packages, package)
						PackageManager:load(package)
						loaded = loaded + 1
						log(
							"[CSR] heist_packages: LOADED '"
								.. tostring(package)
								.. "' (job '"
								.. tostring(job_id)
								.. "')"
						)
					end
				end
			end
		end
		log(
			"[CSR] heist_packages: level '"
				.. tostring(level_id)
				.. "': "
				.. matched
				.. " job(s) matched, "
				.. loaded
				.. " package(s) newly loaded"
		)
	end)
end

-- Spawn safety net for scripted enemies. Even with the job-package loader above,
-- some heists (e.g. First World Bank / red2) reach an ElementSpawnEnemyDummy whose
-- enemy unit isn't in any loaded package -> vanilla produce()'s safe_spawn_unit
-- native-AVs (safe_spawn_unit is NOT safe: editor_load_unit returns true without
-- loading; and a native AV can't be caught with pcall -- dynamic-loading the unit
-- here crashes the same way, because its source package isn't mounted). So this wrap
-- (CSR-run-gated, no vanilla leak) checks the unit is loaded right before vanilla
-- spawns it; if NOT, it SUBSTITUTES the always-loaded default SWAT (so the encounter
-- stays populated instead of leaving a hole) and only SKIPS the spawn if even that is
-- unavailable -- never crashing. The original unit's key is logged so the genuinely
-- missing unit can still be identified later. tostring(name) is the readable path
-- when BLT's idstring reverse-lookup knows it; the key() hex is the fallback id.
if ElementSpawnEnemyDummy and not _G._CSR_SPAWN_SAFETY_HOOKED then
	_G._CSR_SPAWN_SAFETY_HOOKED = true
	local UNIT_EXT = Idstring("unit")
	-- Engine default enemy (ElementSpawnEnemyDummy:init's own fallback). Lives in
	-- packages/game_base, which GameSetup:load_packages always loads, so it is safe
	-- to spawn in any heist. Still has-gated below in case a teardown frees it.
	local DEFAULT_ENEMY = Idstring("units/payday2/characters/ene_swat_1/ene_swat_1")
	local orig_produce = ElementSpawnEnemyDummy.produce
	if orig_produce then
		function ElementSpawnEnemyDummy:produce(params)
			local mgr = managers and managers.csr
			if mgr and mgr.is_run_active and mgr:is_run_active() then
				local name = (params and params.name) or self:value("enemy") or self._enemy_name
				if name then
					-- name is an Idstring (self._enemy_name) or a string (params.name).
					local name_ids = type(name) == "userdata" and name or Idstring(tostring(name))
					if not PackageManager:has(UNIT_EXT, name_ids) then
						if not PackageManager:has(UNIT_EXT, DEFAULT_ENEMY) then
							log(
								"[CSR] spawn-safety: SKIPPED unloaded enemy unit '"
									.. tostring(name)
									.. "' (key="
									.. tostring(name_ids:key())
									.. "); default SWAT also unavailable"
							)
							return
						end
						log(
							"[CSR] spawn-safety: substituting default SWAT for unloaded enemy unit '"
								.. tostring(name)
								.. "' (key="
								.. tostring(name_ids:key())
								.. ")"
						)
						if params and params.name then
							-- Group-AI spawn path (vanilla reads params.name): copy params
							-- and swap the unit so the rest of the spawn data is preserved.
							local p = {}
							for k, v in pairs(params) do
								p[k] = v
							end
							p.name = DEFAULT_ENEMY
							return orig_produce(self, p)
						end
						-- Scripted path (vanilla reads self._enemy_name + applies the
						-- element's team / voice / spawn_action): swap the unit, run, then
						-- restore so a later spawn from this element is unaffected.
						local saved = self._enemy_name
						self._enemy_name = DEFAULT_ENEMY
						local ok, unit = pcall(orig_produce, self, params)
						self._enemy_name = saved
						if ok then
							return unit
						end
						return
					end
				end
			end
			return orig_produce(self, params)
		end
	end
end

log("[CSR] heist_packages.lua loaded (GameSetup job-package loader + spawn safety net)")

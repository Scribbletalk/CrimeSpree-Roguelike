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
		local loaded = 0
		-- Find every job whose chain contains the level being loaded and load its
		-- package -- the real heist's job (e.g. "framing_frame") carries the
		-- scripted enemy units. The crime_spree temp job also matches but its
		-- package is nil/minimal; loading it (if any) is harmless.
		for _, data in pairs(jobs) do
			for _, level_data in ipairs(data.chain or {}) do
				if level_data.level_id == level_id then
					local package = data.package
					if
						package
						and PackageManager:package_exists(package)
						and not PackageManager:loaded(package)
						and not table.contains(self._loaded_job_packages, package)
					then
						table.insert(self._loaded_job_packages, package)
						PackageManager:load(package)
						loaded = loaded + 1
					end
				end
			end
		end
		log("[CSR] heist_packages: loaded " .. loaded .. " job package(s) for level '" .. tostring(level_id) .. "'")
	end)
end

log("[CSR] heist_packages.lua loaded (GameSetup job-package loader)")

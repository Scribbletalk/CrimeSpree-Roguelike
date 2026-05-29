-- Fixes "heists crash on enemy spawn": loads the job package CSR never gets (vanilla
-- gates it on crime_spree gamemode), then substitutes default SWAT for any unloaded unit.

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
		for job_id, data in pairs(jobs) do
			for _, level_data in ipairs(data.chain or {}) do
				if level_data.level_id == level_id then
					matched = matched + 1
					local package = data.package
					if not package then
						csr_log("[CSR] heist_packages: job '" .. tostring(job_id) .. "' matches but has NO package")
					elseif not PackageManager:package_exists(package) then
						csr_log("[CSR] heist_packages: job '" .. tostring(job_id) .. "' package missing")
					elseif PackageManager:loaded(package) then
						csr_log("[CSR] heist_packages: job '" .. tostring(job_id) .. "' package already loaded")
					elseif not table.contains(self._loaded_job_packages, package) then
						table.insert(self._loaded_job_packages, package)
						PackageManager:load(package)
						loaded = loaded + 1
						csr_log("[CSR] heist_packages: LOADED '" .. tostring(package) .. "'")
					end
				end
			end
		end
		csr_log(
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

-- Substitute default SWAT for any unloaded unit; skip entirely if even SWAT is missing.
if ElementSpawnEnemyDummy and not _G._CSR_SPAWN_SAFETY_HOOKED then
	_G._CSR_SPAWN_SAFETY_HOOKED = true
	local UNIT_EXT = Idstring("unit")
	local DEFAULT_ENEMY = Idstring("units/payday2/characters/ene_swat_1/ene_swat_1")
	local orig_produce = ElementSpawnEnemyDummy.produce
	if orig_produce then
		function ElementSpawnEnemyDummy:produce(params)
			local mgr = managers and managers.csr
			if mgr and mgr.is_run_active and mgr:is_run_active() then
				local name = (params and params.name) or self:value("enemy") or self._enemy_name
				if name then
					local name_ids = type(name) == "userdata" and name or Idstring(tostring(name))
					if not PackageManager:has(UNIT_EXT, name_ids) then
						if not PackageManager:has(UNIT_EXT, DEFAULT_ENEMY) then
							csr_log(
								"[CSR] spawn-safety: SKIPPED unloaded enemy '"
									.. tostring(name)
									.. "' (key="
									.. tostring(name_ids:key())
									.. "); default SWAT also unavailable"
							)
							return
						end
						csr_log(
							"[CSR] spawn-safety: substituting default SWAT for unloaded '"
								.. tostring(name)
								.. "' (key="
								.. tostring(name_ids:key())
								.. ")"
						)
						if params and params.name then
							-- Group-AI path uses params.name; scripted path uses self._enemy_name.
							local p = {}
							for k, v in pairs(params) do
								p[k] = v
							end
							p.name = DEFAULT_ENEMY
							return orig_produce(self, p)
						end
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

csr_log("[CSR] heist_packages.lua loaded")

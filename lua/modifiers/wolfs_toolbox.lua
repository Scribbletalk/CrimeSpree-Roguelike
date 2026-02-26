-- Wolf's Toolbox - Wolf's set of tools
-- Kills speed up drills and saws
-- Uncommon item (green)

if not RequiredScript then
	return
end



-- Inherit from CSRBaseModifier (standalone base class with no side effects)
ModifierWolfsToolbox = ModifierWolfsToolbox or class(CSRBaseModifier)

-- Custom desc_id for localization
ModifierWolfsToolbox.desc_id = "csr_wolfs_toolbox_desc"

-- Custom icon
ModifierWolfsToolbox.icon = "csr_toolbox"


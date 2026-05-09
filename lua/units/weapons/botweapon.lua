-- Crime Spree Roguelike - Bot weapon damage passive progression
-- Marks bot weapons at setup, then multiplies dmg_mul on fire.
-- Bots get +1% damage per CS level.

if not RequiredScript then
	return
end

local C = _G.CSR_ItemConstants or {}
local BOT_DMG_PER_LEVEL = C.bot_damage_per_level or 0.01 -- +1% per CS level

-- Mark weapons belonging to AI teammates at setup time.
-- Previous heuristic (`owner ~= local_player_unit`) misclassified REMOTE
-- HUMAN players' weapons as bots on every other client, applying the +1%/level
-- bonus to their damage numbers locally. Damage resolution is server-
-- authoritative so the inflated damage didn't actually deal extra damage to
-- enemies, but visible damage numbers and kill animations on the observer
-- client got boosted incorrectly.
--
-- Now check the criminal-managers ai flag: managers.criminals tracks every
-- crew member with a data table that has `ai = true` for bots and false/nil
-- for human-controlled criminals. Falls back to the old heuristic only if the
-- data lookup fails (defensive — managers.criminals should always be ready
-- by the time NewRaycastWeaponBase:setup fires).
Hooks:PostHook(NewRaycastWeaponBase, "setup", "CSR_BotWeaponMark", function(self)
	local owner = self._setup and self._setup.user_unit
	if not alive(owner) then
		return
	end
	local is_bot = false
	if managers.criminals and managers.criminals.character_data_by_unit then
		local ok, data = pcall(managers.criminals.character_data_by_unit, managers.criminals, owner)
		if ok and data and data.ai then
			is_bot = true
		end
	end
	if is_bot then
		self._csr_is_bot_weapon = true
	end
end)

-- Function override required: PreHook cannot modify parameters,
-- PostHook cannot modify parameters either.
-- dmg_mul must be scaled before NewRaycastWeaponBase.fire runs.
local _original_fire = NewRaycastWeaponBase.fire
_G.CSR_SafeOverride(
	NewRaycastWeaponBase,
	"fire",
	"Bot Damage",
	_original_fire,
	function(self, from_pos, direction, dmg_mul, ...)
		if self._csr_is_bot_weapon and managers.crime_spree and managers.crime_spree:is_active() then
			local spree_level = (_G.CSR_MP and CSR_MP.is_client and CSR_MP.is_client() and _G.CSR_MP_HostRank)
				or managers.crime_spree:spree_level()
				or 0
			if spree_level > 0 then
				dmg_mul = (dmg_mul or 1) * (1 + BOT_DMG_PER_LEVEL * spree_level)
			end
		end
		return _original_fire(self, from_pos, direction, dmg_mul, ...)
	end
)

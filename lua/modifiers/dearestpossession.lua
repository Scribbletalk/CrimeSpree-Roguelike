-- DEAREST POSSESSION - Overheal to temporary armor
-- When healed at full HP, excess healing converts to temporary bonus armor.
-- Armor cap: 50% of base MaxArmor per stack.
-- Armor decays at 20% per second.

if not RequiredScript then
	return
end



ModifierDearestPossession = ModifierDearestPossession or class(CSRBaseModifier)
ModifierDearestPossession.desc_id = "csr_dearest_possession_desc"

local DECAY_RATE = 0.20  -- 20% of current bonus per second

-- == DETECTION: Override set_health to intercept ALL heal sources ==
-- set_health receives the raw (uncapped) value, cap happens inside vanilla.
-- If the intended new HP exceeds base max HP → overheal → convert excess to armor.
local original_set_health = PlayerDamage.set_health

function PlayerDamage:set_health(health)
	if self._csr_dp_in_set_health then
		return original_set_health(self, health)
	end

	if CSR_ActiveBuffs and CSR_ActiveBuffs.dearest_possession then
		local base_fn = _G.CSR_Original_MaxHealth
		local base_max_hp = base_fn and (base_fn(self) * (self._max_health_reduction or 1))

		if base_max_hp and health > base_max_hp then
			local stacks = CSR_ActiveBuffs.dearest_possession
			local base_armor = _G.CSR_Original_MaxArmor and _G.CSR_Original_MaxArmor(self) or self:_max_armor()
			local armor_cap = base_armor * 0.5 * stacks

			local current_bonus = self._csr_dp_armor or 0
			local excess = health - base_max_hp
			local new_bonus = math.min(armor_cap, current_bonus + excess)

			if new_bonus > current_bonus then
				self._csr_dp_armor = new_bonus
				self._csr_dp_in_set_health = true
				self:set_armor(self:_max_armor())
				self._csr_dp_in_set_health = false
			end

			self._csr_dp_in_set_health = true
			original_set_health(self, base_max_hp)
			self._csr_dp_in_set_health = false
			return
		end
	end

	original_set_health(self, health)
end

-- == DECAY: Armor bonus loses 20% per second ==
Hooks:PostHook(PlayerDamage, "update", "CSR_DearestPossession_Decay", function(self, unit, t, dt)
	if not CSR_ActiveBuffs or not CSR_ActiveBuffs.dearest_possession then return end
	local bonus = self._csr_dp_armor
	if not bonus or bonus <= 0 then return end

	local decayed = bonus * DECAY_RATE * dt
	self._csr_dp_armor = math.max(0, bonus - decayed)

	-- Clamp current armor to new effective max if needed
	local current_armor = self:get_real_armor()
	local new_max = self:_max_armor()
	if current_armor > new_max then
		self:set_armor(new_max)
	end
end)

-- == INIT: Reset bonus on player spawn ==
Hooks:PostHook(PlayerDamage, "init", "CSR_DearestPossession_Init", function(self)
	self._csr_dp_armor = 0
end)


extends RefCounted
class_name CombatRules

## Shared non-scheduling combat math. Action timing lives in authored action
## resources, not an enum ledger.

const UNARMED_FLESH_BASE: float = 0.75
const UNARMED_FLESH_PER_BRAWN: float = 0.125
const UNARMED_BALANCE_BASE: float = 1.0
const UNARMED_BALANCE_PER_BRAWN: float = 0.25
const UNARMED_ARMOR_FACTOR: float = 0.35


static func get_unarmed_damage(
	attacker_brawn: int,
	defender_blunt_protection: float,
	_defender_bulk: float
) -> Dictionary:
	var brawn := clampf(float(attacker_brawn), 1.0, GameEnums.SCALE_MAX)
	var raw_flesh := UNARMED_FLESH_BASE + brawn * UNARMED_FLESH_PER_BRAWN
	var raw_balance := UNARMED_BALANCE_BASE + brawn * UNARMED_BALANCE_PER_BRAWN
	return {
		"flesh": maxf(0.1, raw_flesh - maxf(0.0, defender_blunt_protection) * UNARMED_ARMOR_FACTOR),
		"balance_impact": maxf(1.0, raw_balance),
	}

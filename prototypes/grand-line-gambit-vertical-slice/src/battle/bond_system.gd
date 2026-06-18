# VERTICAL SLICE - NOT FOR PRODUCTION
# Validation Question: 共享羁绊槽充能节奏 + 相邻爆发配对（核心循环本体）
# Date: 2026-06-18
#
# 共享羁绊槽（全队一条，战斗内跨回合保留）+ 相邻加成 + 爆发配对判定。
class_name BondSystem
extends RefCounted

var bond_gauge: int = 0

# 攻击充能：相邻 +2 / 单独 +1（订阅模型在切片中由 controller 直接调用）
func on_attack(attacker_id: int, attacker_adjacent_to_ally: bool) -> void:
	var amount: int = SliceConfig.CHARGE_ADJACENT if attacker_adjacent_to_ally else SliceConfig.CHARGE_SOLO
	bond_gauge = min(bond_gauge + amount, SliceConfig.BOND_GAUGE_MAX)
	EventBus.gauge_charged.emit(attacker_id, amount, bond_gauge)
	if bond_gauge >= SliceConfig.BOND_GAUGE_MAX:
		EventBus.bond_gauge_full.emit()

func is_full() -> bool:
	return bond_gauge >= SliceConfig.BOND_GAUGE_MAX

func reset() -> void:
	bond_gauge = 0

# 爆发配对 → effect_id + 伤害。lead/partner 必须相邻且不同。
static func burst_effect_for(lead_class: String, partner_class: String) -> StringName:
	var pair := [lead_class, partner_class]
	pair.sort()
	if pair == ["swordsman", "swordsman"]:
		return &"sword_sword"
	if pair == ["gunner", "swordsman"]:
		return &"sword_gunner"
	return &"generic"

static func burst_damage(effect_id: StringName) -> int:
	return SliceConfig.BURST_DAMAGE.get(String(effect_id), SliceConfig.BURST_DAMAGE["generic"])

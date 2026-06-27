# 套装档位纯函数 helper（②b-2a）。从 UnitInstance.equipment（{slot:def}）算各套件数/档位。
# 无状态、阵营无关、不依赖 RunManager；供 SetEffectSystem 读取。
class_name SetBonus
extends RefCounted

# 各套持有件数 {set_id → count}（仅含 ≥1；无 set_id 的件不计）。
static func count_sets(unit: UnitInstance) -> Dictionary:
	var counts: Dictionary = {}
	if unit == null:
		return counts
	for slot in unit.equipment:
		var def: EquipmentDefinition = unit.equipment[slot]
		if def != null and def.set_id != "":
			counts[def.set_id] = int(counts.get(def.set_id, 0)) + 1
	return counts

# 某套某档是否激活（累加语义：持有件数 ≥ threshold）。
static func is_tier_active(unit: UnitInstance, set_id: String, threshold: int) -> bool:
	return int(count_sets(unit).get(set_id, 0)) >= threshold

# 敌方招牌套配装助手（enemy-loadout）：纯静态，无状态。
# 原型 behavior_type → 招牌套 set_id；地图 island_tier → 件数 N（取该套前 N 个 slot）。
# 复用既有装备/套装引擎：返回的 {slot:int → EquipmentDefinition} 直接喂 UnitInstance.from_definition。
class_name EnemyLoadout
extends RefCounted

# 原型 → 阵营无关招牌套（避开寒霜：玩家无寒霜结算入口）。
const ARCHETYPE_SET := {
	"GUARDIAN": "set_ironwall",
	"MELEE": "set_bloodthirst",
	"SWARMER": "set_thorns",
	"RANGED": "set_executioner",
}

# island_tier → 件数（1/2/3→0/3/6；≥4→9；≤0→0）。
const TIER_PIECES := {1: 0, 2: 3, 3: 6}

# 取件 slot 顺序（对应 eq_<set>_<slotname>，EquipmentDefinition.slot 枚举 0..8 同序）。
const SLOT_NAMES := ["mainweapon", "offweapon", "head", "armor", "gloves", "legs", "boots", "ring", "necklace"]

# 招牌套前 N 件 → {slot:int → EquipmentDefinition}。未知原型 / N≤0 → 空。
static func for_enemy(behavior_type: String, island_tier: int) -> Dictionary:
	var out: Dictionary = {}
	var set_id: String = ARCHETYPE_SET.get(behavior_type, "")
	if set_id == "":
		return out
	var n := _pieces_for_tier(island_tier)
	if n <= 0:
		return out
	var set_short := set_id.trim_prefix("set_")
	for i in range(mini(n, SLOT_NAMES.size())):
		var eid := "eq_%s_%s" % [set_short, SLOT_NAMES[i]]
		var def := EquipmentDataManager.get_equipment(eid)
		if def != null:
			out[def.slot] = def
	return out

static func _pieces_for_tier(island_tier: int) -> int:
	if TIER_PIECES.has(island_tier):
		return int(TIER_PIECES[island_tier])
	return 9 if island_tier >= 4 else 0

# 一次性数据生成器：删旧装备 .tres，按 8 套 × 9 槽生成 72 件。
# 运行：godot --headless --script res://tools/gen_equipment_sets.gd
@tool
extends SceneTree

const OUT_DIR := "res://assets/data/equipment/"
const SLOT_KEYS := ["mainweapon", "offweapon", "head", "armor", "gloves", "legs", "boots", "ring", "necklace"]
const SLOT_NOUNS := ["刃", "盾", "盔", "甲", "护手", "护腿", "战靴", "戒", "坠"]
const SLOT_RARITY := [2, 1, 0, 2, 0, 0, 1, 3, 1]   # slot0..8 稀有度（所有套统一）
const STAT_BY_RARITY := {
	"hp": [2, 4, 6, 8, 10],
	"damage": [1, 2, 3, 4, 5],
	"range": [1, 1, 2, 2, 3],
	"move": [1, 1, 2, 2, 3],
}
const SETS := [
	{"id": "set_ironwall", "name": "铁壁", "stat": "hp"},
	{"id": "set_berserker", "name": "狂战", "stat": "damage"},
	{"id": "set_healer", "name": "医者", "stat": "hp"},
	{"id": "set_navigator", "name": "航海", "stat": "move"},
	{"id": "set_bloodthirst", "name": "嗜血", "stat": "damage"},
	{"id": "set_thorns", "name": "荆棘", "stat": "hp"},
	{"id": "set_executioner", "name": "处决", "stat": "damage"},
	{"id": "set_frost", "name": "寒霜", "stat": "range"},
]

func _init() -> void:
	_delete_old()
	var n := 0
	for s in SETS:
		for slot in range(9):
			var def := EquipmentDefinition.new()
			var short: String = (s["id"] as String).trim_prefix("set_")
			def.id = "eq_%s_%s" % [short, SLOT_KEYS[slot]]
			def.display_name = "%s%s" % [s["name"], SLOT_NOUNS[slot]]
			def.slot = slot
			def.rarity = SLOT_RARITY[slot]
			def.set_id = s["id"]
			var stat: String = s["stat"]
			var val: int = STAT_BY_RARITY[stat][def.rarity]
			def.hp_bonus = val if stat == "hp" else 0
			def.damage_bonus = val if stat == "damage" else 0
			def.range_bonus = val if stat == "range" else 0
			def.move_bonus = val if stat == "move" else 0
			var path := OUT_DIR + def.id + ".tres"
			var err := ResourceSaver.save(def, path)
			assert(err == OK, "保存失败 %s err=%d" % [path, err])
			n += 1
	print("生成装备 %d 件" % n)
	quit()

func _delete_old() -> void:
	var dir := DirAccess.open(OUT_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".tres") or f.ends_with(".tres.import") or f.ends_with(".tres.uid"):
			dir.remove(f)
		f = dir.get_next()

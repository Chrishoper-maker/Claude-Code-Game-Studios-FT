# 装备数据管理器（autoload）。启动扫描 res://assets/data/equipment/ 下全部 .tres，校验后缓存。
# 失败快速：结构错误 → push_error + 清空 → get_all_equipment() 返回 []。
# （autoload 脚本不声明 class_name：注册名 EquipmentDataManager 即全局单例访问）
extends Node

const EQUIPMENT_DATA_PATH := "res://assets/data/equipment/"

var _cache: Dictionary = {}                     # String id → EquipmentDefinition
var _all: Array[EquipmentDefinition] = []
var is_loaded: bool = false

func _ready() -> void:
	_scan_and_load()

func get_equipment(id: String) -> EquipmentDefinition:
	return _cache.get(id, null)

func get_all_equipment() -> Array[EquipmentDefinition]:
	return _all if is_loaded else []

# 按稀有度过滤（Rarity 枚举值）。
func get_equipment_by_rarity(rarity: int) -> Array[EquipmentDefinition]:
	var out: Array[EquipmentDefinition] = []
	for def in get_all_equipment():
		if def.rarity == rarity:
			out.append(def)
	return out

# 按装备槽过滤（Slot 枚举值）。
func get_equipment_by_slot(slot: int) -> Array[EquipmentDefinition]:
	var out: Array[EquipmentDefinition] = []
	for def in get_all_equipment():
		if def.slot == slot:
			out.append(def)
	return out

func _scan_and_load() -> void:
	var dir := DirAccess.open(EQUIPMENT_DATA_PATH)
	if dir == null:
		push_error("EquipmentData parse error: %s — 目录无法打开" % EQUIPMENT_DATA_PATH)
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".tres"):
			var path := EQUIPMENT_DATA_PATH + fname
			var res := ResourceLoader.load(path)
			if res == null:
				push_error("EquipmentData parse error: %s — ResourceLoader 返回 null" % path)
			elif not (res is EquipmentDefinition):
				push_error("EquipmentData parse error: %s — 非 EquipmentDefinition 类型" % path)
			else:
				_all.append(res as EquipmentDefinition)
		fname = dir.get_next()
	_validate_all()

func _validate_all() -> void:
	var seen_ids: Dictionary = {}
	var has_error := false
	for def in _all:
		if def.id in seen_ids:
			push_error("EquipmentData validation error: %s — 重复 id" % def.id)
			has_error = true
		else:
			seen_ids[def.id] = true
		if def.rarity < 0 or def.rarity > EquipmentDefinition.Rarity.LEGENDARY:
			push_error("EquipmentData validation error: %s — rarity 越界 %d" % [def.id, def.rarity])
			has_error = true
		if def.slot < 0 or def.slot > EquipmentDefinition.Slot.NECKLACE:
			push_error("EquipmentData validation error: %s — slot 越界 %d" % [def.id, def.slot])
			has_error = true
	if not has_error:
		for def in _all:
			_cache[def.id] = def
		is_loaded = true
	else:
		_all.clear()

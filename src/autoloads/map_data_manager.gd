# 地图数据管理器（autoload #3，ADR-0003）。
# 在 UnitDataManager 之后初始化：校验期需用 UnitDataManager.get_unit() 交叉核对 enemy_roster。
# （autoload 脚本不声明 class_name：注册名 MapDataManager 即全局单例访问）
extends Node

const MAPS_DATA_PATH := "res://assets/data/maps/"

var _cache: Dictionary = {}                          # String map_id → MapDefinition
var _by_tier: Dictionary = {}                        # int island_tier → Array[MapDefinition]
var is_loaded: bool = false

func _ready() -> void:
	_scan_and_load()

func get_map(map_id: String) -> MapDefinition:
	return _cache.get(map_id, null)

func get_maps_for_tier(island_tier: int) -> Array[MapDefinition]:
	return _by_tier.get(island_tier, [] as Array[MapDefinition])

# 全部已加载地图（任意顺序）；选航降级抽取用。
func get_all_maps() -> Array[MapDefinition]:
	var out: Array[MapDefinition] = []
	for v in _cache.values():
		out.append(v as MapDefinition)
	return out

func _scan_and_load() -> void:
	var dir := DirAccess.open(MAPS_DATA_PATH)
	if dir == null:
		push_error("MapData parse error: %s — 目录无法打开" % MAPS_DATA_PATH)
		return
	var loaded: Array[MapDefinition] = []
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".tres"):
			var path := MAPS_DATA_PATH + fname
			var res := ResourceLoader.load(path)
			if res == null:
				push_error("MapData parse error: %s — ResourceLoader 返回 null" % path)
			elif not (res is MapDefinition):
				push_error("MapData parse error: %s — 非 MapDefinition 类型" % path)
			else:
				loaded.append(res as MapDefinition)
		fname = dir.get_next()
	_validate_and_index(loaded)

func _validate_and_index(loaded: Array[MapDefinition]) -> void:
	var seen_ids: Dictionary = {}
	var has_error := false
	for def in loaded:
		if def.map_id in seen_ids:
			push_error("MapData validation error: %s — map_id — 重复 map_id" % def.map_id)
			has_error = true
			continue
		seen_ids[def.map_id] = true
		# 交叉校验：每个 enemy_roster 槽的 unit_definition_id 须在 UnitDataManager 中存在
		for slot in def.enemy_roster:
			if UnitDataManager.get_unit(slot.unit_definition_id) == null:
				push_error("MapData validation error: %s — enemy_roster — 未知 unit_definition_id [%s]" % [
					def.map_id, slot.unit_definition_id])
				has_error = true
	if has_error:
		return                              # 结构错误 → 不填缓存，is_loaded 保持 false
	for def in loaded:
		_cache[def.map_id] = def
		if not _by_tier.has(def.island_tier):
			_by_tier[def.island_tier] = [] as Array[MapDefinition]
		_by_tier[def.island_tier].append(def)
	is_loaded = true

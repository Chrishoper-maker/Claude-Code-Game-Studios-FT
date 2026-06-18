# 单位数据管理器（autoload #2，ADR-0003）。
# 启动时扫描 res://assets/data/units/ 下全部 .tres，校验后缓存。
# 失败快速：结构错误 → push_error + 清空 → get_all_units() 返回 []（下游拒绝进战斗）。
# （autoload 脚本不声明 class_name：注册名 UnitDataManager 即全局单例访问，避免与 class_name 撞名）
extends Node

const UNITS_DATA_PATH := "res://assets/data/units/"

var _cache: Dictionary = {}                 # String id → UnitDefinition
var _all: Array[UnitDefinition] = []
var is_loaded: bool = false                 # 任一结构错误则 false

func _ready() -> void:
	_scan_and_load()

func get_unit(id: String) -> UnitDefinition:
	return _cache.get(id, null)             # 未找到返回 null

func get_all_units() -> Array[UnitDefinition]:
	return _all if is_loaded else []        # 空数组向调用方表示加载失败

func _scan_and_load() -> void:
	var dir := DirAccess.open(UNITS_DATA_PATH)
	if dir == null:
		push_error("UnitData parse error: %s — 目录无法打开" % UNITS_DATA_PATH)
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".tres"):
			var path := UNITS_DATA_PATH + fname
			var res := ResourceLoader.load(path)
			if res == null:
				push_error("UnitData parse error: %s — ResourceLoader 返回 null" % path)
			elif not (res is UnitDefinition):
				push_error("UnitData parse error: %s — 非 UnitDefinition 类型" % path)
			else:
				_all.append(res as UnitDefinition)
		fname = dir.get_next()
	_validate_all()

func _validate_all() -> void:
	var seen_ids: Dictionary = {}
	var has_error := false
	for def in _all:
		if def.id in seen_ids:
			push_error("UnitData validation error: %s — id — 重复 id" % def.id)
			has_error = true
		else:
			seen_ids[def.id] = true
		# 其余 GDD 校验规则（unit_class 枚举等）在此追加。
	if not has_error:
		for def in _all:
			_cache[def.id] = def
		is_loaded = true
	else:
		_all.clear()        # 结构错误 → get_all_units() 暴露空数组

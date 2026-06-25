# 运行时单位实例（unit-data-system GDD 第5节）。
# 非 Resource：战斗开始时由 UnitDefinition 模板生成，持有模板引用 + 可变状态。
# 字段清单归 unit-data-system；**变更规则归回合管理与战斗解算，本类不含改值逻辑**。
# Downed 由 is_alive==false 表达（无 is_downed 字段，跨系统契约）。
class_name UnitInstance
extends RefCounted

const SENTINEL_POS := Vector2i(-1, -1)  # Downed / 未部署 哨兵（同 grid-board sentinel）

var definition: UnitDefinition          # 模板引用（只读基底数值来源）
var current_hp: int
var grid_position: Vector2i
var has_moved: bool
var has_acted: bool
var has_used_verb: bool
var is_alive: bool
var behavior_type: String               # 部署时由 BattleMap 写入（敌方行为原型）
var home_pos: Vector2i                   # GUARDIAN 守位锚点；非守卫型为哨兵
var equipment: Dictionary = {}   # slot(int) → EquipmentDefinition（仅 crew；敌方/无装备为空）

# 由模板生成运行时实例（unit-data-system 第5节 + 初始化规则）。
# equipment 为 {slot:int → EquipmentDefinition}，默认空。
static func from_definition(def: UnitDefinition, equipment: Dictionary = {}) -> UnitInstance:
	var inst := UnitInstance.new()
	inst.definition = def
	inst.equipment = equipment
	inst.current_hp = inst.get_max_hp()          # 初始 = 有效 max_hp（含装备）
	inst.grid_position = SENTINEL_POS            # 部署时写入真实格
	inst.has_moved = false
	inst.has_acted = false
	# 无职业动词（class_action_id="" 等价 null）→ has_used_verb 初始 true
	inst.has_used_verb = def.class_action_id == ""
	inst.is_alive = true
	inst.behavior_type = ""                      # 部署时由 BattleMap 覆盖
	inst.home_pos = SENTINEL_POS
	return inst

# 持久身份（字符串蛇形 id，取自模板；数值 battle_id 归回合管理系统，不在此）。
func get_unit_id() -> String:
	return definition.id

# 所有已装槽某增量字段之和（hp_bonus/damage_bonus/range_bonus/move_bonus）。
func _equipment_bonus(field: String) -> int:
	var total := 0
	for s in equipment:
		var eq: EquipmentDefinition = equipment[s]
		if eq != null:
			total += int(eq.get(field))
	return total

# ── 有效值（基值 + 装备增量，下限钳 0）。战斗逻辑应读这些而非 definition.X ──
func get_max_hp() -> int:
	return maxi(0, definition.max_hp + _equipment_bonus("hp_bonus"))

func get_base_damage() -> int:
	return maxi(0, definition.base_damage + _equipment_bonus("damage_bonus"))

func get_attack_range() -> int:
	return maxi(0, definition.attack_range + _equipment_bonus("range_bonus"))

func get_move_range() -> int:
	return maxi(0, definition.move_range + _equipment_bonus("move_bonus"))

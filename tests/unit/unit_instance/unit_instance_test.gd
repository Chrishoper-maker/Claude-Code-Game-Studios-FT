# UnitInstance 工厂初始化测试（unit-data-system GDD 第5节运行时实例 + 初始化规则）。
# UnitInstance 是非 Resource 数据持有类，唯一逻辑是 from_definition 初始化；
# 字段变更规则归回合管理/战斗解算，本类不含改值逻辑（故仅测初始化）。
# TDD：先于实现写就。
extends GdUnitTestSuite

func _def(class_action_id: String = "", max_hp: int = 8, id: String = "u_test") -> UnitDefinition:
	var d := UnitDefinition.new()
	d.id = id
	d.max_hp = max_hp
	d.class_action_id = class_action_id
	return d

# current_hp 初始 = max_hp（unit-data-system 第5节）
func test_from_definition_current_hp_equals_max_hp() -> void:
	var inst := UnitInstance.from_definition(_def("", 11))
	assert_int(inst.current_hp).is_equal(11)

# is_alive=true、has_moved/has_acted=false（初始化规则）
func test_from_definition_alive_and_action_flags_reset() -> void:
	var inst := UnitInstance.from_definition(_def("slash"))
	assert_bool(inst.is_alive).is_true()
	assert_bool(inst.has_moved).is_false()
	assert_bool(inst.has_acted).is_false()

# 无职业动词（class_action_id="" 等价 null）→ has_used_verb 初始 true
func test_no_verb_unit_has_used_verb_true() -> void:
	var inst := UnitInstance.from_definition(_def(""))
	assert_bool(inst.has_used_verb).is_true()

# 有职业动词 → has_used_verb 初始 false
func test_verb_unit_has_used_verb_false() -> void:
	var inst := UnitInstance.from_definition(_def("slash"))
	assert_bool(inst.has_used_verb).is_false()

# grid_position 初始为哨兵 Vector2i(-1,-1)（部署时由 BattleMap 写入真实格）
func test_initial_grid_position_is_sentinel() -> void:
	var inst := UnitInstance.from_definition(_def())
	assert_vector(inst.grid_position).is_equal(Vector2i(-1, -1))

# behavior_type/home_pos 默认（部署时由 BattleMap 覆盖）
func test_initial_behavior_defaults() -> void:
	var inst := UnitInstance.from_definition(_def())
	assert_str(inst.behavior_type).is_equal("")
	assert_vector(inst.home_pos).is_equal(Vector2i(-1, -1))

# unit_id 取自模板持久身份（字符串蛇形 id）
func test_unit_id_from_definition() -> void:
	var inst := UnitInstance.from_definition(_def("", 8, "crew_azhan"))
	assert_str(inst.get_unit_id()).is_equal("crew_azhan")

# 引用模板（不复制），下游可读取基底数值
func test_holds_definition_reference() -> void:
	var d := _def("", 8, "u_ref")
	var inst := UnitInstance.from_definition(d)
	assert_object(inst.definition).is_same(d)

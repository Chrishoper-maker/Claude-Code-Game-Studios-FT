# TurnManager 单位注册表 + battle_id 分配测试（turn-management GDD §battle_id / §135 接口）。
# battle_id = 单场战斗的数值句柄（唯一、< 1000；grid_board 占用与先攻 tiebreak 用之）。
# 注册表填充 alive_list；行动标记写回 UnitInstance。先攻队列/轮次推进属后续故事，不在此测。
# TDD：先于实现写就。
extends GdUnitTestSuite

func _tm() -> TurnManager:
	return auto_free(TurnManager.new())

func _unit(faction: String, id: String, verb: String = "") -> UnitInstance:
	var d := UnitDefinition.new()
	d.id = id
	d.faction = faction
	d.max_hp = 8
	d.class_action_id = verb
	return UnitInstance.from_definition(d)

# battle_id 自 0 顺序分配，唯一
func test_register_assigns_sequential_battle_ids() -> void:
	var tm := _tm()
	var first := tm.register_unit(_unit("crew", "a"))
	var second := tm.register_unit(_unit("enemy", "b"))
	assert_int(first).is_equal(0)
	assert_int(second).is_equal(1)

# 注册后可按 battle_id 取回实例
func test_get_unit_returns_registered_instance() -> void:
	var tm := _tm()
	var u := _unit("crew", "a")
	var bid := tm.register_unit(u)
	assert_object(tm.get_unit(bid)).is_same(u)

# 注册即进 alive_list，按阵营分区查询
func test_alive_lists_partitioned_by_faction() -> void:
	var tm := _tm()
	var ally := tm.register_unit(_unit("crew", "a"))
	var enemy := tm.register_unit(_unit("enemy", "b"))
	assert_array(tm.get_alive_allies()).contains_exactly([ally])
	assert_array(tm.get_alive_enemies()).contains_exactly([enemy])

# remove_from_alive 将单位移出 alive_list
func test_remove_from_alive_removes_unit() -> void:
	var tm := _tm()
	var ally := tm.register_unit(_unit("crew", "a"))
	tm.register_unit(_unit("crew", "c"))
	tm.remove_from_alive(ally)
	assert_array(tm.get_alive_allies()).not_contains([ally])

# remove_from_alive 幂等（去重：重复调用安全、不抛错）
func test_remove_from_alive_idempotent() -> void:
	var tm := _tm()
	var ally := tm.register_unit(_unit("crew", "a"))
	tm.remove_from_alive(ally)
	tm.remove_from_alive(ally)  # 第二次不应崩溃
	assert_array(tm.get_alive_allies()).is_empty()

# 行动标记写回对应 UnitInstance
func test_mark_action_flags_write_to_instance() -> void:
	var tm := _tm()
	var u := _unit("crew", "a", "slash")  # 有动词 → has_used_verb 初始 false
	var bid := tm.register_unit(u)
	tm.mark_has_moved(bid)
	tm.mark_has_acted(bid)
	tm.mark_has_used_verb(bid)
	assert_bool(u.has_moved).is_true()
	assert_bool(u.has_acted).is_true()
	assert_bool(u.has_used_verb).is_true()

# 移出 alive 的单位不再计入任一阵营存活查询
func test_downed_unit_excluded_from_both_alive_lists() -> void:
	var tm := _tm()
	var enemy := tm.register_unit(_unit("enemy", "b"))
	tm.remove_from_alive(enemy)
	assert_array(tm.get_alive_enemies()).is_empty()
	assert_array(tm.get_alive_allies()).is_empty()

# BattleMap 部署阶段 + 状态机测试（battle-map-system GDD Rule 3 步骤2-5 / States）。
# 依赖注入真实 GridBoard + TurnManager（plain Node，非 mock）+ unit_lookup。
# TDD：先于实现写就。
extends GdUnitTestSuite

func _bm() -> BattleMap:
	return auto_free(BattleMap.new())

func _gb() -> GridBoard:
	return auto_free(GridBoard.new())

func _tm() -> TurnManager:
	return auto_free(TurnManager.new())

func _cell(pos: Vector2i, type: String = "BLOCKED") -> TerrainCell:
	var c := TerrainCell.new()
	c.pos = pos
	c.type = type
	return c

func _slot(id: String, pos: Vector2i, behavior: String = "MELEE", home := Vector2i(-1, -1)) -> EnemySlotDefinition:
	var s := EnemySlotDefinition.new()
	s.unit_definition_id = id
	s.grid_position = pos
	s.behavior_type = behavior
	s.home_pos = home
	return s

func _lookup() -> Callable:
	return func(id: String) -> UnitDefinition:
		var d := EnemyDefinition.new()
		d.id = id
		d.faction = "enemy"
		d.max_hp = 8
		d.threat_tier = 1
		return d

func _valid_map() -> MapDefinition:
	var m := MapDefinition.new()
	m.map_id = "test_map"
	m.island_tier = 1
	m.terrain_data = [_cell(Vector2i(1, 1)), _cell(Vector2i(1, 2)), _cell(Vector2i(5, 1)), _cell(Vector2i(5, 2))]
	var dz: Array[Vector2i] = []
	for x in range(0, 6):
		dz.append(Vector2i(x, 6))
		dz.append(Vector2i(x, 7))
	m.deploy_zone = dz
	m.enemy_roster = [
		_slot("e_melee", Vector2i(2, 0), "MELEE"),
		_slot("e_ranged", Vector2i(7, 0), "RANGED"),
		_slot("e_swarm", Vector2i(3, 3), "SWARMER"),
		_slot("e_guard", Vector2i(7, 3), "GUARDIAN", Vector2i(7, 3)),
	]
	return m

func _load_valid(bm: BattleMap, gb: GridBoard, tm: TurnManager) -> bool:
	return bm.load_map_definition(_valid_map(), gb, tm, _lookup())

# ── 加载成功路径 ──

func test_load_returns_true_and_state_ready() -> void:
	var bm := _bm()
	assert_bool(_load_valid(bm, _gb(), _tm())).is_true()
	assert_int(bm.get_map_state()).is_equal(BattleMap.MapState.MAP_READY)

func test_load_writes_blocked_terrain() -> void:
	var gb := _gb()
	_load_valid(_bm(), gb, _tm())
	# (1,1) 是 BLOCKED 且无敌人占用 → 不可进入
	assert_bool(gb.is_empty(Vector2i(1, 1))).is_false()
	assert_bool(gb.is_empty(Vector2i(5, 2))).is_false()
	# 无地形无占用格仍可进入
	assert_bool(gb.is_empty(Vector2i(4, 4))).is_true()

func test_load_deploys_enemies_onto_board() -> void:
	var gb := _gb()
	_load_valid(_bm(), gb, _tm())
	assert_int(gb.get_cell(Vector2i(2, 0))).is_not_equal(GridBoard.EMPTY)
	assert_int(gb.get_cell(Vector2i(7, 3))).is_not_equal(GridBoard.EMPTY)

func test_load_registers_all_enemies_alive() -> void:
	var tm := _tm()
	_load_valid(_bm(), _gb(), tm)
	assert_int(tm.get_alive_enemies().size()).is_equal(4)

func test_deployed_guardian_has_behavior_home_and_position() -> void:
	var tm := _tm()
	_load_valid(_bm(), _gb(), tm)
	# 敌人按 roster 顺序注册 → GUARDIAN 是第4个 → battle_id 3
	var guard := tm.get_unit(3)
	assert_str(guard.behavior_type).is_equal("GUARDIAN")
	assert_vector(guard.home_pos).is_equal(Vector2i(7, 3))
	assert_vector(guard.grid_position).is_equal(Vector2i(7, 3))

func test_load_emits_map_loaded_once() -> void:
	var count := [0]
	var cb := func(_id: String) -> void: count[0] += 1
	EventBus.map_loaded.connect(cb)
	_load_valid(_bm(), _gb(), _tm())
	EventBus.map_loaded.disconnect(cb)
	assert_int(count[0]).is_equal(1)

# ── 部署区查询 ──

func test_deploy_zone_available_after_load() -> void:
	var bm := _bm()
	_load_valid(bm, _gb(), _tm())
	assert_int(bm.get_deploy_zone_available().size()).is_equal(12)

func test_deploy_zone_subtracts_occupied() -> void:
	var bm := _bm()
	_load_valid(bm, _gb(), _tm())
	var avail := bm.get_deploy_zone_available([Vector2i(0, 6), Vector2i(1, 6)])
	assert_int(avail.size()).is_equal(10)
	assert_array(avail).not_contains([Vector2i(0, 6)])

# ── 验证失败路径 ──

func test_invalid_map_fails_no_terrain_written() -> void:
	var bm := _bm()
	var gb := _gb()
	var m := _valid_map()
	m.enemy_roster = [_slot("e_melee", Vector2i(2, 0))]  # 仅1敌 → F3 失败
	var ok := bm.load_map_definition(m, gb, _tm(), _lookup())
	assert_bool(ok).is_false()
	assert_int(bm.get_map_state()).is_equal(BattleMap.MapState.MAP_UNLOADED)
	assert_bool(gb.is_empty(Vector2i(1, 1))).is_true()  # 地形未写入

func test_invalid_map_emits_load_failed_with_reason() -> void:
	var reasons: Array[StringName] = []
	var cb := func(r: StringName) -> void: reasons.append(r)
	EventBus.map_load_failed.connect(cb)
	var m := _valid_map()
	m.enemy_roster = [_slot("e_melee", Vector2i(2, 0))]
	_bm().load_map_definition(m, _gb(), _tm(), _lookup())
	EventBus.map_load_failed.disconnect(cb)
	assert_array(reasons).contains([&"enemy_count_below_minimum"])

# ── 状态机转换 ──

func test_battle_started_transitions_to_active() -> void:
	var bm := _bm()
	_load_valid(bm, _gb(), _tm())
	bm.on_battle_started()
	assert_int(bm.get_map_state()).is_equal(BattleMap.MapState.MAP_ACTIVE)

func test_battle_won_transitions_to_resolved() -> void:
	var bm := _bm()
	_load_valid(bm, _gb(), _tm())
	bm.on_battle_started()
	bm.on_battle_won()
	assert_int(bm.get_map_state()).is_equal(BattleMap.MapState.MAP_RESOLVED)

func test_map_reset_clears_and_unloads() -> void:
	var bm := _bm()
	var gb := _gb()
	_load_valid(bm, gb, _tm())
	bm.on_battle_started()
	bm.on_battle_won()
	bm.on_map_reset()
	assert_int(bm.get_map_state()).is_equal(BattleMap.MapState.MAP_UNLOADED)
	assert_array(bm.get_deploy_zone_available()).is_empty()
	assert_bool(gb.is_empty(Vector2i(1, 1))).is_true()  # 地形已清

# EC-9：MAP_ACTIVE 拒绝新加载
func test_load_rejected_when_active() -> void:
	var bm := _bm()
	_load_valid(bm, _gb(), _tm())
	bm.on_battle_started()
	var ok := _load_valid(bm, _gb(), _tm())
	assert_bool(ok).is_false()
	assert_int(bm.get_map_state()).is_equal(BattleMap.MapState.MAP_ACTIVE)

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

# ── 玩家方部署 deploy_crew（battle-map deploy_zone 玩家侧；route-recruitment confirm_deploy 后端）──

func _crew(unit_class: String, base_damage: int = 3, hp: int = 10) -> CrewDefinition:
	var c := CrewDefinition.new()
	c.id = "crew_%s" % unit_class
	c.faction = "crew"
	c.unit_class = unit_class
	c.max_hp = hp
	c.base_damage = base_damage
	c.attack_range = 1
	c.move_range = 2
	c.class_action_id = "slash"
	return c

func _ready_map() -> Array:
	# 返回 [bm, gb, tm]，已加载到 MAP_READY（部署区 = rows6-7×cols0-5）。
	var bm := _bm()
	var gb := _gb()
	var tm := _tm()
	bm.load_map_definition(_valid_map(), gb, tm, _lookup())
	return [bm, gb, tm]

func test_deploy_crew_places_units_in_deploy_zone() -> void:
	var ctx := _ready_map()
	var bm: BattleMap = ctx[0]
	var gb: GridBoard = ctx[1]
	var tm: TurnManager = ctx[2]
	var ok := bm.deploy_crew([_crew("swordsman"), _crew("bulwark")], [Vector2i(0, 6), Vector2i(1, 6)])
	assert_bool(ok).is_true()
	assert_int(tm.get_alive_allies().size()).is_equal(2)
	assert_int(gb.get_cell(Vector2i(0, 6))).is_not_equal(GridBoard.EMPTY)
	assert_int(gb.get_cell(Vector2i(1, 6))).is_not_equal(GridBoard.EMPTY)

func test_deploy_crew_rejects_position_outside_deploy_zone() -> void:
	var ctx := _ready_map()
	var bm: BattleMap = ctx[0]
	var tm: TurnManager = ctx[2]
	var ok := bm.deploy_crew([_crew("swordsman")], [Vector2i(0, 0)])   # row0 不在部署区
	assert_bool(ok).is_false()
	assert_int(tm.get_alive_allies().size()).is_equal(0)

func test_deploy_crew_rejects_occupied_cell() -> void:
	var ctx := _ready_map()
	var bm: BattleMap = ctx[0]
	bm.deploy_crew([_crew("swordsman")], [Vector2i(0, 6)])
	var ok := bm.deploy_crew([_crew("bulwark")], [Vector2i(0, 6)])     # 同格已占
	assert_bool(ok).is_false()

func test_deploy_crew_rejects_duplicate_positions() -> void:
	var ctx := _ready_map()
	var bm: BattleMap = ctx[0]
	var ok := bm.deploy_crew([_crew("swordsman"), _crew("bulwark")], [Vector2i(0, 6), Vector2i(0, 6)])
	assert_bool(ok).is_false()

func test_deploy_crew_rejects_count_mismatch() -> void:
	var ctx := _ready_map()
	var bm: BattleMap = ctx[0]
	var ok := bm.deploy_crew([_crew("swordsman"), _crew("bulwark")], [Vector2i(0, 6)])
	assert_bool(ok).is_false()

func test_deploy_crew_rejects_when_not_map_ready() -> void:
	var bm := _bm()   # MAP_UNLOADED
	var ok := bm.deploy_crew([_crew("swordsman")], [Vector2i(0, 6)])
	assert_bool(ok).is_false()

func test_map_reset_removes_deployed_crew() -> void:
	var ctx := _ready_map()
	var bm: BattleMap = ctx[0]
	var gb: GridBoard = ctx[1]
	bm.deploy_crew([_crew("swordsman"), _crew("bulwark")], [Vector2i(0, 6), Vector2i(1, 6)])
	bm.on_battle_started()
	bm.on_battle_won()
	bm.on_map_reset()
	assert_int(gb.get_cell(Vector2i(0, 6))).is_equal(GridBoard.EMPTY)
	assert_int(gb.get_cell(Vector2i(1, 6))).is_equal(GridBoard.EMPTY)

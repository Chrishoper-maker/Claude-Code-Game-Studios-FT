# 装备经 deploy_crew 上场后，UnitInstance 有效值含加成（AC-7）。
# 通过 BattleMap.deploy_crew 端到端验证，覆盖 I-1 评审意见。
extends GdUnitTestSuite

# ── 辅助工厂（与 battle_map_deploy_test 保持一致） ──

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

func _ready_map() -> Array:
	# 返回 [bm, gb, tm]，已加载到 MAP_READY（部署区 = rows6-7×cols0-5）。
	var bm := _bm()
	var gb := _gb()
	var tm := _tm()
	bm.load_map_definition(_valid_map(), gb, tm, _lookup())
	return [bm, gb, tm]

func _crew_def(unit_class: String = "bulwark", hp: int = 12) -> CrewDefinition:
	var d := CrewDefinition.new()
	d.id = "eqtest_%s" % unit_class
	d.faction = "crew"
	d.unit_class = unit_class
	d.max_hp = hp
	d.base_damage = 2
	d.attack_range = 1
	d.move_range = 2
	d.class_action_id = "guard"
	d.recruit_pool_tier = "pool"
	return d

# ── 主测试：deploy_crew 携装备后 UnitInstance 有效血量含加成 ──

# AC-7：eq_plate 给 +3 HP；基值 12 → 期望 15。
func test_deploy_crew_with_equipment_applies_stat_bonus() -> void:
	var ctx := _ready_map()
	var bm: BattleMap = ctx[0]
	var tm: TurnManager = ctx[2]

	var plate: EquipmentDefinition = EquipmentDataManager.get_equipment("eq_plate")
	var crew: CrewDefinition = _crew_def("bulwark", 12)

	var eq_dict := { EquipmentDefinition.Slot.ARMOR: plate }
	var ok := bm.deploy_crew([crew], [Vector2i(0, 6)], [eq_dict])
	assert_bool(ok).is_true()

	var allies: Array = tm.get_alive_allies()
	assert_int(allies.size()).is_equal(1)

	var inst: UnitInstance = tm.get_unit(allies[0])
	assert_int(inst.get_max_hp()).is_equal(15)
	assert_int(inst.current_hp).is_equal(15)

# 对照组：同格空装备数组 → 基础血量不含加成。
func test_deploy_crew_without_equipment_uses_base_stats() -> void:
	var ctx := _ready_map()
	var bm: BattleMap = ctx[0]
	var tm: TurnManager = ctx[2]

	var crew: CrewDefinition = _crew_def("swordsman", 10)
	var ok := bm.deploy_crew([crew], [Vector2i(0, 6)], [])
	assert_bool(ok).is_true()

	var allies: Array = tm.get_alive_allies()
	assert_int(allies.size()).is_equal(1)

	var inst: UnitInstance = tm.get_unit(allies[0])
	assert_int(inst.get_max_hp()).is_equal(10)
	assert_int(inst.current_hp).is_equal(10)

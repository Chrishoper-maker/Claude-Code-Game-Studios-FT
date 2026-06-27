# BattleMap 部署：敌方按 island_tier 获招牌套；tier1 仍零装备（回归）。
extends GdUnitTestSuite

func _bm() -> BattleMap: return auto_free(BattleMap.new())
func _gb() -> GridBoard: return auto_free(GridBoard.new())
func _tm() -> TurnManager: return auto_free(TurnManager.new())

func _cell(pos: Vector2i) -> TerrainCell:
	var c := TerrainCell.new(); c.pos = pos; c.type = "BLOCKED"; return c

func _slot(id: String, pos: Vector2i, behavior: String, home := Vector2i(-1, -1)) -> EnemySlotDefinition:
	var s := EnemySlotDefinition.new()
	s.unit_definition_id = id; s.grid_position = pos; s.behavior_type = behavior; s.home_pos = home
	return s

func _lookup() -> Callable:
	return func(id: String) -> UnitDefinition:
		var d := EnemyDefinition.new()
		d.id = id
		d.faction = "enemy"
		d.max_hp = 8
		d.threat_tier = 1
		return d

# 双守卫地图（GUARDIAN×2），island_tier 可调；满足 Rule3 最简编制（≥2 敌、无碰撞、部署区充足）。
func _guardian_map(tier: int) -> MapDefinition:
	var m := MapDefinition.new()
	m.map_id = "lo_test"; m.island_tier = tier
	m.terrain_data = []
	var dz: Array[Vector2i] = []
	for x in range(0, 6):
		dz.append(Vector2i(x, 6)); dz.append(Vector2i(x, 7))
	m.deploy_zone = dz
	m.enemy_roster = [
		_slot("e_guard_1", Vector2i(6, 2), "GUARDIAN", Vector2i(6, 2)),
		_slot("e_guard_2", Vector2i(7, 4), "GUARDIAN", Vector2i(7, 4))
	]
	return m

func _first_enemy(tm: TurnManager) -> UnitInstance:
	return tm.get_unit(tm.get_alive_enemies()[0])

func test_tier2_guardian_gets_ironwall_3() -> void:
	var bm := _bm(); var tm := _tm()
	assert_bool(bm.load_map_definition(_guardian_map(2), _gb(), tm, _lookup())).is_true()
	var e := _first_enemy(tm)
	assert_int(e.equipment.size()).is_equal(3)
	assert_bool(SetBonus.is_tier_active(e, "set_ironwall", 3)).is_true()

func test_tier3_guardian_gets_ironwall_6() -> void:
	var bm := _bm(); var tm := _tm()
	assert_bool(bm.load_map_definition(_guardian_map(3), _gb(), tm, _lookup())).is_true()
	var e := _first_enemy(tm)
	assert_int(e.equipment.size()).is_equal(6)
	assert_bool(SetBonus.is_tier_active(e, "set_ironwall", 6)).is_true()

func test_tier1_guardian_has_no_equipment() -> void:
	var bm := _bm(); var tm := _tm()
	assert_bool(bm.load_map_definition(_guardian_map(1), _gb(), tm, _lookup())).is_true()
	assert_int(_first_enemy(tm).equipment.size()).is_equal(0)

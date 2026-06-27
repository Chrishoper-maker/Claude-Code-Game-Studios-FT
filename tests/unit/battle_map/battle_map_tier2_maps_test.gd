# island_tier3 图(006/007)敌人升级为 tier2：roster 全 tier2、仍过 Rule3、部署后为 tier2+6件套。
extends GdUnitTestSuite

func _deployed_first_enemy(map_id: String) -> UnitInstance:
	var bm: BattleMap = auto_free(BattleMap.new())
	var gb: GridBoard = auto_free(GridBoard.new())
	var tm: TurnManager = auto_free(TurnManager.new())
	bm.load_map_definition(MapDataManager.get_map(map_id), gb, tm)
	return tm.get_unit(tm.get_alive_enemies()[0])

func test_map_006_roster_all_tier2() -> void:
	var m := MapDataManager.get_map("battle_map_006") as MapDefinition
	for slot in m.enemy_roster:
		assert_str(slot.unit_definition_id).ends_with("_tier2")

func test_map_007_roster_all_tier2() -> void:
	var m := MapDataManager.get_map("battle_map_007") as MapDefinition
	for slot in m.enemy_roster:
		assert_str(slot.unit_definition_id).ends_with("_tier2")

func test_map_006_passes_rule3() -> void:
	var bm: BattleMap = auto_free(BattleMap.new())
	var gb: GridBoard = auto_free(GridBoard.new())
	var tm: TurnManager = auto_free(TurnManager.new())
	assert_bool(bm.load_map_definition(MapDataManager.get_map("battle_map_006"), gb, tm)).is_true()

func test_map_007_passes_rule3() -> void:
	var bm: BattleMap = auto_free(BattleMap.new())
	var gb: GridBoard = auto_free(GridBoard.new())
	var tm: TurnManager = auto_free(TurnManager.new())
	assert_bool(bm.load_map_definition(MapDataManager.get_map("battle_map_007"), gb, tm)).is_true()

func test_deployed_006_enemy_is_tier2_with_six_piece_loadout() -> void:
	var e := _deployed_first_enemy("battle_map_006")
	assert_int(e.definition.threat_tier).is_equal(2)
	assert_int(e.equipment.size()).is_equal(6)

# 深层图 008(island_tier5 混编)/009(island_tier6 满编全 tier3)：数据 + Rule3 + loadout。
extends GdUnitTestSuite

func _load_ok(map_id: String) -> bool:
	var bm: BattleMap = auto_free(BattleMap.new())
	var gb: GridBoard = auto_free(GridBoard.new())
	var tm: TurnManager = auto_free(TurnManager.new())
	return bm.load_map_definition(MapDataManager.get_map(map_id), gb, tm)

func _deployed_first_enemy(map_id: String) -> UnitInstance:
	var bm: BattleMap = auto_free(BattleMap.new())
	var gb: GridBoard = auto_free(GridBoard.new())
	var tm: TurnManager = auto_free(TurnManager.new())
	bm.load_map_definition(MapDataManager.get_map(map_id), gb, tm)
	return tm.get_unit(tm.get_alive_enemies()[0])

func test_map_008_is_tier5() -> void:
	var m := MapDataManager.get_map("battle_map_008") as MapDefinition
	assert_object(m).is_not_null()
	assert_int(m.island_tier).is_equal(5)

func test_map_009_is_tier6() -> void:
	var m := MapDataManager.get_map("battle_map_009") as MapDefinition
	assert_object(m).is_not_null()
	assert_int(m.island_tier).is_equal(6)

func test_map_009_roster_all_tier3() -> void:
	var m := MapDataManager.get_map("battle_map_009") as MapDefinition
	for slot in m.enemy_roster:
		assert_str(slot.unit_definition_id).ends_with("_tier3")

func test_map_008_passes_rule3() -> void:
	assert_bool(_load_ok("battle_map_008")).is_true()

func test_map_009_passes_rule3() -> void:
	assert_bool(_load_ok("battle_map_009")).is_true()

func test_get_maps_for_tier_5_contains_008() -> void:
	var ids: Array[String] = []
	for m in MapDataManager.get_maps_for_tier(5):
		ids.append(m.map_id)
	assert_array(ids).contains(["battle_map_008"])

func test_get_maps_for_tier_6_contains_009() -> void:
	var ids: Array[String] = []
	for m in MapDataManager.get_maps_for_tier(6):
		ids.append(m.map_id)
	assert_array(ids).contains(["battle_map_009"])

func test_deployed_009_enemy_is_tier3_with_nine_piece_loadout() -> void:
	var e := _deployed_first_enemy("battle_map_009")
	assert_int(e.definition.threat_tier).is_equal(3)
	assert_int(e.equipment.size()).is_equal(9)

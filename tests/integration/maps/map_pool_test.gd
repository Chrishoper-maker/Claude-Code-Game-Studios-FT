# 多地图数据校验：9 张图导入、tier 索引、逐图过 BattleMap Rule 3 部署校验。
# （子项目①建 001-007；史诗②深渊扩展加 008/009 = island_tier 5/6 深层图。）
extends GdUnitTestSuite

const NEW_MAP_IDS := [
	"battle_map_002", "battle_map_003", "battle_map_004",
	"battle_map_005", "battle_map_006", "battle_map_007",
	"battle_map_008", "battle_map_009",
]

# 全部图被 MapDataManager 扫描并缓存（001-009 = 9 张）。
func test_all_maps_loaded() -> void:
	assert_int(MapDataManager.get_all_maps().size()).is_equal(9)

# tier 索引——tier1×3、tier2×2、tier3×2、tier5×1、tier6×1。
func test_maps_indexed_by_tier() -> void:
	assert_int(MapDataManager.get_maps_for_tier(1).size()).is_equal(3)
	assert_int(MapDataManager.get_maps_for_tier(2).size()).is_equal(2)
	assert_int(MapDataManager.get_maps_for_tier(3).size()).is_equal(2)
	assert_int(MapDataManager.get_maps_for_tier(5).size()).is_equal(1)
	assert_int(MapDataManager.get_maps_for_tier(6).size()).is_equal(1)

# AC-9：每张新图都能解析（非 null + map_id 一致）。
func test_each_new_map_resolves() -> void:
	for mid in NEW_MAP_IDS:
		var m := MapDataManager.get_map(mid)
		assert_object(m).is_not_null()
		assert_str((m as MapDefinition).map_id).is_equal(mid)

# AC-9：每张新图通过 BattleMap Rule 3 部署校验（load 返回 true、状态 MAP_READY）。
func test_each_new_map_passes_deploy_validation() -> void:
	for mid in NEW_MAP_IDS:
		var bm: BattleMap = auto_free(BattleMap.new())
		var gb: GridBoard = auto_free(GridBoard.new())
		var tm: TurnManager = auto_free(TurnManager.new())
		var ok := bm.load_map_definition(MapDataManager.get_map(mid), gb, tm)
		assert_bool(ok).override_failure_message("地图 %s 未过 Rule 3 校验" % mid).is_true()

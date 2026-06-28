# 战后滚装 tier 加权 + 通关图 tier 解析。
extends GdUnitTestSuite

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._roster_equipment.clear()
	RunManager._pending_battle_equip.clear()

func _rarity_sum(eids: Array) -> int:
	var s := 0
	for eid in eids:
		var def := EquipmentDataManager.get_equipment(eid)
		if def != null:
			s += def.rarity
	return s

func test_high_tier_rolls_higher_rarity_than_tier1() -> void:
	# c1 无装备 → dominant="" → 8 件全走加权回退（无主套偏向干扰）。
	RunManager._rng.seed = 777
	var low := RunManager.roll_battle_equipment("c1", 1)
	RunManager._rng.seed = 777
	var high := RunManager.roll_battle_equipment("c1", 6)
	assert_int(_rarity_sum(high)).is_greater(_rarity_sum(low))

func test_roll_still_returns_eight_with_tier() -> void:
	RunManager._rng.seed = 777
	assert_int(RunManager.roll_battle_equipment("c1", 6).size()).is_equal(8)

func test_cleared_island_tier_reads_chosen_map() -> void:
	RunManager._chosen_map_id = "battle_map_009"   # island_tier 6
	assert_int(RunManager._cleared_island_tier()).is_equal(6)

func test_cleared_island_tier_missing_map_defaults_one() -> void:
	RunManager._chosen_map_id = ""
	assert_int(RunManager._cleared_island_tier()).is_equal(1)

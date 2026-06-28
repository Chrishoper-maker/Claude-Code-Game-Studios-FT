# AC-7：选高 tier 图 → 通关 → 战后候选稀有度偏高（端到端经 RunManager）。
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

func test_high_tier_clear_yields_richer_candidates() -> void:
	RunManager._rng.seed = 2024
	RunManager._chosen_map_id = "battle_map_001"   # tier1
	var low := RunManager.roll_battle_equipment("hero", RunManager._cleared_island_tier())
	RunManager._rng.seed = 2024
	RunManager._chosen_map_id = "battle_map_009"   # tier6
	var high := RunManager.roll_battle_equipment("hero", RunManager._cleared_island_tier())
	assert_int(_rarity_sum(high)).is_greater(_rarity_sum(low))

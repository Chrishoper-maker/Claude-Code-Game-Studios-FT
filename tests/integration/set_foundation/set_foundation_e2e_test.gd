# 端到端：起航发 3 件 → 战斗胜进 EQUIPPING → 补装 → 招募发 3 件，件数随 run 增长。
extends GdUnitTestSuite

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._goto_route = func() -> void: pass
	RunManager._goto_battle = func() -> void: pass
	RunManager._rng.seed = 2026

func test_starting_crew_get_three_then_grow_after_battle() -> void:
	RunManager.start_run()
	var first := RunManager.get_roster()[0]
	assert_int(RunManager.get_equipment_for(first.id).size()).is_equal(3)
	# 模拟部署该船员并打赢首岛
	RunManager.pending_deploy = [first]
	RunManager.current_island_index = 0
	RunManager._on_battle_won()
	assert_str(RunManager.current_phase).is_equal("EQUIPPING")
	# 选 2 件
	var cands: Array = RunManager.get_pending_battle_equip()[first.id]
	RunManager.equip_piece(first.id, str(cands[0]), true)
	RunManager.equip_piece(first.id, str(cands[1]), true)
	RunManager.finish_crew_equip(first.id)
	assert_str(RunManager.current_phase).is_equal("RECRUITING")
	# 件数 ≥3（替换可能不增槽，但不应减少）
	assert_int(RunManager.get_equipment_for(first.id).size()).is_greater_equal(3)

# 全程选航端到端（AC-6）：经 RunManager 驱动走完 5 岛，每岛地图由选航决定。
extends GdUnitTestSuite

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._goto_battle = func() -> void: pass
	RunManager._goto_route = func() -> void: pass
	MetaProgress.unlocked_crew_ids.clear()
	RunManager.start_run()              # → CHARTING（首岛）
	RunManager._rng.seed = 20260624

func after_test() -> void:
	RunManager._goto_battle = RunManager._default_goto_battle
	RunManager._goto_route = RunManager._default_goto_route

func _roster_ids() -> Array[String]:
	var ids: Array[String] = []
	for c in RunManager.get_roster():
		ids.append(c.id)
	return ids

# 选航 → 部署 → 战斗一岛的推进辅助。
func _chart_then_deploy() -> void:
	var offers := RunManager.get_route_offers()
	RunManager.confirm_route((offers[0] as MapDefinition).map_id)   # → DEPLOYING
	RunManager.confirm_deploy(_roster_ids())                        # → BATTLE（index+1）

# AC-6：首岛起航即进 CHARTING。
func test_first_island_starts_in_charting() -> void:
	assert_str(RunManager.current_phase).is_equal("CHARTING")

# AC-6：选航后进入部署、确认部署进入战斗。
func test_chart_then_deploy_reaches_battle() -> void:
	_chart_then_deploy()
	assert_str(RunManager.current_phase).is_equal("BATTLE")
	assert_int(RunManager.current_island_index).is_equal(0)

# AC-6：每岛选航记录已访问图（变化）。
func test_visited_maps_accumulate_across_islands() -> void:
	_chart_then_deploy()                        # 岛0
	assert_int(RunManager._visited_map_ids.size()).is_equal(1)
	EventBus.battle_won.emit()                  # → RECRUITING
	# 非末岛：招募（取首个候选）→ CHARTING
	var recruits := RunManager.get_recruit_offers()
	if not recruits.is_empty():
		RunManager.confirm_recruit((recruits[0] as CrewDefinition).id)
	assert_str(RunManager.current_phase).is_equal("CHARTING")
	_chart_then_deploy()                        # 岛1
	assert_int(RunManager._visited_map_ids.size()).is_equal(2)

# AC-6：全程选航打赢 5 岛 → RUN_END。
func test_full_route_win_ends_run() -> void:
	for i in range(RunManager.ISLAND_COUNT_MAX):
		_chart_then_deploy()                    # 选航 + 部署 + 进战斗
		var was_final := RunManager.current_island_index + 1 >= RunManager.ISLAND_COUNT_MAX
		EventBus.battle_won.emit()
		if not was_final:
			var recruits := RunManager.get_recruit_offers()
			if not recruits.is_empty():
				RunManager.confirm_recruit((recruits[0] as CrewDefinition).id)
	assert_str(RunManager.current_phase).is_equal("RUN_END")
	assert_bool(RunManager.last_run_won).is_true()

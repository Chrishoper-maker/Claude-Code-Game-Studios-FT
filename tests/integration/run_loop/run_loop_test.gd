# Run 循环集成测试：端到端驱动 起航 → 部署 → 胜/负 → 招募 → 下一岛 → 终局/重启，
# 覆盖 F5 ADVISORY 验收 AC-1..7（把人工目视关卡转为自动回归保护）。
# 经 EventBus 真实信号驱动 RunManager（autoload，battle_won/lost 已在其 _ready 接线）；
# AC-3 实例化 BattleScene.tscn 断言招募的新队员真的部署上场（最难覆盖项）。
# 导航接缝 _goto_battle/_goto_route 在 before_test 设为 no-op，避免单测真的切场景。
extends GdUnitTestSuite

const STARTING_IDS := ["crew_swordsman_01", "crew_bulwark_01"]

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._goto_battle = func() -> void: pass
	RunManager._goto_route  = func() -> void: pass
	MetaProgress.unlocked_crew_ids.clear()
	MetaProgress._save_path = "user://test_run_loop_meta.json"
	RunManager.start_run()
	RunManager._rng.seed = 20260621   # 招募抽样确定性

func after_test() -> void:
	RunManager._goto_battle = RunManager._default_goto_battle
	RunManager._goto_route  = RunManager._default_goto_route
	MetaProgress.unlocked_crew_ids.clear()
	MetaProgress._save_path = "user://meta.json"
	if FileAccess.file_exists("user://test_run_loop_meta.json"):
		DirAccess.remove_absolute("user://test_run_loop_meta.json")

func _roster_ids() -> Array:
	var ids: Array = []
	for c in RunManager.get_roster():
		ids.append(c.id)
	return ids

func _deploy_roster() -> void:
	RunManager.confirm_deploy(_roster_ids())

# AC-1：起航 → CHARTING + 起始编制（阿斩 swordsman + 梅莉 bulwark）入队。
func test_ac1_start_run_charts_then_holds_starting_crew() -> void:
	assert_str(RunManager.current_phase).is_equal("CHARTING")
	var ids := _roster_ids()
	assert_int(ids.size()).is_equal(RunManager.STARTING_CREW)
	for sid in STARTING_IDS:
		assert_bool(ids.has(sid)).is_true()

# AC-2：非末岛打赢 → RECRUITING + 三选一候选（≤3、职业互异、皆 pool tier）。
func test_ac2_win_nonfinal_offers_three_distinct_recruits() -> void:
	_deploy_roster()                       # → island 0, BATTLE
	EventBus.battle_won.emit()             # 真实接线 → RunManager._on_battle_won
	assert_str(RunManager.current_phase).is_equal("RECRUITING")
	var offers := RunManager.get_recruit_offers()
	assert_int(offers.size()).is_greater_equal(2)
	assert_int(offers.size()).is_less_equal(RunManager.RECRUIT_OFFER_COUNT)
	var seen: Dictionary = {}
	for o in offers:
		assert_str((o as CrewDefinition).recruit_pool_tier).is_equal("pool")
		assert_bool(seen.has((o as CrewDefinition).unit_class)).is_false()
		seen[(o as CrewDefinition).unit_class] = true

# AC-3（最难）：招募一名 → 下一岛 BattleScene 战场上真的多一名队员（2→3 上场）。
func test_ac3_recruited_crew_appears_on_field_next_battle() -> void:
	_deploy_roster()                       # island 0
	EventBus.battle_won.emit()             # → RECRUITING
	var offers := RunManager.get_recruit_offers()
	assert_int(offers.size()).is_greater_equal(1)
	RunManager.confirm_recruit((offers[0] as CrewDefinition).id)
	assert_int(RunManager.get_roster().size()).is_equal(3)
	_deploy_roster()                       # island 1, pending_deploy = 3
	var scene: BattleScene = auto_free(preload("res://scenes/BattleScene.tscn").instantiate())
	add_child(scene)                       # _ready：部署敌 + roster crew → start_battle
	assert_int(scene._turn_manager.get_alive_allies().size()).is_equal(3)

# AC-4：连打 5 岛全胜 → RUN_END + 出航成功 + run_completed(true, 5)。
func test_ac4_winning_all_islands_ends_run_victorious() -> void:
	var monitor := monitor_signals(EventBus, false)
	for _i in RunManager.ISLAND_COUNT_MAX:
		_deploy_roster()                   # 进下一岛（RECRUITING/DEPLOYING 均可推进）
		EventBus.battle_won.emit()
	assert_str(RunManager.current_phase).is_equal("RUN_END")
	assert_bool(RunManager.last_run_won).is_true()
	await assert_signal(monitor).is_emitted(
		"run_completed", [true, RunManager.ISLAND_COUNT_MAX, RunManager.get_roster()])

# AC-5：任一场打输 → RUN_END + 全员阵亡 + run_completed(false, 1)，不崩。
func test_ac5_losing_ends_run_in_defeat() -> void:
	var monitor := monitor_signals(EventBus, false)
	_deploy_roster()                       # island 0, BATTLE
	EventBus.battle_lost.emit()
	assert_str(RunManager.current_phase).is_equal("RUN_END")
	assert_bool(RunManager.last_run_won).is_false()
	await assert_signal(monitor).is_emitted(
		"run_completed", [false, 1, RunManager.get_roster()])

# AC-6：重新出航 → 回到首岛重来（index 复位 -1 → 部署后 0）。
func test_ac6_restart_returns_to_first_island() -> void:
	_deploy_roster()
	EventBus.battle_lost.emit()            # RUN_END
	assert_str(RunManager.current_phase).is_equal("RUN_END")
	RunManager.start_run()                 # RouteScene._on_restart_pressed 等价
	assert_int(RunManager.current_island_index).is_equal(-1)
	assert_str(RunManager.current_phase).is_equal("CHARTING")
	_deploy_roster()
	assert_int(RunManager.current_island_index).is_equal(0)
	assert_str(RunManager.current_phase).is_equal("BATTLE")

# AC-7（最难）：招募池抽干 → RouteScene 跳过招募直接进下一岛，不崩。
func test_ac7_exhausted_pool_skips_recruit_via_route_scene() -> void:
	_deploy_roster()
	EventBus.battle_won.emit()             # → RECRUITING
	assert_str(RunManager.current_phase).is_equal("RECRUITING")
	# 抽干招募池：所有 pool tier 进排除集
	for def in UnitDataManager.get_all_units():
		if def is CrewDefinition and (def as CrewDefinition).recruit_pool_tier == "pool":
			RunManager._excluded_offers.append((def as CrewDefinition).id)
	assert_int(RunManager.get_recruit_offers().size()).is_equal(0)
	# RouteScene 在 RECRUITING + 空候选时应跳过招募直接部署下一岛，不崩。
	var island_before := RunManager.current_island_index
	var route: RouteScene = auto_free(RouteScene.new())
	add_child(route)                       # _ready → _show_recruit_offers → 空 → _deploy_current_roster
	assert_str(RunManager.current_phase).is_equal("BATTLE")
	assert_int(RunManager.current_island_index).is_equal(island_before + 1)

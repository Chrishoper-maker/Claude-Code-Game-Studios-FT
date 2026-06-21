# 阵亡通知卡集成测试：战后进入招募前先弹折损通知（RouteScene 白盒门控）。
extends GdUnitTestSuite

func before_test() -> void:
	RunManager._goto_battle = func() -> void: pass
	RunManager._goto_route  = func() -> void: pass
	RunManager.start_run()
	RunManager._rng.seed = 20260621

func after_test() -> void:
	RunManager._goto_battle = RunManager._default_goto_battle
	RunManager._goto_route  = RunManager._default_goto_route

func _enter_recruiting_with_downed(downed_id: String) -> void:
	RunManager.current_island_index = 0
	RunManager._on_crew_member_downed(downed_id)
	RunManager._set_run_phase(RunManager.RunPhase.RUN_RECRUITING)

# AC-3：有阵亡 → 先显示通知卡，暂不显示招募。
func test_downed_shows_notice_before_recruit() -> void:
	_enter_recruiting_with_downed((RunManager.roster[0] as CrewDefinition).id)
	var route: RouteScene = auto_free(RouteScene.new())
	add_child(route)
	assert_bool(route._notice_continue_button != null).is_true()
	assert_str(route._active_screen).is_equal("notice")

# AC-4：点继续 → 清空 pending 并进入招募。
func test_continue_clears_and_shows_recruit() -> void:
	_enter_recruiting_with_downed((RunManager.roster[0] as CrewDefinition).id)
	var route: RouteScene = auto_free(RouteScene.new())
	add_child(route)
	route._notice_continue_button.pressed.emit()
	assert_int(RunManager.get_pending_downed_notice().size()).is_equal(0)
	assert_str(route._active_screen).is_equal("recruit")

# AC-5：无阵亡 → 不弹通知，直接招募（run_loop AC-2 回归保护）。
func test_no_downed_goes_straight_to_recruit() -> void:
	RunManager.current_island_index = 0
	RunManager._set_run_phase(RunManager.RunPhase.RUN_RECRUITING)
	var route: RouteScene = auto_free(RouteScene.new())
	add_child(route)
	assert_bool(route._notice_continue_button == null).is_true()
	assert_str(route._active_screen).is_equal("recruit")

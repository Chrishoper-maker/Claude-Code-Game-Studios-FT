# run-end 运行总结集成测试：RUN_END 渲染总结 + 重新出航回到首岛战斗。
extends GdUnitTestSuite

func before_test() -> void:
	RunManager._goto_battle = func() -> void: pass
	RunManager._goto_route  = func() -> void: pass
	RunManager.start_run()
	RunManager._rng.seed = 20260621

func after_test() -> void:
	RunManager._goto_battle = RunManager._default_goto_battle
	RunManager._goto_route  = RunManager._default_goto_route

# 无阵亡通知挂起时，RUN_END 直接渲染运行总结。
func test_run_end_renders_summary() -> void:
	RunManager.current_island_index = RunManager.ISLAND_COUNT_MAX - 1
	RunManager.last_run_won = true
	RunManager._set_run_phase(RunManager.RunPhase.RUN_END)
	var route: RouteScene = auto_free(RouteScene.new())
	add_child(route)
	assert_str(route._active_screen).is_equal("run_end")

# 重新出航 → 复位并进入首岛战斗。
func test_run_end_restart_returns_to_first_battle() -> void:
	RunManager.current_island_index = 2
	RunManager.last_run_won = false
	RunManager._set_run_phase(RunManager.RunPhase.RUN_END)
	var route: RouteScene = auto_free(RouteScene.new())
	add_child(route)
	route._on_restart_pressed()
	assert_str(RunManager.current_phase).is_equal("BATTLE")
	assert_int(RunManager.current_island_index).is_equal(0)

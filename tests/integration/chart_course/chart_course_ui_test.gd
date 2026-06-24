# 选航 UI 分支（子项目①，白盒 ADVISORY 的可观测部分）。
extends GdUnitTestSuite

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._goto_battle = func() -> void: pass
	RunManager._goto_route = func() -> void: pass
	RunManager.start_run()              # → CHARTING
	RunManager._rng.seed = 20260624

func after_test() -> void:
	RunManager._goto_battle = RunManager._default_goto_battle
	RunManager._goto_route = RunManager._default_goto_route

# CHARTING 阶段进入 RouteScene → 渲染选航界面。
func test_charting_phase_shows_route_screen() -> void:
	var rs: RouteScene = auto_free(RouteScene.new())
	add_child(rs)
	assert_str(rs._active_screen).is_equal("charting")

# 敌情摘要：按 behavior_type 计数 + 中文标签。
func test_enemy_summary_counts_by_behavior() -> void:
	var rs: RouteScene = auto_free(RouteScene.new())
	add_child(rs)
	var summary: String = rs._enemy_summary(MapDataManager.get_map("battle_map_001"))
	# battle_map_001：近战×1 远程×1 突击×1 守卫×1
	assert_str(summary).contains("近战×1")
	assert_str(summary).contains("远程×1")
	assert_str(summary).contains("突击×1")
	assert_str(summary).contains("守卫×1")

# 选航后进入部署阶段（confirm_route → DEPLOYING；roster>4 阻止自动部署停在选人界面）。
func test_choosing_route_advances_to_deploy() -> void:
	# roster 扩到 5 名，防止 _enter_deploy 自动全员直接进 BATTLE
	var extra_ids: Array[String] = [
		"crew_swordsman_02", "crew_gunner_01", "crew_bulwark_02", "crew_medic_01",
	]
	for pid in extra_ids:
		var def := UnitDataManager.get_unit(pid)
		if def is CrewDefinition:
			RunManager.roster.append(def as CrewDefinition)
	var rs: RouteScene = auto_free(RouteScene.new())
	add_child(rs)
	var chosen := RunManager._last_route_offers[0]
	rs._on_route_chosen(chosen)
	assert_str(RunManager.current_phase).is_equal("DEPLOYING")

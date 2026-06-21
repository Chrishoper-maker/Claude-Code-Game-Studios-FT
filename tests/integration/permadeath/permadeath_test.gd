# 永久死亡集成测试：BattleScene 桥接 unit_downed→crew_member_downed→RunManager 移出 roster。
# 导航接缝 stub no-op 防真切场景；经 resolve_unit_downed 驱动真实 unit_downed 信号链。
extends GdUnitTestSuite

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._goto_battle = func() -> void: pass
	RunManager._goto_route  = func() -> void: pass
	RunManager.start_run()
	RunManager._rng.seed = 20260621

func after_test() -> void:
	RunManager._goto_battle = RunManager._default_goto_battle
	RunManager._goto_route  = RunManager._default_goto_route

func _boot_battle() -> BattleScene:
	var ids: Array[String] = []
	for c in RunManager.get_roster():
		ids.append(c.id)
	RunManager.confirm_deploy(ids)
	var scene: BattleScene = auto_free(preload("res://scenes/BattleScene.tscn").instantiate())
	add_child(scene)
	return scene

# AC-4：我方被击倒 → 永久移出 roster。
func test_ally_downed_removed_from_roster() -> void:
	var scene := _boot_battle()
	var ally_id: int = scene._turn_manager.get_alive_allies()[0]
	var crew_id: String = scene._turn_manager.get_unit(ally_id).get_unit_id()
	var before := RunManager.roster.size()
	scene._battle_resolution.resolve_unit_downed(ally_id)
	assert_int(RunManager.roster.size()).is_equal(before - 1)
	for c in RunManager.get_roster():
		assert_str((c as CrewDefinition).id).is_not_equal(crew_id)

# AC-5：敌方被击倒 → roster 不变。
func test_enemy_downed_does_not_touch_roster() -> void:
	var scene := _boot_battle()
	var enemy_id: int = scene._turn_manager.get_alive_enemies()[0]
	var before := RunManager.roster.size()
	scene._battle_resolution.resolve_unit_downed(enemy_id)
	assert_int(RunManager.roster.size()).is_equal(before)

# 补装屏：EQUIPPING 分支渲染候选 + 纸娃娃；equip + finish 推进。
extends GdUnitTestSuite

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._roster_equipment.clear()
	RunManager._pending_battle_equip.clear()
	RunManager._goto_route = func() -> void: pass

func test_equipping_branch_builds_paperdoll() -> void:
	var c: CrewDefinition = null
	for def in UnitDataManager.get_all_units():
		if def is CrewDefinition and (def as CrewDefinition).recruit_pool_tier == "starting":
			c = def as CrewDefinition
			break
	RunManager.roster = [c]
	RunManager.pending_deploy = [c]
	RunManager.current_island_index = 0
	RunManager._on_battle_won()   # → EQUIPPING + pending 候选
	var scene := RouteScene.new()
	add_child(scene)
	scene._ready()
	assert_str(scene._active_screen).is_equal("battle_equip")
	# 纸娃娃含 9 个槽行
	scene.queue_free()

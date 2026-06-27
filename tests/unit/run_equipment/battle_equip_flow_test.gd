# 战后非末岛 → 为出战存活者滚候选 → 进 EQUIPPING；全选完 → RECRUITING。
extends GdUnitTestSuite

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._roster_equipment.clear()
	RunManager._pending_battle_equip.clear()
	RunManager._goto_route = func() -> void: pass   # no-op 防切场景
	RunManager._rng.seed = 99

func _crew(id_substr_tier: String) -> CrewDefinition:
	for def in UnitDataManager.get_all_units():
		if def is CrewDefinition and (def as CrewDefinition).recruit_pool_tier == id_substr_tier:
			return def as CrewDefinition
	return null

func test_battle_won_enters_equipping_for_survivors() -> void:
	var c := _crew("starting")
	RunManager.roster = [c]
	RunManager.pending_deploy = [c]
	RunManager.current_island_index = 0   # 非末岛
	RunManager._on_battle_won()
	assert_str(RunManager.current_phase).is_equal("EQUIPPING")
	assert_bool(RunManager.get_pending_battle_equip().has(c.id)).is_true()
	assert_int((RunManager.get_pending_battle_equip()[c.id] as Array).size()).is_equal(8)

func test_finish_all_advances_to_recruiting() -> void:
	var c := _crew("starting")
	RunManager.roster = [c]
	RunManager.pending_deploy = [c]
	RunManager.current_island_index = 0
	RunManager._on_battle_won()
	RunManager.finish_crew_equip(c.id)
	assert_str(RunManager.current_phase).is_equal("RECRUITING")

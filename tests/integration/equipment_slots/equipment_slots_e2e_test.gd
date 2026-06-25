# 端到端测试：招募时选定的多槽装备加成能正确反映到战斗有效值（AC-7 + AC-8）。
# 流程：start_run → get_recruit_offers → confirm_recruit(crew_id, picks) → UnitInstance 有效值断言。
extends GdUnitTestSuite

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._rng.seed = 99

func test_recruit_two_slots_reflect_in_battle_effective_values() -> void:
	var rm := RunManager
	rm.start_run()
	var offers := rm.get_recruit_offers()
	var crew_id := offers[0].id
	# 选弯刀(+1攻,主武器) + 板甲(+3血,护甲)
	rm.confirm_recruit(crew_id, ["eq_cutlass", "eq_plate"])
	var crew_def := UnitDataManager.get_unit(crew_id)
	var slots := rm.get_equipment_for(crew_id)
	var inst := UnitInstance.from_definition(crew_def, slots)
	assert_int(inst.get_base_damage()).is_equal(crew_def.base_damage + 1)
	assert_int(inst.get_max_hp()).is_equal(crew_def.max_hp + 3)

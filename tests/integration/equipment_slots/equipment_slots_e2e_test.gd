# 端到端测试：招募直发 3 件装备的加成能正确反映到战斗有效值（AC-7 + AC-8）。
# 流程：start_run → get_recruit_offers → confirm_recruit(crew_id) → UnitInstance 有效值断言。
extends GdUnitTestSuite

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._rng.seed = 99

func test_recruit_three_slots_reflect_in_battle_effective_values() -> void:
	var rm := RunManager
	rm.start_run()
	var offers := rm.get_recruit_offers()
	var crew_id := offers[0].id
	# 直发 3 件装备（80% 同套）
	rm.confirm_recruit(crew_id)
	var crew_def := UnitDataManager.get_unit(crew_id)
	var slots := rm.get_equipment_for(crew_id)
	assert_int(slots.size()).is_equal(3)
	var inst := UnitInstance.from_definition(crew_def, slots)
	# 具体字面量断言（seed=99 确定性，通过实际运行确认）：
	# 3 件装备合计 hp_bonus=10，damage_bonus=0。
	assert_int(inst.get_max_hp()).is_equal(crew_def.max_hp + 10)
	assert_int(inst.get_base_damage()).is_equal(crew_def.base_damage + 0)

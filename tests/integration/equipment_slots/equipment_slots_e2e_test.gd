# 端到端测试：装备增量能正确反映到战斗有效值（AC-7 + AC-8）。
# 流程：start_run → 给起始船员装两件已知装备 → UnitInstance 有效值断言。
# 刻意用「已知装备」而非随机招募滚装，使断言确定、稳健（不依赖招募池/解锁/RNG 全局态）。
extends GdUnitTestSuite

func before_test() -> void:
	RunManager._autosave_enabled = false

func test_equipped_slots_reflect_in_battle_effective_values() -> void:
	var rm := RunManager
	rm.start_run()
	var crew_def := rm.get_roster()[0]
	# 直接装两件已知装备（确定性，非随机）：
	#   eq_berserker_mainweapon → damage_bonus +3（slot0）
	#   eq_ironwall_armor       → hp_bonus +6（slot3）
	var eq := {
		0: EquipmentDataManager.get_equipment("eq_berserker_mainweapon"),
		3: EquipmentDataManager.get_equipment("eq_ironwall_armor"),
	}
	assert_object(eq[0]).is_not_null()
	assert_object(eq[3]).is_not_null()
	var inst := UnitInstance.from_definition(crew_def, eq)
	assert_int(inst.get_max_hp()).is_equal(crew_def.max_hp + 6)
	assert_int(inst.get_base_damage()).is_equal(crew_def.base_damage + 3)

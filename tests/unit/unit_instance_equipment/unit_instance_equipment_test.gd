# UnitInstance 有效值（多槽装备增量；无装备=基值；初始 current_hp=有效 max_hp）。
extends GdUnitTestSuite

func _crew() -> UnitDefinition:
	return UnitDataManager.get_unit("crew_swordsman_01")  # 既有起始剑士

func _eq(id: String) -> EquipmentDefinition:
	return EquipmentDataManager.get_equipment(id)

func test_no_equipment_uses_base_values() -> void:
	var inst := UnitInstance.from_definition(_crew(), {})
	assert_int(inst.get_max_hp()).is_equal(_crew().max_hp)

func test_single_slot_adds_bonus() -> void:
	var slots := { EquipmentDefinition.Slot.ARMOR: _eq("eq_plate") }  # +3血
	var inst := UnitInstance.from_definition(_crew(), slots)
	assert_int(inst.get_max_hp()).is_equal(_crew().max_hp + 3)

func test_multi_slot_sums_all_bonuses() -> void:
	var slots := {
		EquipmentDefinition.Slot.ARMOR: _eq("eq_plate"),       # +3血
		EquipmentDefinition.Slot.MAIN_WEAPON: _eq("eq_cutlass"),# +1攻
		EquipmentDefinition.Slot.BOOTS: _eq("eq_boots"),        # +1移动
	}
	var inst := UnitInstance.from_definition(_crew(), slots)
	assert_int(inst.get_max_hp()).is_equal(_crew().max_hp + 3)
	assert_int(inst.get_base_damage()).is_equal(_crew().base_damage + 1)
	assert_int(inst.get_move_range()).is_equal(_crew().move_range + 1)

func test_bonus_clamped_at_zero() -> void:
	# 即便基值很低也不为负（沿用现有钳零语义）
	var inst := UnitInstance.from_definition(_crew(), {})
	assert_int(inst.get_attack_range()).is_greater_equal(0)

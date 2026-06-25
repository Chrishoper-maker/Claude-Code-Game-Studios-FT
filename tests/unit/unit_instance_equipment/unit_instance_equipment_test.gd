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

# AC-clamp：超大负增量时四个访问器均钳零，不返回负数。
func test_negative_bonus_clamped_to_zero_all_accessors() -> void:
	# Arrange — 合成装备：各维度 -100，远超任何基值。
	var neg_equip := EquipmentDefinition.new()
	neg_equip.id = "test_neg_eq"
	neg_equip.display_name = "负增量测试装备"
	neg_equip.slot = EquipmentDefinition.Slot.ARMOR
	neg_equip.hp_bonus = -100
	neg_equip.damage_bonus = -100
	neg_equip.range_bonus = -100
	neg_equip.move_bonus = -100
	var slots := { EquipmentDefinition.Slot.ARMOR: neg_equip }

	# Act
	var inst := UnitInstance.from_definition(_crew(), slots)

	# Assert — maxi(0, base + bonus) 钳零，所有访问器不得为负。
	assert_int(inst.get_max_hp()).is_equal(0)
	assert_int(inst.get_base_damage()).is_equal(0)
	assert_int(inst.get_attack_range()).is_equal(0)
	assert_int(inst.get_move_range()).is_equal(0)

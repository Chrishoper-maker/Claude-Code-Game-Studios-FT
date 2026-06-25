# 校验 EquipmentDataManager 按稀有度/槽过滤查询（用现有 4 件普通装备）。
extends GdUnitTestSuite

func test_query_by_rarity_returns_only_that_rarity() -> void:
	var commons := EquipmentDataManager.get_equipment_by_rarity(EquipmentDefinition.Rarity.COMMON)
	assert_bool(commons.size() >= 4).is_true()  # 现有 4 件均普通
	for eq in commons:
		assert_int(eq.rarity).is_equal(EquipmentDefinition.Rarity.COMMON)

func test_query_by_slot_returns_only_that_slot() -> void:
	# 弯刀(eq_cutlass) 归主武器槽
	var weapons := EquipmentDataManager.get_equipment_by_slot(EquipmentDefinition.Slot.MAIN_WEAPON)
	var ids: Array[String] = []
	for eq in weapons:
		assert_int(eq.slot).is_equal(EquipmentDefinition.Slot.MAIN_WEAPON)
		ids.append(eq.id)
	assert_array(ids).contains(["eq_cutlass"])

func test_existing_equipment_has_default_fields() -> void:
	var plate := EquipmentDataManager.get_equipment("eq_plate")
	assert_object(plate).is_not_null()
	assert_int(plate.rarity).is_equal(EquipmentDefinition.Rarity.COMMON)
	assert_str(plate.set_id).is_equal("")

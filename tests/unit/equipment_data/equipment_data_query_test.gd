# 校验 EquipmentDataManager 按稀有度/槽过滤查询（72 件套装体系）。
extends GdUnitTestSuite

func test_query_by_rarity_returns_only_that_rarity() -> void:
	var commons := EquipmentDataManager.get_equipment_by_rarity(EquipmentDefinition.Rarity.COMMON)
	assert_bool(commons.size() >= 8).is_true()
	for eq in commons:
		assert_int(eq.rarity).is_equal(EquipmentDefinition.Rarity.COMMON)

func test_query_by_slot_returns_only_that_slot() -> void:
	var weapons := EquipmentDataManager.get_equipment_by_slot(EquipmentDefinition.Slot.MAIN_WEAPON)
	var ids: Array[String] = []
	for eq in weapons:
		assert_int(eq.slot).is_equal(EquipmentDefinition.Slot.MAIN_WEAPON)
		ids.append(eq.id)
	assert_array(ids).contains(["eq_berserker_mainweapon"])

func test_existing_equipment_has_default_fields() -> void:
	var armor := EquipmentDataManager.get_equipment("eq_ironwall_armor")
	assert_object(armor).is_not_null()
	assert_int(armor.rarity).is_equal(EquipmentDefinition.Rarity.EPIC)
	assert_str(armor.set_id).is_equal("set_ironwall")

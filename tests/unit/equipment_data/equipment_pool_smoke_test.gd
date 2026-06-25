extends GdUnitTestSuite

# 校验完整 31 件装备池的稀有度分布与基本不变量。
func test_total_count_is_31() -> void:
	assert_int(EquipmentDataManager.get_all_equipment().size()).is_equal(31)

func test_rarity_distribution_10_8_5_5_3() -> void:
	assert_int(EquipmentDataManager.get_equipment_by_rarity(0).size()).is_equal(10)
	assert_int(EquipmentDataManager.get_equipment_by_rarity(1).size()).is_equal(8)
	assert_int(EquipmentDataManager.get_equipment_by_rarity(2).size()).is_equal(5)
	assert_int(EquipmentDataManager.get_equipment_by_rarity(3).size()).is_equal(5)
	assert_int(EquipmentDataManager.get_equipment_by_rarity(4).size()).is_equal(3)

func test_all_loaded_and_unique() -> void:
	assert_bool(EquipmentDataManager.is_loaded).is_true()
	var seen: Dictionary = {}
	for eq in EquipmentDataManager.get_all_equipment():
		assert_bool(seen.has(eq.id)).is_false()
		seen[eq.id] = true
		assert_int(eq.slot).is_between(0, 8)
		assert_int(eq.rarity).is_between(0, 4)

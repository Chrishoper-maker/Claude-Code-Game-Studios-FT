extends GdUnitTestSuite

# 校验 8 套 × 9 槽 = 72 件装备池的分布与不变量。
func test_total_count_is_72() -> void:
	assert_int(EquipmentDataManager.get_all_equipment().size()).is_equal(72)

func test_rarity_distribution_24_24_16_8_0() -> void:
	assert_int(EquipmentDataManager.get_equipment_by_rarity(0).size()).is_equal(24)
	assert_int(EquipmentDataManager.get_equipment_by_rarity(1).size()).is_equal(24)
	assert_int(EquipmentDataManager.get_equipment_by_rarity(2).size()).is_equal(16)
	assert_int(EquipmentDataManager.get_equipment_by_rarity(3).size()).is_equal(8)
	assert_int(EquipmentDataManager.get_equipment_by_rarity(4).size()).is_equal(0)

func test_each_set_has_nine_distinct_slots() -> void:
	var by_set: Dictionary = {}
	for eq in EquipmentDataManager.get_all_equipment():
		assert_str(eq.set_id).is_not_equal("")
		if not by_set.has(eq.set_id):
			by_set[eq.set_id] = {}
		by_set[eq.set_id][eq.slot] = true
	assert_int(by_set.size()).is_equal(8)
	for sid in by_set:
		assert_int((by_set[sid] as Dictionary).size()).is_equal(9)

func test_all_loaded_and_unique() -> void:
	assert_bool(EquipmentDataManager.is_loaded).is_true()
	var seen: Dictionary = {}
	for eq in EquipmentDataManager.get_all_equipment():
		assert_bool(seen.has(eq.id)).is_false()
		seen[eq.id] = true
		assert_int(eq.slot).is_between(0, 8)
		assert_int(eq.rarity).is_between(0, 4)

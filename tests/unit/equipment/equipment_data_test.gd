# EquipmentDataManager 扫描 + 查询（实跑 .tres，仿 definitions_test）。
extends GdUnitTestSuite

# AC-1：扫描后池含 72 件，get_equipment 返回正确增量。
func test_loads_equipment_pool() -> void:
	assert_bool(EquipmentDataManager.is_loaded).is_true()
	assert_int(EquipmentDataManager.get_all_equipment().size()).is_equal(72)
	var armor := EquipmentDataManager.get_equipment("eq_ironwall_armor")
	assert_bool(armor != null).is_true()
	assert_int(armor.hp_bonus).is_equal(6)   # hp 主属性 × 史诗(rarity2)=6
	assert_int(armor.damage_bonus).is_equal(0)

func test_missing_id_returns_null() -> void:
	assert_object(EquipmentDataManager.get_equipment("eq_nonexistent_zzz")).is_null()

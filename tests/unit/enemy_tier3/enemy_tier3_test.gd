# tier3 敌方原型数据校验：经 UnitDataManager 取得、类型/字段正确（spec §3.2）。
extends GdUnitTestSuite

func _enemy(id: String) -> EnemyDefinition:
	return UnitDataManager.get_unit(id) as EnemyDefinition

func test_melee_tier3_fields() -> void:
	var e := _enemy("enemy_melee_tier3")
	assert_object(e).is_not_null()
	assert_int(e.threat_tier).is_equal(3)
	assert_int(e.max_hp).is_equal(12)
	assert_int(e.base_damage).is_equal(5)
	assert_int(e.attack_range).is_equal(1)
	assert_int(e.move_range).is_equal(2)
	assert_str(e.unit_class).is_equal("swordsman")
	assert_str(e.behavior_type).is_equal("MELEE")

func test_ranged_tier3_fields() -> void:
	var e := _enemy("enemy_ranged_tier3")
	assert_object(e).is_not_null()
	assert_int(e.threat_tier).is_equal(3)
	assert_int(e.max_hp).is_equal(11)
	assert_int(e.base_damage).is_equal(5)
	assert_int(e.attack_range).is_equal(3)
	assert_int(e.move_range).is_equal(2)
	assert_str(e.unit_class).is_equal("gunner")
	assert_str(e.behavior_type).is_equal("RANGED")

func test_swarmer_tier3_fields() -> void:
	var e := _enemy("enemy_swarmer_tier3")
	assert_object(e).is_not_null()
	assert_int(e.threat_tier).is_equal(3)
	assert_int(e.max_hp).is_equal(8)
	assert_int(e.base_damage).is_equal(4)
	assert_int(e.attack_range).is_equal(1)
	assert_int(e.move_range).is_equal(3)
	assert_str(e.unit_class).is_equal("swordsman")
	assert_str(e.behavior_type).is_equal("SWARMER")

func test_guardian_tier3_fields() -> void:
	var e := _enemy("enemy_guardian_tier3")
	assert_object(e).is_not_null()
	assert_int(e.threat_tier).is_equal(3)
	assert_int(e.max_hp).is_equal(16)
	assert_int(e.base_damage).is_equal(4)
	assert_int(e.attack_range).is_equal(1)
	assert_int(e.move_range).is_equal(1)
	assert_str(e.unit_class).is_equal("bulwark")
	assert_str(e.behavior_type).is_equal("GUARDIAN")

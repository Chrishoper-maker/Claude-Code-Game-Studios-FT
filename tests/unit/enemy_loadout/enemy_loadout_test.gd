# EnemyLoadout：原型→招牌套 + island_tier→件数（1/2/3→0/3/6），返回 {slot:int → EquipmentDefinition}。
extends GdUnitTestSuite

func _set_ids(lo: Dictionary) -> Array:
	var out: Array = []
	for k in lo:
		out.append((lo[k] as EquipmentDefinition).set_id)
	return out

func test_guardian_tier2_returns_ironwall_3() -> void:
	var lo := EnemyLoadout.for_enemy("GUARDIAN", 2)
	assert_int(lo.size()).is_equal(3)
	for sid in _set_ids(lo):
		assert_str(sid).is_equal("set_ironwall")

func test_melee_tier3_returns_bloodthirst_6() -> void:
	var lo := EnemyLoadout.for_enemy("MELEE", 3)
	assert_int(lo.size()).is_equal(6)
	for sid in _set_ids(lo):
		assert_str(sid).is_equal("set_bloodthirst")

func test_swarmer_tier2_returns_thorns_3() -> void:
	var lo := EnemyLoadout.for_enemy("SWARMER", 2)
	assert_int(lo.size()).is_equal(3)
	for sid in _set_ids(lo):
		assert_str(sid).is_equal("set_thorns")

func test_ranged_tier3_returns_executioner_6() -> void:
	var lo := EnemyLoadout.for_enemy("RANGED", 3)
	assert_int(lo.size()).is_equal(6)
	for sid in _set_ids(lo):
		assert_str(sid).is_equal("set_executioner")

func test_tier1_returns_empty() -> void:
	assert_int(EnemyLoadout.for_enemy("GUARDIAN", 1).size()).is_equal(0)

func test_unknown_type_returns_empty() -> void:
	assert_int(EnemyLoadout.for_enemy("BOSS", 3).size()).is_equal(0)

func test_keys_are_equipment_slot_ints() -> void:
	var lo := EnemyLoadout.for_enemy("GUARDIAN", 2)
	for k in lo:
		assert_int(int(k)).is_equal((lo[k] as EquipmentDefinition).slot)

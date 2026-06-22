# UnitInstance 有效值（装备增量；无装备=基值；初始 current_hp=有效 max_hp）。
extends GdUnitTestSuite

func _def() -> UnitDefinition:
	var d := UnitDefinition.new()
	d.id = "test_unit"
	d.faction = "crew"
	d.unit_class = "swordsman"
	d.max_hp = 10
	d.base_damage = 3
	d.attack_range = 1
	d.move_range = 3
	d.class_action_id = "slash"
	return d

func _equip(hp: int, dmg: int, rng: int, mv: int) -> EquipmentDefinition:
	var e := EquipmentDefinition.new()
	e.id = "test_eq"
	e.display_name = "测试装备"
	e.hp_bonus = hp
	e.damage_bonus = dmg
	e.range_bonus = rng
	e.move_bonus = mv
	return e

# AC-3：无装备 → 有效值=基值。
func test_no_equipment_returns_base() -> void:
	var inst := UnitInstance.from_definition(_def())
	assert_int(inst.get_max_hp()).is_equal(10)
	assert_int(inst.get_base_damage()).is_equal(3)
	assert_int(inst.get_attack_range()).is_equal(1)
	assert_int(inst.get_move_range()).is_equal(3)
	assert_int(inst.current_hp).is_equal(10)

# AC-2：有装备 → 有效值=基值+增量，初始 current_hp=有效 max_hp。
func test_equipment_adds_bonuses() -> void:
	var inst := UnitInstance.from_definition(_def(), _equip(3, 1, 1, 1))
	assert_int(inst.get_max_hp()).is_equal(13)
	assert_int(inst.get_base_damage()).is_equal(4)
	assert_int(inst.get_attack_range()).is_equal(2)
	assert_int(inst.get_move_range()).is_equal(4)
	assert_int(inst.current_hp).is_equal(13)

# 负增量钳 0（防御）。
func test_negative_bonus_clamped_to_zero() -> void:
	var inst := UnitInstance.from_definition(_def(), _equip(-100, -100, -100, -100))
	assert_int(inst.get_max_hp()).is_equal(0)
	assert_int(inst.get_base_damage()).is_equal(0)

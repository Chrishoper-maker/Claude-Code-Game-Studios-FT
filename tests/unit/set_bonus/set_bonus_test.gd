# SetBonus：从 UnitInstance.equipment 算套装件数/档位（累加语义）。
extends GdUnitTestSuite

# 用 K 件某套装备造一个 crew UnitInstance（取该套前 K 个槽）。
const _SLOTKEYS := ["mainweapon", "offweapon", "head", "armor", "gloves", "legs", "boots", "ring", "necklace"]

func _crew_def() -> UnitDefinition:
	for d in UnitDataManager.get_all_units():
		if d is CrewDefinition:
			return d
	return null

func _unit_with(set_short: String, k: int) -> UnitInstance:
	var eq: Dictionary = {}
	for i in range(k):
		var def := EquipmentDataManager.get_equipment("eq_%s_%s" % [set_short, _SLOTKEYS[i]])
		eq[def.slot] = def
	return UnitInstance.from_definition(_crew_def(), eq)

func test_count_sets_groups_by_set_id() -> void:
	var u := _unit_with("ironwall", 5)
	var counts := SetBonus.count_sets(u)
	assert_int(int(counts.get("set_ironwall", 0))).is_equal(5)

func test_count_sets_empty_when_no_equipment() -> void:
	var u := UnitInstance.from_definition(_crew_def(), {})
	assert_int(SetBonus.count_sets(u).size()).is_equal(0)

func test_is_tier_active_cumulative_boundaries() -> void:
	var u := _unit_with("ironwall", 6)
	assert_bool(SetBonus.is_tier_active(u, "set_ironwall", 3)).is_true()
	assert_bool(SetBonus.is_tier_active(u, "set_ironwall", 6)).is_true()
	assert_bool(SetBonus.is_tier_active(u, "set_ironwall", 9)).is_false()

func test_is_tier_active_below_threshold() -> void:
	var u := _unit_with("ironwall", 2)
	assert_bool(SetBonus.is_tier_active(u, "set_ironwall", 3)).is_false()

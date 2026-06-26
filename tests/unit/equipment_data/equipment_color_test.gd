# 校验稀有度配色/标签静态访问器（越界钳制）。
extends GdUnitTestSuite

func test_rarity_label_maps_each_tier() -> void:
	assert_str(EquipmentDefinition.rarity_label(0)).is_equal("普通")
	assert_str(EquipmentDefinition.rarity_label(4)).is_equal("传奇")

func test_rarity_label_clamps_out_of_range() -> void:
	assert_str(EquipmentDefinition.rarity_label(-1)).is_equal("普通")
	assert_str(EquipmentDefinition.rarity_label(99)).is_equal("传奇")

func test_rarity_color_distinct_per_tier() -> void:
	var seen: Dictionary = {}
	for r in range(5):
		var c := EquipmentDefinition.rarity_color(r)
		assert_bool(seen.has(c)).is_false()
		seen[c] = true

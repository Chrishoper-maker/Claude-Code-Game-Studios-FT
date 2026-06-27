# SetEffectCatalog：(set_id,tier) → 中文效果描述。
extends GdUnitTestSuite

func test_describe_known_set_tier_nonempty() -> void:
	assert_str(SetEffectCatalog.describe("set_ironwall", 9)).is_not_equal("")
	assert_str(SetEffectCatalog.describe("set_berserker", 3)).is_not_equal("")
	assert_str(SetEffectCatalog.describe("set_healer", 6)).is_not_equal("")
	assert_str(SetEffectCatalog.describe("set_navigator", 9)).is_not_equal("")

func test_describe_unknown_returns_empty() -> void:
	assert_str(SetEffectCatalog.describe("set_frost", 3)).is_equal("")
	assert_str(SetEffectCatalog.describe("set_ironwall", 1)).is_equal("")

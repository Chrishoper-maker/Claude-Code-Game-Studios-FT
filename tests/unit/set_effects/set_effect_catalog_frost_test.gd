# SetEffectCatalog：寒霜套各档有中文描述。
extends GdUnitTestSuite

func test_frost_set_has_descriptions() -> void:
	assert_str(SetEffectCatalog.describe("set_frost", 3)).is_equal("滞步")
	assert_str(SetEffectCatalog.describe("set_frost", 6)).is_equal("冰封")
	assert_str(SetEffectCatalog.describe("set_frost", 9)).is_equal("冻结")

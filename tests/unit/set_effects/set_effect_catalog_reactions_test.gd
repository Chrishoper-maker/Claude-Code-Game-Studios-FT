# SetEffectCatalog：三反应套各档有中文描述。
extends GdUnitTestSuite

func test_reaction_sets_have_descriptions() -> void:
	for sid in ["set_bloodthirst", "set_thorns", "set_executioner"]:
		for tier in [3, 6, 9]:
			assert_str(SetEffectCatalog.describe(sid, tier)).is_not_equal("")

# 校验 3 名 unlockable 船员存在且 tier 正确（悬赏成长解锁池）。
extends GdUnitTestSuite

const EXPECTED: Array[String] = ["crew_gunner_03", "crew_medic_02", "crew_swordsman_04"]

func test_three_unlockable_crew_exist_with_tier() -> void:
	var found: Array[String] = []
	for def in UnitDataManager.get_all_units():
		if def is CrewDefinition and (def as CrewDefinition).recruit_pool_tier == "unlockable":
			found.append((def as CrewDefinition).id)
	for id in EXPECTED:
		assert_bool(found.has(id)).is_true()
	assert_int(found.size()).is_equal(EXPECTED.size())

func test_unlockable_crew_have_valid_class_action() -> void:
	for id in EXPECTED:
		var def := UnitDataManager.get_unit(id)
		assert_bool(def is CrewDefinition).is_true()
		assert_str((def as CrewDefinition).class_action_id).is_not_equal("")

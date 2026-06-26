# 起始/招募直发 3 件：不同槽、80% 同套分支可复现。
extends GdUnitTestSuite

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._roster_equipment.clear()
	RunManager._excluded_offers.clear()
	RunManager._rng.seed = 12345

func test_initial_grant_returns_three_distinct_slots() -> void:
	var eids := RunManager.roll_initial_equipment()
	assert_int(eids.size()).is_equal(3)
	var slots: Dictionary = {}
	for eid in eids:
		var def := EquipmentDataManager.get_equipment(eid)
		assert_object(def).is_not_null()
		assert_bool(slots.has(def.slot)).is_false()
		slots[def.slot] = true

func test_confirm_recruit_grants_three_pieces() -> void:
	RunManager._last_offers = []
	# 取一个 pool 船员 id
	var crew_id := ""
	for def in UnitDataManager.get_all_units():
		if def is CrewDefinition and (def as CrewDefinition).recruit_pool_tier == "pool":
			crew_id = (def as CrewDefinition).id
			break
	assert_str(crew_id).is_not_equal("")
	RunManager.roster.clear()
	RunManager.confirm_recruit(crew_id)
	assert_int(RunManager.get_equipment_for(crew_id).size()).is_equal(3)

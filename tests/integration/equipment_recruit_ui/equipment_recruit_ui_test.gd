extends GdUnitTestSuite

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._rng.seed = 42

func test_confirm_recruit_equips_three_pieces() -> void:
	var rm := RunManager
	rm.start_run()
	var offers := rm.get_recruit_offers()
	var crew_id := offers[0].id
	rm.confirm_recruit(crew_id)
	assert_int(rm.get_equipment_for(crew_id).size()).is_equal(3)
	assert_str(rm.current_phase).is_equal("CHARTING")

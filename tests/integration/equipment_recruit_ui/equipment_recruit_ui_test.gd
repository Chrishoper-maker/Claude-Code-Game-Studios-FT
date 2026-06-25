extends GdUnitTestSuite

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._rng.seed = 42

func test_roll_then_confirm_two_picks_equips_crew() -> void:
	var rm := RunManager
	rm.start_run()
	var offers := rm.get_recruit_offers()
	var crew_id := offers[0].id
	var rolled := rm.roll_recruit_equipment()
	assert_int(rolled.size()).is_equal(8)
	# 模拟 UI 选 2 件不同槽
	var picks: Array[String] = []
	var seen_slots: Dictionary = {}
	for eq in rolled:
		if seen_slots.has(eq.slot): continue
		seen_slots[eq.slot] = true
		picks.append(eq.id)
		if picks.size() == 2: break
	rm.confirm_recruit(crew_id, picks)
	assert_int(rm.get_equipment_for(crew_id).size()).is_equal(2)
	assert_str(rm.current_phase).is_equal("CHARTING")

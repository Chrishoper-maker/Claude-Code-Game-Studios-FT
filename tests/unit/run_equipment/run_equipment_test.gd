# RunManager 装备账本：招募滚装备（确定性）/ 记账 / 查询 / permadeath 擦除。
extends GdUnitTestSuite

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._goto_battle = func() -> void: pass
	RunManager._goto_route  = func() -> void: pass
	RunManager.start_run()
	RunManager._rng.seed = 20260622

func after_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._goto_battle = RunManager._default_goto_battle
	RunManager._goto_route  = RunManager._default_goto_route

# AC-4：固定 seed 下，offer 装备确定可复现。
func test_offer_equipment_deterministic() -> void:
	RunManager._rng.seed = 777
	var offers_a := RunManager.get_recruit_offers()
	var first_id: String = offers_a[0].id
	var eq_a := RunManager.get_offer_equipment(first_id)
	RunManager._rng.seed = 777
	RunManager.get_recruit_offers()
	var eq_b := RunManager.get_offer_equipment(first_id)
	assert_bool(eq_a != null).is_true()
	assert_str(eq_a.id).is_equal(eq_b.id)

# AC-5：confirm_recruit 后 get_equipment_for 返回招募时滚到的装备。
func test_confirm_recruit_records_equipment() -> void:
	var offers := RunManager.get_recruit_offers()
	var chosen: String = offers[0].id
	var offered_eq := RunManager.get_offer_equipment(chosen)
	RunManager.confirm_recruit(chosen)
	var held := RunManager.get_equipment_for(chosen)
	assert_bool(held != null).is_true()
	assert_str(held.id).is_equal(offered_eq.id)

# AC-6：permadeath 后 get_equipment_for 返回 null。
func test_permadeath_clears_equipment() -> void:
	var offers := RunManager.get_recruit_offers()
	var chosen: String = offers[0].id
	RunManager.confirm_recruit(chosen)
	RunManager._on_crew_member_downed(chosen)
	assert_object(RunManager.get_equipment_for(chosen)).is_null()

# 起始船员无装备。
func test_starting_crew_has_no_equipment() -> void:
	var starter: String = RunManager.get_roster()[0].id
	assert_object(RunManager.get_equipment_for(starter)).is_null()

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

# AC-5：confirm_recruit 后 get_equipment_for 返回包含招募时滚到的装备的字典。
func test_confirm_recruit_records_equipment() -> void:
	var offers := RunManager.get_recruit_offers()
	var chosen: String = offers[0].id
	var offered_eq := RunManager.get_offer_equipment(chosen)
	RunManager.confirm_recruit(chosen)
	var held: Dictionary = RunManager.get_equipment_for(chosen)
	assert_bool(held.is_empty()).is_false()
	# 字典中应该有一个槽装备，值为招募时 offer 的装备
	var found_eq: EquipmentDefinition = null
	for s in held:
		found_eq = held[s]
	assert_bool(found_eq != null).is_true()
	assert_str(found_eq.id).is_equal(offered_eq.id)

# AC-6：permadeath 后 get_equipment_for 返回空字典。
func test_permadeath_clears_equipment() -> void:
	var offers := RunManager.get_recruit_offers()
	var chosen: String = offers[0].id
	RunManager.confirm_recruit(chosen)
	RunManager._on_crew_member_downed(chosen)
	assert_int(RunManager.get_equipment_for(chosen).size()).is_equal(0)

# 起始船员无装备。
func test_starting_crew_has_no_equipment() -> void:
	var starter: String = RunManager.get_roster()[0].id
	assert_int(RunManager.get_equipment_for(starter).size()).is_equal(0)

# get_equipment_for 返回 slot 字典（slot:int → EquipmentDefinition）。
func test_get_equipment_for_returns_slot_dict() -> void:
	var rm := RunManager
	rm._roster_equipment = { "gunner_01": { EquipmentDefinition.Slot.MAIN_WEAPON: "eq_cutlass" } }
	var slots := rm.get_equipment_for("gunner_01")
	assert_int(slots.size()).is_equal(1)
	assert_object(slots[EquipmentDefinition.Slot.MAIN_WEAPON]).is_not_null()
	assert_str(slots[EquipmentDefinition.Slot.MAIN_WEAPON].id).is_equal("eq_cutlass")

# get_equipment_for 无船员时返回空字典。
func test_get_equipment_for_missing_crew_returns_empty() -> void:
	RunManager._roster_equipment = {}
	assert_int(RunManager.get_equipment_for("nobody").size()).is_equal(0)

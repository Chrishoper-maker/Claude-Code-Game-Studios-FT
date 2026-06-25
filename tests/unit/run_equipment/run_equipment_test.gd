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

# AC-5：confirm_recruit with equip_picks records equipment in roster by slot.
func test_confirm_recruit_assigns_two_picks_to_slots() -> void:
	var rm := RunManager
	rm._autosave_enabled = false
	rm.start_run()
	var offers := rm.get_recruit_offers()
	var crew_id := offers[0].id
	# 选两件不同槽：弯刀(主武器) + 板甲(护甲)
	rm.confirm_recruit(crew_id, ["eq_cutlass", "eq_plate"])
	var slots := rm.get_equipment_for(crew_id)
	assert_int(slots.size()).is_equal(2)
	assert_str(slots[EquipmentDefinition.Slot.MAIN_WEAPON].id).is_equal("eq_cutlass")
	assert_str(slots[EquipmentDefinition.Slot.ARMOR].id).is_equal("eq_plate")

# confirm_recruit 两件同槽时仅第一件生效（第二件 push_error 后忽略）。
func test_confirm_recruit_same_slot_keeps_first_only() -> void:
	var rm := RunManager
	rm._autosave_enabled = false
	rm.start_run()
	var offers := rm.get_recruit_offers()
	var crew_id := offers[0].id
	# 两件同为主武器：仅第一件生效
	rm.confirm_recruit(crew_id, ["eq_cutlass", "eq_sabre"])
	var slots := rm.get_equipment_for(crew_id)
	assert_int(slots.size()).is_equal(1)
	assert_str(slots[EquipmentDefinition.Slot.MAIN_WEAPON].id).is_equal("eq_cutlass")

# AC-6：permadeath 后 get_equipment_for 返回空字典。
func test_permadeath_clears_equipment() -> void:
	var offers := RunManager.get_recruit_offers()
	var chosen: String = offers[0].id
	RunManager.confirm_recruit(chosen, ["eq_cutlass"])
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

# confirm_recruit 无装备选择时 get_equipment_for 返回空（默认行为向后兼容）。
func test_confirm_recruit_no_picks_gives_empty_equipment() -> void:
	var offers := RunManager.get_recruit_offers()
	var chosen: String = offers[0].id
	RunManager.confirm_recruit(chosen)
	assert_int(RunManager.get_equipment_for(chosen).size()).is_equal(0)

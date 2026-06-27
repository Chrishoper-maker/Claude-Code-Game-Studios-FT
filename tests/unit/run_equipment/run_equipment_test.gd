# RunManager 装备账本：直发 3 件（确定性）/ 记账 / 查询 / permadeath 擦除。
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

# AC-5：confirm_recruit 直发 3 件，记入 roster 装备账本（各槽不同）。
func test_confirm_recruit_grants_three_pieces_to_distinct_slots() -> void:
	var rm := RunManager
	rm._autosave_enabled = false
	rm.start_run()
	var offers := rm.get_recruit_offers()
	var crew_id := offers[0].id
	rm.confirm_recruit(crew_id)
	var slots := rm.get_equipment_for(crew_id)
	assert_int(slots.size()).is_equal(3)
	# 所有槽互不相同（slot 是 int key，Dictionary 本身保证唯一 key）
	for s in slots:
		assert_object(slots[s]).is_not_null()

# _grant_equipment 同槽覆盖：第二件覆盖第一件（新行为：last-wins）。
func test_grant_equipment_same_slot_overwrites_previous() -> void:
	var rm := RunManager
	rm._roster_equipment.clear()
	# 直接调内部函数：两件同为主武器 → 第二件胜出
	rm._grant_equipment("test_crew", ["eq_berserker_mainweapon", "eq_ironwall_mainweapon"])
	var slots := rm.get_equipment_for("test_crew")
	assert_int(slots.size()).is_equal(1)
	assert_str(slots[EquipmentDefinition.Slot.MAIN_WEAPON].id).is_equal("eq_ironwall_mainweapon")

# AC-6：permadeath 后 get_equipment_for 返回空字典。
func test_permadeath_clears_equipment() -> void:
	var offers := RunManager.get_recruit_offers()
	var chosen: String = offers[0].id
	RunManager.confirm_recruit(chosen)
	RunManager._on_crew_member_downed(chosen)
	assert_int(RunManager.get_equipment_for(chosen).size()).is_equal(0)

# 起始船员在 start_run 时自动获得 3 件装备。
func test_starting_crew_gets_three_equipment() -> void:
	var starter: String = RunManager.get_roster()[0].id
	assert_int(RunManager.get_equipment_for(starter).size()).is_equal(3)

# get_equipment_for 返回 slot 字典（slot:int → EquipmentDefinition）。
func test_get_equipment_for_returns_slot_dict() -> void:
	var rm := RunManager
	rm._roster_equipment = { "gunner_01": { EquipmentDefinition.Slot.MAIN_WEAPON: "eq_berserker_mainweapon" } }
	var slots := rm.get_equipment_for("gunner_01")
	assert_int(slots.size()).is_equal(1)
	assert_object(slots[EquipmentDefinition.Slot.MAIN_WEAPON]).is_not_null()
	assert_str(slots[EquipmentDefinition.Slot.MAIN_WEAPON].id).is_equal("eq_berserker_mainweapon")

# get_equipment_for 无船员时返回空字典。
func test_get_equipment_for_missing_crew_returns_empty() -> void:
	RunManager._roster_equipment = {}
	assert_int(RunManager.get_equipment_for("nobody").size()).is_equal(0)

# confirm_recruit 默认直发 3 件（新行为：无需选择）。
func test_confirm_recruit_default_grants_three_equipment() -> void:
	var offers := RunManager.get_recruit_offers()
	var chosen: String = offers[0].id
	RunManager.confirm_recruit(chosen)
	assert_int(RunManager.get_equipment_for(chosen).size()).is_equal(3)

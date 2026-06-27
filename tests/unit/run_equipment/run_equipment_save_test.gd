# 装备账本进存档：to_save_dict→load 往返恢复（嵌套格式）；旧档扁平 id 迁移；缺失 equip id 跳过。
extends GdUnitTestSuite

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._goto_battle = func() -> void: pass
	RunManager._goto_route  = func() -> void: pass
	RunManager.start_run()

func after_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._goto_battle = RunManager._default_goto_battle
	RunManager._goto_route  = RunManager._default_goto_route

# 嵌套装备账本往返恢复（两个槽都保存还原）。
func test_nested_roster_equipment_roundtrips() -> void:
	var rm := RunManager
	rm.start_run()
	var crew_id := rm.roster[0].id
	rm._roster_equipment = { crew_id: { EquipmentDefinition.Slot.ARMOR: "eq_ironwall_armor", EquipmentDefinition.Slot.MAIN_WEAPON: "eq_berserker_mainweapon" } }
	var d := rm.to_save_dict()
	rm._roster_equipment = {}
	rm.load_from_save_dict(d)
	var slots: Dictionary = rm._roster_equipment[crew_id]
	assert_int(slots.size()).is_equal(2)
	assert_str(str(slots[EquipmentDefinition.Slot.ARMOR])).is_equal("eq_ironwall_armor")

# 旧档扁平 id 格式迁移 → 按装备 slot 放入。
func test_legacy_flat_id_migrates_to_slot() -> void:
	var rm := RunManager
	rm.start_run()
	var crew_id := rm.roster[0].id
	# 旧档：roster_equipment 为 crew_id → 单 eid
	var legacy := rm.to_save_dict()
	legacy["roster_equipment"] = { crew_id: "eq_navigator_boots" }   # 旧扁平格式
	rm._roster_equipment = {}
	rm.load_from_save_dict(legacy)
	var slots: Dictionary = rm._roster_equipment[crew_id]
	assert_str(str(slots[EquipmentDefinition.Slot.BOOTS])).is_equal("eq_navigator_boots")

# 缺失装备定义 → 该条目跳过、不崩。
func test_missing_definition_dropped() -> void:
	var rm := RunManager
	rm.start_run()
	var crew_id := rm.roster[0].id
	var d := rm.to_save_dict()
	d["roster_equipment"] = { crew_id: { EquipmentDefinition.Slot.ARMOR: "eq_does_not_exist" } }
	rm._roster_equipment = {}
	rm.load_from_save_dict(d)
	assert_bool(rm._roster_equipment.has(crew_id)).is_false()

func test_pending_battle_equip_roundtrips() -> void:
	RunManager._autosave_enabled = false
	RunManager._save_path = "user://test_run_pbe.json"
	RunManager.start_run()
	var real_id := RunManager.roster[0].id
	RunManager._roster_equipment.clear()
	RunManager._pending_battle_equip = {real_id: ["eq_ironwall_head", "eq_ironwall_armor"]}
	var d := RunManager.to_save_dict()
	RunManager._pending_battle_equip.clear()
	RunManager.load_from_save_dict(d)
	assert_bool(RunManager.get_pending_battle_equip().has(real_id)).is_true()
	RunManager.delete_save()

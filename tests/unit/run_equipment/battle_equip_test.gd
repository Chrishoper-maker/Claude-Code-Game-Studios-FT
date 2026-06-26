# 战后滚 8 选 2 + 偏向主套 + 阶段流转。
extends GdUnitTestSuite

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._roster_equipment.clear()
	RunManager._pending_battle_equip.clear()
	RunManager._rng.seed = 777

func test_roll_battle_returns_eight() -> void:
	var rolled := RunManager.roll_battle_equipment("c1")
	assert_int(rolled.size()).is_equal(8)

func test_roll_battle_biases_toward_dominant_set() -> void:
	# c1 主套 set_ironwall（2 件）
	RunManager._roster_equipment["c1"] = {0: "eq_ironwall_mainweapon", 3: "eq_ironwall_armor"}
	var rolled := RunManager.roll_battle_equipment("c1")
	var same := 0
	for eid in rolled:
		var def := EquipmentDataManager.get_equipment(eid)
		if def != null and def.set_id == "set_ironwall":
			same += 1
	assert_int(same).is_greater(4)   # 80% 偏向 → 多数同套（固定 seed 下稳定）

func test_equip_piece_fills_empty_slot() -> void:
	var ok := RunManager.equip_piece("c1", "eq_ironwall_head", false)
	assert_bool(ok).is_true()
	assert_int(RunManager.get_equipment_for("c1").size()).is_equal(1)

func test_equip_piece_rejects_occupied_without_replace() -> void:
	RunManager.equip_piece("c1", "eq_ironwall_head", false)
	# eq_berserker_head 同为 head 槽
	var ok := RunManager.equip_piece("c1", "eq_berserker_head", false)
	assert_bool(ok).is_false()
	assert_str(str(RunManager.get_equipment_for("c1")[2].id)).is_equal("eq_ironwall_head")

func test_equip_piece_replaces_when_allowed() -> void:
	RunManager.equip_piece("c1", "eq_ironwall_head", false)
	var ok := RunManager.equip_piece("c1", "eq_berserker_head", true)
	assert_bool(ok).is_true()
	assert_str(str(RunManager.get_equipment_for("c1")[2].id)).is_equal("eq_berserker_head")

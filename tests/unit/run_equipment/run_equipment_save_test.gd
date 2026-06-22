# 装备账本进存档：to_save_dict→load 往返恢复；load 缺失 equip id 跳过。
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

# AC-8：roster_equipment 往返恢复。
func test_roster_equipment_roundtrip() -> void:
	var offers := RunManager.get_recruit_offers()
	var chosen: String = offers[0].id
	RunManager.confirm_recruit(chosen)
	var eq_before := RunManager.get_equipment_for(chosen)
	var d := RunManager.to_save_dict()
	RunManager.start_run()                 # 打乱清账本
	RunManager.load_from_save_dict(d)
	var eq_after := RunManager.get_equipment_for(chosen)
	assert_bool(eq_after != null).is_true()
	assert_str(eq_after.id).is_equal(eq_before.id)

# AC-8：load 缺失 equipment id → 该条目跳过、不崩。
func test_load_skips_missing_equipment_id() -> void:
	var d := {
		"roster": ["crew_swordsman_01"],
		"island_index": 0,
		"phase": "DEPLOYING",
		"roster_equipment": {"crew_swordsman_01": "eq_nonexistent_zzz"},
	}
	RunManager.load_from_save_dict(d)
	assert_object(RunManager.get_equipment_for("crew_swordsman_01")).is_null()

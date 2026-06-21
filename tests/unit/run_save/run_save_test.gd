# RunManager 序列化往返（纯，无文件 I/O）。_autosave_enabled=false 防 Task 2 后 start_run 写盘。
extends GdUnitTestSuite

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager.start_run()   # roster=2 starting, DEPLOYING

func after_test() -> void:
	RunManager._autosave_enabled = false

# AC-1：to_save_dict → load_from_save_dict 往返恢复。
func test_to_from_save_dict_roundtrip() -> void:
	RunManager.current_island_index = 3
	var downed: Array[String] = ["crew_swordsman_01"]
	RunManager._downed_this_run = downed
	var excluded: Array[String] = ["crew_gunner_01"]
	RunManager._excluded_offers = excluded
	var roster_before: Array[String] = []
	for c in RunManager.get_roster():
		roster_before.append(c.id)
	var phase_before := RunManager.current_phase
	var d: Dictionary = RunManager.to_save_dict()
	RunManager.start_run()   # 打乱重置
	RunManager.load_from_save_dict(d)
	assert_int(RunManager.current_island_index).is_equal(3)
	assert_str(RunManager.current_phase).is_equal(phase_before)
	assert_bool(RunManager._downed_this_run.has("crew_swordsman_01")).is_true()
	assert_bool(RunManager._excluded_offers.has("crew_gunner_01")).is_true()
	var roster_after: Array[String] = []
	for c in RunManager.get_roster():
		roster_after.append(c.id)
	assert_array(roster_after).is_equal(roster_before)

# AC-2：load 跳过不存在的 crew id。
func test_load_skips_missing_crew_id() -> void:
	var d: Dictionary = {
		"roster": ["crew_swordsman_01", "nonexistent_crew_zzz"],
		"island_index": 0,
		"phase": "DEPLOYING",
	}
	RunManager.load_from_save_dict(d)
	var ids: Array[String] = []
	for c in RunManager.get_roster():
		ids.append(c.id)
	assert_bool(ids.has("crew_swordsman_01")).is_true()
	assert_bool(ids.has("nonexistent_crew_zzz")).is_false()
	assert_int(ids.size()).is_equal(1)

# AC-3：load 不发 run_phase_changed（直接赋 _phase）。
func test_load_does_not_emit_phase_changed() -> void:
	var monitor := monitor_signals(EventBus, false)
	RunManager.load_from_save_dict({"phase": "RECRUITING", "island_index": 1})
	assert_str(RunManager.current_phase).is_equal("RECRUITING")
	await assert_signal(monitor).is_not_emitted("run_phase_changed")

# 部分 dict 缺键时不破坏既有 island/last_run_won（非破坏性默认）。
func test_load_partial_dict_preserves_absent_fields() -> void:
	RunManager.current_island_index = 4
	RunManager.last_run_won = true
	RunManager.load_from_save_dict({"phase": "RECRUITING"})
	assert_int(RunManager.current_island_index).is_equal(4)
	assert_bool(RunManager.last_run_won).is_true()
	assert_str(RunManager.current_phase).is_equal("RECRUITING")

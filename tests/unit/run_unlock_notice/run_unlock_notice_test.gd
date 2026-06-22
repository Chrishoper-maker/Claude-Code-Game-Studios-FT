# RunManager 记录本航新解锁船员（末岛胜利捕获 unlock_next 返回值）。
extends GdUnitTestSuite

const TMP_META := "user://test_meta_unlock_notice.json"

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._goto_battle = func() -> void: pass
	RunManager._goto_route  = func() -> void: pass
	MetaProgress._save_path = TMP_META
	MetaProgress.unlocked_crew_ids.clear()
	if FileAccess.file_exists(TMP_META):
		DirAccess.remove_absolute(TMP_META)
	RunManager.start_run()

func after_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._goto_battle = RunManager._default_goto_battle
	RunManager._goto_route  = RunManager._default_goto_route
	MetaProgress.unlocked_crew_ids.clear()
	if FileAccess.file_exists(TMP_META):
		DirAccess.remove_absolute(TMP_META)
	MetaProgress._save_path = "user://meta.json"

# AC-1：末岛胜利后记录 unlock_next 解锁的 id（未全解锁时非空）。
func test_final_win_records_unlocked() -> void:
	var expected: String = MetaProgress.get_unlock_order()[0]
	RunManager.current_island_index = RunManager.ISLAND_COUNT_MAX - 1   # +1 >= MAX → 末岛胜利
	RunManager._on_battle_won()
	assert_str(RunManager.get_unlocked_this_run()).is_equal(expected)

# AC-2：全部 unlockable 已解锁 → 末岛胜利后为 ""。
func test_final_win_all_unlocked_empty() -> void:
	MetaProgress.unlocked_crew_ids = MetaProgress.get_unlock_order().duplicate()
	RunManager.current_island_index = RunManager.ISLAND_COUNT_MAX - 1
	RunManager._on_battle_won()
	assert_str(RunManager.get_unlocked_this_run()).is_equal("")

# AC-3：start_run 后为 ""。
func test_start_run_clears_unlocked() -> void:
	RunManager.current_island_index = RunManager.ISLAND_COUNT_MAX - 1
	RunManager._on_battle_won()
	RunManager.start_run()
	assert_str(RunManager.get_unlocked_this_run()).is_equal("")

# AC-4：失败结局不解锁 → "".
func test_loss_does_not_unlock() -> void:
	RunManager._on_battle_lost()
	assert_str(RunManager.get_unlocked_this_run()).is_equal("")

# 航点自动存档：进入 DEPLOYING/RECRUITING 存、RUN_END 删；开关关时不写。
extends GdUnitTestSuite

const TMP := "user://test_autosave.json"

func before_test() -> void:
	RunManager._goto_battle = func() -> void: pass
	RunManager._goto_route  = func() -> void: pass
	RunManager._save_path = TMP
	RunManager._autosave_enabled = true
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(TMP)

func after_test() -> void:
	RunManager._goto_battle = RunManager._default_goto_battle
	RunManager._goto_route  = RunManager._default_goto_route
	RunManager._save_path = "user://run.json"
	RunManager._autosave_enabled = false
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(TMP)

# AC-7：进入 DEPLOYING（start_run）自动存。
func test_entering_deploying_autosaves() -> void:
	RunManager.start_run()
	assert_bool(RunManager.has_save()).is_true()

# AC-7：进入 RECRUITING 自动存。
func test_entering_recruiting_autosaves() -> void:
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(TMP)
	RunManager._set_run_phase(RunManager.RunPhase.RUN_RECRUITING)
	assert_bool(RunManager.has_save()).is_true()

# AC-7：进入 RUN_END 删档。
func test_entering_run_end_deletes_save() -> void:
	RunManager.start_run()
	assert_bool(RunManager.has_save()).is_true()
	RunManager._set_run_phase(RunManager.RunPhase.RUN_END)
	assert_bool(RunManager.has_save()).is_false()

# AC-8：开关关时不写。
func test_autosave_disabled_no_write() -> void:
	RunManager._autosave_enabled = false
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(TMP)
	RunManager.start_run()
	assert_bool(RunManager.has_save()).is_false()

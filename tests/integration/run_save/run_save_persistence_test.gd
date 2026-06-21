# RunManager 文件存读档（临时 user:// 路径）。不调 start_run → 不依赖自动存档。
extends GdUnitTestSuite

const TMP := "user://test_run_save.json"

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._save_path = TMP
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(TMP)

func after_test() -> void:
	RunManager._save_path = "user://run.json"
	RunManager._autosave_enabled = false
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(TMP)

# AC-4：save_run → load_run 文件往返。
func test_save_then_load_roundtrip() -> void:
	RunManager.current_island_index = 2
	RunManager.save_run()
	assert_bool(RunManager.has_save()).is_true()
	RunManager.current_island_index = 99
	RunManager.load_run()
	assert_int(RunManager.current_island_index).is_equal(2)

# AC-5：has_save / delete_save。
func test_has_save_and_delete_save() -> void:
	assert_bool(RunManager.has_save()).is_false()
	RunManager.save_run()
	assert_bool(RunManager.has_save()).is_true()
	RunManager.delete_save()
	assert_bool(RunManager.has_save()).is_false()

# AC-6：缺文件 load 不改状态。
func test_load_missing_file_no_change() -> void:
	RunManager.current_island_index = 5
	RunManager.load_run()
	assert_int(RunManager.current_island_index).is_equal(5)

# AC-6：坏文件 load 不崩、不改状态。
func test_load_corrupt_file_no_change() -> void:
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string("not json {{{")
	f.close()
	RunManager.current_island_index = 7
	RunManager.load_run()
	assert_int(RunManager.current_island_index).is_equal(7)

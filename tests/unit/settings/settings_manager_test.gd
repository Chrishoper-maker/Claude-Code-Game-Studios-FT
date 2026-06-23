# SettingsManager：音量钳/静音、字典与文件往返、缺/坏文件默认。
extends GdUnitTestSuite

const TMP := "user://test_settings_mgr.json"

func before_test() -> void:
	SettingsManager._save_path = TMP
	SettingsManager.master_volume = 1.0
	SettingsManager.fullscreen = false
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(TMP)

func after_test() -> void:
	SettingsManager.master_volume = 1.0
	SettingsManager.fullscreen = false
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(TMP)
	SettingsManager._save_path = "user://settings.json"
	AudioServer.set_bus_mute(0, false)

# AC-1：音量钳 0–1。
func test_set_master_volume_clamps() -> void:
	SettingsManager.set_master_volume(0.5)
	assert_float(SettingsManager.master_volume).is_equal_approx(0.5, 0.0001)
	SettingsManager.set_master_volume(2.0)
	assert_float(SettingsManager.master_volume).is_equal_approx(1.0, 0.0001)
	SettingsManager.set_master_volume(-1.0)
	assert_float(SettingsManager.master_volume).is_equal_approx(0.0, 0.0001)

# AC-2：0 音量静音 Master，非 0 解除。
func test_zero_volume_mutes_master() -> void:
	SettingsManager.set_master_volume(0.0)
	assert_bool(AudioServer.is_bus_mute(0)).is_true()
	SettingsManager.set_master_volume(0.5)
	assert_bool(AudioServer.is_bus_mute(0)).is_false()

# AC-3：to_dict → from_dict 往返。
func test_to_from_dict_roundtrip() -> void:
	SettingsManager.master_volume = 0.3
	SettingsManager.fullscreen = true
	var d := SettingsManager.to_dict()
	SettingsManager.master_volume = 1.0
	SettingsManager.fullscreen = false
	SettingsManager.from_dict(d)
	assert_float(SettingsManager.master_volume).is_equal_approx(0.3, 0.0001)
	assert_bool(SettingsManager.fullscreen).is_true()

# AC-4：save → load 文件往返。
func test_save_load_roundtrip() -> void:
	SettingsManager.set_master_volume(0.7)
	SettingsManager.set_fullscreen(true)
	SettingsManager.master_volume = 1.0
	SettingsManager.fullscreen = false
	SettingsManager.load_settings()
	assert_float(SettingsManager.master_volume).is_equal_approx(0.7, 0.0001)
	assert_bool(SettingsManager.fullscreen).is_true()

# AC-4：缺文件 load → 默认。
func test_load_missing_file_defaults() -> void:
	SettingsManager.master_volume = 0.42
	SettingsManager.load_settings()   # TMP 已在 before_test 删除
	assert_float(SettingsManager.master_volume).is_equal_approx(1.0, 0.0001)

# AC-4：坏文件 load → 默认。
func test_load_corrupt_file_defaults() -> void:
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string("}{ not json")
	f.close()
	SettingsManager.master_volume = 0.42
	SettingsManager.load_settings()
	assert_float(SettingsManager.master_volume).is_equal_approx(1.0, 0.0001)

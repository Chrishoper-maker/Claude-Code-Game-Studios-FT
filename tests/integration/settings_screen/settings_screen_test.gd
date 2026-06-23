# SettingsScreen 白盒交互：音量 ±、显示模式切换、返回接缝、场景实例化。
extends GdUnitTestSuite

const TMP := "user://test_settings_screen.json"

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

# AC-5：＋ 升 0.1 并更新标签。
func test_volume_up_increases_and_labels() -> void:
	SettingsManager.master_volume = 0.5
	var s: SettingsScreen = auto_free(SettingsScreen.new())
	add_child(s)
	s._on_vol_up()
	assert_float(SettingsManager.master_volume).is_equal_approx(0.6, 0.0001)
	assert_str(s._volume_label.text).contains("60")

# AC-5：＋ 上限钳 1.0。
func test_volume_up_clamps_at_one() -> void:
	SettingsManager.master_volume = 1.0
	var s: SettingsScreen = auto_free(SettingsScreen.new())
	add_child(s)
	s._on_vol_up()
	assert_float(SettingsManager.master_volume).is_equal_approx(1.0, 0.0001)

# AC-5：－ 降 0.1。
func test_volume_down_decreases() -> void:
	SettingsManager.master_volume = 0.5
	var s: SettingsScreen = auto_free(SettingsScreen.new())
	add_child(s)
	s._on_vol_down()
	assert_float(SettingsManager.master_volume).is_equal_approx(0.4, 0.0001)

# AC-5：显示模式切换 + 按钮文案。
func test_window_toggle_flips_and_labels() -> void:
	SettingsManager.fullscreen = false
	var s: SettingsScreen = auto_free(SettingsScreen.new())
	add_child(s)
	s._on_window_toggle()
	assert_bool(SettingsManager.fullscreen).is_true()
	assert_str(s._window_button.text).contains("全屏")

# AC-6：返回触发接缝。
func test_back_invokes_nav_seam() -> void:
	var s: SettingsScreen = auto_free(SettingsScreen.new())
	add_child(s)
	var called := [0]
	s._nav_back = func() -> void: called[0] += 1
	s._on_back()
	assert_int(called[0]).is_equal(1)

# 场景实例化 smoke（SceneManager preload 正确）。
func test_scenes_instantiate() -> void:
	var ss: Node = SceneManager.SETTINGS_SCENE.instantiate()
	assert_bool(ss is SettingsScreen).is_true()
	ss.free()
	var mm: Node = SceneManager.MAIN_MENU_SCENE.instantiate()
	assert_bool(mm is MainMenu).is_true()
	mm.free()

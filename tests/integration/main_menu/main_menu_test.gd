# 主菜单集成测试（白盒）：渲染 + 解锁进度 + 导航/退出/继续接缝（不真的切场景/退出）。
extends GdUnitTestSuite

const TMP_SAVE := "user://test_main_menu_save.json"
const TMP_CAPTAIN := "user://test_main_menu_captain.json"

func before_test() -> void:
	MetaProgress.unlocked_crew_ids.clear()
	RunManager._save_path = TMP_SAVE
	if FileAccess.file_exists(TMP_SAVE):
		DirAccess.remove_absolute(TMP_SAVE)
	if FileAccess.file_exists(TMP_CAPTAIN):
		DirAccess.remove_absolute(TMP_CAPTAIN)

func after_test() -> void:
	MetaProgress.unlocked_crew_ids.clear()
	if FileAccess.file_exists(TMP_SAVE):
		DirAccess.remove_absolute(TMP_SAVE)
	RunManager._save_path = "user://run.json"
	if FileAccess.file_exists(TMP_CAPTAIN):
		DirAccess.remove_absolute(TMP_CAPTAIN)

# 写一个最小存档文件，使 RunManager.has_save() 为真。
func _write_dummy_save() -> void:
	var f := FileAccess.open(TMP_SAVE, FileAccess.WRITE)
	f.store_string("{}")
	f.close()

# AC-1：渲染出航/退出按钮 + 解锁进度（清空时 0/3）。
func test_renders_buttons_and_unlock_progress() -> void:
	var mm: MainMenu = auto_free(MainMenu.new())
	add_child(mm)
	assert_bool(mm._set_sail_button != null).is_true()
	assert_bool(mm._quit_button != null).is_true()
	assert_str(mm._unlock_label.text).is_equal("悬赏解锁 0 / 3")

# AC-2：解锁进度反映 MetaProgress。
func test_unlock_progress_reflects_metaprogress() -> void:
	var ids: Array[String] = ["crew_gunner_03", "crew_medic_02"]
	MetaProgress.unlocked_crew_ids = ids
	var mm: MainMenu = auto_free(MainMenu.new())
	add_child(mm)
	assert_str(mm._unlock_label.text).is_equal("悬赏解锁 2 / 3")

# AC-3：出航触发导航接缝。
func test_set_sail_invokes_nav_seam() -> void:
	var mm: MainMenu = auto_free(MainMenu.new())
	mm._captain_path = TMP_CAPTAIN
	add_child(mm)
	var called := [0]
	mm._nav_set_sail = func() -> void: called[0] += 1
	mm._on_set_sail()
	assert_int(called[0]).is_equal(1)

# AC-4：退出触发退出接缝。
func test_quit_invokes_quit_seam() -> void:
	var mm: MainMenu = auto_free(MainMenu.new())
	add_child(mm)
	var called := [0]
	mm._nav_quit = func() -> void: called[0] += 1
	mm._on_quit()
	assert_int(called[0]).is_equal(1)

# AC-5：main_scene 指向 MainMenu。
func test_main_scene_is_main_menu() -> void:
	var scene: String = str(ProjectSettings.get_setting("application/run/main_scene"))
	assert_str(scene).is_equal("res://scenes/MainMenu.tscn")

# AC-6：有存档时渲染"继续航程"按钮。
func test_continue_button_present_when_save_exists() -> void:
	_write_dummy_save()
	var mm: MainMenu = auto_free(MainMenu.new())
	add_child(mm)
	assert_bool(mm._continue_button != null).is_true()

# AC-7：无存档时不渲染"继续航程"按钮。
func test_continue_button_absent_when_no_save() -> void:
	var mm: MainMenu = auto_free(MainMenu.new())
	add_child(mm)
	assert_bool(mm._continue_button == null).is_true()

# AC-8：继续航程触发继续接缝。
func test_continue_invokes_nav_seam() -> void:
	_write_dummy_save()
	var mm: MainMenu = auto_free(MainMenu.new())
	add_child(mm)
	var called := [0]
	mm._nav_continue = func() -> void: called[0] += 1
	mm._on_continue()
	assert_int(called[0]).is_equal(1)

# AC-7：渲染「设置」按钮。
func test_renders_settings_button() -> void:
	var mm: MainMenu = auto_free(MainMenu.new())
	add_child(mm)
	assert_bool(mm._settings_button != null).is_true()

# AC-7：设置触发导航接缝。
func test_settings_invokes_nav_seam() -> void:
	var mm: MainMenu = auto_free(MainMenu.new())
	add_child(mm)
	var called := [0]
	mm._nav_settings = func() -> void: called[0] += 1
	mm._on_settings()
	assert_int(called[0]).is_equal(1)

# AC-5：渲染船长代号输入框。
func test_renders_captain_input() -> void:
	var mm: MainMenu = auto_free(MainMenu.new())
	add_child(mm)
	assert_bool(mm._captain_input != null).is_true()

# AC-5：渲染「游客模式」按钮。
func test_renders_guest_button() -> void:
	var mm: MainMenu = auto_free(MainMenu.new())
	add_child(mm)
	assert_bool(mm._guest_button != null).is_true()

# AC-5：游客模式触发导航接缝。
func test_guest_invokes_nav_seam() -> void:
	var mm: MainMenu = auto_free(MainMenu.new())
	mm._captain_path = TMP_CAPTAIN
	add_child(mm)
	var called := [0]
	mm._nav_guest = func() -> void: called[0] += 1
	mm._on_guest()
	assert_int(called[0]).is_equal(1)

# AC-5：船长代号 getter 返回去空白后的输入文本。
func test_captain_name_returns_trimmed_text() -> void:
	var mm: MainMenu = auto_free(MainMenu.new())
	add_child(mm)
	mm._captain_input.text = "  红胡子  "
	assert_str(mm._captain_name()).is_equal("红胡子")

# AC-5：船长代号存盘往返（注入临时路径）。
func test_captain_save_load_roundtrip() -> void:
	var mm: MainMenu = auto_free(MainMenu.new())
	mm._captain_path = TMP_CAPTAIN
	add_child(mm)
	mm._captain_input.text = "钢爪"
	mm.save_captain()
	assert_str(mm.load_captain()).is_equal("钢爪")

# AC-5：缺文件 load → 空串。
func test_captain_load_missing_returns_empty() -> void:
	var mm: MainMenu = auto_free(MainMenu.new())
	mm._captain_path = TMP_CAPTAIN   # before_test 已删，保证不存在
	add_child(mm)
	assert_str(mm.load_captain()).is_equal("")

# AC-5：坏文件 load → 空串。
func test_captain_load_corrupt_returns_empty() -> void:
	var f := FileAccess.open(TMP_CAPTAIN, FileAccess.WRITE)
	f.store_string("}{ not json")
	f.close()
	var mm: MainMenu = auto_free(MainMenu.new())
	mm._captain_path = TMP_CAPTAIN   # before_test 已删，保证不存在
	add_child(mm)
	assert_str(mm.load_captain()).is_equal("")

# AC-1/2/3：视觉层节点在缺美术素材时仍由占位创建、不崩。
func test_visual_layers_present_with_placeholders() -> void:
	var mm: MainMenu = auto_free(MainMenu.new())
	add_child(mm)
	assert_bool(mm._bg_far != null).is_true()
	assert_bool(mm._hero_center != null).is_true()
	assert_bool(mm._hero_left != null).is_true()
	assert_bool(mm._hero_right != null).is_true()
	assert_bool(mm._vignette != null).is_true()

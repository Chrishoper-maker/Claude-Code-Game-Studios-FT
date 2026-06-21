# 主菜单集成测试（白盒）：渲染 + 解锁进度 + 导航/退出接缝（不真的切场景/退出）。
extends GdUnitTestSuite

func before_test() -> void:
	MetaProgress.unlocked_crew_ids.clear()

func after_test() -> void:
	MetaProgress.unlocked_crew_ids.clear()

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

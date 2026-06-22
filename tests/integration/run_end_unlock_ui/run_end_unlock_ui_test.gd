# RouteScene run-end 页展示本航解锁船员行（AC-5）。直驱 RUN_END 分支。
extends GdUnitTestSuite

const UNLOCK_ID := "crew_gunner_03"   # 既有 unlockable crew

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._goto_battle = func() -> void: pass
	RunManager._goto_route  = func() -> void: pass
	RunManager.start_run()

func after_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._goto_battle = RunManager._default_goto_battle
	RunManager._goto_route  = RunManager._default_goto_route
	RunManager.start_run()

# 递归收集树下所有 Label 文本。
func _all_label_texts(node: Node) -> Array[String]:
	var out: Array[String] = []
	for child in node.get_children():
		if child is Label:
			out.append((child as Label).text)
		out.append_array(_all_label_texts(child))
	return out

# AC-5：有解锁时 run-end 含含该船员 display_name 的解锁行。
func test_run_end_shows_unlock_line() -> void:
	var def := UnitDataManager.get_unit(UNLOCK_ID)
	assert_bool(def is CrewDefinition).is_true()   # 前置：该 unlockable crew 存在
	var crew := def as CrewDefinition
	RunManager.last_run_won = true
	RunManager.current_island_index = RunManager.ISLAND_COUNT_MAX - 1
	RunManager._unlocked_this_run = UNLOCK_ID
	RunManager._phase = RunManager.RunPhase.RUN_END
	var route: RouteScene = auto_free(RouteScene.new())
	add_child(route)   # _ready → RUN_END → _notice_then(_show_run_end)（无阵亡直通）
	assert_str(route._active_screen).is_equal("run_end")
	var texts := _all_label_texts(route)
	var found := false
	for t in texts:
		if t.contains("解锁") and t.contains(crew.display_name):
			found = true
	assert_bool(found).is_true()

# AC-5（反向）：无解锁时无解锁行。
func test_run_end_no_unlock_line_when_empty() -> void:
	RunManager.last_run_won = false
	RunManager.current_island_index = 2
	RunManager._unlocked_this_run = ""
	RunManager._phase = RunManager.RunPhase.RUN_END
	var route: RouteScene = auto_free(RouteScene.new())
	add_child(route)
	var texts := _all_label_texts(route)
	var found := false
	for t in texts:
		if t.contains("解锁新船员"):
			found = true
	assert_bool(found).is_false()

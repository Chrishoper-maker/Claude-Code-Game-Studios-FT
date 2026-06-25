# 招募卡文字（AC-9 已迁移到 Task 5 新 roll-8-pick-2 UI）。
# Task 4 起：get_offer_equipment 已删除；招募卡仅显示职业/名字/口号（装备摘要留 Task 5）。
extends GdUnitTestSuite

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._goto_battle = func() -> void: pass
	RunManager._goto_route  = func() -> void: pass
	RunManager.start_run()
	RunManager._rng.seed = 4242
	RunManager._phase = RunManager.RunPhase.RUN_RECRUITING   # 直接置 RECRUITING（不发信号）

func after_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._goto_battle = RunManager._default_goto_battle
	RunManager._goto_route  = RunManager._default_goto_route

# 递归收集树下所有 Button 文本。
func _all_button_texts(node: Node) -> Array[String]:
	var out: Array[String] = []
	for child in node.get_children():
		if child is Button:
			out.append((child as Button).text)
		out.append_array(_all_button_texts(child))
	return out

# AC-9（Task 4 stub）：招募卡按钮文字含候选 display_name（装备摘要延至 Task 5）。
func test_recruit_card_shows_crew_name() -> void:
	var route: RouteScene = auto_free(RouteScene.new())
	add_child(route)   # _ready → RECRUITING → _show_recruit_offers（无阵亡，直通）
	assert_str(route._active_screen).is_equal("recruit")
	var texts := _all_button_texts(route)
	# 本批候选的 display_name 应出现在某张卡文字中。
	var found := false
	for o in RunManager._last_offers:
		var def := UnitDataManager.get_unit(o)
		if def == null:
			continue
		for t in texts:
			if t.contains((def as CrewDefinition).display_name):
				found = true
	assert_bool(found).is_true()

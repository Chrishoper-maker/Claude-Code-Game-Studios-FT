# 招募卡文字含候选装备名（AC-9）。直驱 RECRUITING 分支（设 _phase）。
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

# AC-9：至少一张招募卡文字含其装备的 display_name。
func test_recruit_card_shows_equipment_name() -> void:
	var route: RouteScene = auto_free(RouteScene.new())
	add_child(route)   # _ready → RECRUITING → _show_recruit_offers（无阵亡，直通）
	assert_str(route._active_screen).is_equal("recruit")
	var texts := _all_button_texts(route)
	# 本批某候选的装备名应出现在某张卡文字中。
	var found := false
	for o in RunManager._last_offers:
		var eq := RunManager.get_offer_equipment(o)
		if eq == null:
			continue
		for t in texts:
			if t.contains(eq.display_name):
				found = true
	assert_bool(found).is_true()

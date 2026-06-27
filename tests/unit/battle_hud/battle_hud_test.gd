# BattleHUD：动作浮窗仅在选中单位时可见；含 4 动作按钮；顶部信息条存在。
extends GdUnitTestSuite

func _make_def(faction: String, unit_class: String, verb: String) -> UnitDefinition:
	var d := UnitDefinition.new()
	d.id = "%s_%s" % [faction, unit_class]
	d.faction = faction; d.unit_class = unit_class
	d.base_damage = 3; d.move_range = 3; d.attack_range = 1; d.max_hp = 10
	d.class_action_id = verb
	return d

func _ctx() -> Dictionary:
	var gb: GridBoard = auto_free(GridBoard.new())
	var tm: TurnManager = auto_free(TurnManager.new())
	var br: BattleResolution = auto_free(BattleResolution.new())
	var bb: BondGaugeBurst = auto_free(BondGaugeBurst.new())
	br.setup(gb, tm); bb.setup(gb, tm, br)
	var ctrl: PlayerTurnController = auto_free(PlayerTurnController.new())
	ctrl.setup(tm, gb, br, bb)
	return {"gb": gb, "tm": tm, "br": br, "bb": bb, "ctrl": ctrl}

func test_action_panel_hidden_when_no_selection() -> void:
	var ctx := _ctx()
	var hud: BattleHUD = auto_free(BattleHUD.new())
	add_child(hud)
	hud.setup(ctx.ctrl, ctx.tm)
	hud.refresh()
	assert_bool(hud._action_panel.visible).is_false()

func test_action_panel_visible_with_selection_and_has_four_buttons() -> void:
	var ctx := _ctx()
	var inst := UnitInstance.from_definition(_make_def("crew", "swordsman", "slash"))
	inst.grid_position = Vector2i(3, 7)
	var bid: int = ctx.tm.register_unit(inst)
	ctx.gb.place_unit(bid, Vector2i(3, 7))
	var hud: BattleHUD = auto_free(BattleHUD.new())
	add_child(hud)
	hud.setup(ctx.ctrl, ctx.tm)
	ctx.ctrl._on_player_phase_started()
	ctx.ctrl.select_unit(bid)
	hud.refresh()
	assert_bool(hud._action_panel.visible).is_true()
	assert_int([hud._btn_move, hud._btn_attack, hud._btn_verb, hud._btn_burst].size()).is_equal(4)

func test_end_unit_button_present_and_enabled_only_when_selected() -> void:
	var ctx := _ctx()
	var inst := UnitInstance.from_definition(_make_def("crew", "swordsman", "slash"))
	inst.grid_position = Vector2i(3, 7)
	var bid: int = ctx.tm.register_unit(inst)
	ctx.gb.place_unit(bid, Vector2i(3, 7))
	var hud: BattleHUD = auto_free(BattleHUD.new())
	add_child(hud)
	hud.setup(ctx.ctrl, ctx.tm)
	ctx.ctrl._on_player_phase_started()
	hud.refresh()
	assert_object(hud._btn_end_unit).is_not_null()
	assert_bool(hud._btn_end_unit.disabled).is_true()   # 未选中 → 禁用
	ctx.ctrl.select_unit(bid)
	hud.refresh()
	assert_bool(hud._btn_end_unit.disabled).is_false()  # 选中 → 可用

func test_action_panel_hidden_in_enemy_phase() -> void:
	var ctx := _ctx()
	var hud: BattleHUD = auto_free(BattleHUD.new())
	add_child(hud)
	hud.setup(ctx.ctrl, ctx.tm)
	ctx.ctrl._on_player_phase_started()
	ctx.ctrl._on_enemy_phase_started()
	hud.refresh()
	assert_bool(hud._action_panel.visible).is_false()

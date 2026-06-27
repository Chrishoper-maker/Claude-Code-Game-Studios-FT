extends GdUnitTestSuite

func before_test() -> void:
	if EventBus.battle_won.is_connected(RunManager._on_battle_won):
		EventBus.battle_won.disconnect(RunManager._on_battle_won)

func after_test() -> void:
	if not EventBus.battle_won.is_connected(RunManager._on_battle_won):
		EventBus.battle_won.connect(RunManager._on_battle_won)

func _make_def(faction: String, unit_class: String, dmg: int, move_range: int, hp: int, verb: String) -> UnitDefinition:
	var d := UnitDefinition.new()
	d.id = "%s_%s" % [faction, unit_class]
	d.faction = faction
	d.unit_class = unit_class
	d.base_damage = dmg
	d.move_range = move_range
	d.attack_range = 1
	d.max_hp = hp
	d.class_action_id = verb
	return d

func _register(tm: TurnManager, gb: GridBoard, def: UnitDefinition, pos: Vector2i) -> int:
	var inst := UnitInstance.from_definition(def)
	inst.grid_position = pos
	var bid := tm.register_unit(inst)
	gb.place_unit(bid, pos)
	return bid

func _make_controller() -> Dictionary:
	var gb: GridBoard = auto_free(GridBoard.new())
	var tm: TurnManager = auto_free(TurnManager.new())
	var br: BattleResolution = auto_free(BattleResolution.new())
	var bb: BondGaugeBurst = auto_free(BondGaugeBurst.new())
	br.setup(gb, tm)
	bb.setup(gb, tm, br)
	var ctrl: PlayerTurnController = auto_free(PlayerTurnController.new())
	ctrl.setup(tm, gb, br, bb)
	return {"gb": gb, "tm": tm, "br": br, "bb": bb, "ctrl": ctrl}

# 进入我方回合并选中一个己方单位指挥（自由点选模型）。
func _begin_select(ctx: Dictionary, unit_id: int) -> void:
	ctx.ctrl._on_player_phase_started()
	ctx.ctrl.select_unit(unit_id)

func _fill_gauge(bb: BondGaugeBurst) -> void:
	for i in 6:
		bb.apply_attack_charge(0, true)  # +2/次，6 次 → clamp 满

# ── 选择 ──
func test_select_crew_unit_makes_it_active() -> void:
	var ctx := _make_controller()
	var crew := _register(ctx.tm, ctx.gb, _make_def("crew", "swordsman", 3, 3, 10, "slash"), Vector2i(3, 7))
	_begin_select(ctx, crew)
	assert_bool(ctx.ctrl.is_active()).is_true()
	assert_int(ctx.ctrl.get_current_unit_id()).is_equal(crew)
	# #1：选中可移动单位后自动进 MOVE（crew 在 (3,7)、move_range 3、未移动 → 可达非空）
	assert_int(ctx.ctrl.get_mode()).is_equal(PlayerTurnController.Mode.MOVE)
	assert_bool(ctx.ctrl.get_valid_targets().is_empty()).is_false()

func test_select_unit_with_no_move_left_stays_idle() -> void:
	var ctx := _make_controller()
	var crew := _register(ctx.tm, ctx.gb, _make_def("crew", "swordsman", 3, 3, 10, "slash"), Vector2i(3, 7))
	ctx.ctrl._on_player_phase_started()
	ctx.tm.mark_has_moved(crew)            # 已移动 → 无可达
	ctx.ctrl.select_unit(crew)
	assert_int(ctx.ctrl.get_mode()).is_equal(PlayerTurnController.Mode.IDLE)

func test_select_enemy_unit_rejected() -> void:
	var ctx := _make_controller()
	var enemy := _register(ctx.tm, ctx.gb, _make_def("enemy", "swordsman", 2, 2, 6, ""), Vector2i(3, 0))
	ctx.ctrl._on_player_phase_started()
	ctx.ctrl.select_unit(enemy)
	assert_bool(ctx.ctrl.is_active()).is_false()

func test_no_input_outside_player_phase() -> void:
	var ctx := _make_controller()
	var crew := _register(ctx.tm, ctx.gb, _make_def("crew", "swordsman", 3, 3, 10, "slash"), Vector2i(3, 7))
	ctx.ctrl._on_enemy_phase_started()   # 敌方回合
	ctx.ctrl.select_unit(crew)
	ctx.ctrl.set_mode(PlayerTurnController.Mode.MOVE)
	assert_bool(ctx.ctrl.is_active()).is_false()
	assert_array(ctx.ctrl.get_valid_targets()).is_empty()

# ── 点击空闲态己方单位 = 选中 ──
func test_click_idle_on_ally_selects_it() -> void:
	var ctx := _make_controller()
	var crew := _register(ctx.tm, ctx.gb, _make_def("crew", "swordsman", 3, 3, 10, "slash"), Vector2i(3, 7))
	ctx.ctrl._on_player_phase_started()
	ctx.ctrl.handle_cell_click(Vector2i(3, 7))
	assert_int(ctx.ctrl.get_current_unit_id()).is_equal(crew)

# ── MOVE ──
func test_set_mode_move_targets_are_reachable_cells() -> void:
	var ctx := _make_controller()
	var crew := _register(ctx.tm, ctx.gb, _make_def("crew", "swordsman", 3, 3, 10, "slash"), Vector2i(3, 7))
	_begin_select(ctx, crew)
	ctx.ctrl.set_mode(PlayerTurnController.Mode.MOVE)
	var expected: Array = ctx.gb.get_reachable_cells(Vector2i(3, 7), 3)
	assert_array(ctx.ctrl.get_valid_targets()).is_equal(expected)
	assert_int(ctx.ctrl.get_mode()).is_equal(PlayerTurnController.Mode.MOVE)

func test_handle_cell_click_move_relocates_unit_and_marks_moved() -> void:
	var ctx := _make_controller()
	var crew := _register(ctx.tm, ctx.gb, _make_def("crew", "swordsman", 3, 3, 10, "slash"), Vector2i(3, 7))
	_begin_select(ctx, crew)
	ctx.ctrl.set_mode(PlayerTurnController.Mode.MOVE)
	ctx.ctrl.handle_cell_click(Vector2i(3, 6))
	var u: UnitInstance = ctx.tm.get_unit(crew)
	assert_vector(u.grid_position).is_equal(Vector2i(3, 6))
	assert_bool(u.has_moved).is_true()
	assert_vector(ctx.gb.get_unit_pos(crew)).is_equal(Vector2i(3, 6))
	assert_int(ctx.ctrl.get_mode()).is_equal(PlayerTurnController.Mode.IDLE)

func test_handle_cell_click_illegal_cell_no_effect() -> void:
	var ctx := _make_controller()
	var crew := _register(ctx.tm, ctx.gb, _make_def("crew", "swordsman", 3, 3, 10, "slash"), Vector2i(3, 7))
	_begin_select(ctx, crew)
	ctx.ctrl.set_mode(PlayerTurnController.Mode.MOVE)
	ctx.ctrl.handle_cell_click(Vector2i(0, 0))
	var u: UnitInstance = ctx.tm.get_unit(crew)
	assert_vector(u.grid_position).is_equal(Vector2i(3, 7))
	assert_bool(u.has_moved).is_false()

# ── ATTACK ──
func test_set_mode_attack_targets_are_in_range_enemies() -> void:
	var ctx := _make_controller()
	var crew := _register(ctx.tm, ctx.gb, _make_def("crew", "swordsman", 3, 3, 10, "slash"), Vector2i(3, 6))
	_register(ctx.tm, ctx.gb, _make_def("enemy", "swordsman", 2, 2, 6, ""), Vector2i(3, 5))
	_begin_select(ctx, crew)
	ctx.ctrl.set_mode(PlayerTurnController.Mode.ATTACK)
	assert_array(ctx.ctrl.get_valid_targets()).contains([Vector2i(3, 5)])

func test_handle_cell_click_attack_damages_enemy() -> void:
	var ctx := _make_controller()
	var crew := _register(ctx.tm, ctx.gb, _make_def("crew", "swordsman", 3, 3, 10, "slash"), Vector2i(3, 6))
	var enemy := _register(ctx.tm, ctx.gb, _make_def("enemy", "swordsman", 2, 2, 6, ""), Vector2i(3, 5))
	_begin_select(ctx, crew)
	ctx.ctrl.set_mode(PlayerTurnController.Mode.ATTACK)
	ctx.ctrl.handle_cell_click(Vector2i(3, 5))
	assert_int(ctx.tm.get_unit(enemy).current_hp).is_equal(3)
	assert_bool(ctx.tm.get_unit(crew).has_acted).is_true()
	assert_int(ctx.ctrl.get_mode()).is_equal(PlayerTurnController.Mode.IDLE)

# ── 技能（slash/guard）──
func test_do_verb_slash_hits_adjacent_enemy_and_marks_verb() -> void:
	var ctx := _make_controller()
	var crew := _register(ctx.tm, ctx.gb, _make_def("crew", "swordsman", 3, 3, 10, "slash"), Vector2i(3, 6))
	var enemy := _register(ctx.tm, ctx.gb, _make_def("enemy", "swordsman", 2, 2, 6, ""), Vector2i(3, 5))
	_begin_select(ctx, crew)
	ctx.ctrl.do_verb()
	assert_bool(ctx.tm.get_unit(crew).has_used_verb).is_true()
	assert_int(ctx.tm.get_unit(enemy).current_hp).is_equal(3)

func test_do_verb_guard_marks_self_verb() -> void:
	var ctx := _make_controller()
	var crew := _register(ctx.tm, ctx.gb, _make_def("crew", "bulwark", 2, 2, 12, "guard"), Vector2i(3, 6))
	_begin_select(ctx, crew)
	ctx.ctrl.do_verb()
	assert_bool(ctx.tm.get_unit(crew).has_used_verb).is_true()

# ── 爆发 ──
func test_begin_burst_targeting_highlights_eligible_leads() -> void:
	var ctx := _make_controller()
	_register(ctx.tm, ctx.gb, _make_def("crew", "swordsman", 3, 3, 10, "slash"), Vector2i(3, 7))
	_register(ctx.tm, ctx.gb, _make_def("crew", "bulwark", 2, 2, 12, "guard"), Vector2i(3, 6))
	_fill_gauge(ctx.bb)
	ctx.ctrl._on_player_phase_started()
	ctx.ctrl.begin_burst_targeting()
	assert_int(ctx.ctrl.get_mode()).is_equal(PlayerTurnController.Mode.BURST_LEAD)
	assert_array(ctx.ctrl.get_valid_targets()).contains([Vector2i(3, 7), Vector2i(3, 6)])

func test_burst_lead_then_partner_activates_burst() -> void:
	var ctx := _make_controller()
	_register(ctx.tm, ctx.gb, _make_def("crew", "swordsman", 3, 3, 10, "slash"), Vector2i(3, 7))
	_register(ctx.tm, ctx.gb, _make_def("crew", "bulwark", 2, 2, 12, "guard"), Vector2i(3, 6))
	_register(ctx.tm, ctx.gb, _make_def("enemy", "swordsman", 2, 2, 6, ""), Vector2i(3, 5))
	_fill_gauge(ctx.bb)
	ctx.ctrl._on_player_phase_started()
	ctx.ctrl.begin_burst_targeting()
	ctx.ctrl.handle_cell_click(Vector2i(3, 7))
	assert_int(ctx.ctrl.get_mode()).is_equal(PlayerTurnController.Mode.BURST_PARTNER)
	ctx.ctrl.handle_cell_click(Vector2i(3, 6))
	assert_bool(ctx.bb.is_full()).is_false()
	assert_int(ctx.ctrl.get_mode()).is_equal(PlayerTurnController.Mode.IDLE)

# ── available_actions + end_player_phase ──
func test_get_available_actions_reflects_flags() -> void:
	var ctx := _make_controller()
	var crew := _register(ctx.tm, ctx.gb, _make_def("crew", "swordsman", 3, 3, 10, "slash"), Vector2i(3, 6))
	_register(ctx.tm, ctx.gb, _make_def("enemy", "swordsman", 2, 2, 6, ""), Vector2i(3, 5))
	_begin_select(ctx, crew)
	var a: Dictionary = ctx.ctrl.get_available_actions()
	assert_bool(a["move"]).is_true()
	assert_bool(a["attack"]).is_true()
	assert_bool(a["verb"]).is_true()
	assert_bool(a["burst"]).is_false()
	ctx.ctrl.set_mode(PlayerTurnController.Mode.ATTACK)
	ctx.ctrl.handle_cell_click(Vector2i(3, 5))
	assert_bool(ctx.ctrl.get_available_actions()["attack"]).is_false()

func test_end_player_phase_advances_round() -> void:
	var ctx := _make_controller()
	var crew := _register(ctx.tm, ctx.gb, _make_def("crew", "swordsman", 3, 3, 10, "slash"), Vector2i(3, 6))
	_register(ctx.tm, ctx.gb, _make_def("enemy", "swordsman", 2, 2, 6, ""), Vector2i(3, 0))
	ctx.tm.start_battle()           # → 我方回合（controller 经信号激活）
	ctx.ctrl.select_unit(crew)
	ctx.ctrl.end_player_phase()
	assert_int(ctx.tm.get_current_round()).is_equal(2)
	assert_int(ctx.tm.get_battle_state()).is_equal(TurnManager.BattleState.PLAYER_PHASE)

# ── 动词选靶（aura / heal / displace）──
# AC-1：aura 无目标立即执行 → 相邻友方获 AURA + 标记动词。
func test_do_verb_aura_buffs_adjacent_ally_and_marks_verb() -> void:
	var ctx := _make_controller()
	var bard := _register(ctx.tm, ctx.gb, _make_def("crew", "musician", 1, 2, 8, "aura"), Vector2i(3, 6))
	var ally := _register(ctx.tm, ctx.gb, _make_def("crew", "swordsman", 3, 3, 10, "slash"), Vector2i(3, 5))
	_begin_select(ctx, bard)
	ctx.ctrl.do_verb()
	assert_bool(ctx.tm.get_unit(bard).has_used_verb).is_true()
	assert_bool(ctx.br.get_unit_status(ally, BattleResolution.STATUS_AURA)).is_true()
	assert_int(ctx.ctrl.get_mode()).is_equal(PlayerTurnController.Mode.IDLE)

# AC-2：heal 进入选靶，点相邻受损友方 → 治疗 + 标记动词。
func test_do_verb_heal_targets_and_heals_adjacent_ally() -> void:
	var ctx := _make_controller()
	var medic := _register(ctx.tm, ctx.gb, _make_def("crew", "medic", 1, 2, 8, "heal"), Vector2i(3, 6))
	var ally := _register(ctx.tm, ctx.gb, _make_def("crew", "swordsman", 3, 3, 10, "slash"), Vector2i(3, 5))
	ctx.tm.get_unit(ally).current_hp = 4
	_begin_select(ctx, medic)
	ctx.ctrl.do_verb()
	assert_int(ctx.ctrl.get_mode()).is_equal(PlayerTurnController.Mode.VERB)
	assert_array(ctx.ctrl.get_valid_targets()).contains([Vector2i(3, 5)])
	ctx.ctrl.handle_cell_click(Vector2i(3, 5))
	assert_int(ctx.tm.get_unit(ally).current_hp).is_equal(7)   # 4 + HEAL_AMOUNT(3)
	assert_bool(ctx.tm.get_unit(medic).has_used_verb).is_true()
	assert_int(ctx.ctrl.get_mode()).is_equal(PlayerTurnController.Mode.IDLE)

# AC-3：displace 进入选靶，点相邻敌方 → 推离 + 标记动词。
func test_do_verb_displace_pushes_adjacent_enemy() -> void:
	var ctx := _make_controller()
	var nav := _register(ctx.tm, ctx.gb, _make_def("crew", "navigator", 1, 2, 8, "displace"), Vector2i(3, 6))
	var enemy := _register(ctx.tm, ctx.gb, _make_def("enemy", "swordsman", 2, 2, 6, ""), Vector2i(3, 5))
	_begin_select(ctx, nav)
	ctx.ctrl.do_verb()
	assert_int(ctx.ctrl.get_mode()).is_equal(PlayerTurnController.Mode.VERB)
	assert_array(ctx.ctrl.get_valid_targets()).contains([Vector2i(3, 5)])
	ctx.ctrl.handle_cell_click(Vector2i(3, 5))
	assert_vector(ctx.tm.get_unit(enemy).grid_position).is_equal(Vector2i(3, 3))   # 推离 nav 方向 2 格
	assert_bool(ctx.tm.get_unit(nav).has_used_verb).is_true()

# AC-4：heal 无相邻友方 → 目标空、verb 不可用。
func test_heal_no_adjacent_ally_no_targets() -> void:
	var ctx := _make_controller()
	var medic := _register(ctx.tm, ctx.gb, _make_def("crew", "medic", 1, 2, 8, "heal"), Vector2i(3, 6))
	_register(ctx.tm, ctx.gb, _make_def("enemy", "swordsman", 2, 2, 6, ""), Vector2i(0, 0))
	_begin_select(ctx, medic)
	ctx.ctrl.do_verb()
	assert_array(ctx.ctrl.get_valid_targets()).is_empty()
	assert_bool(ctx.ctrl.get_available_actions()["verb"]).is_false()

# AC-5：cannon 选直线（≥最小射程）敌方，穿透命中 + 标记动词；近于最小射程者不可选。
func test_do_verb_cannon_targets_inline_enemy_and_fires() -> void:
	var ctx := _make_controller()
	var gdef := _make_def("crew", "gunner", 3, 2, 7, "cannon")
	gdef.attack_range = 3   # 炮手远程（fixture 默认 1，cannon 需更大射程）
	var gunner := _register(ctx.tm, ctx.gb, gdef, Vector2i(3, 6))
	_register(ctx.tm, ctx.gb, _make_def("enemy", "swordsman", 2, 2, 6, ""), Vector2i(3, 5))   # 曼哈顿1 <2 不可选
	var far := _register(ctx.tm, ctx.gb, _make_def("enemy", "swordsman", 2, 2, 6, ""), Vector2i(3, 3))  # 同列 曼哈顿3 ∈[2,3] 可选
	_begin_select(ctx, gunner)
	ctx.ctrl.do_verb()
	assert_int(ctx.ctrl.get_mode()).is_equal(PlayerTurnController.Mode.VERB)
	assert_array(ctx.ctrl.get_valid_targets()).contains([Vector2i(3, 3)])
	assert_array(ctx.ctrl.get_valid_targets()).not_contains([Vector2i(3, 5)])
	ctx.ctrl.handle_cell_click(Vector2i(3, 3))
	assert_bool(ctx.tm.get_unit(gunner).has_used_verb).is_true()
	assert_int(ctx.tm.get_unit(far).current_hp).is_less(6)   # 穿透命中
	assert_int(ctx.ctrl.get_mode()).is_equal(PlayerTurnController.Mode.IDLE)

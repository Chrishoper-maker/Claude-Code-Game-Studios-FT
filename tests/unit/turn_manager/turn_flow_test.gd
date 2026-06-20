# TurnManager 阶段制回合流转 + 胜负（2026-06-20 设计：我方回合→敌方回合，无回合上限，一方全灭分胜负）。
extends GdUnitTestSuite

func before_test() -> void:
	if EventBus.battle_won.is_connected(RunManager._on_battle_won):
		EventBus.battle_won.disconnect(RunManager._on_battle_won)

func after_test() -> void:
	if not EventBus.battle_won.is_connected(RunManager._on_battle_won):
		EventBus.battle_won.connect(RunManager._on_battle_won)

var _uid: int

func _tm() -> TurnManager:
	return auto_free(TurnManager.new())

func _reg(tm: TurnManager, faction: String, move_range: int, verb: String = "") -> int:
	_uid += 1
	var d := UnitDefinition.new()
	d.id = "u%d" % _uid
	d.faction = faction
	d.move_range = move_range
	d.max_hp = 6
	d.class_action_id = verb
	var inst := UnitInstance.from_definition(d)
	return tm.register_unit(inst)

# ── 阶段流转 ──

func test_start_battle_enters_player_phase() -> void:
	var tm := _tm()
	_reg(tm, "crew", 3)
	_reg(tm, "enemy", 1)
	tm.start_battle()
	assert_int(tm.get_battle_state()).is_equal(TurnManager.BattleState.PLAYER_PHASE)
	assert_int(tm.get_current_round()).is_equal(1)

func test_end_player_phase_runs_enemies_and_returns_to_player_phase_next_round() -> void:
	var tm := _tm()
	_reg(tm, "crew", 3)
	_reg(tm, "enemy", 1)   # 无 EnemyAI 接线 → 敌方回合空转，直接进下一轮
	tm.start_battle()
	tm.end_player_phase()
	assert_int(tm.get_battle_state()).is_equal(TurnManager.BattleState.PLAYER_PHASE)
	assert_int(tm.get_current_round()).is_equal(2)

func test_action_flags_reset_each_round() -> void:
	var tm := _tm()
	var a := _reg(tm, "crew", 3, "slash")
	_reg(tm, "enemy", 1)
	tm.start_battle()
	tm.mark_has_moved(a)
	tm.mark_has_used_verb(a)
	tm.end_player_phase()   # → 第2轮，重置
	assert_bool(tm.get_unit(a).has_moved).is_false()
	assert_bool(tm.get_unit(a).has_used_verb).is_false()

func test_no_verb_unit_keeps_used_verb_true_on_reset() -> void:
	var tm := _tm()
	var a := _reg(tm, "crew", 3, "")
	_reg(tm, "enemy", 1)
	tm.start_battle()
	tm.end_player_phase()
	assert_bool(tm.get_unit(a).has_used_verb).is_true()

func test_no_round_limit_battle_continues() -> void:
	var tm := _tm()
	_reg(tm, "crew", 3)
	_reg(tm, "enemy", 1)
	tm.start_battle()
	for i in 10:
		tm.end_player_phase()
	assert_int(tm.get_battle_state()).is_equal(TurnManager.BattleState.PLAYER_PHASE)
	assert_int(tm.get_current_round()).is_equal(11)
	assert_bool(tm.is_in_terminal_state()).is_false()

# ── 胜负（一方全灭）──

func test_victory_when_all_enemies_downed() -> void:
	var tm := _tm()
	_reg(tm, "crew", 3)
	var e := _reg(tm, "enemy", 1)
	tm.start_battle()
	tm.remove_from_alive(e)
	EventBus.unit_downed.emit(e)
	assert_int(tm.get_battle_state()).is_equal(TurnManager.BattleState.BATTLE_WIN)

func test_defeat_when_all_allies_downed() -> void:
	var tm := _tm()
	var a := _reg(tm, "crew", 3)
	_reg(tm, "enemy", 1)
	tm.start_battle()
	tm.remove_from_alive(a)
	EventBus.unit_downed.emit(a)
	assert_int(tm.get_battle_state()).is_equal(TurnManager.BattleState.BATTLE_LOSS)

func test_ally_downed_with_survivors_no_terminal() -> void:
	var tm := _tm()
	var a := _reg(tm, "crew", 3)
	_reg(tm, "crew", 2)
	_reg(tm, "enemy", 1)
	tm.start_battle()
	tm.remove_from_alive(a)
	EventBus.unit_downed.emit(a)
	assert_bool(tm.is_in_terminal_state()).is_false()

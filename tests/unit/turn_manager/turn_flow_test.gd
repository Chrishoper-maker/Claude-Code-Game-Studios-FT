# TurnManager 先攻队列 + 回合轮转 + 胜负（turn-management GDD Rule 1-6 / 公式1）。
# 先攻 = move_range×2 + ally_bonus + tiebreak(unit_id) 降序；行动点每轮重置；
# 胜利即时(敌全灭)，失败 ROUND_END 检测(round_count==ROUND_LIMIT)。
# TDD：先于实现写就。
extends GdUnitTestSuite

# 隔离：BATTLE_WIN/LOSS 会 emit battle_won/lost，全局 RunManager(autoload) 监听 battle_won。
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

# ── 先攻队列（公式1，降序）──

func test_initiative_queue_descending() -> void:
	var tm := _tm()
	var a_fast := _reg(tm, "crew", 3)    # 7.x 最高
	var e_fast := _reg(tm, "enemy", 3)   # 6.x
	var a_slow := _reg(tm, "crew", 1)    # 2.x
	tm.start_battle()
	assert_array(tm.get_initiative_queue()).is_equal([a_fast, e_fast, a_slow])

func test_initiative_same_faction_tiebreak_by_id() -> void:
	var tm := _tm()
	var first := _reg(tm, "crew", 3)     # bid 较小 → tiebreak 较小
	var second := _reg(tm, "crew", 3)    # bid 较大 → tiebreak 较大 → 更前
	tm.start_battle()
	assert_array(tm.get_initiative_queue()).is_equal([second, first])

# ── 回合轮转 ──

func test_first_unit_turn_begins_after_start() -> void:
	var tm := _tm()
	var a := _reg(tm, "crew", 3)
	_reg(tm, "enemy", 1)
	tm.start_battle()
	assert_int(tm.get_battle_state()).is_equal(TurnManager.BattleState.ACTIVE_TURN)
	assert_int(tm.get_current_unit_id()).is_equal(a)

func test_end_turn_advances_to_next() -> void:
	var tm := _tm()
	var a := _reg(tm, "crew", 3)
	var b := _reg(tm, "enemy", 1)
	tm.start_battle()
	tm.end_current_turn()
	assert_int(tm.get_current_unit_id()).is_equal(b)

func test_round_advances_after_all_turns() -> void:
	var tm := _tm()
	_reg(tm, "crew", 3)
	_reg(tm, "enemy", 1)
	tm.start_battle()
	assert_int(tm.get_current_round()).is_equal(1)
	tm.end_current_turn()
	tm.end_current_turn()   # 本轮两单位走完 → 进第2轮
	assert_int(tm.get_current_round()).is_equal(2)
	assert_int(tm.get_battle_state()).is_equal(TurnManager.BattleState.ACTIVE_TURN)

func test_action_flags_reset_each_round() -> void:
	var tm := _tm()
	var a := _reg(tm, "crew", 3, "slash")   # 有动词
	_reg(tm, "enemy", 1)
	tm.start_battle()
	tm.mark_has_moved(a)
	tm.mark_has_used_verb(a)
	tm.end_current_turn()
	tm.end_current_turn()   # 进第2轮 → 重置
	assert_bool(tm.get_unit(a).has_moved).is_false()
	assert_bool(tm.get_unit(a).has_used_verb).is_false()

func test_no_verb_unit_keeps_used_verb_true_on_reset() -> void:
	var tm := _tm()
	var a := _reg(tm, "crew", 3, "")        # 无动词 → has_used_verb 恒 true
	_reg(tm, "enemy", 1)
	tm.start_battle()
	tm.end_current_turn()
	tm.end_current_turn()   # 第2轮重置
	assert_bool(tm.get_unit(a).has_used_verb).is_true()

# ── 胜负 ──

func test_victory_when_all_enemies_downed() -> void:
	var tm := _tm()
	_reg(tm, "crew", 3)
	var e := _reg(tm, "enemy", 1)
	tm.start_battle()
	tm.remove_from_alive(e)
	EventBus.unit_downed.emit(e)            # 最后一个敌人倒下
	assert_int(tm.get_battle_state()).is_equal(TurnManager.BattleState.BATTLE_WIN)

func test_no_victory_when_ally_downed() -> void:
	var tm := _tm()
	var a := _reg(tm, "crew", 3)
	_reg(tm, "enemy", 1)
	tm.start_battle()
	tm.remove_from_alive(a)
	EventBus.unit_downed.emit(a)            # 友方倒下，敌方仍存活
	assert_int(tm.get_battle_state()).is_not_equal(TurnManager.BattleState.BATTLE_WIN)

func test_defeat_at_round_limit() -> void:
	var tm := _tm()
	_reg(tm, "crew", 3)                     # 永不死，耗尽轮数
	_reg(tm, "enemy", 1)
	tm.start_battle()
	var guard := 0
	while tm.get_battle_state() == TurnManager.BattleState.ACTIVE_TURN and guard < 100:
		tm.end_current_turn()
		guard += 1
	assert_int(tm.get_battle_state()).is_equal(TurnManager.BattleState.BATTLE_LOSS)
	assert_int(tm.get_current_round()).is_equal(TurnManager.ROUND_LIMIT)

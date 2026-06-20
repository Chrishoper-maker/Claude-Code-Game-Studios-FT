# TurnManager 状态机测试（ADR-0004；阶段制）。
extends GdUnitTestSuite

func before_test() -> void:
	if EventBus.battle_won.is_connected(RunManager._on_battle_won):
		EventBus.battle_won.disconnect(RunManager._on_battle_won)

func after_test() -> void:
	if not EventBus.battle_won.is_connected(RunManager._on_battle_won):
		EventBus.battle_won.connect(RunManager._on_battle_won)

func test_start_battle_enters_player_phase_and_counts_round() -> void:
	var tm: TurnManager = auto_free(TurnManager.new())
	tm.start_battle()
	assert_int(tm.get_battle_state()).is_equal(TurnManager.BattleState.PLAYER_PHASE)
	assert_int(tm.get_current_round()).is_equal(1)

# 终态守卫：进入 BATTLE_WIN 后任何转换被拒，状态保持。
func test_terminal_state_guard_blocks_exit() -> void:
	var tm: TurnManager = auto_free(TurnManager.new())
	tm._set_battle_state(TurnManager.BattleState.BATTLE_WIN)
	tm._set_battle_state(TurnManager.BattleState.PLAYER_PHASE)
	assert_int(tm.get_battle_state()).is_equal(TurnManager.BattleState.BATTLE_WIN)
	assert_bool(tm.is_in_terminal_state()).is_true()

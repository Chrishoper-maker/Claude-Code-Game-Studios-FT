# TurnManager 状态机测试（ADR-0004 验证条 1/3/5）。
extends GdUnitTestSuite

# 测试隔离：TurnManager 进入 BATTLE_WIN 会 emit battle_won，而全局 RunManager(autoload)
# 监听它并调 SceneManager.goto_route()（route_scene 未赋值→assert）。单测 TurnManager 期间
# 临时断开该跨系统反应，测完恢复。
func before_test() -> void:
	if EventBus.battle_won.is_connected(RunManager._on_battle_won):
		EventBus.battle_won.disconnect(RunManager._on_battle_won)

func after_test() -> void:
	if not EventBus.battle_won.is_connected(RunManager._on_battle_won):
		EventBus.battle_won.connect(RunManager._on_battle_won)

func test_start_battle_enters_round_start_and_counts_round() -> void:
	var tm: TurnManager = auto_free(TurnManager.new())
	tm.start_battle()
	assert_int(tm.get_battle_state()).is_equal(TurnManager.BattleState.ROUND_START)
	assert_int(tm.get_current_round()).is_equal(1)

# 终态守卫（AC-12）：进入 BATTLE_WIN 后任何转换被拒，状态保持。
func test_terminal_state_guard_blocks_exit() -> void:
	var tm: TurnManager = auto_free(TurnManager.new())
	tm._set_battle_state(TurnManager.BattleState.BATTLE_WIN)
	tm._set_battle_state(TurnManager.BattleState.ROUND_START)
	assert_int(tm.get_battle_state()).is_equal(TurnManager.BattleState.BATTLE_WIN)
	assert_bool(tm.is_in_terminal_state()).is_true()

# 参数化状态：ACTIVE_TURN 携带 unit_id。
func test_active_turn_carries_unit_id() -> void:
	var tm: TurnManager = auto_free(TurnManager.new())
	tm._begin_active_turn(42)
	assert_int(tm.get_battle_state()).is_equal(TurnManager.BattleState.ACTIVE_TURN)
	assert_int(tm.get_current_unit_id()).is_equal(42)

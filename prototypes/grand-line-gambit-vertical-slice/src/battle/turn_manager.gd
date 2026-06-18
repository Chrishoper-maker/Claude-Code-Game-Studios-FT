# VERTICAL SLICE - NOT FOR PRODUCTION
# Validation Question: enum+match 状态机模式 + 终态守卫（ADR-0004）
# Date: 2026-06-18
#
# 回合状态机（ADR-0004 enum+match 模式）。切片简化为 5 态；终态守卫 + 信号发于状态进入。
class_name TurnManager
extends RefCounted

enum BattleState {
	SETUP,
	PLAYER_PHASE,
	ENEMY_PHASE,
	BATTLE_WIN,    # 终态
	BATTLE_LOSS,   # 终态
}
const TERMINAL_STATES: Array = [BattleState.BATTLE_WIN, BattleState.BATTLE_LOSS]

var _state: BattleState = BattleState.SETUP
var round_count: int = 0

func get_state() -> BattleState:
	return _state

func is_terminal() -> bool:
	return _state in TERMINAL_STATES

# 唯一转换入口（终态守卫）
func set_state(new_state: BattleState) -> void:
	if _state in TERMINAL_STATES:
		push_warning("TurnManager: 终态 [%s] 不可转换至 [%s]" % [
			BattleState.keys()[_state], BattleState.keys()[new_state]])
		return
	_state = new_state
	_on_state_entered(new_state)

func _on_state_entered(state: BattleState) -> void:
	match state:
		BattleState.PLAYER_PHASE:
			round_count += 1
			EventBus.round_started.emit(round_count)
			EventBus.player_phase_started.emit()
		BattleState.ENEMY_PHASE:
			EventBus.enemy_phase_started.emit()
		BattleState.BATTLE_WIN:
			EventBus.battle_won.emit()
		BattleState.BATTLE_LOSS:
			pass
		_:
			pass

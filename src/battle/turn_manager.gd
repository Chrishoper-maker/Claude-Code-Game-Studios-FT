# 回合状态机（BattleScene 内节点，非 autoload）。ADR-0004 enum+match 模式。
# 状态机已完整落地；alive_list/initiative/action-bool 等玩法接口（architecture.md §135）留 stub 给
# turn-management 实现 story。
class_name TurnManager
extends Node

enum BattleState {
	SETUP,
	ROUND_START,
	ACTIVE_TURN,   # 当前单位存于 _current_unit_id
	TURN_END,
	ROUND_END,
	BATTLE_WIN,    # 终态 — 不可退出（AC-12）
	BATTLE_LOSS,   # 终态
}
const BATTLE_TERMINAL_STATES: Array = [BattleState.BATTLE_WIN, BattleState.BATTLE_LOSS]

var _battle_state: BattleState = BattleState.SETUP
var _current_unit_id: int = -1              # 状态参数，仅 ACTIVE_TURN 有效
var round_count: int = 0

# §135 拥有状态：单位注册表 + 存活列表（battle_id 为数值句柄）
var _alive_list: Array[int] = []
var _units: Dictionary = {}        # int battle_id → UnitInstance
var _next_battle_id: int = 0       # 顺序分配；< 1000 约束（公式1 tiebreak 防碰撞）

const BATTLE_ID_MAX := 1000        # turn-management GDD §111/113：unit_id 必须 < 1000

# 由 BattleScene._ready() 在子系统就绪后调用（ADR-0002 / architecture.md 4d）
func start_battle() -> void:
	round_count = 0
	EventBus.battle_started.emit()
	# TODO(turn-management story)：从部署结果初始化 alive_list / initiative_queue
	_set_battle_state(BattleState.ROUND_START)

# ── 唯一转换入口（ADR-0004 终态守卫）──
func _set_battle_state(new_state: BattleState) -> void:
	if _battle_state in BATTLE_TERMINAL_STATES:
		push_warning("TurnManager: 终态 [%s] 不可转换至 [%s]" % [
			BattleState.keys()[_battle_state], BattleState.keys()[new_state]])
		return
	_battle_state = new_state
	_on_battle_state_entered(new_state)

func _on_battle_state_entered(state: BattleState) -> void:
	match state:
		BattleState.ROUND_START:
			round_count += 1
			EventBus.round_started.emit(round_count)
		BattleState.ACTIVE_TURN:
			EventBus.unit_turn_started.emit(_current_unit_id)
		BattleState.ROUND_END:
			EventBus.round_ended.emit()
		BattleState.BATTLE_WIN:
			EventBus.battle_won.emit()
		BattleState.BATTLE_LOSS:
			EventBus.battle_lost.emit()
		_:
			pass  # SETUP / TURN_END 由调用方直接处理

# ── 参数化状态（ADR-0004：先设伴随变量，再转换）──
func _begin_active_turn(unit_id: int) -> void:
	assert(unit_id >= 0, "TurnManager._begin_active_turn: 非法 unit_id")
	_current_unit_id = unit_id
	_set_battle_state(BattleState.ACTIVE_TURN)

# ── 公开接口（ADR-0004 Key Interfaces）──
func get_battle_state() -> BattleState:
	return _battle_state

func is_in_terminal_state() -> bool:
	return _battle_state in BATTLE_TERMINAL_STATES

func get_current_unit_id() -> int:
	assert(_battle_state == BattleState.ACTIVE_TURN,
		"get_current_unit_id() 在非 ACTIVE_TURN 状态调用")
	return _current_unit_id

func get_current_round() -> int:
	return round_count

# ── §135 单位注册表 + 玩法接口 ──

# 注册一个 UnitInstance，分配并返回数值 battle_id（部署阶段由 BattleMap/部署系统调用）。
# 注册即进 alive_list；battle_id 顺序唯一，断言 < 1000（GDD §113 运行时防御，拒绝静默降级）。
func register_unit(unit: UnitInstance) -> int:
	assert(_next_battle_id < BATTLE_ID_MAX, "TurnManager.register_unit: battle_id 超出 < 1000 约束")
	var battle_id := _next_battle_id
	_next_battle_id += 1
	_units[battle_id] = unit
	_alive_list.append(battle_id)
	return battle_id

func get_unit(battle_id: int) -> UnitInstance:
	return _units.get(battle_id, null)

func mark_has_moved(id: int) -> void:
	if _units.has(id): _units[id].has_moved = true

func mark_has_acted(id: int) -> void:
	if _units.has(id): _units[id].has_acted = true

func mark_has_used_verb(id: int) -> void:
	if _units.has(id): _units[id].has_used_verb = true

# 从存活列表移除（幂等：重复调用安全；erase 缺席不报错）。
func remove_from_alive(id: int) -> void:
	_alive_list.erase(id)

func get_alive_allies() -> Array[int]:
	return _alive_by_faction("crew")

func get_alive_enemies() -> Array[int]:
	return _alive_by_faction("enemy")

func _alive_by_faction(faction: String) -> Array[int]:
	var out: Array[int] = []
	for id in _alive_list:
		var u: UnitInstance = _units.get(id, null)
		if u != null and u.definition.faction == faction:
			out.append(id)
	return out

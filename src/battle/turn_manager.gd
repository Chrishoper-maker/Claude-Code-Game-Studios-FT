# 回合状态机（BattleScene 内节点，非 autoload）。ADR-0004 enum+match 模式。
# 阶段制（2026-06-20 设计改动，取代先攻交替+回合上限）：每轮 = 我方回合（玩家自由点选指挥己方
# 单位）→ 敌方回合（敌方依次自动行动）。无回合上限；胜负 = 一方全灭。
class_name TurnManager
extends Node

enum BattleState {
	SETUP,
	PLAYER_PHASE,   # 我方回合：玩家自由点选己方单位下达指令
	ENEMY_PHASE,    # 敌方回合：敌方依次自动行动
	BATTLE_WIN,     # 终态 — 不可退出
	BATTLE_LOSS,    # 终态
}
const BATTLE_TERMINAL_STATES: Array = [BattleState.BATTLE_WIN, BattleState.BATTLE_LOSS]

var _battle_state: BattleState = BattleState.SETUP
var round_count: int = 0

# §135 拥有状态：单位注册表 + 存活列表（battle_id 为数值句柄）
var _alive_list: Array[int] = []
var _units: Dictionary = {}        # int battle_id → UnitInstance
var _next_battle_id: int = 0       # 顺序分配；< 1000 约束（防碰撞）

const BATTLE_ID_MAX := 1000

# 由 BattleScene._ready() 在子系统就绪后调用（ADR-0002 / architecture.md 4d）
func start_battle() -> void:
	round_count = 0
	EventBus.battle_started.emit()
	if not EventBus.unit_downed.is_connected(_on_unit_downed):
		EventBus.unit_downed.connect(_on_unit_downed)   # 胜负即时检测（一方全灭）
	_begin_player_phase()

# 我方回合：递增轮次 + 重置行动点 + 进 PLAYER_PHASE，等待玩家指令。
func _begin_player_phase() -> void:
	round_count += 1
	_reset_action_flags()
	_set_battle_state(BattleState.PLAYER_PHASE)
	EventBus.round_started.emit(round_count)
	EventBus.player_phase_started.emit()

# 玩家点"结束我方回合"调用 → 敌方回合。
func end_player_phase() -> void:
	if _battle_state != BattleState.PLAYER_PHASE:
		return
	_set_battle_state(BattleState.ENEMY_PHASE)
	EventBus.enemy_phase_started.emit()
	_run_enemy_phase()

# 敌方回合：对回合开始时存活的每个敌方依次触发 AI（EnemyAI 订阅 enemy_turn_started 同步解算）。
# 任一时刻进入终态即停。全部行动完 → 开新一轮我方回合。
func _run_enemy_phase() -> void:
	for eid in get_alive_enemies():
		if _battle_state in BATTLE_TERMINAL_STATES:
			return
		if eid in _alive_list:
			EventBus.enemy_turn_started.emit(eid)
	if _battle_state in BATTLE_TERMINAL_STATES:
		return
	EventBus.round_ended.emit()
	_begin_player_phase()

# 胜负即时检测：任一 unit_downed 后若敌方全灭 → WIN；若我方全灭 → LOSS（unit_downed 先于 battle_*）。
func _on_unit_downed(_id: int) -> void:
	if _battle_state == BattleState.SETUP or _battle_state in BATTLE_TERMINAL_STATES:
		return
	if get_alive_enemies().is_empty():
		_set_battle_state(BattleState.BATTLE_WIN)
	elif get_alive_allies().is_empty():
		_set_battle_state(BattleState.BATTLE_LOSS)

# 每轮重置行动点（无职业动词单位 has_used_verb 恒 true）。
func _reset_action_flags() -> void:
	for id in _alive_list:
		var u: UnitInstance = _units[id]
		u.has_moved = false
		u.has_acted = false
		u.has_used_verb = u.definition.class_action_id == ""

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
		BattleState.BATTLE_WIN:
			EventBus.battle_won.emit()
		BattleState.BATTLE_LOSS:
			EventBus.battle_lost.emit()
		_:
			pass

# ── 公开接口 ──
func get_battle_state() -> BattleState:
	return _battle_state

func is_in_terminal_state() -> bool:
	return _battle_state in BATTLE_TERMINAL_STATES

func get_current_round() -> int:
	return round_count

# ── §135 单位注册表 + 玩法接口 ──

# 注册一个 UnitInstance，分配并返回数值 battle_id（部署阶段由 BattleMap/部署系统调用）。
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

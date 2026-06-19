# 敌人 AI 意图计算（architecture.md §145 / enemy-ai-intent-system / ADR-0005 消费方）。
# 决策树（Rule 2）+ 目标选择子程序（Rule 5）+ 确定性（Rule 6，平局 unit_id 升序）。
# DI 注入 GridBoard + TurnManager + BattleResolution。
# 意图执行循环（Rule 3/4：enemy_turn_started 执行 + 过期检测）属运行时编排，留后续 story。
# get_path_to 以贪心最近可达格等价替代（MVP 白盒；行为等价：尽量靠近目标）。
class_name EnemyAI
extends Node

const RANGED_RETREAT_THRESHOLD := 2
const SWARMER_STACK_THRESHOLD := 1
const ALLY_FACTION := "crew"

var _grid_board: GridBoard
var _turn_manager: TurnManager
var _battle_resolution: BattleResolution
var _intent_map: Dictionary = {}   # int unit_id → IntentRecord

func setup(grid_board: GridBoard, turn_manager: TurnManager, battle_resolution: BattleResolution) -> void:
	_grid_board = grid_board
	_turn_manager = turn_manager
	_battle_resolution = battle_resolution

# ── Rule 5 目标选择子程序 ──

# 最近 → 最低 HP → 最小 id（贴身/群攻回退用）。
func select_nearest_lowest_hp(self_id: int) -> int:
	var s := _turn_manager.get_unit(self_id)
	var best := -1
	var best_key: Array = []
	for aid in _turn_manager.get_alive_allies():
		var a := _turn_manager.get_unit(aid)
		var key := [GridBoard.chebyshev(s.grid_position, a.grid_position), a.current_hp, aid]
		if best == -1 or key < best_key:
			best = aid
			best_key = key
	return best

# 当前射程内 → 最低 HP → 最小 id（驻守专用）。
func select_target_in_attack_range(self_id: int) -> int:
	var best := -1
	var best_key: Array = []
	for aid in _turn_manager.get_alive_allies():
		if _battle_resolution.is_valid_attack(self_id, aid):
			var a := _turn_manager.get_unit(aid)
			var key := [a.current_hp, aid]
			if best == -1 or key < best_key:
				best = aid
				best_key = key
	return best

# 最高堆叠数（相邻敌方数，不含自身）→ 最低 HP → 最小 id（群攻专用）。
func select_highest_stack_count(self_id: int) -> int:
	var best := -1
	var best_key: Array = []
	for aid in _turn_manager.get_alive_allies():
		var a := _turn_manager.get_unit(aid)
		var stack := 0
		for eid in _turn_manager.get_alive_enemies():
			if eid != self_id and GridBoard.is_adjacent(_turn_manager.get_unit(eid).grid_position, a.grid_position):
				stack += 1
		if stack >= SWARMER_STACK_THRESHOLD:
			var key := [-stack, a.current_hp, aid]   # stack 降序 → 取负
			if best == -1 or key < best_key:
				best = aid
				best_key = key
	return best

# ── Rule 1/2 意图决策 ──

func decide_intent(self_id: int) -> IntentRecord:
	var u := _turn_manager.get_unit(self_id)
	match u.behavior_type:
		"RANGED": return _decide_ranged(self_id)
		"GUARDIAN": return _decide_guardian(self_id)
		"SWARMER": return _decide_swarmer(self_id)
		_: return _decide_melee(self_id)   # MELEE 及未知

func _decide_melee(self_id: int) -> IntentRecord:
	var target := select_nearest_lowest_hp(self_id)
	if target == -1:
		return _wait(self_id)
	return _engage(self_id, target)

func _decide_swarmer(self_id: int) -> IntentRecord:
	var target := select_highest_stack_count(self_id)
	if target == -1:
		target = select_nearest_lowest_hp(self_id)
	if target == -1:
		return _wait(self_id)
	return _engage(self_id, target)

func _decide_ranged(self_id: int) -> IntentRecord:
	var u := _turn_manager.get_unit(self_id)
	var in_range := select_target_in_attack_range(self_id)
	if in_range != -1 and GridBoard.manhattan(u.grid_position, _turn_manager.get_unit(in_range).grid_position) >= RANGED_RETREAT_THRESHOLD:
		return _attack(self_id, in_range)
	var target := select_nearest_lowest_hp(self_id)
	if target == -1:
		return _wait(self_id)
	var t := _turn_manager.get_unit(target)
	if GridBoard.manhattan(u.grid_position, t.grid_position) < RANGED_RETREAT_THRESHOLD:
		var retreat := _retreat_from(u, t.grid_position)
		if retreat != u.grid_position:
			return _move(self_id, retreat)
		if in_range != -1:
			return _attack(self_id, in_range)
		return _wait(self_id)
	return _engage(self_id, target)

func _decide_guardian(self_id: int) -> IntentRecord:
	var u := _turn_manager.get_unit(self_id)
	if u.home_pos == UnitInstance.SENTINEL_POS:
		return _decide_melee(self_id)   # 无 home_pos → 退化 MELEE
	var target := select_target_in_attack_range(self_id)
	if target != -1:
		return _attack(self_id, target)
	if u.grid_position != u.home_pos:
		var move_to := _greedy_approach(u, u.home_pos)
		if move_to != u.grid_position:
			return _move(self_id, move_to)
	return _wait(self_id)

# 攻击或接近（贴身/群攻共用）。
func _engage(self_id: int, target_id: int) -> IntentRecord:
	var u := _turn_manager.get_unit(self_id)
	var t := _turn_manager.get_unit(target_id)
	if _battle_resolution.is_valid_attack(self_id, target_id):
		return _attack(self_id, target_id)
	var staging := _grid_board.get_attack_staging_cells(u.grid_position, u.definition.move_range, t.grid_position, u.definition.attack_range)
	if not staging.is_empty():
		return _move_attack(self_id, target_id, staging[0])
	var move_to := _greedy_approach(u, t.grid_position)
	if move_to != u.grid_position:
		return _move(self_id, move_to)
	return _wait(self_id)

# 贪心接近：可达格中曼哈顿距目标更近者；平局 x*8+y 升序（替代 get_path_to）。
func _greedy_approach(u: UnitInstance, goal: Vector2i) -> Vector2i:
	var cur_d := GridBoard.manhattan(u.grid_position, goal)
	var chosen := u.grid_position
	var chosen_key: Array = []
	for cell in _grid_board.get_reachable_cells(u.grid_position, u.definition.move_range):
		var d := GridBoard.manhattan(cell, goal)
		if d >= cur_d:
			continue
		var key := [d, cell.x * 8 + cell.y]
		if chosen == u.grid_position or key < chosen_key:
			chosen = cell
			chosen_key = key
	return chosen

# 后退：可达格中曼哈顿距目标最远；平局 x*8+y 升序。
func _retreat_from(u: UnitInstance, goal: Vector2i) -> Vector2i:
	var best := u.grid_position
	var best_d := GridBoard.manhattan(best, goal)
	var best_key := best.x * 8 + best.y
	for cell in _grid_board.get_reachable_cells(u.grid_position, u.definition.move_range):
		var d := GridBoard.manhattan(cell, goal)
		var key := cell.x * 8 + cell.y
		if d > best_d or (d == best_d and key < best_key):
			best = cell
			best_d = d
			best_key = key
	return best

# ── IntentRecord 构造 ──

func _new_rec(self_id: int) -> IntentRecord:
	var rec := IntentRecord.new()
	rec.unit_id = self_id
	rec.intent_type = IntentRecord.IntentType.INTENT_WAIT
	rec.target_id = -1
	rec.target_pos = UnitInstance.SENTINEL_POS
	return rec

func _wait(self_id: int) -> IntentRecord:
	return _new_rec(self_id)

func _attack(self_id: int, target_id: int) -> IntentRecord:
	var rec := _new_rec(self_id)
	rec.intent_type = IntentRecord.IntentType.INTENT_ATTACK
	rec.target_id = target_id
	return rec

func _move(self_id: int, dest: Vector2i) -> IntentRecord:
	var rec := _new_rec(self_id)
	rec.intent_type = IntentRecord.IntentType.INTENT_MOVE
	rec.target_pos = dest
	return rec

func _move_attack(self_id: int, target_id: int, dest: Vector2i) -> IntentRecord:
	var rec := _new_rec(self_id)
	rec.intent_type = IntentRecord.IntentType.INTENT_MOVE_ATTACK
	rec.target_id = target_id
	rec.target_pos = dest
	return rec

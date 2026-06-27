# 战斗解算（combat math，architecture.md §142/§389 / battle-resolution-system / ADR-0005）。
# 有状态 Node：unit_statuses + pending_modifiers。注入 GridBoard + TurnManager（DI）。
# current_hp 与 unit_statuses 的唯一改值者；行动点/alive 列表归 TurnManager（调其接口）。
# register_attack_modifier 是 ADR-0001 唯一允许的直连例外（AdjacencyBond 单向注入）。
# 普通攻击核心（Rule 1/9/10/11）已实现；六动词（Rule 3-8）实现见 execute_* 方法。
class_name BattleResolution
extends Node

enum VerbType { SLASH, CANNON, GUARD, HEAL, MOVE, AURA }

const MAX_MODIFIER_SUM := 2       # 相邻羁绊修正器注入上限（防破坏两发击杀）
const AURA_VALUE := 1             # 光环独立第三项加成
const GUARD_DIVISOR := 2          # GUARDED 减伤除数（floor）
const HEAL_AMOUNT := 3            # 医师·愈固定治疗量
const PUSH_DISTANCE := 2          # 航海士·移最大位移
const GUNNER_MIN_RANGE := 2       # 炮手普通攻击最小曼哈顿射程（Rule 11）
const DOWNED_SENTINEL := Vector2i(-1, -1)
const STATUS_GUARDED := &"GUARDED"
const STATUS_AURA := &"AURA_BONUS"
const STATUS_FRENZY := &"FRENZY"               # 套装攻击增益 +2（攻击后消耗）
const STATUS_FRENZY_PERSIST := &"FRENZY_PERSIST"  # 套装攻击增益 +2（本轮不消耗）
const STATUS_SET_GUARD := &"SET_GUARD"         # 套装减半（本轮不消耗）
const STATUS_FROST_SLOW := &"FROST_SLOW"       # 寒霜3档：移动减半（敌回合消费）
const STATUS_FROST_ROOT := &"FROST_ROOT"       # 寒霜6档：不能移动（敌回合消费）
const STATUS_FROST_FREEZE := &"FROST_FREEZE"   # 寒霜9档：跳过整回合（敌回合消费）
const STATUS_FROST_IMMUNE := &"FROST_IMMUNE"   # 解冻后一回合免疫（跨回合，防永冻）
const FRENZY_VALUE := 2                         # 狂热增益

var _grid_board: GridBoard
var _turn_manager: TurnManager
var _pending_modifiers: Dictionary = {}   # int attacker_id → int 累加 bonus（每次攻击缓冲）
var _unit_statuses: Dictionary = {}        # int unit_id → Dictionary[StringName → bool]

func setup(grid_board: GridBoard, turn_manager: TurnManager) -> void:
	_grid_board = grid_board
	_turn_manager = turn_manager
	if not EventBus.round_ended.is_connected(clear_round_statuses):
		EventBus.round_ended.connect(clear_round_statuses)

# ── 状态（ADR D6）──
func get_unit_status(unit_id: int, status: StringName) -> bool:
	return _unit_statuses.get(unit_id, {}).get(status, false)

func apply_status(unit_id: int, status: StringName) -> void:
	if not _unit_statuses.has(unit_id):
		_unit_statuses[unit_id] = {}
	_unit_statuses[unit_id][status] = true

func _consume_status(unit_id: int, status: StringName) -> void:
	if _unit_statuses.has(unit_id):
		_unit_statuses[unit_id].erase(status)

# ROUND_END 清 GUARDED/FRENZY/FRENZY_PERSIST/SET_GUARD（AURA_BONUS 跨轮保留）。
func clear_round_statuses() -> void:
	for id in _unit_statuses:
		_unit_statuses[id].erase(STATUS_GUARDED)
		_unit_statuses[id].erase(STATUS_FRENZY)
		_unit_statuses[id].erase(STATUS_FRENZY_PERSIST)
		_unit_statuses[id].erase(STATUS_SET_GUARD)
		_unit_statuses[id].erase(STATUS_FROST_SLOW)
		_unit_statuses[id].erase(STATUS_FROST_ROOT)
		_unit_statuses[id].erase(STATUS_FROST_FREEZE)

# 敌方单位回合开始结算寒霜：返回 {skip, move_cap}（move_cap=-1 表正常用 get_move_range）。
# 有寒霜→算 outcome（冻结跳过/冰封move0/滞步move减半）+消费该状态+置 FROST_IMMUNE；
# 无寒霜→清 FROST_IMMUNE（免疫到期）。FROST_x 回合级、FROST_IMMUNE 跨回合（见 clear_round_statuses）。
func resolve_frost_for_turn(unit_id: int) -> Dictionary:
	var u := _turn_manager.get_unit(unit_id)
	if u == null:
		return {"skip": false, "move_cap": -1}
	if get_unit_status(unit_id, STATUS_FROST_FREEZE):
		_consume_status(unit_id, STATUS_FROST_FREEZE)
		apply_status(unit_id, STATUS_FROST_IMMUNE)
		EventBus.frost_resolved.emit(unit_id, STATUS_FROST_FREEZE)
		return {"skip": true, "move_cap": 0}
	if get_unit_status(unit_id, STATUS_FROST_ROOT):
		_consume_status(unit_id, STATUS_FROST_ROOT)
		apply_status(unit_id, STATUS_FROST_IMMUNE)
		EventBus.frost_resolved.emit(unit_id, STATUS_FROST_ROOT)
		return {"skip": false, "move_cap": 0}
	if get_unit_status(unit_id, STATUS_FROST_SLOW):
		_consume_status(unit_id, STATUS_FROST_SLOW)
		apply_status(unit_id, STATUS_FROST_IMMUNE)
		EventBus.frost_resolved.emit(unit_id, STATUS_FROST_SLOW)
		return {"skip": false, "move_cap": u.get_move_range() / 2}   # int 除法 = floor
	_consume_status(unit_id, STATUS_FROST_IMMUNE)   # 无寒霜 → 免疫到期
	return {"skip": false, "move_cap": -1}

# ── 修正器注入（Rule 10 / ADR D5 直连例外）──
func register_attack_modifier(attacker_id: int, bonus: int) -> void:
	_pending_modifiers[attacker_id] = _pending_modifiers.get(attacker_id, 0) + bonus

# 读取累计注入值（未钳制；供 AdjacencyBond 测试观测 + HUD 预测伤害）。
func get_pending_modifier(attacker_id: int) -> int:
	return _pending_modifiers.get(attacker_id, 0)

# ── Rule 1 触发条件 + Rule 11 炮手最小射程 ──
func is_valid_attack(attacker_id: int, target_id: int) -> bool:
	var a := _turn_manager.get_unit(attacker_id)
	var t := _turn_manager.get_unit(target_id)
	if a == null or t == null:
		return false
	if not a.is_alive or not t.is_alive:
		return false
	if a.has_acted:
		return false
	if attacker_id == target_id:
		return false
	if a.definition.faction == t.definition.faction:
		return false
	if not _grid_board.in_attack_range(a.grid_position, t.grid_position, a.get_attack_range()):
		return false
	if a.definition.unit_class == "gunner" and GridBoard.manhattan(a.grid_position, t.grid_position) < GUNNER_MIN_RANGE:
		return false
	return true

# ── Rule 1 普通攻击执行（步骤 0-11）──
func execute_attack(attacker_id: int, target_id: int) -> void:
	var a := _turn_manager.get_unit(attacker_id)
	var t := _turn_manager.get_unit(target_id)
	EventBus.attack_initiated.emit(str(attacker_id), "normal_attack")  # 0：触发通知（同步，羁绊在回调注入）
	var dmg := _compute_attack_damage(attacker_id, a)                  # 1-3：修正器(钳制)+光环(消耗)
	var final_damage := _apply_guard(target_id, dmg)                   # 4：GUARDED 减伤+消耗
	var new_hp := maxi(0, t.current_hp - final_damage)                 # 5
	t.current_hp = new_hp                                              # 6
	_pending_modifiers.erase(attacker_id)                             # 7：修正器仅本次有效
	EventBus.attack_executed.emit(attacker_id, target_id, final_damage)  # 8
	EventBus.damage_dealt.emit(target_id, final_damage, new_hp)        # 9
	_turn_manager.mark_has_acted(attacker_id)                          # 10
	if new_hp == 0:                                                    # 11
		resolve_unit_downed(target_id)

# 攻击增益（不消耗，仅查询）：FRENZY/PERSIST→+2 取代 AURA→+1。
func _peek_attack_bonus(attacker_id: int) -> int:
	if get_unit_status(attacker_id, STATUS_FRENZY) or get_unit_status(attacker_id, STATUS_FRENZY_PERSIST):
		return FRENZY_VALUE
	if get_unit_status(attacker_id, STATUS_AURA):
		return AURA_VALUE
	return 0

# 攻击后消耗一次性增益（FRENZY + AURA；PERSIST 不消耗）。
func _consume_attack_bonus(attacker_id: int) -> void:
	_consume_status(attacker_id, STATUS_FRENZY)
	_consume_status(attacker_id, STATUS_AURA)

# 伤害管线（ADR D2）：base + min(modifier, cap) + 独立 aura（不受 cap）。消耗 AURA_BONUS。
func _compute_attack_damage(attacker_id: int, a: UnitInstance) -> int:
	var modifier_sum := mini(_pending_modifiers.get(attacker_id, 0), MAX_MODIFIER_SUM)
	var bonus := _peek_attack_bonus(attacker_id)
	_consume_attack_bonus(attacker_id)
	return a.get_base_damage() + modifier_sum + bonus

# GUARDED/SET_GUARD 减伤（floor）；SET_GUARD 不消耗，GUARDED 消耗。
func _apply_guard(target_id: int, dmg: int) -> int:
	if get_unit_status(target_id, STATUS_SET_GUARD):
		return dmg / GUARD_DIVISOR            # 套装减半，不消耗
	if get_unit_status(target_id, STATUS_GUARDED):
		_consume_status(target_id, STATUS_GUARDED)
		return dmg / GUARD_DIVISOR
	return dmg

# ── Rule 9 击倒解算（7 步，顺序固定；步骤 1-6 必在 7 之前）──
func resolve_unit_downed(unit_id: int) -> void:
	var u := _turn_manager.get_unit(unit_id)
	_turn_manager.remove_from_alive(unit_id)   # 1
	u.is_alive = false                         # 2
	u.grid_position = DOWNED_SENTINEL          # 3
	_grid_board.remove_unit(unit_id)           # 4
	_pending_modifiers.erase(unit_id)          # 5
	_unit_statuses.erase(unit_id)              # 6
	EventBus.unit_downed.emit(unit_id)         # 7

# 反应伤害入口（②b-2b 荆棘反伤/处决斩杀）：扣 hp、emit damage_dealt、致死走 downed。
# 绝不 emit attack_executed（防再次触发套装反应/羁绊充能；同 execute_burst_* 先例）。
func apply_reaction_damage(target_id: int, amount: int) -> void:
	var t := _turn_manager.get_unit(target_id)
	if t == null or not t.is_alive:
		return
	var new_hp := maxi(0, t.current_hp - amount)
	t.current_hp = new_hp
	EventBus.damage_dealt.emit(target_id, amount, new_hp)
	if new_hp == 0:
		resolve_unit_downed(target_id)

# ── 六动词（Rule 3-8）──
const _DIRS_4: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]  # 上下左右

# 分发器（架构 §389 execute_verb；方向型动词从 unit→target 推导基本方向）。
func execute_verb(unit_id: int, verb: VerbType, target_id: int) -> void:
	match verb:
		VerbType.SLASH: execute_slash(unit_id)
		VerbType.AURA: execute_aura(unit_id)
		VerbType.GUARD: execute_guard(unit_id, target_id)
		VerbType.HEAL: execute_heal(unit_id, target_id)
		VerbType.CANNON: execute_cannon(unit_id, _cardinal_toward(unit_id, target_id))
		VerbType.MOVE: execute_displace(unit_id, target_id, _cardinal_toward(unit_id, target_id))

# Rule 3 斩：相邻 AoE，可受修正器/光环（与普通攻击同管线，快照后逐目标减伤）。
func execute_slash(attacker_id: int) -> void:
	var a := _turn_manager.get_unit(attacker_id)
	EventBus.attack_initiated.emit(str(attacker_id), "slash")  # 同步：羁绊在回调注入
	var modifier_sum := mini(_pending_modifiers.get(attacker_id, 0), MAX_MODIFIER_SUM)
	var aura := _peek_attack_bonus(attacker_id)
	var targets: Array[int] = []
	for nid in _grid_board.get_adjacents(a.grid_position):
		var n := _turn_manager.get_unit(nid)
		if n != null and n.is_alive and n.definition.faction != a.definition.faction:
			targets.append(nid)
	var pre_guard := 0
	if not targets.is_empty():
		pre_guard = a.get_base_damage() + modifier_sum + aura
		for tid in targets:
			var t := _turn_manager.get_unit(tid)
			var fd := _apply_guard(tid, pre_guard)
			var new_hp := maxi(0, t.current_hp - fd)
			t.current_hp = new_hp
			EventBus.attack_executed.emit(attacker_id, tid, fd)
			EventBus.damage_dealt.emit(tid, fd, new_hp)
			if new_hp == 0:
				resolve_unit_downed(tid)
	_pending_modifiers.erase(attacker_id)            # ⑦
	_consume_attack_bonus(attacker_id)               # ⑧
	EventBus.slash_executed.emit(str(attacker_id), targets, pre_guard)
	_turn_manager.mark_has_used_verb(attacker_id)

# 爆发增强斩（bond-gauge-burst Rule 7 破阵先锋②/热血演奏②）：相邻敌方 AoE，
# 伤害 = base × multiplier，穿透 GUARDED（不减伤），不接受修正器。
# consume_aura=true 时（热血演奏，EC-12）：施放者持 AURA_BONUS 则追加 AURA_VALUE 并消耗。
# 不消耗施放者动词（动作点由 BondGaugeBurst 经羁绊槽消耗）。施放者已 Downed 则跳过（EC-2）。
func execute_burst_slash(attacker_id: int, multiplier: int, consume_aura: bool = false) -> void:
	var a := _turn_manager.get_unit(attacker_id)
	if a == null or not a.is_alive:
		return
	var dmg := a.get_base_damage() * multiplier
	if consume_aura and get_unit_status(attacker_id, STATUS_AURA):
		dmg += AURA_VALUE
		_consume_status(attacker_id, STATUS_AURA)
	var targets: Array[int] = []
	for nid in _grid_board.get_adjacents(a.grid_position):
		var n := _turn_manager.get_unit(nid)
		if n != null and n.is_alive and n.definition.faction != a.definition.faction:
			targets.append(nid)
	for tid in targets:
		var t := _turn_manager.get_unit(tid)
		var new_hp := maxi(0, t.current_hp - dmg)   # 穿透：不走 _apply_guard
		t.current_hp = new_hp
		# 不发 attack_executed：爆发斩非"普通攻击/斩"，不触发羁绊充能（EC-8 防"即刻又半满"）。
		EventBus.damage_dealt.emit(tid, dmg, new_hp)
		if new_hp == 0:
			resolve_unit_downed(tid)

# 爆发推移（bond-gauge-burst Rule 7 瞄准定位①）：沿 caster→target 方向推 target
# ≤PUSH_DISTANCE，遇边界/障碍/占用停。返回是否成功移动（用于 EC-6 推移失败取消炮击）。
# 不消耗施放者动词（动作点由 BondGaugeBurst 经羁绊槽消耗）。
func execute_burst_displace(caster_id: int, target_id: int) -> bool:
	var c := _turn_manager.get_unit(caster_id)
	var t := _turn_manager.get_unit(target_id)
	if c == null or t == null or not c.is_alive or not t.is_alive:
		return false
	var direction := _cardinal_toward(caster_id, target_id)
	var from_pos := t.grid_position
	var dest := from_pos
	for _i in PUSH_DISTANCE:
		var nxt := dest + direction
		if not _grid_board.is_empty(nxt):
			break
		dest = nxt
	if dest == from_pos:
		return false
	_grid_board.forced_move_unit(target_id, dest)
	t.grid_position = dest
	EventBus.displacement_executed.emit(target_id, from_pos, dest)
	return true

# 爆发穿透炮（bond-gauge-burst Rule 7 瞄准定位②）：朝 attacker→target 方向发射。
func execute_burst_cannon(attacker_id: int, target_id: int, multiplier: int) -> void:
	var a := _turn_manager.get_unit(attacker_id)
	var t := _turn_manager.get_unit(target_id)
	if a == null or t == null or not a.is_alive:
		return
	execute_burst_cannon_dir(attacker_id, _cardinal_toward(attacker_id, target_id), multiplier)

# 爆发定向穿透炮（瞄准定位②核心 / 轰鸣序曲② 4 基本方向）：从 attacker 沿 direction
# 穿透直线，弹道上所有存活单位受伤害 = base × multiplier（不分阵营，同普通轰；EC-7）。
# 不消耗动词；不 emit cannon_executed（避免触发羁绊充能→爆发即刻又充能，同 EC-8）。
func execute_burst_cannon_dir(attacker_id: int, direction: Vector2i, multiplier: int) -> void:
	var a := _turn_manager.get_unit(attacker_id)
	if a == null or not a.is_alive:
		return
	var dmg := a.get_base_damage() * multiplier
	var cell := a.grid_position
	for _i in a.get_attack_range():
		cell += direction
		if not _grid_board.in_bounds(cell):
			break
		var uid := _grid_board.get_cell(cell)
		if uid != GridBoard.EMPTY:
			var u := _turn_manager.get_unit(uid)
			if u != null and u.is_alive:
				var new_hp := maxi(0, u.current_hp - dmg)
				u.current_hp = new_hp
				EventBus.damage_dealt.emit(uid, dmg, new_hp)
				if new_hp == 0:
					resolve_unit_downed(uid)

# 爆发治疗（护持突破②/钢铁壁垒②）：target 回复 amount HP，钳制 max_hp。
# 不消耗施放者动词；emit heal_executed（不触发充能）。
func execute_burst_heal(target_id: int, amount: int) -> void:
	var t := _turn_manager.get_unit(target_id)
	if t == null or not t.is_alive:
		return
	var new_hp := mini(t.current_hp + amount, t.get_max_hp())
	var healed := new_hp - t.current_hp
	t.current_hp = new_hp
	EventBus.heal_executed.emit(target_id, healed)

# Rule 4 轰：穿透直线，不分阵营，仅 base 伤害（无修正器/光环），不 emit attack_executed。
func execute_cannon(attacker_id: int, direction: Vector2i) -> void:
	var a := _turn_manager.get_unit(attacker_id)
	var hits: Array[int] = []
	var cell := a.grid_position
	for _i in a.get_attack_range():
		cell += direction
		if not _grid_board.in_bounds(cell):
			break
		var uid := _grid_board.get_cell(cell)
		if uid != GridBoard.EMPTY:
			var u := _turn_manager.get_unit(uid)
			if u != null and u.is_alive:
				hits.append(uid)
	var base_fire := a.get_base_damage()
	for tid in hits:
		var t := _turn_manager.get_unit(tid)
		var fd := _apply_guard(tid, base_fire)
		var new_hp := maxi(0, t.current_hp - fd)
		t.current_hp = new_hp
		EventBus.damage_dealt.emit(tid, fd, new_hp)
		if new_hp == 0:
			resolve_unit_downed(tid)
	EventBus.cannon_executed.emit(str(attacker_id), _DIRS_4.find(direction), hits, base_fire)
	_turn_manager.mark_has_used_verb(attacker_id)

# Rule 5 挡：目标获 GUARDED。
func execute_guard(caster_id: int, target_id: int) -> void:
	apply_status(target_id, STATUS_GUARDED)
	EventBus.guard_applied.emit(target_id)
	_turn_manager.mark_has_used_verb(caster_id)

# Rule 6 愈：+HEAL_AMOUNT，钳制 max_hp。
func execute_heal(caster_id: int, target_id: int) -> void:
	var t := _turn_manager.get_unit(target_id)
	var new_hp := mini(t.current_hp + HEAL_AMOUNT, t.get_max_hp())
	var amount := new_hp - t.current_hp
	t.current_hp = new_hp
	EventBus.heal_executed.emit(target_id, amount)
	_turn_manager.mark_has_used_verb(caster_id)

# Rule 7 移：沿方向逐格推 ≤PUSH_DISTANCE，遇边界/障碍/占用停。
func execute_displace(caster_id: int, target_id: int, direction: Vector2i) -> void:
	var t := _turn_manager.get_unit(target_id)
	var from_pos := t.grid_position
	var dest := from_pos
	for _i in PUSH_DISTANCE:
		var nxt := dest + direction
		if not _grid_board.is_empty(nxt):
			break
		dest = nxt
	if dest != from_pos:
		_grid_board.forced_move_unit(target_id, dest)
		t.grid_position = dest
	EventBus.displacement_executed.emit(target_id, from_pos, dest)
	_turn_manager.mark_has_used_verb(caster_id)

# Rule 8 奏：相邻友方（不含自身）获 AURA_BONUS。
func execute_aura(caster_id: int) -> void:
	var a := _turn_manager.get_unit(caster_id)
	var buffed: Array[int] = []
	for nid in _grid_board.get_adjacents(a.grid_position):
		var n := _turn_manager.get_unit(nid)
		if n != null and n.is_alive and n.definition.faction == a.definition.faction:
			apply_status(nid, STATUS_AURA)
			buffed.append(nid)
	EventBus.aura_performed.emit(str(caster_id), buffed, AURA_VALUE)
	_turn_manager.mark_has_used_verb(caster_id)

# 从 unit→target 推导最近基本方向（分发器用；主轴优先）。
func _cardinal_toward(unit_id: int, target_id: int) -> Vector2i:
	var u := _turn_manager.get_unit(unit_id)
	var t := _turn_manager.get_unit(target_id)
	var delta := t.grid_position - u.grid_position
	if absi(delta.x) >= absi(delta.y):
		return Vector2i(signi(delta.x), 0)
	return Vector2i(0, signi(delta.y))

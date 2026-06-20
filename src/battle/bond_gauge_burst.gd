# 羁绊槽 + 爆发技（architecture.md §144 / bond-gauge-burst-system）。
# 共享槽 BOND_GAUGE_MAX=10、跨回合保留、不跨战斗保留。
# 充能核心（Rule 1-4）+ 爆发激活（Rule 5-6）+ 效果路由（Rule 7）已实现。
# 效果体当前仅 MVP 破阵先锋落地；瞄准定位/通用 Combined Strike 路由正确但效果留 TODO。
class_name BondGaugeBurst
extends Node

# 旋钮常量（bond-gauge-burst-system §Tuning Knobs / entities.yaml）。
const BOND_GAUGE_MAX := 10        # 槽上限（原型验证值，不可随意调低）
const CHARGE_ADJACENT := 2        # 相邻站位充能
const CHARGE_SOLO := 1            # 单独作战充能
const CHARGE_HIT := 1             # 受击充能
const RECEIVED_CHARGE_CAP := 2    # 每回合受击充能上限（压制"故意挨打"策略）
const BURST_DAMAGE_MULTIPLIER := 2  # 精英爆发伤害倍率（剑豪爆发 = max_hp，一击必杀满血）
const BURST_HEAL_MULTIPLIER := 2    # 爆发治疗倍率（HEAL_AMOUNT × 2 = 全量治疗）
const ALLY_FACTION := "crew"        # 友方阵营字符串

# 精英配对爆发 effect_id（Rule 7；矩阵对称，非配对 → 通用 Combined Strike）。
const BURST_VANGUARD_BREACH := &"vanguard_breach"   # 剑豪+铁壁（MVP）
const BURST_GUIDED_SALVO := &"guided_salvo"         # 炮手+航海士（MVP）
const BURST_BARDIC_FURY := &"bardic_fury"           # 剑豪+乐手
const BURST_THUNDER_ARIA := &"thunder_aria"         # 炮手+乐手
const BURST_LIFELINE_SLASH := &"lifeline_slash"     # 剑豪+医师
const BURST_IRON_SANCTUM := &"iron_sanctum"         # 铁壁+医师
const BURST_COMBINED_STRIKE := &"combined_strike"   # 通用（非精英配对）

# 精英配对表（对称；class 字符串对 → effect_id）。
const _ELITE_BURSTS := [
	[["swordsman", "bulwark"], BURST_VANGUARD_BREACH],
	[["gunner", "navigator"], BURST_GUIDED_SALVO],
	[["swordsman", "musician"], BURST_BARDIC_FURY],
	[["gunner", "musician"], BURST_THUNDER_ARIA],
	[["swordsman", "medic"], BURST_LIFELINE_SLASH],
	[["bulwark", "medic"], BURST_IRON_SANCTUM],
]

var _gauge: int = 0                       # bond_gauge_current ∈ [0, BOND_GAUGE_MAX]
var _received_charge_this_round: int = 0  # 本回合已受击充能量（ROUND_END 重置）
var _grid_board: GridBoard                # 充能相邻判定 get_adjacents（DI）
var _turn_manager: TurnManager            # 读单位状态 + 消耗动作点（DI）
var _battle_resolution: BattleResolution  # 爆发效果走解算层（DI）

# 注入依赖 + 订阅充能信号（Rule 2-4 + ROUND_END）。
# 纯充能核心测试用 .new() 不调 setup（不需 DI/信号）。
func setup(grid_board: GridBoard, turn_manager: TurnManager, battle_resolution: BattleResolution) -> void:
	_grid_board = grid_board
	_turn_manager = turn_manager
	_battle_resolution = battle_resolution
	if not EventBus.attack_executed.is_connected(_on_attack_executed):
		EventBus.attack_executed.connect(_on_attack_executed)
	if not EventBus.cannon_executed.is_connected(_on_cannon_executed):
		EventBus.cannon_executed.connect(_on_cannon_executed)
	if not EventBus.damage_dealt.is_connected(_on_damage_dealt):
		EventBus.damage_dealt.connect(_on_damage_dealt)
	if not EventBus.round_ended.is_connected(_on_round_ended):
		EventBus.round_ended.connect(_on_round_ended)

func get_gauge_value() -> int:
	return _gauge

func is_full() -> bool:
	return _gauge >= BOND_GAUGE_MAX

# ── 信号订阅处理（Rule 2-4 wiring；相邻判定经 grid_board 自算）──

# Rule 2：attack_executed（普通攻击 + 斩，每命中一目标一次；仅友方攻击者充能）。
func _on_attack_executed(attacker_id: int, _target_id: int, _final_damage: int) -> void:
	if not _is_ally(attacker_id):
		return
	apply_attack_charge(attacker_id, _has_adjacent_ally(attacker_id))

# Rule 3：cannon_executed（轰每次发动一次；第一参为 String id）。
func _on_cannon_executed(attacker_id_str: String, _direction: int, _hit_target_ids: Array, _base_fire_damage: int) -> void:
	var attacker_id := int(attacker_id_str)
	if not _is_ally(attacker_id):
		return
	apply_cannon_charge(attacker_id, _has_adjacent_ally(attacker_id))

# Rule 4：damage_dealt（仅友方受击充能，每回合上限由 apply_received_charge 把关）。
func _on_damage_dealt(target_id: int, _final_damage: int, _new_hp: int) -> void:
	if not _is_ally(target_id):
		return
	apply_received_charge(target_id)

# ROUND_END：重置受击计数。
func _on_round_ended() -> void:
	on_round_end()

# 友方且存活（充能阵营过滤）。
func _is_ally(unit_id: int) -> bool:
	var u := _turn_manager.get_unit(unit_id)
	return u != null and u.is_alive and u.definition.faction == ALLY_FACTION

# Formula 1：是否有相邻存活友方（决定 +CHARGE_ADJACENT / +CHARGE_SOLO）。
func _has_adjacent_ally(unit_id: int) -> bool:
	var u := _turn_manager.get_unit(unit_id)
	if u == null:
		return false
	for nid in _grid_board.get_adjacents(u.grid_position):
		if nid == unit_id:
			continue
		var n := _turn_manager.get_unit(nid)
		if n != null and n.is_alive and n.definition.faction == ALLY_FACTION:
			return true
	return false

# Rule 2：普通攻击 / 斩 命中充能。相邻与否由调用方（GridBoard 计算）传入。
func apply_attack_charge(attacker_id: int, is_adjacent: bool) -> void:
	_charge(attacker_id, CHARGE_ADJACENT if is_adjacent else CHARGE_SOLO)

# Rule 3：炮手·轰每次使用充能（充能逻辑同攻击）。
func apply_cannon_charge(attacker_id: int, is_adjacent: bool) -> void:
	_charge(attacker_id, CHARGE_ADJACENT if is_adjacent else CHARGE_SOLO)

# Rule 4：己方受击充能，每回合上限 RECEIVED_CHARGE_CAP（拦截后不增计数）。
func apply_received_charge(target_id: int) -> void:
	if _received_charge_this_round >= RECEIVED_CHARGE_CAP:
		return
	_received_charge_this_round += 1
	_charge(target_id, CHARGE_HIT)

# ROUND_END：重置受击计数（不重置槽——槽跨回合保留）。
func on_round_end() -> void:
	_received_charge_this_round = 0

# 爆发执行后归零（不跨战斗保留时也调用）。
func reset_gauge() -> void:
	_gauge = 0

# 共享充能内核（Rule 1 步骤 4-7）：clamp + emit gauge_charged + 首次满槽 emit bond_gauge_full。
func _charge(source_id: int, amount: int) -> void:
	var prev := _gauge
	_gauge = mini(_gauge + amount, BOND_GAUGE_MAX)
	# gauge_charged 第一参声明 String；本系统 id 用 int（与代码库一致），emit 边界转换。
	EventBus.gauge_charged.emit(str(source_id), amount, _gauge)
	if prev < BOND_GAUGE_MAX and _gauge == BOND_GAUGE_MAX:
		EventBus.bond_gauge_full.emit()

# Rule 5：爆发激活资格（5 条件全满足才返回 true）。
func can_activate_burst(lead_id: int, partner_id: int) -> bool:
	if not is_full():                                   # 条件 1：槽满
		return false
	if lead_id == partner_id:                           # 条件 4：lead ≠ partner
		return false
	var lead := _turn_manager.get_unit(lead_id)
	var partner := _turn_manager.get_unit(partner_id)
	if lead == null or partner == null:
		return false
	# 条件 2：lead 友方、存活、未行动
	if lead.definition.faction != ALLY_FACTION or not lead.is_alive or lead.has_acted:
		return false
	# 条件 3：partner 友方、存活、未用职业动词
	if partner.definition.faction != ALLY_FACTION or not partner.is_alive or partner.has_used_verb:
		return false
	# 条件 5：切比雪夫相邻（距离 = 1）
	if GridBoard.chebyshev(lead.grid_position, partner.grid_position) != 1:
		return false
	return true

# Rule 7：查精英配对表，返回 effect_id（对称；非配对 → Combined Strike）。
func get_burst_effect_id(class_a: String, class_b: String) -> StringName:
	for entry in _ELITE_BURSTS:
		var pair: Array = entry[0]
		if (pair[0] == class_a and pair[1] == class_b) or (pair[0] == class_b and pair[1] == class_a):
			return entry[1]
	return BURST_COMBINED_STRIKE

# Rule 6：爆发执行（资格不符返回 false，不动状态）。成功则按步骤 1-6 顺序执行。
func activate_burst(lead_id: int, partner_id: int) -> bool:
	if not can_activate_burst(lead_id, partner_id):
		return false
	var lead := _turn_manager.get_unit(lead_id)
	var partner := _turn_manager.get_unit(partner_id)
	var effect_id := get_burst_effect_id(lead.definition.unit_class, partner.definition.unit_class)
	reset_gauge()                                       # 1：立即清零，先于所有效果
	_turn_manager.mark_has_acted(lead_id)              # 2
	_turn_manager.mark_has_used_verb(partner_id)       # 3
	_execute_burst_effect(effect_id, lead_id, partner_id)  # 4
	EventBus.burst_executed.emit(lead_id, partner_id)  # 5
	EventBus.burst_presentation_requested.emit(lead_id, partner_id, effect_id)  # 6
	return true

# Rule 7 效果分发。MVP 仅破阵先锋落地；其余路由正确，效果体留 TODO。
func _execute_burst_effect(effect_id: StringName, lead_id: int, partner_id: int) -> void:
	match effect_id:
		BURST_VANGUARD_BREACH:
			_burst_vanguard_breach(lead_id, partner_id)
		BURST_GUIDED_SALVO:
			_burst_guided_salvo(lead_id, partner_id)
		BURST_BARDIC_FURY:
			_burst_bardic_fury(lead_id, partner_id)
		BURST_THUNDER_ARIA:
			_burst_thunder_aria(lead_id, partner_id)
		BURST_LIFELINE_SLASH:
			_burst_lifeline_slash(lead_id, partner_id)
		BURST_IRON_SANCTUM:
			_burst_iron_sanctum(lead_id, partner_id)
		_:
			_burst_combined_strike(lead_id, partner_id)   # BURST_COMBINED_STRIKE 通用配对

# 破阵先锋（Vanguard Breach，MVP）：①铁壁自身获 GUARDED；②剑豪增强穿透斩相邻敌方。
# lead/partner 角色对称——按职业定位施放者，不依赖谁是 lead。
func _burst_vanguard_breach(lead_id: int, partner_id: int) -> void:
	var bulwark_id := _unit_of_class(lead_id, partner_id, "bulwark")
	var swordsman_id := _unit_of_class(lead_id, partner_id, "swordsman")
	if bulwark_id != -1:
		_battle_resolution.apply_status(bulwark_id, BattleResolution.STATUS_GUARDED)
	if swordsman_id != -1:
		_battle_resolution.execute_burst_slash(swordsman_id, BURST_DAMAGE_MULTIPLIER)

# 瞄准定位（Guided Salvo，MVP）：①航海士推移1名相邻敌方；②炮手朝该敌方当前位置
# 方向发穿透炮（base×倍率）。推移失败（无相邻敌方 / 无合法落点）→ 炮弹取消（EC-6）。
func _burst_guided_salvo(lead_id: int, partner_id: int) -> void:
	var navigator_id := _unit_of_class(lead_id, partner_id, "navigator")
	var gunner_id := _unit_of_class(lead_id, partner_id, "gunner")
	if navigator_id == -1 or gunner_id == -1:
		return
	var enemy_id := _adjacent_enemy_of(navigator_id)
	if enemy_id == -1:
		return                                            # 无相邻敌方 → 炮弹取消
	if not _battle_resolution.execute_burst_displace(navigator_id, enemy_id):
		return                                            # 推移失败 → 炮弹取消
	_battle_resolution.execute_burst_cannon(gunner_id, enemy_id, BURST_DAMAGE_MULTIPLIER)

# 通用协力强击（Combined Strike，非精英配对；OQ-3 裁决：动词自动选靶=最近敌人）：
# lead 与 partner 各执行其职业动词原版效果（效果量不加成），顺序执行。
func _burst_combined_strike(lead_id: int, partner_id: int) -> void:
	_execute_combined_verb(lead_id)
	_execute_combined_verb(partner_id)

# 按职业执行单位原版动词（×1）。斩/轰用 burst 变体避免触发充能(EC-8)；
# 挡/愈/奏/移不发充能信号，用常规效果。攻击型动词自动选靶=最近敌人。
func _execute_combined_verb(unit_id: int) -> void:
	var u := _turn_manager.get_unit(unit_id)
	if u == null or not u.is_alive:
		return
	var target := _nearest_enemy_of(unit_id)
	match u.definition.unit_class:
		"swordsman":
			_battle_resolution.execute_burst_slash(unit_id, 1)          # 相邻 AoE，原版伤害
		"gunner":
			if target != -1:
				_battle_resolution.execute_burst_cannon(unit_id, target, 1)
		"navigator":
			if target != -1:
				_battle_resolution.execute_burst_displace(unit_id, target)
		"bulwark":
			_battle_resolution.execute_guard(unit_id, unit_id)          # 自身挡
		"medic":
			_battle_resolution.execute_heal(unit_id, unit_id)           # 自愈
		"musician":
			_battle_resolution.execute_aura(unit_id)                    # 相邻友方光环

# 4 基本方向（轰鸣序曲②；上下左右，与 BattleResolution._DIRS_4 一致）。
const _CARDINALS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]

# 热血演奏（Bardic Fury，Alpha）：①乐手对相邻友方施 AURA_BONUS；
# ②剑豪增强斩（×倍率 + 持 AURA 追加 AURA_VALUE，EC-12）。
func _burst_bardic_fury(lead_id: int, partner_id: int) -> void:
	var musician_id := _unit_of_class(lead_id, partner_id, "musician")
	var swordsman_id := _unit_of_class(lead_id, partner_id, "swordsman")
	if musician_id != -1:
		_battle_resolution.execute_aura(musician_id)            # 相邻友方（含剑豪）获 AURA
	if swordsman_id != -1:
		_battle_resolution.execute_burst_slash(swordsman_id, BURST_DAMAGE_MULTIPLIER, true)

# 轰鸣序曲（Thunder Aria，Alpha）：①乐手施 AURA_BONUS；
# ②炮手向 4 基本方向各发穿透炮（×倍率；炮不吃 AURA）。
func _burst_thunder_aria(lead_id: int, partner_id: int) -> void:
	var musician_id := _unit_of_class(lead_id, partner_id, "musician")
	var gunner_id := _unit_of_class(lead_id, partner_id, "gunner")
	if musician_id != -1:
		_battle_resolution.execute_aura(musician_id)
	if gunner_id != -1:
		for dir in _CARDINALS:
			_battle_resolution.execute_burst_cannon_dir(gunner_id, dir, BURST_DAMAGE_MULTIPLIER)

# 护持突破（Lifeline Slash，Alpha）：①剑豪增强斩（×倍率）；
# ②斩后医师愈剑豪 HEAL_AMOUNT × BURST_HEAL_MULTIPLIER。
func _burst_lifeline_slash(lead_id: int, partner_id: int) -> void:
	var swordsman_id := _unit_of_class(lead_id, partner_id, "swordsman")
	var medic_id := _unit_of_class(lead_id, partner_id, "medic")
	if swordsman_id != -1:
		_battle_resolution.execute_burst_slash(swordsman_id, BURST_DAMAGE_MULTIPLIER)
	if medic_id != -1 and swordsman_id != -1:
		_battle_resolution.execute_burst_heal(swordsman_id, BattleResolution.HEAL_AMOUNT * BURST_HEAL_MULTIPLIER)

# 钢铁壁垒（Iron Sanctum，Alpha）：①铁壁给全体存活友方（含自身）施 GUARDED；
# ②医师给全体存活友方各愈 HEAL_AMOUNT（无倍率）。
func _burst_iron_sanctum(_lead_id: int, _partner_id: int) -> void:
	var allies := _turn_manager.get_alive_allies()
	for aid in allies:
		_battle_resolution.apply_status(aid, BattleResolution.STATUS_GUARDED)
	for aid in allies:
		_battle_resolution.execute_burst_heal(aid, BattleResolution.HEAL_AMOUNT)

# 取单位最近存活敌方（切比雪夫；battle_id 平局升序，确定性）；无则 -1。
func _nearest_enemy_of(unit_id: int) -> int:
	var u := _turn_manager.get_unit(unit_id)
	if u == null:
		return -1
	var best := -1
	var best_dist := 1 << 30
	for eid in _turn_manager.get_alive_enemies():
		var e := _turn_manager.get_unit(eid)
		var d := GridBoard.chebyshev(u.grid_position, e.grid_position)
		if d < best_dist or (d == best_dist and eid < best):
			best_dist = d
			best = eid
	return best

# 取单位相邻存活敌方中 battle_id 最小者（确定性平局）；无则 -1。
func _adjacent_enemy_of(unit_id: int) -> int:
	var u := _turn_manager.get_unit(unit_id)
	if u == null:
		return -1
	var best := -1
	for nid in _grid_board.get_adjacents(u.grid_position):
		var n := _turn_manager.get_unit(nid)
		if n != null and n.is_alive and n.definition.faction != ALLY_FACTION:
			if best == -1 or nid < best:
				best = nid
	return best

# 在 {a, b} 中按职业取单位 id；无匹配返回 -1。
func _unit_of_class(a_id: int, b_id: int, unit_class: String) -> int:
	for id in [a_id, b_id]:
		var u := _turn_manager.get_unit(id)
		if u != null and u.definition.unit_class == unit_class:
			return id
	return -1

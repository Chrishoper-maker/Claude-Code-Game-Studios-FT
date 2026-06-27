# 套装反应引擎（②b-2b）。订阅 attack_executed，按攻击者/目标的套装档位触发反应
# （嗜血/处决看攻击者，荆棘看目标）。阵营无关。反应伤害走 apply_reaction_damage（不发
# attack_executed，防递归）；治疗走 execute_burst_heal。
class_name SetReactionSystem
extends Node

const BLOODTHIRST_DIV_LOW := 4    # 嗜血 3 档：floor(dmg/4)
const BLOODTHIRST_DIV_HIGH := 2   # 嗜血 6/9 档：floor(dmg/2)
const THORNS_DMG := {3: 1, 6: 2, 9: 3}   # 荆棘反伤（按激活档取最高）
const EXECUTIONER := {3: {"thr": 3, "dmg": 3}, 6: {"thr": 5, "dmg": 5}, 9: {"thr": 7, "dmg": 7}}
const FROST_STATUS_BY_TIER := {
	9: BattleResolution.STATUS_FROST_FREEZE,
	6: BattleResolution.STATUS_FROST_ROOT,
	3: BattleResolution.STATUS_FROST_SLOW,
}

var _grid_board: GridBoard
var _turn_manager: TurnManager
var _battle_resolution: BattleResolution

func setup(grid_board: GridBoard, turn_manager: TurnManager, battle_resolution: BattleResolution) -> void:
	_grid_board = grid_board
	_turn_manager = turn_manager
	_battle_resolution = battle_resolution
	if not EventBus.attack_executed.is_connected(on_attack_executed):
		EventBus.attack_executed.connect(on_attack_executed)

# 命中后：攻击者侧（嗜血/处决/寒霜）+ 目标侧（荆棘）反应。
func on_attack_executed(attacker_id: int, target_id: int, damage: int) -> void:
	var attacker := _turn_manager.get_unit(attacker_id)
	var target := _turn_manager.get_unit(target_id)
	if attacker != null and attacker.is_alive:
		if SetBonus.count_sets(attacker).has("set_bloodthirst"):
			_apply_bloodthirst(attacker_id, attacker, damage)
		if SetBonus.count_sets(attacker).has("set_executioner"):
			_apply_executioner(attacker, target_id)
		if SetBonus.count_sets(attacker).has("set_frost"):
			_apply_frost(attacker, target_id)

	if target != null and target.is_alive and SetBonus.count_sets(target).has("set_thorns"):
		_apply_thorns(attacker_id, target)

# 嗜血：攻击者回血 floor(dmg/4)（3档）或 floor(dmg/2)（6/9档）；9档相邻同阵营友军另 floor(dmg/4)。
func _apply_bloodthirst(attacker_id: int, attacker: UnitInstance, damage: int) -> void:
	var div := BLOODTHIRST_DIV_HIGH if SetBonus.is_tier_active(attacker, "set_bloodthirst", 6) else BLOODTHIRST_DIV_LOW
	_battle_resolution.execute_burst_heal(attacker_id, damage / div)
	if SetBonus.is_tier_active(attacker, "set_bloodthirst", 9):
		for ally_id in _adjacent_allies(attacker):
			_battle_resolution.execute_burst_heal(ally_id, damage / BLOODTHIRST_DIV_LOW)

# 相邻八向（切比雪夫≤1）、同阵营、存活、非自身的单位 battle_id。
# 几何遍历（不依赖 GridBoard._occupancy），与 SetEffectSystem 保持一致。
func _adjacent_allies(source: UnitInstance) -> Array[int]:
	var out: Array[int] = []
	var all_ids: Array[int] = _turn_manager.get_alive_allies()
	all_ids.append_array(_turn_manager.get_alive_enemies())
	for id in all_ids:
		var u := _turn_manager.get_unit(id)
		if u != null and u != source and u.is_alive \
				and u.definition.faction == source.definition.faction \
				and GridBoard.chebyshev(source.grid_position, u.grid_position) <= 1:
			out.append(id)
	return out

# 荆棘：被命中后对攻击者反弹固定伤害（取最高激活档；可致死，不发 attack_executed）。
func _apply_thorns(attacker_id: int, target: UnitInstance) -> void:
	var dmg := 0
	for t in [9, 6, 3]:
		if SetBonus.is_tier_active(target, "set_thorns", t):
			dmg = int(THORNS_DMG[t])
			break
	if dmg > 0:
		_battle_resolution.apply_reaction_damage(attacker_id, dmg)

# 处决：命中后若目标存活且 hp≤阈值 → 追加斩杀（取最高激活档；可致死）。
func _apply_executioner(attacker: UnitInstance, target_id: int) -> void:
	var t := _turn_manager.get_unit(target_id)
	# 同帧致死时 is_alive 尚未翻转，需额外检查 current_hp≤0 来确保跳过已死目标。
	if t == null or not t.is_alive or t.current_hp <= 0:
		return
	for tier in [9, 6, 3]:
		if SetBonus.is_tier_active(attacker, "set_executioner", tier):
			var spec: Dictionary = EXECUTIONER[tier]
			if t.current_hp <= int(spec["thr"]):
				_battle_resolution.apply_reaction_damage(target_id, int(spec["dmg"]))
			return

# 寒霜：命中给非免疫敌方按最高激活档施寒霜状态（滞步/冰封/冻结）；不造成伤害。
func _apply_frost(attacker: UnitInstance, target_id: int) -> void:
	var t := _turn_manager.get_unit(target_id)
	if t == null or not t.is_alive or t.current_hp <= 0:
		return
	if _battle_resolution.get_unit_status(target_id, BattleResolution.STATUS_FROST_IMMUNE):
		return
	for tier in [9, 6, 3]:
		if SetBonus.is_tier_active(attacker, "set_frost", tier):
			_battle_resolution.apply_status(target_id, FROST_STATUS_BY_TIER[tier])
			return

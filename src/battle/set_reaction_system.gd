# 套装反应引擎（②b-2b）。订阅 attack_executed，按攻击者/目标的套装档位触发反应
# （嗜血/处决看攻击者，荆棘看目标）。阵营无关。反应伤害走 apply_reaction_damage（不发
# attack_executed，防递归）；治疗走 execute_burst_heal。
class_name SetReactionSystem
extends Node

const BLOODTHIRST_DIV_LOW := 4    # 嗜血 3 档：floor(dmg/4)
const BLOODTHIRST_DIV_HIGH := 2   # 嗜血 6/9 档：floor(dmg/2)

var _grid_board: GridBoard
var _turn_manager: TurnManager
var _battle_resolution: BattleResolution

func setup(grid_board: GridBoard, turn_manager: TurnManager, battle_resolution: BattleResolution) -> void:
	_grid_board = grid_board
	_turn_manager = turn_manager
	_battle_resolution = battle_resolution
	if not EventBus.attack_executed.is_connected(on_attack_executed):
		EventBus.attack_executed.connect(on_attack_executed)

# 命中后：攻击者侧（嗜血/处决）+ 目标侧（荆棘）反应。
func on_attack_executed(attacker_id: int, target_id: int, damage: int) -> void:
	var attacker := _turn_manager.get_unit(attacker_id)
	if attacker != null and attacker.is_alive:
		if SetBonus.count_sets(attacker).has("set_bloodthirst"):
			_apply_bloodthirst(attacker_id, attacker, damage)

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

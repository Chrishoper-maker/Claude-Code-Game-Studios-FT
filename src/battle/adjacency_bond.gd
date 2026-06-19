# 相邻羁绊修正器注入（architecture.md §143 / adjacency-bond-system / ADR-0005 D5）。
# 订阅 EventBus.attack_initiated，按阵营+动词过滤，查 BOND_MATRIX，
# 向 BattleResolution.register_attack_modifier 单向注入（不反向引用，防循环依赖）。
class_name AdjacencyBond
extends Node

const BOND_BASE := 1     # 通用羁绊
const BOND_ELITE := 2    # 精英羁绊（单伙伴即达 MAX_MODIFIER_SUM）
const ALLY_FACTION := "crew"
const TRIGGER_VERBS := ["normal_attack", "slash"]

# 精英羁绊 6 对（对称；其余含同职业对角线均为通用 BOND_BASE）。
const _ELITE_PAIRS := [
	["swordsman", "musician"], ["gunner", "musician"], ["swordsman", "medic"],
	["gunner", "navigator"], ["bulwark", "medic"], ["swordsman", "bulwark"],
]

var _grid_board: GridBoard
var _turn_manager: TurnManager
var _battle_resolution: BattleResolution

func setup(grid_board: GridBoard, turn_manager: TurnManager, battle_resolution: BattleResolution) -> void:
	_grid_board = grid_board
	_turn_manager = turn_manager
	_battle_resolution = battle_resolution
	if not EventBus.attack_initiated.is_connected(on_attack_initiated):
		EventBus.attack_initiated.connect(on_attack_initiated)

# Rule 1/2：阵营+动词前置过滤 → 扫描相邻友方 → 查矩阵 → 注入。
func on_attack_initiated(attacker_id_str: String, verb: String) -> void:
	if not verb in TRIGGER_VERBS:
		return
	var attacker_id := int(attacker_id_str)
	var a := _turn_manager.get_unit(attacker_id)
	if a == null or not a.is_alive or a.definition.faction != ALLY_FACTION:
		return
	for nid in _grid_board.get_adjacents(a.grid_position):
		var n := _turn_manager.get_unit(nid)
		if n != null and n.is_alive and n.definition.faction == ALLY_FACTION:
			var bonus := _bond_value(a.definition.unit_class, n.definition.unit_class)
			_battle_resolution.register_attack_modifier(attacker_id, bonus)

# Rule 3：查 BOND_MATRIX（精英对返回 2，其余返回 1）。
func _bond_value(class_a: String, class_b: String) -> int:
	for pair in _ELITE_PAIRS:
		if (pair[0] == class_a and pair[1] == class_b) or (pair[0] == class_b and pair[1] == class_a):
			return BOND_ELITE
	return BOND_BASE

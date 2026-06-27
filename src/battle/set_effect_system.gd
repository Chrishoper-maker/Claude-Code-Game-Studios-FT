# 套装效果引擎（②b-2a）。订阅 round_started，每轮起对全体存活单位按套装档位施加效果。
# 阵营无关（对任何持装备+档位激活的存活单位生效）。复用 BattleResolution status/heal。
class_name SetEffectSystem
extends Node

const IRONWALL_HEAL := 3
const HEALER_HEAL := 3
const HEALER_HEAL_HIGH := 6
const NAVIGATOR_RADIUS := 1
const NAVIGATOR_RADIUS_HIGH := 2

var _grid_board: GridBoard
var _turn_manager: TurnManager
var _battle_resolution: BattleResolution

func setup(grid_board: GridBoard, turn_manager: TurnManager, battle_resolution: BattleResolution) -> void:
	_grid_board = grid_board
	_turn_manager = turn_manager
	_battle_resolution = battle_resolution
	if not EventBus.round_started.is_connected(on_round_started):
		EventBus.round_started.connect(on_round_started)

# 每轮起：遍历全体存活单位，按其激活套装施加效果。
func on_round_started(_round_count: int) -> void:
	for uid in _all_alive_ids():
		var unit := _turn_manager.get_unit(uid)
		if unit == null or not unit.is_alive:
			continue
		for sid in SetBonus.count_sets(unit):
			match sid:
				"set_ironwall": _apply_ironwall(uid, unit)
				_: pass

# 铁壁：3=GUARDED（升级轴），9=SET_GUARD（取代 GUARDED）；6=+3自愈（新增轴）。
func _apply_ironwall(uid: int, unit: UnitInstance) -> void:
	if SetBonus.is_tier_active(unit, "set_ironwall", 9):
		_battle_resolution.apply_status(uid, BattleResolution.STATUS_SET_GUARD)
	elif SetBonus.is_tier_active(unit, "set_ironwall", 3):
		_battle_resolution.apply_status(uid, BattleResolution.STATUS_GUARDED)
	if SetBonus.is_tier_active(unit, "set_ironwall", 6):
		_battle_resolution.execute_burst_heal(uid, IRONWALL_HEAL)

# 全体存活 battle_id（两阵营）。
func _all_alive_ids() -> Array[int]:
	var ids: Array[int] = _turn_manager.get_alive_allies()
	ids.append_array(_turn_manager.get_alive_enemies())
	return ids

# 与 source 同阵营、存活、非自身、切比雪夫 ≤radius 的单位 battle_id。
func _same_faction_within_ids(source: UnitInstance, radius: int) -> Array[int]:
	var out: Array[int] = []
	for id in _all_alive_ids():
		var u := _turn_manager.get_unit(id)
		if u != null and u != source and u.is_alive \
				and u.definition.faction == source.definition.faction \
				and GridBoard.chebyshev(source.grid_position, u.grid_position) <= radius:
			out.append(id)
	return out

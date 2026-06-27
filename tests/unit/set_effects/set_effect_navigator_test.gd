# 航海套：3=相邻友军AURA / 6=相邻友军也GUARDED / 9=半径扩到2格。
extends GdUnitTestSuite

var _gb: GridBoard
var _tm: TurnManager
var _br: BattleResolution
var _ses: SetEffectSystem
const _SLOTKEYS := ["mainweapon", "offweapon", "head", "armor", "gloves", "legs", "boots", "ring", "necklace"]

func before_test() -> void:
	_gb = GridBoard.new(); _tm = TurnManager.new(); _br = BattleResolution.new(); _ses = SetEffectSystem.new()
	add_child(_tm); add_child(_br); add_child(_ses)
	_br.setup(_gb, _tm); _ses.setup(_gb, _tm, _br)

func after_test() -> void:
	_tm.free(); _br.free(); _ses.free(); _gb.free()   # GridBoard 是 Node，未入树也须 free 防孤儿

func _crew_def() -> UnitDefinition:
	for d in UnitDataManager.get_all_units():
		if d is CrewDefinition: return d
	return null

func _register_with(set_short: String, k: int, pos: Vector2i) -> int:
	var eq: Dictionary = {}
	for i in range(k):
		var def := EquipmentDataManager.get_equipment("eq_%s_%s" % [set_short, _SLOTKEYS[i]])
		eq[def.slot] = def
	var u := UnitInstance.from_definition(_crew_def(), eq)
	var id := _tm.register_unit(u); u.grid_position = pos
	return id

func _register_plain(pos: Vector2i) -> int:
	var u := UnitInstance.from_definition(_crew_def(), {})
	var id := _tm.register_unit(u); u.grid_position = pos
	return id

func test_navigator_3_buffs_adjacent_aura() -> void:
	_register_with("navigator", 3, Vector2i(0, 0))
	var aid := _register_plain(Vector2i(1, 0))
	_ses.on_round_started(1)
	assert_bool(_br.get_unit_status(aid, BattleResolution.STATUS_AURA)).is_true()

func test_navigator_6_buffs_adjacent_guarded() -> void:
	_register_with("navigator", 6, Vector2i(0, 0))
	var aid := _register_plain(Vector2i(1, 0))
	_ses.on_round_started(1)
	assert_bool(_br.get_unit_status(aid, BattleResolution.STATUS_GUARDED)).is_true()

func test_navigator_9_extends_radius_to_two() -> void:
	_register_with("navigator", 9, Vector2i(0, 0))
	var near := _register_plain(Vector2i(2, 0))   # 切比雪夫=2
	_ses.on_round_started(1)
	assert_bool(_br.get_unit_status(near, BattleResolution.STATUS_AURA)).is_true()

func test_navigator_3_does_not_reach_two() -> void:
	_register_with("navigator", 3, Vector2i(0, 0))
	var far := _register_plain(Vector2i(2, 0))   # 半径1够不到
	_ses.on_round_started(1)
	assert_bool(_br.get_unit_status(far, BattleResolution.STATUS_AURA)).is_false()

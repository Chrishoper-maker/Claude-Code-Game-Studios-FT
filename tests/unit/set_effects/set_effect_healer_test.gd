# 医者套：3=自身+3 / 6=相邻友军也+3 / 9=翻倍+6。
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
	var id := _tm.register_unit(u)
	u.grid_position = pos
	return id

func _register_plain(pos: Vector2i) -> int:
	var u := UnitInstance.from_definition(_crew_def(), {})
	var id := _tm.register_unit(u)
	u.grid_position = pos
	return id

func test_healer_3_heals_self() -> void:
	var id := _register_with("healer", 3, Vector2i(0, 0))
	var u := _tm.get_unit(id); u.current_hp = 1
	_ses.on_round_started(1)
	assert_int(u.current_hp).is_equal(mini(1 + SetEffectSystem.HEALER_HEAL, u.get_max_hp()))

func test_healer_6_heals_adjacent_ally() -> void:
	var hid := _register_with("healer", 6, Vector2i(0, 0))
	var aid := _register_plain(Vector2i(1, 0))   # 相邻
	var ally := _tm.get_unit(aid); ally.current_hp = 1
	_ses.on_round_started(1)
	assert_int(ally.current_hp).is_equal(mini(1 + SetEffectSystem.HEALER_HEAL, ally.get_max_hp()))

func test_healer_9_doubles_amount() -> void:
	var id := _register_with("healer", 9, Vector2i(0, 0))
	var u := _tm.get_unit(id); u.current_hp = 1
	_ses.on_round_started(1)
	assert_int(u.current_hp).is_equal(mini(1 + SetEffectSystem.HEALER_HEAL_HIGH, u.get_max_hp()))

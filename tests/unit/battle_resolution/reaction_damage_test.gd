# apply_reaction_damage：扣血/钳0/致死走 downed/不发 attack_executed（防递归）。
extends GdUnitTestSuite

var _gb: GridBoard
var _tm: TurnManager
var _br: BattleResolution

func before_test() -> void:
	_gb = GridBoard.new(); _tm = TurnManager.new(); _br = BattleResolution.new()
	add_child(_tm); add_child(_br)
	_br.setup(_gb, _tm)

func after_test() -> void:
	_tm.free(); _br.free(); _gb.free()

func _enemy_def() -> UnitDefinition:
	for d in UnitDataManager.get_all_units():
		if d is EnemyDefinition:
			return d
	return null

func _register() -> int:
	return _tm.register_unit(UnitInstance.from_definition(_enemy_def()))

func test_reaction_damage_reduces_hp() -> void:
	var id := _register()
	var u := _tm.get_unit(id)
	u.current_hp = 10
	_br.apply_reaction_damage(id, 3)
	assert_int(u.current_hp).is_equal(7)

func test_reaction_damage_clamps_to_zero_and_downs() -> void:
	var id := _register()
	var u := _tm.get_unit(id)
	u.current_hp = 2
	_br.apply_reaction_damage(id, 5)
	assert_int(u.current_hp).is_equal(0)
	assert_bool(u.is_alive).is_false()

func test_reaction_damage_does_not_emit_attack_executed() -> void:
	var id := _register()
	_tm.get_unit(id).current_hp = 10
	var spy := [0]
	EventBus.attack_executed.connect(func(_a: int, _b: int, _c: int) -> void: spy[0] += 1)
	_br.apply_reaction_damage(id, 3)
	assert_int(spy[0]).is_equal(0)

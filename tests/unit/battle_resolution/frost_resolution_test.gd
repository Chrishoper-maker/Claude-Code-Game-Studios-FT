# resolve_frost_for_turn：冻结/冰封/滞步 outcome + 消费 + 置免疫；无寒霜清免疫；
# FROST_x 回合级清除而 FROST_IMMUNE 跨回合保留。
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

func _register(move_range: int) -> int:
	var d := UnitDefinition.new()
	d.id = "e"; d.faction = "enemy"; d.unit_class = "swordsman"
	d.move_range = move_range; d.attack_range = 1; d.base_damage = 3; d.max_hp = 6
	var u := UnitInstance.from_definition(d)
	return _tm.register_unit(u)

func test_freeze_returns_skip_and_consumes_and_immunes() -> void:
	var id := _register(4)
	_br.apply_status(id, BattleResolution.STATUS_FROST_FREEZE)
	var fr := _br.resolve_frost_for_turn(id)
	assert_bool(fr["skip"]).is_true()
	assert_bool(_br.get_unit_status(id, BattleResolution.STATUS_FROST_FREEZE)).is_false()   # 已消费
	assert_bool(_br.get_unit_status(id, BattleResolution.STATUS_FROST_IMMUNE)).is_true()    # 置免疫

func test_root_returns_move_cap_zero() -> void:
	var id := _register(4)
	_br.apply_status(id, BattleResolution.STATUS_FROST_ROOT)
	var fr := _br.resolve_frost_for_turn(id)
	assert_bool(fr["skip"]).is_false()
	assert_int(fr["move_cap"]).is_equal(0)
	assert_bool(_br.get_unit_status(id, BattleResolution.STATUS_FROST_ROOT)).is_false()

func test_slow_returns_half_move_cap() -> void:
	var id := _register(4)
	_br.apply_status(id, BattleResolution.STATUS_FROST_SLOW)
	var fr := _br.resolve_frost_for_turn(id)
	assert_bool(fr["skip"]).is_false()
	assert_int(fr["move_cap"]).is_equal(2)   # floor(4/2)
	assert_bool(_br.get_unit_status(id, BattleResolution.STATUS_FROST_SLOW)).is_false()

func test_no_frost_clears_immune_and_returns_normal() -> void:
	var id := _register(4)
	_br.apply_status(id, BattleResolution.STATUS_FROST_IMMUNE)
	var fr := _br.resolve_frost_for_turn(id)
	assert_bool(fr["skip"]).is_false()
	assert_int(fr["move_cap"]).is_equal(-1)
	assert_bool(_br.get_unit_status(id, BattleResolution.STATUS_FROST_IMMUNE)).is_false()   # 免疫到期

func test_clear_round_statuses_clears_frost_x_not_immune() -> void:
	var id := _register(4)
	_br.apply_status(id, BattleResolution.STATUS_FROST_SLOW)
	_br.apply_status(id, BattleResolution.STATUS_FROST_IMMUNE)
	_br.clear_round_statuses()
	assert_bool(_br.get_unit_status(id, BattleResolution.STATUS_FROST_SLOW)).is_false()    # 回合级清除
	assert_bool(_br.get_unit_status(id, BattleResolution.STATUS_FROST_IMMUNE)).is_true()   # 跨回合保留

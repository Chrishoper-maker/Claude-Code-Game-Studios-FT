# BattleResolution 新 round-status：frenzy 取高/persist 不消耗、set_guard 减半不消耗、round 清除。
extends GdUnitTestSuite

var _br: BattleResolution
var _tm: TurnManager
var _gb: GridBoard

func before_test() -> void:
	_gb = GridBoard.new()
	_tm = TurnManager.new()
	_br = BattleResolution.new()
	add_child(_tm)
	add_child(_br)
	_br.setup(_gb, _tm)

func after_test() -> void:
	_tm.free()
	_br.free()
	_gb.free()

func _enemy_def() -> UnitDefinition:
	for d in UnitDataManager.get_all_units():
		if d is EnemyDefinition:
			return d
	return null

func _register(faction_def: UnitDefinition) -> int:
	var u := UnitInstance.from_definition(faction_def)
	return _tm.register_unit(u)

func test_frenzy_gives_plus_two_and_consumes() -> void:
	var aid := _register(_enemy_def())
	_br.apply_status(aid, BattleResolution.STATUS_FRENZY)
	var a := _tm.get_unit(aid)
	var dmg := _br._compute_attack_damage(aid, a)
	assert_int(dmg).is_equal(a.get_base_damage() + 2)
	# 消耗：第二次无加成
	assert_int(_br._compute_attack_damage(aid, a)).is_equal(a.get_base_damage())

func test_frenzy_persist_not_consumed() -> void:
	var aid := _register(_enemy_def())
	_br.apply_status(aid, BattleResolution.STATUS_FRENZY_PERSIST)
	var a := _tm.get_unit(aid)
	assert_int(_br._compute_attack_damage(aid, a)).is_equal(a.get_base_damage() + 2)
	assert_int(_br._compute_attack_damage(aid, a)).is_equal(a.get_base_damage() + 2)

func test_frenzy_takes_priority_over_aura() -> void:
	var aid := _register(_enemy_def())
	_br.apply_status(aid, BattleResolution.STATUS_AURA)
	_br.apply_status(aid, BattleResolution.STATUS_FRENZY)
	var a := _tm.get_unit(aid)
	assert_int(_br._compute_attack_damage(aid, a)).is_equal(a.get_base_damage() + 2)

func test_set_guard_halves_without_consume() -> void:
	var tid := _register(_enemy_def())
	_br.apply_status(tid, BattleResolution.STATUS_SET_GUARD)
	assert_int(_br._apply_guard(tid, 10)).is_equal(5)
	assert_int(_br._apply_guard(tid, 8)).is_equal(4)   # 未消耗，仍减半

func test_clear_round_statuses_clears_new() -> void:
	var id := _register(_enemy_def())
	_br.apply_status(id, BattleResolution.STATUS_FRENZY_PERSIST)
	_br.apply_status(id, BattleResolution.STATUS_SET_GUARD)
	_br.clear_round_statuses()
	assert_bool(_br.get_unit_status(id, BattleResolution.STATUS_FRENZY_PERSIST)).is_false()
	assert_bool(_br.get_unit_status(id, BattleResolution.STATUS_SET_GUARD)).is_false()

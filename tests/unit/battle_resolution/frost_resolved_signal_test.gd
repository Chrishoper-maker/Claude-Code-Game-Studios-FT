# resolve_frost_for_turn：三消费分支各发 frost_resolved(id, consumed)；无寒霜分支不发。
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

func _register() -> int:
	var d := UnitDefinition.new()
	d.id = "e"; d.faction = "enemy"; d.unit_class = "swordsman"
	d.move_range = 4; d.attack_range = 1; d.base_damage = 3; d.max_hp = 6
	return _tm.register_unit(UnitInstance.from_definition(d))

func test_freeze_emits_frost_resolved_freeze() -> void:
	var id := _register()
	_br.apply_status(id, BattleResolution.STATUS_FROST_FREEZE)
	var monitor := monitor_signals(EventBus, false)
	_br.resolve_frost_for_turn(id)
	await assert_signal(monitor).is_emitted("frost_resolved", [id, BattleResolution.STATUS_FROST_FREEZE])

func test_root_emits_frost_resolved_root() -> void:
	var id := _register()
	_br.apply_status(id, BattleResolution.STATUS_FROST_ROOT)
	var monitor := monitor_signals(EventBus, false)
	_br.resolve_frost_for_turn(id)
	await assert_signal(monitor).is_emitted("frost_resolved", [id, BattleResolution.STATUS_FROST_ROOT])

func test_slow_emits_frost_resolved_slow() -> void:
	var id := _register()
	_br.apply_status(id, BattleResolution.STATUS_FROST_SLOW)
	var monitor := monitor_signals(EventBus, false)
	_br.resolve_frost_for_turn(id)
	await assert_signal(monitor).is_emitted("frost_resolved", [id, BattleResolution.STATUS_FROST_SLOW])

func test_no_frost_emits_no_frost_resolved() -> void:
	var id := _register()
	_br.apply_status(id, BattleResolution.STATUS_FROST_IMMUNE)
	var monitor := monitor_signals(EventBus, false)
	_br.resolve_frost_for_turn(id)
	await assert_signal(monitor).is_not_emitted("frost_resolved")

# 端到端：真实 round_started 信号驱动 SetEffectSystem，铁壁9件单位本轮多次受击均减半；
# 阵营无关——enemy faction 带装备也生效（AC-6）。
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

func _def(is_crew: bool) -> UnitDefinition:
	for d in UnitDataManager.get_all_units():
		if is_crew and d is CrewDefinition: return d
		if not is_crew and d is EnemyDefinition: return d
	return null

func _register_set(is_crew: bool, set_short: String, k: int) -> int:
	var eq: Dictionary = {}
	for i in range(k):
		var def := EquipmentDataManager.get_equipment("eq_%s_%s" % [set_short, _SLOTKEYS[i]])
		eq[def.slot] = def
	return _tm.register_unit(UnitInstance.from_definition(_def(is_crew), eq))

func test_round_started_signal_drives_set_guard() -> void:
	var id := _register_set(true, "ironwall", 9)
	EventBus.round_started.emit(1)   # 真实信号
	assert_bool(_br.get_unit_status(id, BattleResolution.STATUS_SET_GUARD)).is_true()
	# 本轮多次受击均减半（set_guard 不消耗）
	assert_int(_br._apply_guard(id, 10)).is_equal(5)
	assert_int(_br._apply_guard(id, 6)).is_equal(3)

func test_effect_is_faction_agnostic_for_enemy() -> void:
	var eid := _register_set(false, "berserker", 6)   # 敌方带狂战6
	EventBus.round_started.emit(1)
	assert_bool(_br.get_unit_status(eid, BattleResolution.STATUS_FRENZY)).is_true()

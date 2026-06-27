# 荆棘套：被命中后对攻击者反伤 1/2/3；反伤不发 attack_executed（防递归）。
extends GdUnitTestSuite

var _gb: GridBoard
var _tm: TurnManager
var _br: BattleResolution
var _srs: SetReactionSystem
const _SLOTKEYS := ["mainweapon", "offweapon", "head", "armor", "gloves", "legs", "boots", "ring", "necklace"]

func before_test() -> void:
	_gb = GridBoard.new(); _tm = TurnManager.new(); _br = BattleResolution.new(); _srs = SetReactionSystem.new()
	add_child(_tm); add_child(_br); add_child(_srs)
	_br.setup(_gb, _tm); _srs.setup(_gb, _tm, _br)

func after_test() -> void:
	_tm.free(); _br.free(); _srs.free(); _gb.free()

func _crew_def() -> UnitDefinition:
	for d in UnitDataManager.get_all_units():
		if d is CrewDefinition: return d
	return null

func _register_set(set_short: String, k: int) -> int:
	var eq: Dictionary = {}
	for i in range(k):
		var def := EquipmentDataManager.get_equipment("eq_%s_%s" % [set_short, _SLOTKEYS[i]])
		eq[def.slot] = def
	return _tm.register_unit(UnitInstance.from_definition(_crew_def(), eq))

func _register_plain() -> int:
	return _tm.register_unit(UnitInstance.from_definition(_crew_def(), {}))

func test_thorns_3_reflects_one() -> void:
	var aid := _register_plain()
	var tid := _register_set("thorns", 3)
	var a := _tm.get_unit(aid); a.current_hp = 10
	_srs.on_attack_executed(aid, tid, 5)
	assert_int(a.current_hp).is_equal(9)   # 反伤 1

func test_thorns_9_reflects_three() -> void:
	var aid := _register_plain()
	var tid := _register_set("thorns", 9)
	var a := _tm.get_unit(aid); a.current_hp = 10
	_srs.on_attack_executed(aid, tid, 5)
	assert_int(a.current_hp).is_equal(7)   # 反伤 3

func test_thorns_reflection_emits_no_attack_executed() -> void:
	var aid := _register_plain()
	var tid := _register_set("thorns", 3)
	_tm.get_unit(aid).current_hp = 10
	var spy := [0]
	EventBus.attack_executed.connect(func(_a: int, _b: int, _c: int) -> void: spy[0] += 1)
	_srs.on_attack_executed(aid, tid, 5)
	assert_int(spy[0]).is_equal(0)

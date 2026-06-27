# 寒霜套（看攻击者）：命中给非免疫敌方按最高档施寒霜状态；免疫则跳过。
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

func _register_frost(k: int) -> int:
	var eq: Dictionary = {}
	for i in range(k):
		var def := EquipmentDataManager.get_equipment("eq_frost_%s" % _SLOTKEYS[i])
		eq[def.slot] = def
	return _tm.register_unit(UnitInstance.from_definition(_crew_def(), eq))

func _register_plain() -> int:
	return _tm.register_unit(UnitInstance.from_definition(_crew_def(), {}))

func test_frost_3_applies_slow() -> void:
	var aid := _register_frost(3)
	var tid := _register_plain()
	_srs.on_attack_executed(aid, tid, 3)
	assert_bool(_br.get_unit_status(tid, BattleResolution.STATUS_FROST_SLOW)).is_true()

func test_frost_6_applies_root() -> void:
	var aid := _register_frost(6)
	var tid := _register_plain()
	_srs.on_attack_executed(aid, tid, 3)
	assert_bool(_br.get_unit_status(tid, BattleResolution.STATUS_FROST_ROOT)).is_true()

func test_frost_9_applies_freeze() -> void:
	var aid := _register_frost(9)
	var tid := _register_plain()
	_srs.on_attack_executed(aid, tid, 3)
	assert_bool(_br.get_unit_status(tid, BattleResolution.STATUS_FROST_FREEZE)).is_true()

func test_frost_skips_immune_target() -> void:
	var aid := _register_frost(9)
	var tid := _register_plain()
	_br.apply_status(tid, BattleResolution.STATUS_FROST_IMMUNE)
	_srs.on_attack_executed(aid, tid, 3)
	assert_bool(_br.get_unit_status(tid, BattleResolution.STATUS_FROST_FREEZE)).is_false()   # 免疫挡掉

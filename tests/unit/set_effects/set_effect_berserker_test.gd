# 狂战套：3=AURA / 6=FRENZY(取代AURA) / 9=FRENZY_PERSIST。
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

func _register_with(set_short: String, k: int) -> int:
	var eq: Dictionary = {}
	for i in range(k):
		var def := EquipmentDataManager.get_equipment("eq_%s_%s" % [set_short, _SLOTKEYS[i]])
		eq[def.slot] = def
	return _tm.register_unit(UnitInstance.from_definition(_crew_def(), eq))

func test_berserker_3_grants_aura() -> void:
	var id := _register_with("berserker", 3)
	_ses.on_round_started(1)
	assert_bool(_br.get_unit_status(id, BattleResolution.STATUS_AURA)).is_true()
	assert_bool(_br.get_unit_status(id, BattleResolution.STATUS_FRENZY)).is_false()

func test_berserker_6_grants_frenzy_not_aura() -> void:
	var id := _register_with("berserker", 6)
	_ses.on_round_started(1)
	assert_bool(_br.get_unit_status(id, BattleResolution.STATUS_FRENZY)).is_true()
	assert_bool(_br.get_unit_status(id, BattleResolution.STATUS_AURA)).is_false()

func test_berserker_9_grants_frenzy_persist() -> void:
	var id := _register_with("berserker", 9)
	_ses.on_round_started(1)
	assert_bool(_br.get_unit_status(id, BattleResolution.STATUS_FRENZY_PERSIST)).is_true()

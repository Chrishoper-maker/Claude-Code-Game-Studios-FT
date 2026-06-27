# 嗜血套：命中后攻击者按伤害回血（3=¼ / 6=½ / 9=½+相邻¼）。
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

func _register_set(set_short: String, k: int, pos: Vector2i) -> int:
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

func test_bloodthirst_3_heals_quarter() -> void:
	var aid := _register_set("bloodthirst", 3, Vector2i(0, 0))
	var a := _tm.get_unit(aid); a.current_hp = 1
	_srs.on_attack_executed(aid, _register_plain(Vector2i(5, 5)), 8)
	assert_int(a.current_hp).is_equal(mini(1 + 2, a.get_max_hp()))   # floor(8/4)=2

func test_bloodthirst_6_heals_half() -> void:
	var aid := _register_set("bloodthirst", 6, Vector2i(0, 0))
	var a := _tm.get_unit(aid); a.current_hp = 1
	_srs.on_attack_executed(aid, _register_plain(Vector2i(5, 5)), 8)
	assert_int(a.current_hp).is_equal(mini(1 + 4, a.get_max_hp()))   # floor(8/2)=4

func test_bloodthirst_9_overflows_to_adjacent() -> void:
	var aid := _register_set("bloodthirst", 9, Vector2i(0, 0))
	var ally := _register_plain(Vector2i(1, 0))   # 相邻
	var a := _tm.get_unit(aid); a.current_hp = 1
	var al := _tm.get_unit(ally); al.current_hp = 1
	_srs.on_attack_executed(aid, _register_plain(Vector2i(5, 5)), 8)
	assert_int(al.current_hp).is_equal(mini(1 + 2, al.get_max_hp()))   # 相邻 floor(8/4)=2

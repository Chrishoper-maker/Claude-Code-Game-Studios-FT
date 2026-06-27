# 处决套：命中后目标存活且 hp≤阈值 → 追加斩杀（3/5/7）；hp>阈值不触发。
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

func test_executioner_3_finishes_low_hp() -> void:
	var aid := _register_set("executioner", 3)
	var tid := _register_plain()
	var t := _tm.get_unit(tid); t.current_hp = 3   # ≤阈值3
	_srs.on_attack_executed(aid, tid, 1)
	assert_int(t.current_hp).is_equal(0)            # 追加3致死
	assert_bool(t.is_alive).is_false()

func test_executioner_3_skips_high_hp() -> void:
	var aid := _register_set("executioner", 3)
	var tid := _register_plain()
	var t := _tm.get_unit(tid); t.current_hp = 4   # >阈值3
	_srs.on_attack_executed(aid, tid, 1)
	assert_int(t.current_hp).is_equal(4)            # 不触发

func test_executioner_9_threshold_seven() -> void:
	var aid := _register_set("executioner", 9)
	var tid := _register_plain()
	var t := _tm.get_unit(tid); t.current_hp = 7   # ≤阈值7
	_srs.on_attack_executed(aid, tid, 1)
	assert_int(t.current_hp).is_equal(0)            # 追加7致死

# 普攻同帧致死：attack_executed 触发时目标 current_hp==0 但 is_alive 尚未翻转——
# 处决须跳过，不对 0 血目标追击（否则重复 down/飘字）。
func test_executioner_skips_target_already_at_zero_hp() -> void:
	var aid := _register_set("executioner", 3)
	var tid := _register_plain()
	var t := _tm.get_unit(tid); t.current_hp = 0   # 本次普攻已致死同帧（is_alive 仍 true）
	var spy := [0]
	EventBus.damage_dealt.connect(func(_a: int, _b: int, _c: int) -> void: spy[0] += 1)
	_srs.on_attack_executed(aid, tid, 1)
	assert_int(spy[0]).is_equal(0)   # 处决未追击 0 血目标

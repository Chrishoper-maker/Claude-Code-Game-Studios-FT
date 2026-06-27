# 端到端：crew 持寒霜真打敌→施寒霜状态→敌回合 resolve 结算消费+免疫；免疫挡掉次回合施加。
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

func _register_frost9(pos: Vector2i) -> int:
	var eq: Dictionary = {}
	for i in range(9):
		var ed := EquipmentDataManager.get_equipment("eq_frost_%s" % _SLOTKEYS[i])
		eq[ed.slot] = ed
	var u := UnitInstance.from_definition(_crew_def(), eq)
	var id := _tm.register_unit(u); u.grid_position = pos; _gb.place_unit(id, pos)
	return id

func _register_enemy(pos: Vector2i) -> int:
	var d := UnitDefinition.new()
	d.id = "e"; d.faction = "enemy"; d.unit_class = "swordsman"
	d.move_range = 4; d.attack_range = 1; d.base_damage = 3; d.max_hp = 20
	var u := UnitInstance.from_definition(d)
	u.current_hp = 20
	var id := _tm.register_unit(u); u.grid_position = pos; _gb.place_unit(id, pos)
	return id

func test_attack_applies_freeze_then_resolved_and_immune() -> void:
	var crew := _register_frost9(Vector2i(0, 0))
	var enemy := _register_enemy(Vector2i(1, 0))
	_br.execute_attack(crew, enemy)                              # 真信号链 → 施冻结
	assert_bool(_br.get_unit_status(enemy, BattleResolution.STATUS_FROST_FREEZE)).is_true()
	var fr := _br.resolve_frost_for_turn(enemy)                  # 敌回合结算
	assert_bool(fr["skip"]).is_true()
	assert_bool(_br.get_unit_status(enemy, BattleResolution.STATUS_FROST_FREEZE)).is_false()   # 消费
	assert_bool(_br.get_unit_status(enemy, BattleResolution.STATUS_FROST_IMMUNE)).is_true()    # 免疫

func test_immune_blocks_next_application() -> void:
	var crew := _register_frost9(Vector2i(0, 0))
	var enemy := _register_enemy(Vector2i(1, 0))
	_br.apply_status(enemy, BattleResolution.STATUS_FROST_IMMUNE)
	_br.execute_attack(crew, enemy)
	assert_bool(_br.get_unit_status(enemy, BattleResolution.STATUS_FROST_FREEZE)).is_false()   # 免疫挡掉施加

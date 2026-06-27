# 端到端：真实 execute_attack 触发 attack_executed → SetReactionSystem 反应；阵营无关；防递归。
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

func _def(is_crew: bool, dmg: int) -> UnitDefinition:
	# 取一个对应阵营 def 副本式：直接构造最小 def 保证 base_damage/range 可控。
	var d := UnitDefinition.new()
	d.id = "x"; d.faction = "crew" if is_crew else "enemy"
	d.unit_class = "swordsman"; d.base_damage = dmg; d.move_range = 1; d.attack_range = 1; d.max_hp = 20
	return d

func _register_set(faction_def: UnitDefinition, set_short: String, k: int, pos: Vector2i) -> int:
	var eq: Dictionary = {}
	for i in range(k):
		var ed := EquipmentDataManager.get_equipment("eq_%s_%s" % [set_short, _SLOTKEYS[i]])
		eq[ed.slot] = ed
	var u := UnitInstance.from_definition(faction_def, eq)
	var id := _tm.register_unit(u); u.grid_position = pos; _gb.place_unit(id, pos)
	return id

func test_execute_attack_triggers_bloodthirst_for_enemy_attacker() -> void:
	# 阵营无关：敌方攻击者持嗜血，真打后回血。
	var aid := _register_set(_def(false, 6), "bloodthirst", 6, Vector2i(0, 0))
	var crew_target := UnitInstance.from_definition(_def(true, 0))
	var tid := _tm.register_unit(crew_target); crew_target.grid_position = Vector2i(1, 0); _gb.place_unit(tid, Vector2i(1, 0))
	var a := _tm.get_unit(aid); a.current_hp = 1
	_br.execute_attack(aid, tid)   # 真信号链
	assert_int(a.current_hp).is_greater(1)   # 嗜血回血

func test_attack_into_thorns_reflects_without_recursion() -> void:
	var aid := _register_set(_def(true, 6), "", 0, Vector2i(0, 0))   # 无装备攻击者
	var tdef := _def(false, 0)
	var tid := _register_set(tdef, "thorns", 3, Vector2i(1, 0))
	var a := _tm.get_unit(aid); a.current_hp = 10
	_br.execute_attack(aid, tid)
	assert_int(a.current_hp).is_equal(9)   # 反伤1，且无递归（若递归会多次扣）

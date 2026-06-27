# EnemyAI 寒霜整合：冻结→不行动(WAIT);冰封→可攻不可移;滞步→移动范围减半。
# 经 _on_enemy_turn_started 驱真实意图执行（resolve_frost_for_turn 消费+免疫）。
extends GdUnitTestSuite

var _gb: GridBoard
var _tm: TurnManager
var _br: BattleResolution
var _ai: EnemyAI
var _uid: int

func before_test() -> void:
	if EventBus.battle_won.is_connected(RunManager._on_battle_won):
		EventBus.battle_won.disconnect(RunManager._on_battle_won)
	_gb = auto_free(GridBoard.new())
	_tm = auto_free(TurnManager.new())
	_br = auto_free(BattleResolution.new())
	_br.setup(_gb, _tm)
	_ai = auto_free(EnemyAI.new())
	_ai.setup(_gb, _tm, _br)
	_uid = 0

func after_test() -> void:
	if not EventBus.battle_won.is_connected(RunManager._on_battle_won):
		EventBus.battle_won.connect(RunManager._on_battle_won)

func _add(faction: String, pos: Vector2i, move_range: int) -> int:
	_uid += 1
	var d := UnitDefinition.new()
	d.id = "u%d" % _uid; d.faction = faction; d.unit_class = "swordsman"
	d.move_range = move_range; d.attack_range = 1; d.base_damage = 3; d.max_hp = 6
	var inst := UnitInstance.from_definition(d)
	inst.current_hp = 6; inst.grid_position = pos; inst.behavior_type = "MELEE"
	var bid := _tm.register_unit(inst)
	_gb.place_unit(bid, pos)
	return bid

func test_freeze_makes_enemy_skip_turn() -> void:
	var enemy := _add("enemy", Vector2i(3, 3), 4)
	var crew := _add("crew", Vector2i(3, 2), 4)   # 相邻，正常会被攻击
	_br.apply_status(enemy, BattleResolution.STATUS_FROST_FREEZE)
	_ai._on_enemy_turn_started(enemy)
	assert_int(_tm.get_unit(crew).current_hp).is_equal(6)                 # 未被攻击
	assert_vector(_tm.get_unit(enemy).grid_position).is_equal(Vector2i(3, 3))  # 未移动
	assert_bool(_br.get_unit_status(enemy, BattleResolution.STATUS_FROST_IMMUNE)).is_true()

func test_root_allows_attack_but_no_move() -> void:
	var enemy := _add("enemy", Vector2i(3, 3), 4)
	var crew := _add("crew", Vector2i(3, 2), 4)   # 相邻
	_br.apply_status(enemy, BattleResolution.STATUS_FROST_ROOT)
	_ai._on_enemy_turn_started(enemy)
	assert_int(_tm.get_unit(crew).current_hp).is_less(6)                  # 相邻仍可攻
	assert_vector(_tm.get_unit(enemy).grid_position).is_equal(Vector2i(3, 3))  # 未移动

func test_root_cannot_approach_distant_target() -> void:
	var enemy := _add("enemy", Vector2i(3, 5), 4)
	_add("crew", Vector2i(3, 0), 4)   # 远，正常会接近
	_br.apply_status(enemy, BattleResolution.STATUS_FROST_ROOT)
	_ai._on_enemy_turn_started(enemy)
	assert_vector(_tm.get_unit(enemy).grid_position).is_equal(Vector2i(3, 5))  # 不能移动

func test_slow_halves_move_range() -> void:
	var enemy := _add("enemy", Vector2i(3, 6), 4)
	_add("crew", Vector2i(3, 0), 4)   # 远（曼哈顿6），正常 move4 接近
	_br.apply_status(enemy, BattleResolution.STATUS_FROST_SLOW)
	_ai._on_enemy_turn_started(enemy)
	# 有效移动 floor(4/2)=2：从 (3,6) 最多移 2 格逼近 → y 不低于 4
	var moved := _tm.get_unit(enemy).grid_position
	assert_int(moved.y).is_greater_equal(4)
	assert_int(GridBoard.manhattan(Vector2i(3, 6), moved)).is_less_equal(2)

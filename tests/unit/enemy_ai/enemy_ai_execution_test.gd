# EnemyAI 执行循环 + TurnManager 敌方回合集成（enemy-ai Rule 1/3 + turn-management 跨GDD合同）。
# 真实 GridBoard+TurnManager+BattleResolution+EnemyAI 全接线；start_battle 同步驱动敌方回合。
# TDD：先于实现写就。
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

func _add(faction: String, pos: Vector2i, move_range: int, base_damage: int = 3, attack_range: int = 1, behavior: String = "MELEE") -> int:
	_uid += 1
	var d := UnitDefinition.new()
	d.id = "u%d" % _uid
	d.faction = faction
	d.unit_class = "swordsman"
	d.move_range = move_range
	d.attack_range = attack_range
	d.base_damage = base_damage
	d.max_hp = 6
	var inst := UnitInstance.from_definition(d)
	inst.current_hp = 6
	inst.grid_position = pos
	inst.behavior_type = behavior
	var bid := _tm.register_unit(inst)
	_gb.place_unit(bid, pos)
	return bid

# 敌方在其回合自动攻击相邻友方（turn flow → enemy_turn_started → AI → execute_attack）
func test_enemy_attacks_adjacent_ally_on_turn() -> void:
	var ally := _add("crew", Vector2i(0, 1), 0)        # move0 → 先攻最低，敌方先行
	_add("enemy", Vector2i(0, 0), 3, 3, 1)             # 邻接 ally
	_tm.start_battle()
	assert_int(_tm.get_unit(ally).current_hp).is_equal(3)

# 敌方行动完毕后回合推进至下一单位
func test_turn_advances_after_enemy_acts() -> void:
	var ally := _add("crew", Vector2i(0, 1), 0)
	_add("enemy", Vector2i(0, 0), 3)
	_tm.start_battle()
	assert_int(_tm.get_current_unit_id()).is_equal(ally)

# ROUND_START 为所有敌方声明意图（intent_declared）
func test_round_start_declares_enemy_intents() -> void:
	_add("crew", Vector2i(0, 1), 0)
	_add("enemy", Vector2i(5, 5), 3)
	_add("enemy", Vector2i(6, 6), 3)
	var count := [0]
	var cb := func(_id: int, _rec: IntentRecord) -> void: count[0] += 1
	EventBus.intent_declared.connect(cb)
	_tm.start_battle()
	EventBus.intent_declared.disconnect(cb)
	assert_bool(count[0] >= 2).is_true()

# 够不着的敌方在其回合向友方移动靠近
func test_enemy_moves_toward_distant_ally() -> void:
	var ally := _add("crew", Vector2i(0, 7), 0)
	var enemy := _add("enemy", Vector2i(0, 0), 2, 3, 1)   # 距 ally manhattan 7，move2
	_tm.start_battle()
	var e := _tm.get_unit(enemy)
	assert_bool(GridBoard.manhattan(e.grid_position, Vector2i(0, 7)) < 7).is_true()
	assert_bool(e.has_moved).is_true()

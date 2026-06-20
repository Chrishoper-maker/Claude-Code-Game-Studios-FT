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

# 敌方回合自动攻击相邻友方（敌方回合 → enemy_turn_started → AI → execute_attack）
func test_enemy_attacks_adjacent_ally_on_enemy_phase() -> void:
	var ally := _add("crew", Vector2i(0, 1), 0)
	_add("enemy", Vector2i(0, 0), 3, 3, 1)             # 邻接 ally
	_tm.start_battle()
	_tm.end_player_phase()                              # 触发敌方回合
	assert_int(_tm.get_unit(ally).current_hp).is_equal(3)

# 敌方回合结束后回到下一轮我方回合
func test_returns_to_player_phase_after_enemy_phase() -> void:
	_add("crew", Vector2i(0, 1), 0)
	_add("enemy", Vector2i(0, 0), 3)
	_tm.start_battle()
	_tm.end_player_phase()
	assert_int(_tm.get_battle_state()).is_equal(TurnManager.BattleState.PLAYER_PHASE)
	assert_int(_tm.get_current_round()).is_equal(2)

# 我方回合开始（round_started）为所有敌方声明意图（intent_declared）
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

# 够不着的敌方在敌方回合向友方移动靠近
func test_enemy_moves_toward_distant_ally() -> void:
	_add("crew", Vector2i(0, 7), 0)
	var enemy := _add("enemy", Vector2i(0, 0), 2, 3, 1)   # 距 ally manhattan 7，move2
	_tm.start_battle()
	_tm.end_player_phase()
	var e := _tm.get_unit(enemy)
	# 敌方回合已向 ally 靠近（位置变化为证；has_moved 于下一轮我方回合开始已被重置，不可断言）。
	assert_bool(GridBoard.manhattan(e.grid_position, Vector2i(0, 7)) < 7).is_true()

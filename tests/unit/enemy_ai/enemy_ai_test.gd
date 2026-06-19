# EnemyAI 意图计算测试（enemy-ai-intent-system GDD Rule 2/5/6）。
# 子程序（目标选择）+ decide_intent 四行为决策树；确定性，平局按 unit_id 升序。
# 意图执行循环（Rule 3/4）属运行时编排，留后续 story，不在此测。
# get_path_to 以贪心最近可达格等价替代（MVP 白盒）。
# TDD：先于实现写就。
extends GdUnitTestSuite

var _gb: GridBoard
var _tm: TurnManager
var _br: BattleResolution
var _ai: EnemyAI
var _uid: int

func before_test() -> void:
	_gb = auto_free(GridBoard.new())
	_tm = auto_free(TurnManager.new())
	_br = auto_free(BattleResolution.new())
	_br.setup(_gb, _tm)
	_ai = auto_free(EnemyAI.new())
	_ai.setup(_gb, _tm, _br)
	_uid = 0

func _add(faction: String, pos: Vector2i, hp: int = 6, move_range: int = 2, attack_range: int = 1, unit_class: String = "swordsman", behavior: String = "MELEE", home := Vector2i(-1, -1)) -> int:
	_uid += 1
	var d := UnitDefinition.new()
	d.id = "u%d" % _uid
	d.faction = faction
	d.unit_class = unit_class
	d.max_hp = hp
	d.move_range = move_range
	d.attack_range = attack_range
	var inst := UnitInstance.from_definition(d)
	inst.current_hp = hp
	inst.grid_position = pos
	inst.behavior_type = behavior
	inst.home_pos = home
	var bid := _tm.register_unit(inst)
	_gb.place_unit(bid, pos)
	return bid

# ── Rule 5 子程序 ──

func test_select_nearest_lowest_hp_prefers_nearest() -> void:
	var self_id := _add("enemy", Vector2i(0, 0))
	var near := _add("crew", Vector2i(0, 1), 5)
	_add("crew", Vector2i(0, 2), 3)               # 更低血但更远
	assert_int(_ai.select_nearest_lowest_hp(self_id)).is_equal(near)

func test_select_nearest_lowest_hp_tiebreak_by_hp() -> void:
	var self_id := _add("enemy", Vector2i(0, 0))
	_add("crew", Vector2i(0, 1), 5)
	var low := _add("crew", Vector2i(1, 0), 3)    # 同距离(切比雪夫1)，更低血
	assert_int(_ai.select_nearest_lowest_hp(self_id)).is_equal(low)

func test_select_nearest_returns_minus_one_when_no_allies() -> void:
	var self_id := _add("enemy", Vector2i(0, 0))
	assert_int(_ai.select_nearest_lowest_hp(self_id)).is_equal(-1)

func test_select_highest_stack_count() -> void:
	var self_id := _add("enemy", Vector2i(4, 5))
	var stacked := _add("crew", Vector2i(4, 4))   # 被 self + enemy2 包夹
	_add("enemy", Vector2i(3, 4))                 # enemy2，邻接 stacked
	_add("crew", Vector2i(0, 0))                  # 孤立，stack 0
	assert_int(_ai.select_highest_stack_count(self_id)).is_equal(stacked)

# ── Rule 2A MELEE ──

func test_melee_attacks_when_in_range() -> void:
	var s := _add("enemy", Vector2i(0, 0))
	var t := _add("crew", Vector2i(0, 1))
	var rec := _ai.decide_intent(s)
	assert_int(rec.intent_type).is_equal(IntentRecord.IntentType.INTENT_ATTACK)
	assert_int(rec.target_id).is_equal(t)

func test_melee_move_attack_when_staging_exists() -> void:
	var s := _add("enemy", Vector2i(0, 0), 6, 2, 1)
	var t := _add("crew", Vector2i(0, 3))
	var rec := _ai.decide_intent(s)
	assert_int(rec.intent_type).is_equal(IntentRecord.IntentType.INTENT_MOVE_ATTACK)
	assert_int(rec.target_id).is_equal(t)
	assert_vector(rec.target_pos).is_equal(Vector2i(0, 2))

func test_melee_wait_when_no_target() -> void:
	var s := _add("enemy", Vector2i(0, 0))
	var rec := _ai.decide_intent(s)
	assert_int(rec.intent_type).is_equal(IntentRecord.IntentType.INTENT_WAIT)

# ── Rule 2B RANGED ──

func test_ranged_attacks_at_comfortable_distance() -> void:
	var s := _add("enemy", Vector2i(0, 0), 6, 2, 3, "gunner", "MELEE")  # 行为下设
	_tm.get_unit(s).behavior_type = "RANGED"
	var t := _add("crew", Vector2i(0, 3))         # manhattan 3 >= 阈值2 且可攻击
	var rec := _ai.decide_intent(s)
	assert_int(rec.intent_type).is_equal(IntentRecord.IntentType.INTENT_ATTACK)
	assert_int(rec.target_id).is_equal(t)

func test_ranged_retreats_when_too_close() -> void:
	var s := _add("enemy", Vector2i(0, 1), 6, 2, 3, "gunner", "RANGED")
	_add("crew", Vector2i(0, 0))                  # manhattan 1 < 阈值2
	var rec := _ai.decide_intent(s)
	assert_int(rec.intent_type).is_equal(IntentRecord.IntentType.INTENT_MOVE)
	# 后退后距离应增大
	assert_bool(GridBoard.manhattan(rec.target_pos, Vector2i(0, 0)) > 1).is_true()

# ── Rule 2C GUARDIAN ──

func test_guardian_attacks_in_range() -> void:
	var s := _add("enemy", Vector2i(3, 3), 6, 2, 1, "swordsman", "GUARDIAN", Vector2i(3, 3))
	var t := _add("crew", Vector2i(3, 4))
	var rec := _ai.decide_intent(s)
	assert_int(rec.intent_type).is_equal(IntentRecord.IntentType.INTENT_ATTACK)
	assert_int(rec.target_id).is_equal(t)

func test_guardian_returns_home_when_displaced() -> void:
	var s := _add("enemy", Vector2i(3, 5), 6, 2, 1, "swordsman", "GUARDIAN", Vector2i(3, 3))
	_add("crew", Vector2i(7, 7))                  # 远，无射程内目标
	var rec := _ai.decide_intent(s)
	assert_int(rec.intent_type).is_equal(IntentRecord.IntentType.INTENT_MOVE)
	assert_vector(rec.target_pos).is_equal(Vector2i(3, 3))

func test_guardian_waits_at_home_no_target() -> void:
	var s := _add("enemy", Vector2i(3, 3), 6, 2, 1, "swordsman", "GUARDIAN", Vector2i(3, 3))
	_add("crew", Vector2i(7, 7))
	var rec := _ai.decide_intent(s)
	assert_int(rec.intent_type).is_equal(IntentRecord.IntentType.INTENT_WAIT)

# ── Rule 2D SWARMER ──

func test_swarmer_attacks_stacked_target() -> void:
	var s := _add("enemy", Vector2i(4, 5), 6, 2, 1, "swordsman", "SWARMER")
	var stacked := _add("crew", Vector2i(4, 4))
	_add("enemy", Vector2i(3, 4))                 # 邻接 stacked → stack 计数
	_add("crew", Vector2i(0, 0))
	var rec := _ai.decide_intent(s)
	assert_int(rec.intent_type).is_equal(IntentRecord.IntentType.INTENT_ATTACK)
	assert_int(rec.target_id).is_equal(stacked)

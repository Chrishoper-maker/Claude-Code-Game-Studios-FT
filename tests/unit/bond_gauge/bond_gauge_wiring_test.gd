# BondGaugeBurst 充能信号 wiring 测试（bond-gauge-burst GDD Rule 2-4 信号订阅）。
# setup 连 EventBus.attack_executed/cannon_executed/damage_dealt/round_ended，
# 实战循环里自动充能（相邻判定由本系统经 grid_board.get_adjacents 计算）。
# 经真实 EventBus.emit 驱动；EventBus 连接靠 auto_free 清理（freed 节点自动断开）。
# TDD：先于实现写就。
extends GdUnitTestSuite

var _bg: BondGaugeBurst
var _br: BattleResolution
var _gb: GridBoard
var _tm: TurnManager
var _uid_counter: int

func before_test() -> void:
	_gb = auto_free(GridBoard.new())
	_tm = auto_free(TurnManager.new())
	_br = auto_free(BattleResolution.new())
	_br.setup(_gb, _tm)
	_bg = auto_free(BondGaugeBurst.new())
	_bg.setup(_gb, _tm, _br)
	_uid_counter = 0

func _add(unit_class: String, faction: String, pos: Vector2i, base_damage: int = 3, max_hp: int = 10) -> int:
	_uid_counter += 1
	var d := UnitDefinition.new()
	d.id = "u%d" % _uid_counter
	d.faction = faction
	d.unit_class = unit_class
	d.base_damage = base_damage
	d.attack_range = 1
	d.max_hp = max_hp
	d.class_action_id = "v"
	var inst := UnitInstance.from_definition(d)
	inst.grid_position = pos
	var bid := _tm.register_unit(inst)
	_gb.place_unit(bid, pos)
	return bid

# ── Rule 2：attack_executed 充能 ──

# 相邻友方存在 → +CHARGE_ADJACENT(2)
func test_ally_attack_executed_charges_two_when_adjacent() -> void:
	var a := _add("swordsman", "crew", Vector2i(1, 1))
	_add("bulwark", "crew", Vector2i(1, 0))          # 相邻友方
	var e := _add("x", "enemy", Vector2i(1, 2))
	EventBus.attack_executed.emit(a, e, 3)
	assert_int(_bg.get_gauge_value()).is_equal(2)

# 无相邻友方 → +CHARGE_SOLO(1)
func test_ally_attack_executed_charges_one_when_solo() -> void:
	var a := _add("swordsman", "crew", Vector2i(1, 1))
	var e := _add("x", "enemy", Vector2i(1, 2))
	EventBus.attack_executed.emit(a, e, 3)
	assert_int(_bg.get_gauge_value()).is_equal(1)

# AC-10：敌方攻击不充能己方槽（阵营过滤）
func test_enemy_attack_executed_does_not_charge() -> void:
	var e := _add("x", "enemy", Vector2i(1, 1))
	var a := _add("swordsman", "crew", Vector2i(1, 2))
	EventBus.attack_executed.emit(e, a, 3)
	assert_int(_bg.get_gauge_value()).is_equal(0)

# 斩命中多目标：每次 attack_executed 各充能一次（AC-3）
func test_slash_multiple_attack_executed_charges_each() -> void:
	var a := _add("swordsman", "crew", Vector2i(1, 1))
	_add("bulwark", "crew", Vector2i(1, 0))          # 相邻友方 → 每次 +2
	var e1 := _add("x", "enemy", Vector2i(1, 2))
	var e2 := _add("y", "enemy", Vector2i(0, 1))
	EventBus.attack_executed.emit(a, e1, 3)
	EventBus.attack_executed.emit(a, e2, 3)
	assert_int(_bg.get_gauge_value()).is_equal(4)    # 2 + 2

# ── Rule 3：cannon_executed 充能（每次一次，第一参 String）──

func test_cannon_executed_charges_once_when_adjacent() -> void:
	var g := _add("gunner", "crew", Vector2i(1, 1))
	_add("bulwark", "crew", Vector2i(1, 0))          # 相邻友方
	var e1 := _add("x", "enemy", Vector2i(1, 3))
	var e2 := _add("y", "enemy", Vector2i(1, 4))
	EventBus.cannon_executed.emit(str(g), 1, [e1, e2], 2)
	assert_int(_bg.get_gauge_value()).is_equal(2)    # +2 一次，非 +4

# ── Rule 4：damage_dealt 受击充能 ──

# AC-6：己方受击 +CHARGE_HIT(1)
func test_received_damage_charges_ally() -> void:
	var a := _add("swordsman", "crew", Vector2i(1, 1))
	EventBus.damage_dealt.emit(a, 3, 7)
	assert_int(_bg.get_gauge_value()).is_equal(1)

# AC-7：每回合受击充能上限 RECEIVED_CHARGE_CAP(2)
func test_received_damage_capped_per_round() -> void:
	var a := _add("swordsman", "crew", Vector2i(1, 1))
	for i in 3:
		EventBus.damage_dealt.emit(a, 3, 7)
	assert_int(_bg.get_gauge_value()).is_equal(2)

# 敌方受击不充能己方槽
func test_enemy_received_damage_does_not_charge() -> void:
	var e := _add("x", "enemy", Vector2i(1, 1))
	EventBus.damage_dealt.emit(e, 3, 7)
	assert_int(_bg.get_gauge_value()).is_equal(0)

# AC-8：round_ended 重置受击计数（槽保留）
func test_round_ended_resets_received_cap() -> void:
	var a := _add("swordsman", "crew", Vector2i(1, 1))
	for i in 3:
		EventBus.damage_dealt.emit(a, 3, 7)          # 本回合到上限 2
	EventBus.round_ended.emit()
	EventBus.damage_dealt.emit(a, 3, 7)              # 新回合再充
	assert_int(_bg.get_gauge_value()).is_equal(3)    # 2 + 1（槽跨回合保留）

# ── EC-8：爆发斩自身伤害不重新充能（爆发清零后不"即刻又半满"）──

func test_burst_slash_does_not_recharge_gauge() -> void:
	var lead := _add("swordsman", "crew", Vector2i(1, 1), 3)
	var partner := _add("bulwark", "crew", Vector2i(1, 0))
	_add("x", "enemy", Vector2i(1, 2), 3, 10)        # 剑豪相邻敌方（爆发斩命中）
	for i in 5:
		_bg.apply_attack_charge(0, true)             # 充满到 10
	_bg.activate_burst(lead, partner)
	assert_int(_bg.get_gauge_value()).is_equal(0)    # 清零后不被爆发斩重新充能

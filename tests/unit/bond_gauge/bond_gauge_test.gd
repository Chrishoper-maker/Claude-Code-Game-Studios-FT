# BondGaugeBurst 羁绊槽核心测试（bond-gauge-burst GDD Rule 1-4）。
# 纯逻辑：相邻与否由调用方传入 bool（GridBoard 计算），不依赖 UnitInstance。
# 爆发激活(Rule 5-6)需 UnitInstance，留 TODO，不在此测。
# TDD：先于实现写就。
extends GdUnitTestSuite

func _bg() -> BondGaugeBurst:
	return auto_free(BondGaugeBurst.new())

func test_starts_empty_and_not_full() -> void:
	var bg := _bg()
	assert_int(bg.get_gauge_value()).is_equal(0)
	assert_bool(bg.is_full()).is_false()

# Rule 2：相邻 +CHARGE_ADJACENT(2) / 单独 +CHARGE_SOLO(1)
func test_attack_charge_adjacent_adds_two() -> void:
	var bg := _bg()
	bg.apply_attack_charge(1, true)
	assert_int(bg.get_gauge_value()).is_equal(2)

func test_attack_charge_solo_adds_one() -> void:
	var bg := _bg()
	bg.apply_attack_charge(1, false)
	assert_int(bg.get_gauge_value()).is_equal(1)

# Rule 3：轰击充能同攻击（每次一次，相邻 +2）
func test_cannon_charge_adjacent_adds_two() -> void:
	var bg := _bg()
	bg.apply_cannon_charge(1, true)
	assert_int(bg.get_gauge_value()).is_equal(2)

# Rule 1/2：钳制到 MAX，无溢出
func test_charge_clamps_at_max() -> void:
	var bg := _bg()
	for i in 6:
		bg.apply_attack_charge(1, true)   # 6×2 = 12 → 钳到 10
	assert_int(bg.get_gauge_value()).is_equal(10)
	assert_bool(bg.is_full()).is_true()

# Rule 4：受击 +CHARGE_HIT(1)，每回合上限 RECEIVED_CHARGE_CAP(2)
func test_received_charge_capped_per_round() -> void:
	var bg := _bg()
	bg.apply_received_charge(9)
	bg.apply_received_charge(9)
	bg.apply_received_charge(9)   # 第 3 次本回合：被上限拦截
	assert_int(bg.get_gauge_value()).is_equal(2)

# Rule 4：ROUND_END 重置受击计数（但不重置槽）
func test_round_end_resets_received_counter_not_gauge() -> void:
	var bg := _bg()
	bg.apply_received_charge(9)
	bg.apply_received_charge(9)   # 到上限
	bg.on_round_end()
	assert_int(bg.get_gauge_value()).is_equal(2)   # 槽保留
	bg.apply_received_charge(9)                     # 新回合可再充
	assert_int(bg.get_gauge_value()).is_equal(3)

# 爆发后 reset：槽归零
func test_reset_gauge_zeroes() -> void:
	var bg := _bg()
	bg.apply_attack_charge(1, true)
	bg.reset_gauge()
	assert_int(bg.get_gauge_value()).is_equal(0)

# Rule 2 步骤 7：bond_gauge_full 仅在跨越到满时发一次
func test_bond_gauge_full_emitted_once_on_crossing() -> void:
	var bg := _bg()
	var count := [0]
	var cb := func() -> void: count[0] += 1
	EventBus.bond_gauge_full.connect(cb)
	for i in 5:
		bg.apply_attack_charge(1, true)   # 5×2 = 10，第 5 次跨越到满
	bg.apply_attack_charge(1, true)       # 已满再充：不再发
	EventBus.bond_gauge_full.disconnect(cb)
	assert_int(count[0]).is_equal(1)

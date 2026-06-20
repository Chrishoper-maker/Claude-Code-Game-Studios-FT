# BattleResolution 爆发增强斩测试（bond-gauge-burst GDD Rule 7 破阵先锋②）。
# execute_burst_slash：相邻敌方 AoE，伤害 = base × multiplier，穿透 GUARDED，
# 不消耗动词（动作点由 BondGaugeBurst 编排层经羁绊槽消耗）。
# TDD：先于实现写就。
extends GdUnitTestSuite

var _br: BattleResolution
var _gb: GridBoard
var _tm: TurnManager
var _uid_counter: int

func before_test() -> void:
	_gb = auto_free(GridBoard.new())
	_tm = auto_free(TurnManager.new())
	_br = auto_free(BattleResolution.new())
	_br.setup(_gb, _tm)
	_uid_counter = 0

func _add(faction: String, pos: Vector2i, base_damage: int = 3, max_hp: int = 10, unit_class: String = "swordsman", attack_range: int = 1) -> int:
	_uid_counter += 1
	var d := UnitDefinition.new()
	d.id = "u%d" % _uid_counter
	d.faction = faction
	d.unit_class = unit_class
	d.base_damage = base_damage
	d.attack_range = attack_range
	d.max_hp = max_hp
	d.class_action_id = "v"
	var inst := UnitInstance.from_definition(d)
	inst.grid_position = pos
	var bid := _tm.register_unit(inst)
	_gb.place_unit(bid, pos)
	return bid

# Rule 7 破阵先锋②：相邻敌方各受 base × multiplier，友方不受
func test_burst_slash_hits_adjacent_enemies_with_multiplied_damage() -> void:
	var a := _add("crew", Vector2i(1, 1), 3)        # base 3
	var e1 := _add("enemy", Vector2i(1, 2), 3, 10)
	var e2 := _add("enemy", Vector2i(2, 1), 3, 10)
	var ally := _add("crew", Vector2i(0, 1), 3, 10)
	_br.execute_burst_slash(a, 2)                   # 3 × 2 = 6
	assert_int(_tm.get_unit(e1).current_hp).is_equal(4)
	assert_int(_tm.get_unit(e2).current_hp).is_equal(4)
	assert_int(_tm.get_unit(ally).current_hp).is_equal(10)   # 友方不受

# Rule 7 破阵先锋② + EC-9：穿透目标 GUARDED（不减半）
func test_burst_slash_pierces_target_guarded() -> void:
	var a := _add("crew", Vector2i(1, 1), 3)
	var e := _add("enemy", Vector2i(1, 2), 3, 10)
	_br.apply_status(e, BattleResolution.STATUS_GUARDED)
	_br.execute_burst_slash(a, 2)                   # 穿透：6 全额，非 3
	assert_int(_tm.get_unit(e).current_hp).is_equal(4)

# 不消耗施放者职业动词（动作点归编排层经羁绊槽消耗）
func test_burst_slash_does_not_consume_attacker_verb() -> void:
	var a := _add("crew", Vector2i(1, 1), 3)
	_add("enemy", Vector2i(1, 2), 3, 10)
	_br.execute_burst_slash(a, 2)
	assert_bool(_tm.get_unit(a).has_used_verb).is_false()

# 伤害致死触发 Downed 解算
func test_burst_slash_downs_target_at_zero_hp() -> void:
	var a := _add("crew", Vector2i(1, 1), 3)
	var e := _add("enemy", Vector2i(1, 2), 3, 6)    # 6 hp，受 6 伤 → 0
	_br.execute_burst_slash(a, 2)
	assert_bool(_tm.get_unit(e).is_alive).is_false()

# EC-2：施放者已 Downed 则跳过（无相邻敌方受伤）
func test_burst_slash_skips_when_attacker_downed() -> void:
	var a := _add("crew", Vector2i(1, 1), 3)
	var e := _add("enemy", Vector2i(1, 2), 3, 10)
	_tm.get_unit(a).is_alive = false
	_br.execute_burst_slash(a, 2)
	assert_int(_tm.get_unit(e).current_hp).is_equal(10)   # 未受伤

# ── 爆发推移（瞄准定位① execute_burst_displace）──

# 沿 caster→target 方向推 target ≤PUSH_DISTANCE，移动成功返 true
func test_burst_displace_pushes_target_and_returns_true() -> void:
	var nav := _add("crew", Vector2i(0, 0), 3, 10, "navigator")
	var e := _add("enemy", Vector2i(1, 0), 3, 10)        # caster→target = +x
	var moved := _br.execute_burst_displace(nav, e)
	assert_bool(moved).is_true()
	assert_vector(_tm.get_unit(e).grid_position).is_equal(Vector2i(3, 0))   # 推 2 格

# 无合法落点（边界）→ 返 false，目标不动（EC-6）
func test_burst_displace_blocked_returns_false() -> void:
	var nav := _add("crew", Vector2i(6, 0), 3, 10, "navigator")
	var e := _add("enemy", Vector2i(7, 0), 3, 10)        # +x 即出界
	var moved := _br.execute_burst_displace(nav, e)
	assert_bool(moved).is_false()
	assert_vector(_tm.get_unit(e).grid_position).is_equal(Vector2i(7, 0))

# 不消耗施放者动词
func test_burst_displace_does_not_consume_verb() -> void:
	var nav := _add("crew", Vector2i(0, 0), 3, 10, "navigator")
	var e := _add("enemy", Vector2i(1, 0), 3, 10)
	_br.execute_burst_displace(nav, e)
	assert_bool(_tm.get_unit(nav).has_used_verb).is_false()

# ── 爆发穿透炮（瞄准定位② execute_burst_cannon）──

# 朝 attacker→target 方向穿透直线，伤害 = base × multiplier
func test_burst_cannon_hits_line_with_multiplied_damage() -> void:
	var g := _add("crew", Vector2i(0, 0), 2, 10, "gunner", 4)   # base 2, range 4
	var e := _add("enemy", Vector2i(3, 0), 3, 10)               # 同行，attacker→target = +x
	_br.execute_burst_cannon(g, e, 2)                           # 2 × 2 = 4
	assert_int(_tm.get_unit(e).current_hp).is_equal(6)

# 穿透命中弹道上多名敌方（EC-7）
func test_burst_cannon_pierces_multiple_targets() -> void:
	var g := _add("crew", Vector2i(0, 0), 2, 10, "gunner", 4)
	var e1 := _add("enemy", Vector2i(2, 0), 3, 10)
	var e2 := _add("enemy", Vector2i(3, 0), 3, 10)
	_br.execute_burst_cannon(g, e2, 2)
	assert_int(_tm.get_unit(e1).current_hp).is_equal(6)
	assert_int(_tm.get_unit(e2).current_hp).is_equal(6)

# 不消耗动词
func test_burst_cannon_does_not_consume_verb() -> void:
	var g := _add("crew", Vector2i(0, 0), 2, 10, "gunner", 4)
	var e := _add("enemy", Vector2i(3, 0), 3, 10)
	_br.execute_burst_cannon(g, e, 2)
	assert_bool(_tm.get_unit(g).has_used_verb).is_false()

# 不发 cannon_executed（否则触发羁绊充能→爆发即刻又充能）
func test_burst_cannon_does_not_emit_cannon_executed() -> void:
	var g := _add("crew", Vector2i(0, 0), 2, 10, "gunner", 4)
	var e := _add("enemy", Vector2i(3, 0), 3, 10)
	var count := [0]
	var cb := func(_a: String, _d: int, _h: Array, _b: int) -> void: count[0] += 1
	EventBus.cannon_executed.connect(cb)
	_br.execute_burst_cannon(g, e, 2)
	EventBus.cannon_executed.disconnect(cb)
	assert_int(count[0]).is_equal(0)

# ── 爆发治疗 execute_burst_heal（护持突破②/钢铁壁垒②）──

func test_burst_heal_heals_target_by_amount() -> void:
	var u := _add("crew", Vector2i(0, 0), 3, 10)
	_tm.get_unit(u).current_hp = 4
	_br.execute_burst_heal(u, 6)
	assert_int(_tm.get_unit(u).current_hp).is_equal(10)

func test_burst_heal_clamps_to_max_hp() -> void:
	var u := _add("crew", Vector2i(0, 0), 3, 10)
	_tm.get_unit(u).current_hp = 8
	_br.execute_burst_heal(u, 6)
	assert_int(_tm.get_unit(u).current_hp).is_equal(10)

func test_burst_heal_does_not_consume_verb() -> void:
	var u := _add("crew", Vector2i(0, 0), 3, 10)
	_br.execute_burst_heal(u, 3)
	assert_bool(_tm.get_unit(u).has_used_verb).is_false()

# ── 爆发定向穿透炮 execute_burst_cannon_dir（轰鸣序曲②：4 基本方向）──

func test_burst_cannon_dir_fires_in_given_direction() -> void:
	var g := _add("crew", Vector2i(0, 0), 2, 10, "gunner", 4)
	var e := _add("enemy", Vector2i(0, 3), 3, 10)            # 同列下方
	_br.execute_burst_cannon_dir(g, Vector2i(0, 1), 2)        # 向下发射，2×2=4
	assert_int(_tm.get_unit(e).current_hp).is_equal(6)

# ── 爆发斩吃 AURA_BONUS（热血演奏②：剑豪持 AURA 追加 AURA_VALUE，EC-12）──

func test_burst_slash_consume_aura_adds_aura_value() -> void:
	var a := _add("crew", Vector2i(1, 1), 3)
	var e := _add("enemy", Vector2i(1, 2), 3, 10)
	_br.apply_status(a, BattleResolution.STATUS_AURA)
	_br.execute_burst_slash(a, 2, true)                       # 3×2 + AURA_VALUE(1) = 7
	assert_int(_tm.get_unit(e).current_hp).is_equal(3)
	assert_bool(_br.get_unit_status(a, BattleResolution.STATUS_AURA)).is_false()   # 已消耗

func test_burst_slash_ignores_aura_when_flag_off() -> void:
	var a := _add("crew", Vector2i(1, 1), 3)
	var e := _add("enemy", Vector2i(1, 2), 3, 10)
	_br.apply_status(a, BattleResolution.STATUS_AURA)
	_br.execute_burst_slash(a, 2)                             # 不消耗 aura：仅 3×2 = 6
	assert_int(_tm.get_unit(e).current_hp).is_equal(4)
	assert_bool(_br.get_unit_status(a, BattleResolution.STATUS_AURA)).is_true()    # 未消耗

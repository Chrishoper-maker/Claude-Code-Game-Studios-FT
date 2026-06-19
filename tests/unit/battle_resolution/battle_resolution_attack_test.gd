# BattleResolution 普通攻击核心测试（battle-resolution GDD Rule 1/9/10/11 + ADR-0005 D2/D4-D7）。
# DI 注入真实 GridBoard + TurnManager。伤害管线/状态/Downed 7步。
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

func _add(faction: String, pos: Vector2i, base_damage: int = 3, attack_range: int = 1, max_hp: int = 6, unit_class: String = "swordsman") -> int:
	_uid_counter += 1
	var d := UnitDefinition.new()
	d.id = "u%d" % _uid_counter
	d.faction = faction
	d.unit_class = unit_class
	d.base_damage = base_damage
	d.attack_range = attack_range
	d.max_hp = max_hp
	var inst := UnitInstance.from_definition(d)
	inst.grid_position = pos
	var bid := _tm.register_unit(inst)
	_gb.place_unit(bid, pos)
	return bid

# ── Rule 1 触发条件 / Rule 11 炮手 ──

func test_valid_attack_adjacent_enemy() -> void:
	var a := _add("crew", Vector2i(0, 0))
	var t := _add("enemy", Vector2i(0, 1))
	assert_bool(_br.is_valid_attack(a, t)).is_true()

func test_invalid_attack_same_faction() -> void:
	var a := _add("crew", Vector2i(0, 0))
	var t := _add("crew", Vector2i(0, 1))
	assert_bool(_br.is_valid_attack(a, t)).is_false()

func test_invalid_attack_out_of_range() -> void:
	var a := _add("crew", Vector2i(0, 0))           # 近战 range 1
	var t := _add("enemy", Vector2i(0, 3))          # 切比雪夫 3
	assert_bool(_br.is_valid_attack(a, t)).is_false()

func test_invalid_attack_when_has_acted() -> void:
	var a := _add("crew", Vector2i(0, 0))
	var t := _add("enemy", Vector2i(0, 1))
	_tm.get_unit(a).has_acted = true
	assert_bool(_br.is_valid_attack(a, t)).is_false()

func test_invalid_gunner_attack_adjacent() -> void:
	var a := _add("crew", Vector2i(0, 0), 3, 3, 6, "gunner")
	var t := _add("enemy", Vector2i(0, 1))          # manhattan 1 < GUNNER_MIN_RANGE
	assert_bool(_br.is_valid_attack(a, t)).is_false()

func test_valid_gunner_attack_at_min_range() -> void:
	var a := _add("crew", Vector2i(0, 0), 3, 3, 6, "gunner")
	var t := _add("enemy", Vector2i(0, 2))          # manhattan 2 == GUNNER_MIN_RANGE
	assert_bool(_br.is_valid_attack(a, t)).is_true()

# ── Rule 1 伤害管线（ADR D2）──

func test_execute_attack_deals_base_damage() -> void:
	var a := _add("crew", Vector2i(0, 0), 3)
	var t := _add("enemy", Vector2i(0, 1), 3, 1, 6)
	_br.execute_attack(a, t)
	assert_int(_tm.get_unit(t).current_hp).is_equal(3)

func test_modifier_capped_at_max() -> void:
	var a := _add("crew", Vector2i(0, 0), 3)
	var t := _add("enemy", Vector2i(0, 1), 3, 1, 10)
	_br.register_attack_modifier(a, 5)              # 截断到 MAX_MODIFIER_SUM=2
	_br.execute_attack(a, t)
	assert_int(_tm.get_unit(t).current_hp).is_equal(5)  # 10 - (3+2)

func test_aura_independent_of_modifier_cap() -> void:
	var a := _add("crew", Vector2i(0, 0), 3)
	var t := _add("enemy", Vector2i(0, 1), 3, 1, 6)
	_br.register_attack_modifier(a, 5)              # cap 2
	_br.apply_status(a, &"AURA_BONUS")              # +1 独立第三项
	_br.execute_attack(a, t)
	assert_int(_tm.get_unit(t).current_hp).is_equal(0)  # 6 - (3+2+1) = 0 一击必杀

func test_aura_consumed_after_attack() -> void:
	var a := _add("crew", Vector2i(0, 0), 3)
	var t := _add("enemy", Vector2i(0, 1), 3, 1, 10)
	_br.apply_status(a, &"AURA_BONUS")
	_br.execute_attack(a, t)
	assert_bool(_br.get_unit_status(a, &"AURA_BONUS")).is_false()

func test_pending_modifiers_cleared_after_attack() -> void:
	var a := _add("crew", Vector2i(0, 0), 3)
	var t1 := _add("enemy", Vector2i(0, 1), 3, 1, 10)
	var t2 := _add("enemy", Vector2i(1, 0), 3, 1, 10)
	_br.register_attack_modifier(a, 2)
	_br.execute_attack(a, t1)                       # 消费修正器
	_tm.get_unit(a).has_acted = false               # 复位以便二次攻击
	_br.execute_attack(a, t2)                       # 应只有 base damage
	assert_int(_tm.get_unit(t2).current_hp).is_equal(7)  # 10 - 3（无修正器残留）

func test_guarded_target_halves_damage_and_consumes() -> void:
	var a := _add("crew", Vector2i(0, 0), 4)
	var t := _add("enemy", Vector2i(0, 1), 3, 1, 10)
	_br.apply_status(t, &"GUARDED")
	_br.execute_attack(a, t)
	assert_int(_tm.get_unit(t).current_hp).is_equal(8)   # 10 - floor(4/2)=2
	assert_bool(_br.get_unit_status(t, &"GUARDED")).is_false()

func test_execute_attack_marks_has_acted() -> void:
	var a := _add("crew", Vector2i(0, 0), 3)
	var t := _add("enemy", Vector2i(0, 1), 3, 1, 10)
	_br.execute_attack(a, t)
	assert_bool(_tm.get_unit(a).has_acted).is_true()

# ── Rule 9 resolve_unit_downed 7 步 ──

func test_downed_sequence_full() -> void:
	var a := _add("crew", Vector2i(0, 0), 6)
	var t := _add("enemy", Vector2i(0, 1), 3, 1, 6)
	var downed := [0]
	var cb := func(_id: int) -> void: downed[0] += 1
	EventBus.unit_downed.connect(cb)
	_br.execute_attack(a, t)
	EventBus.unit_downed.disconnect(cb)
	var ti := _tm.get_unit(t)
	assert_bool(ti.is_alive).is_false()
	assert_vector(ti.grid_position).is_equal(Vector2i(-1, -1))
	assert_int(_gb.get_cell(Vector2i(0, 1))).is_equal(GridBoard.EMPTY)
	assert_array(_tm.get_alive_enemies()).not_contains([t])
	assert_int(downed[0]).is_equal(1)

# ── 信号 ──

func test_attack_and_damage_signals_emitted() -> void:
	var a := _add("crew", Vector2i(0, 0), 3)
	var t := _add("enemy", Vector2i(0, 1), 3, 1, 10)
	var atk := [0]
	var dmg := [0]
	var cb_a := func(_aid: int, _tid: int, _d: int) -> void: atk[0] += 1
	var cb_d := func(_tid: int, _d: int, _hp: int) -> void: dmg[0] += 1
	EventBus.attack_executed.connect(cb_a)
	EventBus.damage_dealt.connect(cb_d)
	_br.execute_attack(a, t)
	EventBus.attack_executed.disconnect(cb_a)
	EventBus.damage_dealt.disconnect(cb_d)
	assert_int(atk[0]).is_equal(1)
	assert_int(dmg[0]).is_equal(1)

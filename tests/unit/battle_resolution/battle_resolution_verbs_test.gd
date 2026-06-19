# BattleResolution 六动词测试（battle-resolution GDD Rule 3-8 / ADR-0005 D3）。
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

func _add(faction: String, pos: Vector2i, base_damage: int = 3, attack_range: int = 1, max_hp: int = 10, unit_class: String = "swordsman", verb: String = "v") -> int:
	_uid_counter += 1
	var d := UnitDefinition.new()
	d.id = "u%d" % _uid_counter
	d.faction = faction
	d.unit_class = unit_class
	d.base_damage = base_damage
	d.attack_range = attack_range
	d.max_hp = max_hp
	d.class_action_id = verb
	var inst := UnitInstance.from_definition(d)
	inst.grid_position = pos
	var bid := _tm.register_unit(inst)
	_gb.place_unit(bid, pos)
	return bid

# ── Rule 3 斩 ──

func test_slash_hits_all_adjacent_enemies_not_allies() -> void:
	var a := _add("crew", Vector2i(1, 1), 4)
	var e1 := _add("enemy", Vector2i(1, 2))
	var e2 := _add("enemy", Vector2i(2, 1))
	var ally := _add("crew", Vector2i(0, 1))
	_br.execute_slash(a)
	assert_int(_tm.get_unit(e1).current_hp).is_equal(6)
	assert_int(_tm.get_unit(e2).current_hp).is_equal(6)
	assert_int(_tm.get_unit(ally).current_hp).is_equal(10)

func test_slash_uses_modifier_and_aura() -> void:
	var a := _add("crew", Vector2i(1, 1), 3)
	var e := _add("enemy", Vector2i(1, 2))
	_br.register_attack_modifier(a, 2)
	_br.apply_status(a, &"AURA_BONUS")
	_br.execute_slash(a)
	assert_int(_tm.get_unit(e).current_hp).is_equal(4)  # 10 - (3+2+1)

func test_slash_consumes_aura_and_marks_verb() -> void:
	var a := _add("crew", Vector2i(1, 1), 3)
	_add("enemy", Vector2i(1, 2))
	_br.apply_status(a, &"AURA_BONUS")
	_br.execute_slash(a)
	assert_bool(_br.get_unit_status(a, &"AURA_BONUS")).is_false()
	assert_bool(_tm.get_unit(a).has_used_verb).is_true()

func test_slash_no_adjacent_enemy_still_marks_verb() -> void:
	var a := _add("crew", Vector2i(1, 1), 3)
	_br.execute_slash(a)
	assert_bool(_tm.get_unit(a).has_used_verb).is_true()

# ── Rule 4 轰 ──

func test_cannon_hits_all_on_line_both_factions() -> void:
	var a := _add("crew", Vector2i(0, 0), 3, 3)
	var e := _add("enemy", Vector2i(0, 1))
	var ally := _add("crew", Vector2i(0, 2))
	_br.execute_cannon(a, Vector2i(0, 1))
	assert_int(_tm.get_unit(e).current_hp).is_equal(7)
	assert_int(_tm.get_unit(ally).current_hp).is_equal(7)  # 友伤：不分阵营

func test_cannon_ignores_modifier_and_aura() -> void:
	var a := _add("crew", Vector2i(0, 0), 3, 3)
	var e := _add("enemy", Vector2i(0, 2))
	_br.register_attack_modifier(a, 2)
	_br.apply_status(a, &"AURA_BONUS")
	_br.execute_cannon(a, Vector2i(0, 1))
	assert_int(_tm.get_unit(e).current_hp).is_equal(7)  # 仅 base 3

func test_cannon_marks_verb() -> void:
	var a := _add("crew", Vector2i(0, 0), 3, 3)
	_br.execute_cannon(a, Vector2i(0, 1))
	assert_bool(_tm.get_unit(a).has_used_verb).is_true()

# ── Rule 5 挡 ──

func test_guard_applies_guarded_to_ally() -> void:
	var caster := _add("crew", Vector2i(1, 1))
	var ally := _add("crew", Vector2i(1, 2))
	_br.execute_guard(caster, ally)
	assert_bool(_br.get_unit_status(ally, &"GUARDED")).is_true()
	assert_bool(_tm.get_unit(caster).has_used_verb).is_true()

# ── Rule 6 愈 ──

func test_heal_restores_hp() -> void:
	var caster := _add("crew", Vector2i(1, 1))
	var ally := _add("crew", Vector2i(1, 2), 3, 1, 10)
	_tm.get_unit(ally).current_hp = 2
	_br.execute_heal(caster, ally)
	assert_int(_tm.get_unit(ally).current_hp).is_equal(5)

func test_heal_caps_at_max_hp() -> void:
	var caster := _add("crew", Vector2i(1, 1))
	var ally := _add("crew", Vector2i(1, 2), 3, 1, 6)
	_tm.get_unit(ally).current_hp = 5
	_br.execute_heal(caster, ally)
	assert_int(_tm.get_unit(ally).current_hp).is_equal(6)  # 不溢出

# ── Rule 7 移 ──

func test_displace_pushes_target_full_distance() -> void:
	var caster := _add("crew", Vector2i(3, 2))
	var target := _add("enemy", Vector2i(3, 3))
	_br.execute_displace(caster, target, Vector2i(1, 0))
	assert_vector(_tm.get_unit(target).grid_position).is_equal(Vector2i(5, 3))
	assert_int(_gb.get_cell(Vector2i(5, 3))).is_equal(target)
	assert_int(_gb.get_cell(Vector2i(3, 3))).is_equal(GridBoard.EMPTY)

func test_displace_stops_at_occupied_cell() -> void:
	var caster := _add("crew", Vector2i(3, 2))
	var target := _add("enemy", Vector2i(3, 3))
	_add("enemy", Vector2i(5, 3))  # 阻挡
	_br.execute_displace(caster, target, Vector2i(1, 0))
	assert_vector(_tm.get_unit(target).grid_position).is_equal(Vector2i(4, 3))  # 仅移1格

# ── Rule 8 奏 ──

func test_aura_buffs_adjacent_allies_not_self() -> void:
	var caster := _add("crew", Vector2i(1, 1))
	var ally := _add("crew", Vector2i(1, 2))
	var far := _add("crew", Vector2i(5, 5))
	_br.execute_aura(caster)
	assert_bool(_br.get_unit_status(ally, &"AURA_BONUS")).is_true()
	assert_bool(_br.get_unit_status(caster, &"AURA_BONUS")).is_false()
	assert_bool(_br.get_unit_status(far, &"AURA_BONUS")).is_false()

func test_aura_marks_verb() -> void:
	var caster := _add("crew", Vector2i(1, 1))
	_add("crew", Vector2i(1, 2))
	_br.execute_aura(caster)
	assert_bool(_tm.get_unit(caster).has_used_verb).is_true()

# ── execute_verb 分发 ──

func test_execute_verb_dispatches_slash() -> void:
	var a := _add("crew", Vector2i(1, 1), 4)
	var e := _add("enemy", Vector2i(1, 2))
	_br.execute_verb(a, BattleResolution.VerbType.SLASH, -1)
	assert_int(_tm.get_unit(e).current_hp).is_equal(6)

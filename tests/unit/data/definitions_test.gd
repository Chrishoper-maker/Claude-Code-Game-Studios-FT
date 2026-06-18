# Foundation 数据类单元测试（ADR-0003 继承层级与字段）。
# ✅ 实测通过（GdUnit4 v6.1.3 / Godot 4.6.3，2026-06-19）：4/4 PASSED。
extends GdUnitTestSuite

func test_crew_definition_is_a_unit_definition() -> void:
	var c := CrewDefinition.new()
	c.id = "crew_test"
	c.battle_cry = "为了伙伴！"
	assert_bool(c is UnitDefinition).is_true()
	assert_str(c.id).is_equal("crew_test")
	assert_str(c.battle_cry).is_equal("为了伙伴！")

func test_enemy_definition_is_a_unit_definition() -> void:
	var e := EnemyDefinition.new()
	e.behavior_type = "MELEE"
	assert_bool(e is UnitDefinition).is_true()
	assert_str(e.behavior_type).is_equal("MELEE")

func test_map_definition_holds_typed_subresources() -> void:
	var m := MapDefinition.new()
	var slot := EnemySlotDefinition.new()
	slot.unit_definition_id = "enemy_melee_t1"
	m.enemy_roster = [slot]
	assert_int(m.enemy_roster.size()).is_equal(1)
	assert_str(m.enemy_roster[0].unit_definition_id).is_equal("enemy_melee_t1")

func test_intent_record_defaults_to_wait() -> void:
	var ir := IntentRecord.new()
	assert_int(ir.intent_type).is_equal(IntentRecord.IntentType.INTENT_WAIT)
	assert_int(ir.target_id).is_equal(-1)

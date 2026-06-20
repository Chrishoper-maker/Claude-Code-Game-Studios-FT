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

# crew .tres 加载校验（白盒船员数据文件结构/字段正确）。
func test_crew_tres_files_load_as_crew_definitions() -> void:
	var ids := ["crew_swordsman_01", "crew_bulwark_01", "crew_swordsman_02", "crew_gunner_01"]
	for id in ids:
		var res := ResourceLoader.load("res://assets/data/units/%s.tres" % id)
		assert_object(res).is_not_null()
		assert_bool(res is CrewDefinition).is_true()
		assert_str(res.faction).is_equal("crew")
		assert_str(res.id).is_equal(id)
		assert_bool(res.class_action_id != "").is_true()   # crew 有职业动词

# 破阵先锋（MVP 爆发）所需的剑豪+铁壁起始配对存在于起始编制。
func test_starting_crew_includes_vanguard_breach_pair() -> void:
	var sword := ResourceLoader.load("res://assets/data/units/crew_swordsman_01.tres")
	var bulwark := ResourceLoader.load("res://assets/data/units/crew_bulwark_01.tres")
	assert_str(sword.unit_class).is_equal("swordsman")
	assert_str(sword.recruit_pool_tier).is_equal("starting")
	assert_str(bulwark.unit_class).is_equal("bulwark")
	assert_str(bulwark.recruit_pool_tier).is_equal("starting")

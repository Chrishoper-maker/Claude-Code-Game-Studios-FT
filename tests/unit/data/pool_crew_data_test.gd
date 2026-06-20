# 新增 pool crew .tres 结构校验：类型/tier/字段齐 + 职业覆盖（route-recruitment 招募池）。
extends GdUnitTestSuite

const POOL_PATHS := [
	"res://assets/data/units/crew_medic_01.tres",
	"res://assets/data/units/crew_navigator_01.tres",
	"res://assets/data/units/crew_musician_01.tres",
	"res://assets/data/units/crew_bulwark_02.tres",
	"res://assets/data/units/crew_swordsman_03.tres",
	"res://assets/data/units/crew_gunner_02.tres",
]

func test_each_pool_crew_loads_as_pool_tier_crew_definition() -> void:
	for path in POOL_PATHS:
		var res := ResourceLoader.load(path)
		assert_object(res).is_not_null()
		assert_bool(res is CrewDefinition).is_true()
		var crew := res as CrewDefinition
		assert_str(crew.recruit_pool_tier).is_equal("pool")
		assert_str(crew.id).is_not_empty()
		assert_str(crew.faction).is_equal("crew")
		assert_str(crew.class_action_id).is_not_empty()
		assert_int(crew.max_hp).is_greater(0)

func test_pool_crew_cover_recruit_classes() -> void:
	var classes: Dictionary = {}
	for path in POOL_PATHS:
		classes[(ResourceLoader.load(path) as CrewDefinition).unit_class] = true
	for required in ["medic", "navigator", "musician", "bulwark"]:
		assert_bool(classes.has(required)).is_true()

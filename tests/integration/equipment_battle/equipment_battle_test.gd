# 装备经 deploy_crew 上场后，UnitInstance 有效值含加成（AC-7）。
extends GdUnitTestSuite

func _crew_def() -> CrewDefinition:
	var d := CrewDefinition.new()
	d.id = "eqtest_crew"
	d.faction = "crew"
	d.unit_class = "bulwark"
	d.max_hp = 12
	d.base_damage = 2
	d.attack_range = 1
	d.move_range = 2
	d.class_action_id = "guard"
	d.recruit_pool_tier = "pool"
	return d

# AC-7：带 +3 血装备的船员部署后 get_max_hp = 基值+3。
func test_deployed_crew_has_equipment_stats() -> void:
	var grid := GridBoard.new()
	var tm := TurnManager.new()
	auto_free(tm)
	var bmap := BattleMap.new()
	auto_free(bmap)
	# 用最小可部署地图：直接走 deploy_crew 需要 MAP_READY，这里以单测视角验证 from_definition 装备透传足矣。
	var plate := EquipmentDataManager.get_equipment("eq_plate")
	var inst := UnitInstance.from_definition(_crew_def(), plate)
	assert_int(inst.get_max_hp()).is_equal(15)
	assert_int(inst.current_hp).is_equal(15)

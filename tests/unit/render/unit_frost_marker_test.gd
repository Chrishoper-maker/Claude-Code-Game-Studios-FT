# 寒霜标记：set_frost_marker 着色为冰蓝（≠基色）；clear_frost_marker 复原。
# flash_hit 在寒霜态下回到寒霜色而非基色（albedo 通道优先级 frost>dimmed>base）。
extends GdUnitTestSuite

func _view() -> UnitView:
	var v: UnitView = auto_free(UnitView.new())
	add_child(v)
	v.setup("swordsman", "crew", 1, Vector2i(0, 0))
	return v

func _albedo(v: UnitView) -> Color:
	return (v._mesh.material_override as StandardMaterial3D).albedo_color

func test_set_frost_marker_tints_then_clear_restores() -> void:
	var v := _view()
	var base := _albedo(v)
	v.set_frost_marker(BattleResolution.STATUS_FROST_FREEZE)
	assert_object(_albedo(v)).is_not_equal(base)              # 着色改变
	v.clear_frost_marker()
	assert_object(_albedo(v)).is_equal(base)                  # 复原

func test_flash_hit_returns_to_frost_color_when_frosted() -> void:
	var v := _view()
	v.set_frost_marker(BattleResolution.STATUS_FROST_FREEZE)
	var frost_color := _albedo(v)
	v.flash_hit()                                            # 瞬时置白，tween 回正色
	await get_tree().create_timer(0.2).timeout
	assert_object(_albedo(v)).is_equal(frost_color)          # 回到寒霜色（非基色）

func test_frost_label_has_three_tiers() -> void:
	assert_str(UnitView.FROST_LABEL[BattleResolution.STATUS_FROST_SLOW]).is_equal("滞步")
	assert_str(UnitView.FROST_LABEL[BattleResolution.STATUS_FROST_ROOT]).is_equal("冰封")
	assert_str(UnitView.FROST_LABEL[BattleResolution.STATUS_FROST_FREEZE]).is_equal("冻结")

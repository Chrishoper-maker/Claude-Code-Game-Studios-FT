# 变灰（end-unit-turn 视觉）：UnitView.set_dimmed 压暗 albedo；
# UnitRenderer 经 unit_turn_ended 变灰、player_phase_started 解除。
extends GdUnitTestSuite

func _view() -> UnitView:
	var v: UnitView = auto_free(UnitView.new())
	add_child(v)
	v.setup("swordsman", "crew", 1, Vector2i(0, 0))
	return v

func _albedo(v: UnitView) -> Color:
	return (v._mesh.material_override as StandardMaterial3D).albedo_color

func test_set_dimmed_darkens_then_restores() -> void:
	var v := _view()
	var base := _albedo(v)
	v.set_dimmed(true)
	assert_bool(_albedo(v).v < base.v).is_true()   # 明度下降
	v.set_dimmed(false)
	assert_object(_albedo(v)).is_equal(base)        # 复原

func test_renderer_dims_on_unit_turn_ended_and_restores_on_phase() -> void:
	var r: UnitRenderer = auto_free(UnitRenderer.new())
	add_child(r)
	var v := r.spawn_view("swordsman", "crew", 7, Vector2i(0, 0))
	var base := _albedo(v)
	EventBus.unit_turn_ended.emit(7)
	assert_bool(_albedo(v).v < base.v).is_true()
	EventBus.player_phase_started.emit()
	assert_object(_albedo(v)).is_equal(base)

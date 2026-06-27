# 寒霜飘字文案助手 + 订阅 frost_applied/frost_resolved 不崩（无相机优雅跳过）。
extends GdUnitTestSuite

func _floater() -> DamageFloater:
	var f: DamageFloater = auto_free(DamageFloater.new())
	var r: UnitRenderer = auto_free(UnitRenderer.new())
	add_child(r); add_child(f)
	f.setup(r, func(_id: int) -> String: return "enemy")
	return f

func test_frost_text_maps_three_tiers() -> void:
	assert_str(DamageFloater.frost_text(BattleResolution.STATUS_FROST_SLOW)).is_equal("滞步!")
	assert_str(DamageFloater.frost_text(BattleResolution.STATUS_FROST_ROOT)).is_equal("冰封!")
	assert_str(DamageFloater.frost_text(BattleResolution.STATUS_FROST_FREEZE)).is_equal("冻结!")

func test_frost_signals_do_not_crash_without_camera() -> void:
	var f := _floater()
	EventBus.frost_applied.emit(1, BattleResolution.STATUS_FROST_FREEZE)     # 无相机 → 静默跳过
	EventBus.frost_resolved.emit(1, BattleResolution.STATUS_FROST_FREEZE)
	assert_object(f).is_not_null()   # 走到此处即未崩

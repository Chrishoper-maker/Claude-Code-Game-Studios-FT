extends GdUnitTestSuite

func test_damage_color_enemy_is_red() -> void:
	assert_object(DamageFloater.damage_color("enemy")).is_equal(Color("#FF2222"))

func test_damage_color_crew_is_orange() -> void:
	assert_object(DamageFloater.damage_color("crew")).is_equal(Color("#FF8800"))

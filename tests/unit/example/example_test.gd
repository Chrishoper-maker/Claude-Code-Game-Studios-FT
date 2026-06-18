# GdUnit4 示例测试 —— 模板，落地首个系统时替换/删除。
# 演示命名（test_[scenario]_[expected]）与断言流式 API。
# 运行：godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/unit/example
extends GdUnitTestSuite

# 占位被测逻辑——真实项目里改为 import 生产 src/ 下的纯函数/系统。
func _sample_damage(base: int, adjacency_bonus: int) -> int:
	return base + adjacency_bonus


func test_sample_damage_with_adjacency_adds_bonus() -> void:
	assert_int(_sample_damage(3, 1)).is_equal(4)


func test_sample_damage_solo_returns_base() -> void:
	assert_int(_sample_damage(3, 0)).is_equal(3)

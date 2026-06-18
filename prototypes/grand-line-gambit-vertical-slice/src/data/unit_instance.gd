# VERTICAL SLICE - NOT FOR PRODUCTION
# Validation Question: 数据—视觉单向流（运行时状态与模板分离，ADR-0003）
# Date: 2026-06-18
#
# 单位运行时实例（可变状态）。持模板只读引用，绝不写回 UnitDefinition。
class_name UnitInstance
extends RefCounted

var instance_id: int                 # 运行时整数身份
var definition: UnitDefinition       # 只读模板引用
var current_hp: int
var grid_position: Vector2i
var has_moved: bool = false
var has_acted: bool = false
var is_alive: bool = true

func _init(p_id: int, p_def: UnitDefinition, p_pos: Vector2i) -> void:
	instance_id = p_id
	definition = p_def
	current_hp = p_def.max_hp
	grid_position = p_pos

func faction() -> String:
	return definition.faction

func unit_class() -> String:
	return definition.unit_class

func reset_turn_flags() -> void:
	has_moved = false
	has_acted = false

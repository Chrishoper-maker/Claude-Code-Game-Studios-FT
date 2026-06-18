# VERTICAL SLICE - NOT FOR PRODUCTION
# Validation Question: 单位视觉节点管理（UnitView 唯一节点契约，ADR-0007）
# Date: 2026-06-18
#
# UnitLayer（ADR-0007）：管理全部 UnitView 子节点 + instance_id↔UnitView 字典。
class_name UnitLayer
extends Node3D

const UnitViewScript = preload("res://src/systems/board/unit_view.gd")

var _views: Dictionary = {}           # int instance_id -> UnitView

func spawn_view(def: UnitDefinition, inst_id: int, grid_pos: Vector2i) -> UnitView:
	var view: UnitView = UnitViewScript.new()
	add_child(view)
	view.setup(def, inst_id, grid_pos)
	_views[inst_id] = view
	return view

func get_view(inst_id: int) -> UnitView:
	return _views.get(inst_id, null)

func _ready() -> void:
	EventBus.unit_moved.connect(_on_unit_moved)
	EventBus.unit_downed.connect(_on_unit_downed)

func _on_unit_moved(unit_id: int, _from_pos: Vector2i, to_pos: Vector2i) -> void:
	var v: UnitView = get_view(unit_id)
	if v != null:
		v.move_to(to_pos)

func _on_unit_downed(unit_id: int) -> void:
	var v: UnitView = get_view(unit_id)
	if v != null:
		v.set_downed()

# VERTICAL SLICE - NOT FOR PRODUCTION
# Validation Question: 白盒单位视觉 + 离散移动补间 + 可辨识度（ADR-0007）
# Date: 2026-06-18
#
# 单位视觉节点（ADR-0007）：纯 Node3D + MeshInstance3D，无物理体。数据→视觉单向。
class_name UnitView
extends Node3D

const MOVE_TWEEN_DURATION: float = SliceConfig.MOVE_TWEEN_DURATION

var instance_id: int
var _mesh: MeshInstance3D
var _move_tween: Tween

# 由 UnitLayer 生成时调用
func setup(def: UnitDefinition, inst_id: int, grid_pos: Vector2i) -> void:
	instance_id = inst_id
	_build_whitebox(def.unit_class, def.faction)
	global_position = GridCoordMapper.grid_to_world(grid_pos)

func _build_whitebox(unit_class: String, faction: String) -> void:
	_mesh = MeshInstance3D.new()
	var shape: String = SliceConfig.CLASS_SHAPE.get(unit_class, "box")
	match shape:
		"cylinder":
			var cm := CylinderMesh.new()
			cm.height = 1.5
			cm.top_radius = 0.45
			cm.bottom_radius = 0.45
			_mesh.mesh = cm
		"capsule":
			var cap := CapsuleMesh.new()
			cap.height = 1.5
			cap.radius = 0.45
			_mesh.mesh = cap
		_:
			var bm := BoxMesh.new()
			bm.size = Vector3(0.9, 1.5, 0.9)
			_mesh.mesh = bm
	# 底面贴 y=0
	_mesh.position = Vector3(0, 0.75, 0)

	var mat := StandardMaterial3D.new()
	var base: Color = SliceConfig.CLASS_COLOR.get(unit_class, Color.WHITE)
	if faction == "enemy":
		base = base.darkened(1.0 - SliceConfig.ENEMY_DARKEN)
		mat.rim_enabled = true
		mat.rim = 0.8
		mat.rim_tint = 0.5
	else:
		mat.rim_enabled = true
		mat.rim = 0.6
		mat.rim_tint = 0.5
	mat.albedo_color = base
	# rim 颜色靠 emission 近似（StandardMaterial3D rim 无独立色，用轻 emission 区分阵营冷暖）
	mat.emission_enabled = true
	mat.emission = (SliceConfig.ENEMY_RIM if faction == "enemy" else SliceConfig.CREW_RIM)
	mat.emission_energy_multiplier = 0.15
	_mesh.material_override = mat
	add_child(_mesh)

# 离散补间移动（scaled 时间；FREEZE 期会减速 = 定格，回合制下不并发）
func move_to(grid_pos: Vector2i) -> void:
	if is_instance_valid(_move_tween):
		_move_tween.kill()
	var target := GridCoordMapper.grid_to_world(grid_pos)
	_move_tween = create_tween()
	_move_tween.tween_property(self, "global_position", target, MOVE_TWEEN_DURATION)

func set_downed() -> void:
	visible = false

func set_selected(selected: bool) -> void:
	if _mesh == null:
		return
	var mat := _mesh.material_override as StandardMaterial3D
	if mat == null:
		return
	mat.emission_energy_multiplier = 0.6 if selected else 0.15

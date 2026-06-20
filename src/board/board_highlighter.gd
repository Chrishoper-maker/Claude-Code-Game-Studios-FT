# 棋盘格高亮（Node3D，ADR-0006 高亮规范）。MeshInstance3D 池，y=0.01 防 z-fighting。纯视觉，零逻辑。
class_name BoardHighlighter
extends Node3D

const HIGHLIGHT_Y: float = 0.01

var _pool: Array[MeshInstance3D] = []

func show_cells(cells: Array[Vector2i], color: Color) -> void:
	clear()
	_ensure_pool(cells.size())
	for i in cells.size():
		var hl := _pool[i]
		var mat := hl.material_override as StandardMaterial3D
		mat.albedo_color = Color(color.r, color.g, color.b, 0.45)
		var world := GridCoordMapper.grid_to_world(cells[i])
		hl.position = Vector3(world.x, HIGHLIGHT_Y, world.z)
		hl.visible = true

func clear() -> void:
	for hl in _pool:
		hl.visible = false

func _ensure_pool(n: int) -> void:
	while _pool.size() < n:
		var hl := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(GridCoordMapper.CELL_SIZE * 0.92, GridCoordMapper.CELL_SIZE * 0.92)
		hl.mesh = pm
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		hl.material_override = mat
		hl.visible = false
		add_child(hl)
		_pool.append(hl)

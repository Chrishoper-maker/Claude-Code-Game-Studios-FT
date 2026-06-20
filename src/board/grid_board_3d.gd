# 视觉棋盘（Node3D，ADR-0006）。透视相机 + 平行光 + 环境 + 8×8 白盒格面。
# 坐标一律走 GridCoordMapper（禁止内联 col*CELL_SIZE）。零物理体、纯视觉。
# _ready 自建场景树（最小化 .tscn 手写风险，构建走代码 — 见 active.md 垂直切片决策）。
class_name GridBoard3D
extends Node3D

# 相机参考配置（ADR-0006「相机参考配置」）。
const CAMERA_FOV: float = 60.0
const CAMERA_POSITION := Vector3(7.0, 16.0, 22.0)   # ~55° 仰角，从 +Z 侧俯视

# 棋格白盒配色（art-bible 待定前的中性占位；明暗双色读出格线）。
const TILE_LIGHT := Color("#3A4A5A")    # 偏亮格
const TILE_DARK := Color("#2E3B49")     # 偏暗格
const TILE_GAP: float = 0.1             # 格间缝（露出底板 → 视觉格线）
const BASE_COLOR := Color("#1A2430")    # 底板（缝隙处可见 = 格线色）

func _ready() -> void:
	_build_environment()
	_build_camera()
	_build_light()
	_build_board()

# 海蓝灰纯色背景 + 环境光（forward+ 无 WorldEnvironment 会全黑；不引 Sky 资源）。
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#10161D")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#6A7585")
	env.ambient_light_energy = 0.4
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

func _build_camera() -> void:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = CAMERA_FOV
	add_child(cam)                              # 先入树再设全局变换 + look_at
	cam.global_position = CAMERA_POSITION
	cam.look_at(GridCoordMapper.board_center(), Vector3.UP)

func _build_light() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, -40.0, 0.0)   # 斜上方主光
	light.shadow_enabled = true
	light.light_energy = 1.2
	add_child(light)

# 底板 + 8×8 棋格（共享 2 材质，draw call 友好）。
func _build_board() -> void:
	var size := GridCoordMapper.BOARD_SIZE
	var cell := GridCoordMapper.CELL_SIZE
	var center := GridCoordMapper.board_center()

	# 底板：略大于棋盘，y 微沉 → 格缝处露出此色作为格线。
	var base := MeshInstance3D.new()
	var base_mesh := PlaneMesh.new()
	base_mesh.size = Vector2(size * cell + cell, size * cell + cell)
	base.mesh = base_mesh
	base.material_override = _flat_material(BASE_COLOR)
	base.position = Vector3(center.x, -0.02, center.z)
	add_child(base)

	var mat_light := _flat_material(TILE_LIGHT)
	var mat_dark := _flat_material(TILE_DARK)
	var tile_mesh := PlaneMesh.new()
	tile_mesh.size = Vector2(cell - TILE_GAP, cell - TILE_GAP)
	for row in size:
		for col in size:
			var tile := MeshInstance3D.new()
			tile.mesh = tile_mesh                         # 共享网格
			tile.material_override = mat_dark if (col + row) % 2 == 0 else mat_light
			tile.position = GridCoordMapper.grid_to_world(Vector2i(col, row))
			add_child(tile)

func _flat_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	return mat

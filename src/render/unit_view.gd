# 单位视觉节点（ADR-0007）：纯 Node3D + MeshInstance3D，**无任何物理体**。
# 数据（UnitInstance/UnitDefinition）→ 视觉单向，禁写回。白盒 MVP：图元 + 每职业 albedo
# + 阵营冷暖。移动用 Tween 离散补间 global_position。拾取走 ADR-0006 world_to_grid（非物理）。
class_name UnitView
extends Node3D

const MOVE_TWEEN_DURATION: float = 0.35   # 离散补间时长（ADR-0007）

# 配色权威源 = art-bible §4.4（职业身份）+ §4.5（阵营 rim）。art-bible 调色时回填此处一处。
const CLASS_VISUAL := {
	"swordsman": {"shape": "box",      "color": "#B23A48"},  # 剑豪 — 绯红钢
	"gunner":    {"shape": "cylinder", "color": "#C0703A"},  # 炮手 — 火药褐橙
	"bulwark":   {"shape": "box",      "color": "#5E7488"},  # 铁壁 — 钢青灰
	"medic":     {"shape": "capsule",  "color": "#4FA68A"},  # 医师 — 薄荷青绿
	"navigator": {"shape": "capsule",  "color": "#3B4F9E"},  # 航海士 — 靛蓝
	"musician":  {"shape": "cylinder", "color": "#8E5BA6"},  # 乐手 — 紫罗兰
}
const CREW_RIM := Color("#FFE0B0")    # crew 暖 rim（emission 近似）
const ENEMY_RIM := Color("#7FAFFF")   # enemy 冷 rim
const ENEMY_DARKEN := 0.3             # enemy albedo 压暗比例（art-bible 4.5）

var instance_id: int
var _mesh: MeshInstance3D
var _move_tween: Tween
var _hp_label: Label3D
var _base_albedo: Color

# 由 UnitRenderer 生成时调用。
func setup(unit_class: String, faction: String, inst_id: int, grid_pos: Vector2i) -> void:
	instance_id = inst_id
	_build_whitebox(unit_class, faction)
	global_position = GridCoordMapper.grid_to_world(grid_pos)
	_hp_label = Label3D.new()
	_hp_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hp_label.no_depth_test = true
	_hp_label.pixel_size = 0.006           # 整串 "10/10" 总宽 ≈ 模型宽，随透视缩放
	_hp_label.font_size = 48
	_hp_label.outline_size = 12
	_hp_label.outline_modulate = Color.BLACK
	_hp_label.position = Vector3(0, 1.95, 0)
	_hp_label.modulate = Color.WHITE
	add_child(_hp_label)

# 头顶 HP 文本（UnitRenderer 订阅 damage/heal 后调用）。
func set_hp(current: int, max_hp: int) -> void:
	if _hp_label != null:
		_hp_label.text = "%d/%d" % [current, max_hp]

func _build_whitebox(unit_class: String, faction: String) -> void:
	_mesh = MeshInstance3D.new()
	var vis: Dictionary = CLASS_VISUAL.get(unit_class, {"shape": "box", "color": "#FFFFFF"})
	match vis.shape:
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
	_mesh.position = Vector3(0, 0.75, 0)   # 底面贴 Y=0

	var mat := StandardMaterial3D.new()
	var base := Color(vis.color)
	if faction == "enemy":
		base = base.darkened(ENEMY_DARKEN)
	mat.albedo_color = base
	_base_albedo = base
	mat.rim_enabled = true
	mat.rim = 0.7
	mat.rim_tint = 0.5
	# StandardMaterial3D rim 无独立色 → 用轻 emission 近似阵营冷暖。
	mat.emission_enabled = true
	mat.emission = ENEMY_RIM if faction == "enemy" else CREW_RIM
	mat.emission_energy_multiplier = 0.15
	_mesh.material_override = mat
	add_child(_mesh)

# 离散补间移动（scaled 时间；FREEZE 期减速=定格效果）。
func move_to(grid_pos: Vector2i) -> void:
	if is_instance_valid(_move_tween):
		_move_tween.kill()
	var target := GridCoordMapper.grid_to_world(grid_pos)
	_move_tween = create_tween()
	_move_tween.tween_property(self, "global_position", target, MOVE_TWEEN_DURATION)

# 命中闪白再回原色（~0.15s）。由 UnitRenderer 在 damage_dealt 时调用。
func flash_hit() -> void:
	if _mesh == null:
		return
	var mat := _mesh.material_override as StandardMaterial3D
	if mat == null:
		return
	mat.albedo_color = Color.WHITE
	var tw := create_tween()
	tw.tween_property(mat, "albedo_color", _base_albedo, 0.15)

# 击倒退场：快速下沉 + 缩小后隐藏（KO 大字由 DamageFloater 同时弹出）。
func set_downed() -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "position:y", position.y - 0.5, 0.3)
	tw.tween_property(self, "scale", Vector3(0.1, 0.1, 0.1), 0.3)
	tw.chain().tween_callback(func() -> void: visible = false)

func set_selected(selected: bool) -> void:
	if _mesh == null:
		return
	var mat := _mesh.material_override as StandardMaterial3D
	if mat != null:
		mat.emission_energy_multiplier = 0.6 if selected else 0.15

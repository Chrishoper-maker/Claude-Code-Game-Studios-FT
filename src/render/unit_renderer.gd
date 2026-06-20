# 单位渲染管理（Node3D，ADR-0007）。管理 UnitView 子节点 + battle_id↔view 字典；零物理体。
# 数据→视觉单向：订阅 EventBus.unit_moved/unit_downed，驱动 UnitView 补间/隐藏。
class_name UnitRenderer
extends Node3D

var _views: Dictionary = {}   # int battle_id → UnitView
var _max_hp: Dictionary = {}  # int battle_id → int max_hp（spawn 时由 BattleScene 写入）

func _ready() -> void:
	if not EventBus.unit_moved.is_connected(_on_unit_moved):
		EventBus.unit_moved.connect(_on_unit_moved)
	if not EventBus.unit_downed.is_connected(_on_unit_downed):
		EventBus.unit_downed.connect(_on_unit_downed)
	if not EventBus.damage_dealt.is_connected(_on_hp_changed):
		EventBus.damage_dealt.connect(_on_hp_changed)

func set_unit_max_hp(battle_id: int, max_hp: int) -> void:
	_max_hp[battle_id] = max_hp

func _on_hp_changed(target_id: int, _final_damage: int, new_hp: int) -> void:
	var v: UnitView = _views.get(target_id, null)
	if v != null:
		v.set_hp(new_hp, _max_hp.get(target_id, new_hp))
		v.flash_hit()

# 为单位生成视觉节点（部署后由 BattleScene/预览调用）。
func spawn_view(unit_class: String, faction: String, battle_id: int, grid_pos: Vector2i) -> UnitView:
	var view := UnitView.new()
	add_child(view)
	view.setup(unit_class, faction, battle_id, grid_pos)
	_views[battle_id] = view
	return view

func get_view(battle_id: int) -> UnitView:
	return _views.get(battle_id, null)

func _on_unit_moved(unit_id: int, _from_pos: Vector2i, to_pos: Vector2i) -> void:
	var v: UnitView = _views.get(unit_id, null)
	if v != null:
		v.move_to(to_pos)

func _on_unit_downed(unit_id: int) -> void:
	var v: UnitView = _views.get(unit_id, null)
	if v != null:
		v.set_downed()

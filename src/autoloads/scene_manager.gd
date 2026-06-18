# 场景切换控制器（autoload #5，必须最后一条，ADR-0002）。
# 封装 SceneTree.change_scene_to_packed()，提供类型化 goto_battle()/goto_route()。
# run_phase_changed 由调用方（RunManager）在切换前发射，本类不发射。
# PackedScene 在 Project Settings → Autoload Inspector 中赋值（BattleScene/RouteScene 实现后）。
# （autoload 脚本不声明 class_name：注册名 SceneManager 即全局单例访问）
extends Node

@export var battle_scene: PackedScene
@export var route_scene: PackedScene

func goto_battle() -> void:
	assert(battle_scene != null, "SceneManager: battle_scene 未在 Inspector 中赋值")
	get_tree().change_scene_to_packed(battle_scene)

func goto_route() -> void:
	assert(route_scene != null, "SceneManager: route_scene 未在 Inspector 中赋值")
	get_tree().change_scene_to_packed(route_scene)

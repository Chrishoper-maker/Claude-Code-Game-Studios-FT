# 场景切换控制器（autoload #5，必须最后一条，ADR-0002）。
# 封装 SceneTree.change_scene_to_packed()，提供类型化 goto_battle()/goto_route()。
# run_phase_changed 由调用方（RunManager）在切换前发射，本类不发射。
# 注：script 型 autoload 无法在 Inspector 赋 @export，故用 preload 常量持有场景（确定性、可headless）。
# （autoload 脚本不声明 class_name：注册名 SceneManager 即全局单例访问）
extends Node

const BATTLE_SCENE := preload("res://scenes/BattleScene.tscn")
const ROUTE_SCENE := preload("res://scenes/RouteScene.tscn")

func goto_battle() -> void:
	get_tree().change_scene_to_packed(BATTLE_SCENE)

func goto_route() -> void:
	get_tree().change_scene_to_packed(ROUTE_SCENE)

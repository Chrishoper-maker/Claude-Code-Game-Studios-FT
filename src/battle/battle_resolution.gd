# 战斗解算（combat math，architecture.md §142 / battle-resolution-system）。
# register_attack_modifier 是 ADR-0001 唯一允许的直连例外（AdjacencyBond 单向注入）。
# 骨架 stub：接口就位，伤害公式/动词执行/状态实现留 battle-resolution story（需先立项 ADR-0005）。
class_name BattleResolution
extends Node

func is_valid_attack(_attacker_id: int, _target_id: int) -> bool: return false
func execute_attack(_attacker_id: int, _target_id: int) -> void: pass
func execute_verb(_id: int, _verb: String, _target_id: int) -> void: pass
# ADR-0001 唯一直连例外：AdjacencyBond 注入相邻羁绊修正器
func register_attack_modifier(_id: int, _bonus: int) -> void: pass
func get_unit_status(_id: int, _status: String) -> int: return 0
func apply_status(_id: int, _status: String) -> void: pass

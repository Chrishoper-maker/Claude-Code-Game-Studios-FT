# 相邻羁绊修正器注入（architecture.md §143 / adjacency-bond-system）。
# 无对外接口：订阅 EventBus.attack_initiated，向 BattleResolution.register_attack_modifier 注入。
# 骨架 stub：羁绊矩阵 + 触发过滤实现留 adjacency-bond story。
class_name AdjacencyBond
extends Node

# TODO(adjacency-bond story)：_ready 订阅 attack_initiated；按 verb（普攻/斩）+ 阵营过滤；
#   查羁绊矩阵（精英 BOND_ELITE=2 / 通用 BOND_BASE=1）→ register_attack_modifier。

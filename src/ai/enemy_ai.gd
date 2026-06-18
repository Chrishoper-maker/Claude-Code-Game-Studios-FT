# 敌人 AI 意图计算（architecture.md §145 / enemy-ai-intent-system）。
# 无对外接口：订阅 EventBus.round_started，ROUND_START 时全明示声明意图（intent_declared）。
# 骨架 stub：4 行为原型（MELEE/RANGED/GUARDIAN/SWARMER）+ 意图执行实现留 enemy-ai story。
class_name EnemyAI
extends Node

var _intent_map: Dictionary = {}   # int unit_id → IntentRecord

# TODO(enemy-ai story)：_ready 订阅 round_started → 为每个存活敌人算 IntentRecord →
#   EventBus.intent_declared.emit；enemy_turn_started 时执行；确定性（平局按 unit_id 升序）。

# VERTICAL SLICE - NOT FOR PRODUCTION
# Validation Question: 爆发演出与核心循环在 Godot 3D 的落地
# Date: 2026-06-18
#
# 全局事件总线（ADR-0001）。静态定义的类型化信号；系统经 EventBus.signal.connect/emit 通信。
# 切片只定义本场战斗用到的信号子集；签名与 ADR-0001 保持一致。
extends Node

# ── 战斗信号 ──
signal attack_executed(attacker_id: int, target_id: int, damage: int)
signal damage_dealt(target_id: int, final_damage: int, new_hp: int)
signal unit_downed(unit_id: int)
signal unit_moved(unit_id: int, from_pos: Vector2i, to_pos: Vector2i)

# ── 回合信号 ──
signal battle_started()
signal battle_won()
signal round_started(round_count: int)
signal round_ended()
signal player_phase_started()
signal enemy_phase_started()

# ── 羁绊 / 爆发信号 ──
signal gauge_charged(attacker_id: int, charge_amount: int, bond_gauge_current: int)
signal bond_gauge_full()
signal burst_executed(lead_id: int, partner_id: int)
signal burst_presentation_requested(lead_id: int, partner_id: int, effect_id: StringName)
signal burst_presentation_started()
signal burst_presentation_ended()

# 羁绊槽 + 爆发技（architecture.md §144 / bond-gauge-burst-system）。
# 共享槽 BOND_GAUGE_MAX=10、跨回合保留、不跨战斗保留。
# 骨架 stub：充能/配对/触发实现留 bond-gauge-burst story；演出走 BurstPresentation(ADR-0008)。
class_name BondGaugeBurst
extends Node

func activate_burst(_lead_id: int, _partner_id: int) -> void:
	# TODO(bond-gauge-burst story)：校验槽满 + lead/partner 相邻 → 消耗行动点 →
	#   EventBus.burst_executed / burst_presentation_requested。
	pass

func get_gauge_value() -> int:
	return 0

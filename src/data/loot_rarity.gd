# 战利品稀有度加权助手（risk-reward ②c）：纯静态无状态。
# 通关地图 island_tier → 稀有度权重 → 战后候选逐件加权抽取。
class_name LootRarity
extends RefCounted

# tier → 5 稀有度 [普通0,稀有1,史诗2,稀世3,传奇4] 权重。传奇恒 0（池无件）。
const TIER_WEIGHTS := {
	1: [60, 30, 10, 0, 0],
	2: [35, 40, 20, 5, 0],
	3: [20, 35, 30, 15, 0],
	5: [10, 25, 35, 30, 0],
	6: [5, 15, 35, 45, 0],
}
const DEFAULT_WEIGHTS := [60, 30, 10, 0, 0]   # 未知 tier 保守
const BAND_THRESHOLD := 15                      # 品阶带显示阈值

static func rarity_weights(island_tier: int) -> Array[int]:
	var raw: Array = TIER_WEIGHTS.get(island_tier, DEFAULT_WEIGHTS)
	var out: Array[int] = []
	for w in raw:
		out.append(int(w))
	return out

# 逐件按其稀有度权重加权随机抽一件；空池 / total<=0 → null。
static func weighted_pick(pool: Array, island_tier: int, rng: RandomNumberGenerator) -> EquipmentDefinition:
	if pool.is_empty():
		return null
	var weights := rarity_weights(island_tier)
	var total := 0
	for piece in pool:
		total += weights[clampi((piece as EquipmentDefinition).rarity, 0, 4)]
	if total <= 0:
		return null
	var r := rng.randi_range(0, total - 1)
	var acc := 0
	for piece in pool:
		acc += weights[clampi((piece as EquipmentDefinition).rarity, 0, 4)]
		if r < acc:
			return piece as EquipmentDefinition
	return pool[pool.size() - 1] as EquipmentDefinition   # 浮点/边界兜底

# 该 tier 权重 ≥ BAND_THRESHOLD 的稀有度区间中文标签（最低~最高，单档显一档）。
static func loot_band_label(island_tier: int) -> String:
	var weights := rarity_weights(island_tier)
	var lo := -1
	var hi := -1
	for i in range(weights.size()):
		if weights[i] >= BAND_THRESHOLD:
			if lo < 0:
				lo = i
			hi = i
	if lo < 0:
		return "无"
	if lo == hi:
		return EquipmentDefinition.rarity_label(lo)
	return "%s~%s" % [EquipmentDefinition.rarity_label(lo), EquipmentDefinition.rarity_label(hi)]

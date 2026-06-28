# LootRarity 纯助手：tier→稀有度权重表、逐件加权抽取、品阶带标签。
extends GdUnitTestSuite

func _eq(rarity: int) -> EquipmentDefinition:
	var e := EquipmentDefinition.new()
	e.rarity = rarity
	return e

func test_rarity_weights_known_tiers() -> void:
	assert_array(LootRarity.rarity_weights(1)).is_equal([60, 30, 10, 0, 0])
	assert_array(LootRarity.rarity_weights(2)).is_equal([35, 40, 20, 5, 0])
	assert_array(LootRarity.rarity_weights(3)).is_equal([20, 35, 30, 15, 0])
	assert_array(LootRarity.rarity_weights(5)).is_equal([10, 25, 35, 30, 0])
	assert_array(LootRarity.rarity_weights(6)).is_equal([5, 15, 35, 45, 0])

func test_rarity_weights_unknown_tier_defaults_conservative() -> void:
	assert_array(LootRarity.rarity_weights(4)).is_equal([60, 30, 10, 0, 0])
	assert_array(LootRarity.rarity_weights(99)).is_equal([60, 30, 10, 0, 0])

func test_weighted_pick_empty_pool_returns_null() -> void:
	var rng := RandomNumberGenerator.new()
	assert_object(LootRarity.weighted_pick([], 6, rng)).is_null()

func test_weighted_pick_zero_total_returns_null() -> void:
	# 池只有传奇(权重恒0) → total 0 → null
	var rng := RandomNumberGenerator.new()
	assert_object(LootRarity.weighted_pick([_eq(4)], 6, rng)).is_null()

func test_weighted_pick_single_nonzero_piece_deterministic() -> void:
	# 池只有一件普通，tier6 普通权重 5>0 → 必返回它
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var only := _eq(0)
	assert_object(LootRarity.weighted_pick([only], 6, rng)).is_same(only)

func test_weighted_pick_never_returns_zero_weight_rarity() -> void:
	# 池含普通+传奇，传奇权重恒0 → 永远返回普通
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var common := _eq(0)
	var legend := _eq(4)
	for i in range(20):
		assert_object(LootRarity.weighted_pick([common, legend], 6, rng)).is_same(common)

func test_loot_band_label_thresholded() -> void:
	assert_str(LootRarity.loot_band_label(1)).is_equal("普通~稀有")
	assert_str(LootRarity.loot_band_label(2)).is_equal("普通~史诗")
	assert_str(LootRarity.loot_band_label(3)).is_equal("普通~稀世")
	assert_str(LootRarity.loot_band_label(5)).is_equal("稀有~稀世")
	assert_str(LootRarity.loot_band_label(6)).is_equal("稀有~稀世")

# 战斗集成测试：装配全部子系统跑完整战斗循环 + 实例化 BattleScene.tscn 冒烟。
# 多系统集成（tests/integration），验证逻辑链装配后端到端可运行。
extends GdUnitTestSuite

var _uid: int

func before_test() -> void:
	RunManager._autosave_enabled = false
	if EventBus.battle_won.is_connected(RunManager._on_battle_won):
		EventBus.battle_won.disconnect(RunManager._on_battle_won)
	RunManager._goto_battle = func() -> void: pass   # 防止 confirm_deploy 真的切场景
	RunManager._goto_route  = func() -> void: pass   # 防止 battle_won 真的切场景

func after_test() -> void:
	if not EventBus.battle_won.is_connected(RunManager._on_battle_won):
		EventBus.battle_won.connect(RunManager._on_battle_won)
	RunManager._goto_battle = RunManager._default_goto_battle
	RunManager._goto_route  = RunManager._default_goto_route

func _add(tm: TurnManager, gb: GridBoard, faction: String, pos: Vector2i, base_damage: int, move_range: int, hp: int) -> int:
	_uid += 1
	var d := UnitDefinition.new()
	d.id = "u%d" % _uid
	d.faction = faction
	d.unit_class = "swordsman"
	d.base_damage = base_damage
	d.move_range = move_range
	d.attack_range = 1
	d.max_hp = hp
	var inst := UnitInstance.from_definition(d)
	inst.current_hp = hp
	inst.grid_position = pos
	inst.behavior_type = "MELEE"
	var bid := tm.register_unit(inst)
	gb.place_unit(bid, pos)
	return bid

# 装配全链：先攻 → 玩家攻击 → 解算 → 击倒 → 胜利
func test_assembled_battle_reaches_victory() -> void:
	_uid = 0
	var gb: GridBoard = auto_free(GridBoard.new())
	var tm: TurnManager = auto_free(TurnManager.new())
	var br: BattleResolution = auto_free(BattleResolution.new())
	var ab: AdjacencyBond = auto_free(AdjacencyBond.new())
	var ai: EnemyAI = auto_free(EnemyAI.new())
	br.setup(gb, tm)
	ab.setup(gb, tm, br)
	ai.setup(gb, tm, br)
	var ally := _add(tm, gb, "crew", Vector2i(0, 0), 6, 1, 6)    # 强力
	var enemy := _add(tm, gb, "enemy", Vector2i(0, 1), 2, 1, 3)  # 脆弱，邻接
	tm.start_battle()                                           # → 我方回合
	assert_int(tm.get_battle_state()).is_equal(TurnManager.BattleState.PLAYER_PHASE)
	br.execute_attack(ally, enemy)                              # 6 伤 → 敌方倒下 → 即时胜利
	assert_int(tm.get_battle_state()).is_equal(TurnManager.BattleState.BATTLE_WIN)

# 实例化 BattleScene.tscn：接线 + 部署 4 敌 + roster 驱动部署 2 crew → 战斗在首个玩家回合等待输入。
# 验证 roster 驱动部署：start_run → confirm_deploy 填 pending_deploy → BattleScene 读取部署。
func test_battle_scene_boots_deploys_and_runs() -> void:
	# 准备 RunManager：填入起始 2 名 crew 到 pending_deploy（confirm_deploy 写入，BattleScene 读取）。
	RunManager.start_run()
	var ids: Array = []
	for c in RunManager.get_roster():
		ids.append(c.id)
	RunManager.confirm_deploy(ids)   # _goto_battle 已在 before_test 设为 no-op
	var started := [0]
	var cb := func() -> void: started[0] += 1
	EventBus.battle_started.connect(cb)
	var scene: BattleScene = auto_free(preload("res://scenes/BattleScene.tscn").instantiate())
	add_child(scene)   # 触发 _ready：接线 → load_map 部署 4 敌 → _deploy_run_crew 部署 roster crew → start_battle
	EventBus.battle_started.disconnect(cb)
	assert_int(started[0]).is_equal(1)
	# battle_map_001 部署 4 个敌方单位
	assert_int(scene._turn_manager.get_alive_enemies().size()).is_equal(4)
	# roster 驱动自动部署起始编制（STARTING_CREW=2；具体身份由 starting-tier crew 数据决定）
	assert_int(scene._turn_manager.get_alive_allies().size()).is_equal(2)
	# 阶段制：start_battle 后停在我方回合，等待玩家自由点选指挥（非终态）。
	assert_int(scene._turn_manager.get_battle_state()).is_equal(TurnManager.BattleState.PLAYER_PHASE)
	# I-1 接线：BattleScene._ready 须把 battle_started 连到 BattleMap.on_battle_started，
	# 否则地图状态机停在 MAP_READY（EC-9「战斗进行中拒绝重新加载」守卫永不生效）。
	assert_int(scene._battle_map.get_map_state()).is_equal(BattleMap.MapState.MAP_ACTIVE)

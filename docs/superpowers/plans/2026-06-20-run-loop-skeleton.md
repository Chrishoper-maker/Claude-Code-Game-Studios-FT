# 可玩 run 循环骨架（子项目 A）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把单场战斗扩成一整局肉鸽 run——出航→部署→战斗→胜利→三选一招募→下一岛→…→终局，并清掉 BattleScene 的临时 hack。

**Architecture:** 纯逻辑落在 autoload `RunManager`（招募/部署/流转规则，全部单测覆盖）；新建白盒 `RouteScene` 作为战斗之间的中枢，按 `RunManager.current_phase` 分支渲染三选一卡 / run-end 页；`SceneManager` 用 `preload` 常量持有两张场景；`BattleScene` 改为读 `RunManager.get_pending_deploy()` 自动排位部署。场景导航通过 RunManager 内可注入的 `Callable` 接缝实现，使 confirm_deploy / 战斗胜负流转可在无场景切换的前提下单测。

**Tech Stack:** Godot 4.6.3 / GDScript / GdUnit4 v6.1.3。白盒 = Control + 图元，无美术。

## Global Constraints

- 引擎 Godot 4.6.3，GDScript 静态类型；autoload 脚本不声明 `class_name`（注册名即全局单例）。
- 权威设计：`docs/superpowers/specs/2026-06-20-run-loop-skeleton-design.md` 与 route-recruitment-system GDD（Approved）。
- 注册契约：`run_phase_changed` 唯一发射方是 RunManager；`current_phase` 对外只读 String（IDLE/DEPLOYING/BATTLE/RECRUITING/RUN_END）。
- 常量：`STARTING_CREW=2`、`RECRUIT_OFFER_COUNT=3`、`ISLAND_COUNT_MAX=5`（已在 run_manager.gd 定义，勿改）。
- ID 二元性（ADR-0001）：crew `unit_id` 是 **String**（资源键）；战斗运行时 `battle_id` 是 **int**。本子项目只在 String 域操作 roster/offer。
- 测试规范：`test_[scenario]_[expected]` 命名；Arrange/Act/Assert；确定性（注入 `_rng.seed`，断言不变量而非具体身份）；autoload 单态须在 before/after 复位。
- 招募卡只显示「职业 · display_name · battle_cry」，不显数值（GDD）。battle_cry ≤24 字。
- 范围边界（不做）：DeployScreen 手动选人 / DEPLOY_LIMIT（A 全员自动部署）、船员永久死亡移出 roster、unlockable tier / 悬赏、阵亡通知卡、主菜单、存档、美术。

## File Structure

- `src/autoloads/run_manager.gd`（改）— 招募/部署/流转纯逻辑 + 导航接缝。
- `src/autoloads/scene_manager.gd`（改）— `preload` 常量替代未赋值的 `@export`。
- `scenes/RouteScene.tscn`（建）+ `src/ui/route_scene.gd`（建）— 白盒中枢。
- `src/battle/battle_scene.gd`（改）— roster 驱动部署 + 删 hack。
- `scenes/BattleScene.tscn`（改）— 移除 BattleResultOverlay 节点。
- `project.godot`（改）— `main_scene` → RouteScene。
- `assets/data/units/crew_*.tres`（建 6 个）— 补 pool crew。
- `tests/unit/run_manager/run_manager_test.gd`（改）— 招募/部署/流转单测。
- `tests/unit/data/pool_crew_data_test.gd`（建）— pool crew .tres 校验。

---

### Task 1: RunManager — 起航填编制 + 导航接缝 + 胜负流转

把 `start_run` 填入起始编制；引入可注入导航 `Callable`（默认转调 SceneManager）使流转可测；连接 `battle_lost`；让胜利（含末岛）与失败都切到 RouteScene；记录 `last_run_won` 供 run-end 页判文案。

**Files:**
- Modify: `src/autoloads/run_manager.gd`
- Test: `tests/unit/run_manager/run_manager_test.gd`

**Interfaces:**
- Consumes: `UnitDataManager.get_all_units() -> Array[UnitDefinition]`、`CrewDefinition.recruit_pool_tier:String`、`SceneManager.goto_battle()/goto_route()`、`EventBus.battle_lost/battle_won/run_completed`。
- Produces:
  - `start_run() -> void`（roster 填全部 `tier=="starting"` 的 CrewDefinition；清 `_excluded_offers/_last_offers/pending_deploy/_downed_this_run`；island_index=-1；→DEPLOYING）。
  - `var last_run_won: bool`（末岛胜=true / 失败=false）。
  - `_goto_battle: Callable` / `_goto_route: Callable`（导航接缝，测试可覆盖为 no-op）。
  - `_on_battle_lost() -> void`（→RUN_END + run_completed(false,…) + goto_route）。
  - `_on_battle_won()`（非末岛→RECRUITING+goto_route；末岛→RUN_END+run_completed(true,…)+goto_route）。

- [ ] **Step 1: 写失败测试 — start_run 填起始编制 + 导航接缝复位**

在 `tests/unit/run_manager/run_manager_test.gd`：把现有 `before_test` 替换为下方版本（注入 seed + no-op 导航 + 复位），并加新测试。`after_test` 还原默认导航。

```gdscript
func before_test() -> void:
	RunManager._goto_battle = func() -> void: pass   # 防止单测真的切场景
	RunManager._goto_route = func() -> void: pass
	RunManager.start_run()        # 复位：DEPLOYING + 填起始编制 + 清 offer/pending
	RunManager._rng.seed = 20260620

func after_test() -> void:
	RunManager._goto_battle = RunManager._default_goto_battle
	RunManager._goto_route = RunManager._default_goto_route

func test_start_run_fills_roster_with_starting_crew() -> void:
	# Arrange/Act done in before_test
	# Assert: roster 全为 starting tier，且数量 == 注册表中 starting crew 数
	var expected := 0
	for def in UnitDataManager.get_all_units():
		if def is CrewDefinition and (def as CrewDefinition).recruit_pool_tier == "starting":
			expected += 1
	assert_int(RunManager.roster.size()).is_equal(expected)
	assert_int(expected).is_greater_equal(1)
	for c in RunManager.roster:
		assert_str((c as CrewDefinition).recruit_pool_tier).is_equal("starting")

func test_start_run_resets_run_state() -> void:
	RunManager._excluded_offers.append("x")
	RunManager.pending_deploy.append(null)
	RunManager.start_run()
	assert_int(RunManager._excluded_offers.size()).is_equal(0)
	assert_int(RunManager.pending_deploy.size()).is_equal(0)
	assert_int(RunManager.current_island_index).is_equal(-1)
	assert_str(RunManager.current_phase).is_equal("DEPLOYING")
```

- [ ] **Step 2: 运行测试确认失败**

Run: `godot --headless --import && godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/run_manager/run_manager_test.gd`
Expected: FAIL（`_excluded_offers`/`pending_deploy`/`_rng`/`_default_goto_*` 未定义；roster 为空）。

- [ ] **Step 3: 实现 — RunManager 成员 + start_run + 导航接缝 + 胜负**

在 `src/autoloads/run_manager.gd` 做以下修改。

1) 在 `var roster ...` 之后、`func _ready` 之前，新增成员：

```gdscript
var pending_deploy: Array[CrewDefinition] = []   # 本场出场名单（confirm_deploy 写，BattleScene 读）
var last_run_won: bool = false                   # run-end 页据此判「出航成功/全员阵亡」
var _excluded_offers: Array[String] = []         # 本 run 落选 unit_id（不再 offer）
var _last_offers: Array[String] = []             # 本批候选 unit_id（confirm_recruit 据此排除其余）
var _rng := RandomNumberGenerator.new()          # 招募抽样（测试可 seed；断言不变量）

# 导航接缝（DI over singleton）：默认转调 SceneManager，单测覆盖为 no-op 以免真的切场景。
var _goto_battle: Callable
var _goto_route: Callable
func _default_goto_battle() -> void: SceneManager.goto_battle()
func _default_goto_route() -> void: SceneManager.goto_route()
```

2) 把 `_ready` 替换为（新增 battle_lost 连接 + 初始化导航接缝）：

```gdscript
func _ready() -> void:
	assert(_PHASE_TO_STRING.size() == RunPhase.size(),
		"RunManager: _PHASE_TO_STRING 不完整 — 新增 RunPhase 后须同步更新")
	_goto_battle = _default_goto_battle
	_goto_route = _default_goto_route
	EventBus.battle_won.connect(_on_battle_won)
	EventBus.battle_lost.connect(_on_battle_lost)
	EventBus.crew_member_downed.connect(_on_crew_member_downed)
```

3) 把 `start_run` 替换为（填起始编制 + 清新状态）：

```gdscript
func start_run() -> void:
	roster.clear()
	_excluded_offers.clear()
	_last_offers.clear()
	pending_deploy.clear()
	_downed_this_run.clear()
	current_island_index = -1
	for def in UnitDataManager.get_all_units():
		if def is CrewDefinition and (def as CrewDefinition).recruit_pool_tier == "starting":
			roster.append(def as CrewDefinition)
	_set_run_phase(RunPhase.RUN_DEPLOYING)
```

4) 把 `_on_battle_won` 替换为（末岛也切 RouteScene 以显示 run-end）：

```gdscript
func _on_battle_won() -> void:
	if current_island_index + 1 >= ISLAND_COUNT_MAX:
		last_run_won = true
		_set_run_phase(RunPhase.RUN_END)
		EventBus.run_completed.emit(true, current_island_index + 1, roster.duplicate())
		_goto_route.call()
		return
	_set_run_phase(RunPhase.RUN_RECRUITING)
	_goto_route.call()
```

5) 在 `_on_battle_won` 之后新增失败处理：

```gdscript
# 战斗失败 → run 终局（全员阵亡）。切回 RouteScene 显示 run-end。
func _on_battle_lost() -> void:
	last_run_won = false
	_set_run_phase(RunPhase.RUN_END)
	EventBus.run_completed.emit(false, current_island_index + 1, roster.duplicate())
	_goto_route.call()
```

- [ ] **Step 4: 运行测试确认通过**

Run: `godot --headless --import && godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/run_manager/run_manager_test.gd`
Expected: PASS（含原有 7 条仍绿 + 2 条新增）。

- [ ] **Step 5: 加流转测试（非末岛胜→RECRUITING / 失败→RUN_END+run_completed(false)）**

追加到 `run_manager_test.gd`：

```gdscript
func test_battle_won_non_final_enters_recruiting() -> void:
	RunManager.current_island_index = 0   # 0+1 < 5 → 非末岛
	RunManager._on_battle_won()
	assert_str(RunManager.current_phase).is_equal("RECRUITING")

func test_battle_won_final_sets_last_run_won_true() -> void:
	RunManager.current_island_index = RunManager.ISLAND_COUNT_MAX - 1
	RunManager._on_battle_won()
	assert_str(RunManager.current_phase).is_equal("RUN_END")
	assert_bool(RunManager.last_run_won).is_true()

func test_battle_lost_ends_run_with_loss() -> void:
	var monitor := monitor_signals(EventBus)
	RunManager.current_island_index = 2
	RunManager._on_battle_lost()
	assert_str(RunManager.current_phase).is_equal("RUN_END")
	assert_bool(RunManager.last_run_won).is_false()
	await assert_signal(monitor).is_emitted("run_completed", [false, 3, RunManager.roster])
```

注：`monitor_signals`/`assert_signal` 为 GdUnit4 信号断言 API。若该版本签名匹配比对困难，退化为 `assert_signal(monitor).is_emitted("run_completed")`（仅断发射）。

- [ ] **Step 6: 运行全 run_manager 套件确认通过**

Run: `godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/run_manager/run_manager_test.gd`
Expected: PASS（全绿）。

- [ ] **Step 7: 提交**

```bash
git add src/autoloads/run_manager.gd tests/unit/run_manager/run_manager_test.gd
git commit -m "feat(run): start_run fills starting crew + nav seam + win/lose routing

Story: run-loop-skeleton (A)"
```

---

### Task 2: RunManager — 三选一招募候选 + confirm_recruit

实现 `get_recruit_offers`（无放回随机、≤3、三者职业互不相同、排除 roster/excluded）与 `confirm_recruit`（选中入队、其余候选入排除、→DEPLOYING）。

**Files:**
- Modify: `src/autoloads/run_manager.gd`
- Test: `tests/unit/run_manager/run_manager_test.gd`

**Interfaces:**
- Consumes: Task 1 的 `_excluded_offers/_last_offers/_rng/roster`、`UnitDataManager.get_unit(id)`、`CrewDefinition.unit_class`。
- Produces:
  - `get_recruit_offers() -> Array[CrewDefinition]`（写入 `_last_offers`；可用池<3 返回实际数；=0 返回空）。
  - `confirm_recruit(unit_id: String) -> void`（选中入 roster；`_last_offers` 其余入 `_excluded_offers`；→DEPLOYING）。

- [ ] **Step 1: 写失败测试 — offers 不变量 + confirm_recruit**

追加到 `run_manager_test.gd`：

```gdscript
func test_offers_are_pool_tier_and_exclude_roster() -> void:
	var roster_ids: Dictionary = {}
	for c in RunManager.roster:
		roster_ids[(c as CrewDefinition).id] = true
	var offers := RunManager.get_recruit_offers()
	assert_int(offers.size()).is_less_equal(RunManager.RECRUIT_OFFER_COUNT)
	for o in offers:
		assert_str((o as CrewDefinition).recruit_pool_tier).is_equal("pool")
		assert_bool(roster_ids.has((o as CrewDefinition).id)).is_false()

func test_offers_have_distinct_unit_classes() -> void:
	var offers := RunManager.get_recruit_offers()
	var seen: Dictionary = {}
	for o in offers:
		var cls := (o as CrewDefinition).unit_class
		assert_bool(seen.has(cls)).is_false()
		seen[cls] = true

func test_offers_exclude_excluded_ids() -> void:
	var first := RunManager.get_recruit_offers()
	# 把首批全部塞入排除集，再抽：不得再出现这些 id
	for o in first:
		RunManager._excluded_offers.append((o as CrewDefinition).id)
	var second := RunManager.get_recruit_offers()
	for o in second:
		assert_bool(RunManager._excluded_offers.has((o as CrewDefinition).id)).is_false()

func test_offers_empty_when_pool_exhausted() -> void:
	for def in UnitDataManager.get_all_units():
		if def is CrewDefinition and (def as CrewDefinition).recruit_pool_tier == "pool":
			RunManager._excluded_offers.append((def as CrewDefinition).id)
	var offers := RunManager.get_recruit_offers()
	assert_int(offers.size()).is_equal(0)

func test_confirm_recruit_adds_choice_excludes_rest() -> void:
	var offers := RunManager.get_recruit_offers()
	assert_int(offers.size()).is_greater_equal(2)   # 需≥2 才能验「其余被排除」
	var chosen := (offers[0] as CrewDefinition).id
	var rest := (offers[1] as CrewDefinition).id
	var before := RunManager.roster.size()
	RunManager.confirm_recruit(chosen)
	assert_int(RunManager.roster.size()).is_equal(before + 1)
	var ids: Array[String] = []
	for c in RunManager.roster:
		ids.append((c as CrewDefinition).id)
	assert_bool(ids.has(chosen)).is_true()
	assert_bool(RunManager._excluded_offers.has(rest)).is_true()
	assert_str(RunManager.current_phase).is_equal("DEPLOYING")
```

- [ ] **Step 2: 运行测试确认失败**

Run: `godot --headless --import && godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/run_manager/run_manager_test.gd`
Expected: FAIL（`get_recruit_offers` 返回空；`confirm_recruit` 不入队）。

- [ ] **Step 3: 实现 get_recruit_offers + confirm_recruit**

替换 `src/autoloads/run_manager.gd` 中现有的 `get_recruit_offers` 与 `confirm_recruit`：

```gdscript
# 三选一招募候选（GDD Rule 1-2 / R1）：无放回随机 ≤3 名，且三者 unit_class 互不相同
# （某职业可用不足时豁免）。排除 roster 内与 _excluded_offers 内 unit_id。写入 _last_offers。
func get_recruit_offers() -> Array[CrewDefinition]:
	var roster_ids: Dictionary = {}
	for c in roster:
		roster_ids[c.id] = true
	var pool: Array[CrewDefinition] = []
	for def in UnitDataManager.get_all_units():
		if def is CrewDefinition:
			var crew := def as CrewDefinition
			if crew.recruit_pool_tier == "pool" \
					and not roster_ids.has(crew.id) \
					and not _excluded_offers.has(crew.id):
				pool.append(crew)
	# Fisher-Yates 用持有的 _rng（确定性，测试可 seed）。
	for i in range(pool.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	# 取前 ≤3 名，职业互不相同。
	var offers: Array[CrewDefinition] = []
	var seen_classes: Dictionary = {}
	for crew in pool:
		if offers.size() >= RECRUIT_OFFER_COUNT:
			break
		if seen_classes.has(crew.unit_class):
			continue
		seen_classes[crew.unit_class] = true
		offers.append(crew)
	_last_offers.clear()
	for o in offers:
		_last_offers.append(o.id)
	return offers

# 选中候选加入 roster；本批其余候选进 _excluded_offers（本 run 不再 offer）；→DEPLOYING。
func confirm_recruit(unit_id: String) -> void:
	var def := UnitDataManager.get_unit(unit_id)
	if def is CrewDefinition:
		roster.append(def as CrewDefinition)
	for offered_id in _last_offers:
		if offered_id != unit_id and not _excluded_offers.has(offered_id):
			_excluded_offers.append(offered_id)
	_last_offers.clear()
	_set_run_phase(RunPhase.RUN_DEPLOYING)
```

- [ ] **Step 4: 运行测试确认通过**

Run: `godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/run_manager/run_manager_test.gd`
Expected: PASS（注：本步依赖 Task 4 的 pool crew 数据才能让职业互不相同/≥2 的断言有足够候选；若 Task 4 尚未完成，这些断言可能因 pool 仅 2 个同类不足而偏弱——按 subagent 顺序 Task 4 在本任务后，但断言以「不变量」写法对小池仍成立：≤3、distinct、exclude 均不依赖池大小。`test_confirm_recruit` 的 `is_greater_equal(2)` 需现有 2 个 pool crew(swordsman_02+gunner_01，职业不同)即可满足）。

- [ ] **Step 5: 提交**

```bash
git add src/autoloads/run_manager.gd tests/unit/run_manager/run_manager_test.gd
git commit -m "feat(run): recruit offers (no-replacement, distinct-class) + confirm_recruit

Story: run-loop-skeleton (A)"
```

---

### Task 3: RunManager — confirm_deploy + pending_deploy

`confirm_deploy` 把 roster 中被选 id 的 CrewDefinition 存入 `pending_deploy`，岛序号 +1，转 BATTLE，并经导航接缝切战斗场景。

**Files:**
- Modify: `src/autoloads/run_manager.gd`
- Test: `tests/unit/run_manager/run_manager_test.gd`

**Interfaces:**
- Consumes: Task 1 的 `pending_deploy/_goto_battle`、`roster`。
- Produces:
  - `confirm_deploy(selected_ids: Array) -> void`（pending_deploy=被选 defs；island_index++；→BATTLE；goto_battle）。
  - `get_pending_deploy() -> Array[CrewDefinition]`（BattleScene 读出场名单）。

- [ ] **Step 1: 写失败测试**

追加到 `run_manager_test.gd`：

```gdscript
func test_confirm_deploy_builds_pending_and_advances_island() -> void:
	# Arrange: roster 已含起始编制（before_test）
	var ids: Array[String] = []
	for c in RunManager.roster:
		ids.append((c as CrewDefinition).id)
	var island_before := RunManager.current_island_index
	# Act
	RunManager.confirm_deploy(ids)
	# Assert
	assert_int(RunManager.get_pending_deploy().size()).is_equal(ids.size())
	assert_int(RunManager.current_island_index).is_equal(island_before + 1)
	assert_str(RunManager.current_phase).is_equal("BATTLE")

func test_confirm_deploy_filters_to_selected_ids() -> void:
	var all_ids: Array[String] = []
	for c in RunManager.roster:
		all_ids.append((c as CrewDefinition).id)
	assert_int(all_ids.size()).is_greater_equal(1)
	var subset: Array = [all_ids[0]]
	RunManager.confirm_deploy(subset)
	assert_int(RunManager.get_pending_deploy().size()).is_equal(1)
	assert_str((RunManager.get_pending_deploy()[0] as CrewDefinition).id).is_equal(all_ids[0])
```

- [ ] **Step 2: 运行测试确认失败**

Run: `godot --headless --import && godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/run_manager/run_manager_test.gd`
Expected: FAIL（`get_pending_deploy` 未定义；pending 为空）。

- [ ] **Step 3: 实现 confirm_deploy + get_pending_deploy**

替换 `src/autoloads/run_manager.gd` 中现有的 `confirm_deploy`，并在其后新增 `get_pending_deploy`：

```gdscript
# 部署确认 → 进入战斗（ADR-0002 场景切换序列）。pending_deploy = roster 中被选 id 的 defs。
func confirm_deploy(selected_ids: Array) -> void:
	pending_deploy.clear()
	for c in roster:
		if selected_ids.has(c.id):
			pending_deploy.append(c)
	current_island_index += 1
	_set_run_phase(RunPhase.RUN_ISLAND_BATTLE)   # 发 run_phase_changed("BATTLE")
	_goto_battle.call()

func get_pending_deploy() -> Array[CrewDefinition]:
	return pending_deploy
```

- [ ] **Step 4: 运行测试确认通过**

Run: `godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/run_manager/run_manager_test.gd`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add src/autoloads/run_manager.gd tests/unit/run_manager/run_manager_test.gd
git commit -m "feat(run): confirm_deploy builds pending_deploy + advances island

Story: run-loop-skeleton (A)"
```

---

### Task 4: 补 pool crew 数据 + 校验测试

新增 6 个 `recruit_pool_tier=="pool"` 的 CrewDefinition .tres，覆盖缺失职业（medic/navigator/musician/bulwark + swordsman/gunner 各 1），使三选一有真实选择。

**Files:**
- Create: `assets/data/units/crew_medic_01.tres`、`crew_navigator_01.tres`、`crew_musician_01.tres`、`crew_bulwark_02.tres`、`crew_swordsman_03.tres`、`crew_gunner_02.tres`
- Test: `tests/unit/data/pool_crew_data_test.gd`

**Interfaces:**
- Consumes: `src/data/crew_definition.gd`（脚本路径作 ExtResource）。
- Produces: 6 个 pool crew 资源（UnitDataManager 启动扫描后纳入 `get_all_units()`）。class_action_id 映射：swordsman=slash / bulwark=guard / gunner=cannon / medic=heal / navigator=displace / musician=aura。

- [ ] **Step 1: 写校验测试（先失败）**

创建 `tests/unit/data/pool_crew_data_test.gd`：

```gdscript
# 新增 pool crew .tres 结构校验：类型/tier/字段齐 + 职业覆盖（route-recruitment 招募池）。
extends GdUnitTestSuite

const POOL_PATHS := [
	"res://assets/data/units/crew_medic_01.tres",
	"res://assets/data/units/crew_navigator_01.tres",
	"res://assets/data/units/crew_musician_01.tres",
	"res://assets/data/units/crew_bulwark_02.tres",
	"res://assets/data/units/crew_swordsman_03.tres",
	"res://assets/data/units/crew_gunner_02.tres",
]

func test_each_pool_crew_loads_as_pool_tier_crew_definition() -> void:
	for path in POOL_PATHS:
		var res := ResourceLoader.load(path)
		assert_object(res).is_not_null()
		assert_bool(res is CrewDefinition).is_true()
		var crew := res as CrewDefinition
		assert_str(crew.recruit_pool_tier).is_equal("pool")
		assert_str(crew.id).is_not_empty()
		assert_str(crew.faction).is_equal("crew")
		assert_str(crew.class_action_id).is_not_empty()
		assert_int(crew.max_hp).is_greater(0)

func test_pool_crew_cover_recruit_classes() -> void:
	var classes: Dictionary = {}
	for path in POOL_PATHS:
		classes[(ResourceLoader.load(path) as CrewDefinition).unit_class] = true
	for required in ["medic", "navigator", "musician", "bulwark"]:
		assert_bool(classes.has(required)).is_true()
```

- [ ] **Step 2: 运行测试确认失败**

Run: `godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/data/pool_crew_data_test.gd`
Expected: FAIL（资源文件不存在 → load 返回 null）。

- [ ] **Step 3: 创建 6 个 pool crew .tres**

`assets/data/units/crew_medic_01.tres`：
```
[gd_resource type="Resource" script_class="CrewDefinition" load_steps=2 format=3]

[ext_resource type="Script" path="res://src/data/crew_definition.gd" id="1"]

[resource]
script = ExtResource("1")
id = "crew_medic_01"
display_name = "药师·苓"
faction = "crew"
unit_class = "medic"
max_hp = 8
move_range = 3
attack_range = 1
base_damage = 2
class_action_id = "heal"
title = "随船医师"
battle_cry = "撑住，有我在！"
persona_line = "伤口我来缝，命你自己保。"
recruit_pool_tier = "pool"
portrait_id = "medic_01"
model_id = "whitebox_medic"
```

`assets/data/units/crew_navigator_01.tres`：
```
[gd_resource type="Resource" script_class="CrewDefinition" load_steps=2 format=3]

[ext_resource type="Script" path="res://src/data/crew_definition.gd" id="1"]

[resource]
script = ExtResource("1")
id = "crew_navigator_01"
display_name = "舵手·星"
faction = "crew"
unit_class = "navigator"
max_hp = 8
move_range = 4
attack_range = 1
base_damage = 2
class_action_id = "displace"
title = "领航舵手"
battle_cry = "跟紧我的航线！"
persona_line = "风往哪吹，我说了算。"
recruit_pool_tier = "pool"
portrait_id = "navigator_01"
model_id = "whitebox_navigator"
```

`assets/data/units/crew_musician_01.tres`：
```
[gd_resource type="Resource" script_class="CrewDefinition" load_steps=2 format=3]

[ext_resource type="Script" path="res://src/data/crew_definition.gd" id="1"]

[resource]
script = ExtResource("1")
id = "crew_musician_01"
display_name = "琴师·谣"
faction = "crew"
unit_class = "musician"
max_hp = 7
move_range = 3
attack_range = 1
base_damage = 2
class_action_id = "aura"
title = "甲板乐手"
battle_cry = "听我一曲！"
persona_line = "鼓点起，士气不落。"
recruit_pool_tier = "pool"
portrait_id = "musician_01"
model_id = "whitebox_musician"
```

`assets/data/units/crew_bulwark_02.tres`：
```
[gd_resource type="Resource" script_class="CrewDefinition" load_steps=2 format=3]

[ext_resource type="Script" path="res://src/data/crew_definition.gd" id="1"]

[resource]
script = ExtResource("1")
id = "crew_bulwark_02"
display_name = "盾卫·岩"
faction = "crew"
unit_class = "bulwark"
max_hp = 12
move_range = 2
attack_range = 1
base_damage = 3
class_action_id = "guard"
title = "船首盾卫"
battle_cry = "想过去？先过我！"
persona_line = "我不退，船就不沉。"
recruit_pool_tier = "pool"
portrait_id = "bulwark_02"
model_id = "whitebox_bulwark"
```

`assets/data/units/crew_swordsman_03.tres`：
```
[gd_resource type="Resource" script_class="CrewDefinition" load_steps=2 format=3]

[ext_resource type="Script" path="res://src/data/crew_definition.gd" id="1"]

[resource]
script = ExtResource("1")
id = "crew_swordsman_03"
display_name = "浪人·辰"
faction = "crew"
unit_class = "swordsman"
max_hp = 10
move_range = 3
attack_range = 1
base_damage = 3
class_action_id = "slash"
title = "流浪剑客"
battle_cry = "一刀两断。"
persona_line = "剑出，话止。"
recruit_pool_tier = "pool"
portrait_id = "swordsman_03"
model_id = "whitebox_swordsman"
```

`assets/data/units/crew_gunner_02.tres`：
```
[gd_resource type="Resource" script_class="CrewDefinition" load_steps=2 format=3]

[ext_resource type="Script" path="res://src/data/crew_definition.gd" id="1"]

[resource]
script = ExtResource("1")
id = "crew_gunner_02"
display_name = "火枪·硝"
faction = "crew"
unit_class = "gunner"
max_hp = 7
move_range = 2
attack_range = 3
base_damage = 3
class_action_id = "cannon"
title = "火枪手"
battle_cry = "在我射程内。"
persona_line = "距离，就是胜负手。"
recruit_pool_tier = "pool"
portrait_id = "gunner_02"
model_id = "whitebox_gunner"
```

- [ ] **Step 4: 重新导入并运行校验测试**

Run: `godot --headless --import && godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/data/pool_crew_data_test.gd`
Expected: PASS（6 资源加载、tier=pool、职业覆盖 medic/navigator/musician/bulwark）。

- [ ] **Step 5: 提交**

```bash
git add assets/data/units/crew_medic_01.tres assets/data/units/crew_navigator_01.tres assets/data/units/crew_musician_01.tres assets/data/units/crew_bulwark_02.tres assets/data/units/crew_swordsman_03.tres assets/data/units/crew_gunner_02.tres tests/unit/data/pool_crew_data_test.gd
git commit -m "feat(data): add 6 pool crew covering medic/navigator/musician/bulwark

Story: run-loop-skeleton (A)"
```

---

### Task 5: RouteScene 白盒中枢（场景 + 脚本）

新建 RouteScene：`_ready` 按 `RunManager.current_phase` 分支——IDLE 起航直接部署首岛；RECRUITING 显示三选一卡；RUN_END 显示结果 + 重新出航。

**Files:**
- Create: `scenes/RouteScene.tscn`、`src/ui/route_scene.gd`

**Interfaces:**
- Consumes: `RunManager.current_phase`、`start_run()`、`get_roster()`、`get_recruit_offers()`、`confirm_recruit(id)`、`confirm_deploy(ids)`、`last_run_won`、`CrewDefinition.{unit_class,display_name,battle_cry,id}`。
- Produces: `scenes/RouteScene.tscn`（Control 根，脚本 route_scene.gd），供 Task 6 的 SceneManager preload 与 main_scene。

- [ ] **Step 1: 写脚本 src/ui/route_scene.gd**

```gdscript
# 战斗之间的中枢（白盒，Control）。按 RunManager.current_phase 分支：
# IDLE→起航直发首岛；RECRUITING→三选一卡；RUN_END→结果页+重新出航。
# 招募卡只显示「职业 · 名 · 台词」（不显数值，GDD）。
class_name RouteScene
extends Control

func _ready() -> void:
	match RunManager.current_phase:
		"IDLE":
			_begin_run()
		"RECRUITING":
			_show_recruit_offers()
		"RUN_END":
			_show_run_end()
		_:
			# DEPLOYING/BATTLE 不应停留于此；防御性直接部署当前 roster。
			_deploy_current_roster()

# 起航：填起始编制 → 直接部署首岛（无招募）。
func _begin_run() -> void:
	RunManager.start_run()
	_deploy_current_roster()

# 收集 roster 全员 id 提交部署（A 全员自动部署）。
func _deploy_current_roster() -> void:
	var ids: Array = []
	for c in RunManager.get_roster():
		ids.append((c as CrewDefinition).id)
	RunManager.confirm_deploy(ids)

# 三选一招募卡。候选为空 → 跳过招募直接部署下一岛。
func _show_recruit_offers() -> void:
	var offers := RunManager.get_recruit_offers()
	if offers.is_empty():
		_deploy_current_roster()
		return
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	add_child(box)
	var title := Label.new()
	title.text = "选择一名船员加入"
	box.add_child(title)
	for o in offers:
		var crew := o as CrewDefinition
		var btn := Button.new()
		btn.text = "%s · %s · %s" % [crew.unit_class, crew.display_name, crew.battle_cry]
		btn.pressed.connect(_on_recruit_chosen.bind(crew.id))
		box.add_child(btn)

func _on_recruit_chosen(unit_id: String) -> void:
	RunManager.confirm_recruit(unit_id)
	_deploy_current_roster()

# run-end：出航成功 / 全员阵亡 + 重新出航。
func _show_run_end() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	add_child(box)
	var result := Label.new()
	result.text = "出航成功!" if RunManager.last_run_won else "全员阵亡…"
	box.add_child(result)
	var restart := Button.new()
	restart.text = "重新出航"
	restart.pressed.connect(_on_restart_pressed)
	box.add_child(restart)

func _on_restart_pressed() -> void:
	RunManager.start_run()
	_deploy_current_roster()
```

- [ ] **Step 2: 写场景 scenes/RouteScene.tscn**

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://src/ui/route_scene.gd" id="1"]

[node name="RouteScene" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
script = ExtResource("1")
```

- [ ] **Step 3: 导入并验证脚本/场景编译**

Run: `godot --headless --import`
Expected: 无 parse error；`RouteScene` 全局类名注册成功（无 "Could not resolve class" / 脚本错误输出）。

- [ ] **Step 4: 提交**

```bash
git add scenes/RouteScene.tscn src/ui/route_scene.gd
git commit -m "feat(route): whitebox RouteScene hub (recruit cards + run-end)

Story: run-loop-skeleton (A)"
```

---

### Task 6: SceneManager preload 接线 + main_scene 切 RouteScene

把 SceneManager 改用 `preload` 常量（script 型 autoload 无法在 Inspector 赋 `@export`，preload 是确定性、可headless 的等价做法），并将启动主场景改为 RouteScene。

**Files:**
- Modify: `src/autoloads/scene_manager.gd`
- Modify: `project.godot`

**Interfaces:**
- Consumes: `scenes/BattleScene.tscn`（已存在）、`scenes/RouteScene.tscn`（Task 5）。
- Produces: `SceneManager.goto_battle()/goto_route()` 实际切到对应场景；游戏启动进 RouteScene（IDLE→起航）。

- [ ] **Step 1: 改 scene_manager.gd 为 preload 常量**

把 `src/autoloads/scene_manager.gd` 替换为：

```gdscript
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
```

- [ ] **Step 2: 改 project.godot 主场景**

把 `project.godot` 中 `run/main_scene="res://scenes/BattleScene.tscn"` 改为：

```
run/main_scene="res://scenes/RouteScene.tscn"
```

- [ ] **Step 3: 导入验证（无 parse / 循环加载错误）**

Run: `godot --headless --import`
Expected: 无错误（preload 解析到两张 PackedScene；RunManager 默认导航接缝转调成功）。

- [ ] **Step 4: 运行全单测套件确认未回归**

Run: `godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests`
Expected: 全绿（既有 244 + 本子项目新增；单测经导航接缝 no-op 不触发真实切场景）。

- [ ] **Step 5: 提交**

```bash
git add src/autoloads/scene_manager.gd project.godot
git commit -m "feat(scene): SceneManager preloads scenes; boot into RouteScene

Story: run-loop-skeleton (A)"
```

---

### Task 7: BattleScene roster 驱动部署 + 清临时 hack

删硬编码起始编制与 RunManager 断连 hack，改读 `RunManager.get_pending_deploy()` 自动排位部署；移除 BattleResultOverlay 节点与引用（run 流程由 RouteScene 接管）。

**Files:**
- Modify: `src/battle/battle_scene.gd`
- Modify: `scenes/BattleScene.tscn`

**Interfaces:**
- Consumes: `RunManager.get_pending_deploy() -> Array[CrewDefinition]`、`BattleMap.get_deploy_zone_available() -> Array[Vector2i]`、`BattleMap.deploy_crew(defs, positions)`。
- Produces: 战斗按 run roster 部署；BattleScene 不再断连 RunManager；胜负由 RunManager+RouteScene 接管。

- [ ] **Step 1: 改 battle_scene.gd**

替换 `src/battle/battle_scene.gd` 第 22-24 行（`_BOOTSTRAP_*` 常量）为（删常量，留注释占位）：

```gdscript
# 出场名单由 RunManager.get_pending_deploy() 提供（route confirm_deploy 写入）。
```

在 `_ready()` 中删除这段临时断连 hack（第 35-37 行）：
```gdscript
	# TEMP：航线/招募元层未做 → 断开 RunManager 的胜利跳转（否则 goto_route 因 route_scene 未赋值 assert 崩）。
	if EventBus.battle_won.is_connected(RunManager._on_battle_won):
		EventBus.battle_won.disconnect(RunManager._on_battle_won)
```

删除 `_battle_result_overlay` 的 @onready（第 20 行）与其 `setup()` 调用（第 40 行 `_battle_result_overlay.setup()`）。

把 `_ready()` 中 `_deploy_starting_crew()`（第 43 行）改为 `_deploy_run_crew()`。

把 `_deploy_starting_crew()` 函数（第 47-55 行）整体替换为：

```gdscript
# 按 run roster 部署：读 pending_deploy → 取前 N 个，自动排入部署区前 N 个可用格。
# N = min(出场名单数, 可用部署格数)。A 全员自动部署，忽略 DEPLOY_LIMIT（手动选归子项目 B）。
func _deploy_run_crew() -> void:
	var pending := RunManager.get_pending_deploy()
	if pending.is_empty():
		return
	var cells := _battle_map.get_deploy_zone_available()
	var n: int = min(pending.size(), cells.size())
	if n <= 0:
		return
	var defs: Array = []
	var positions: Array = []
	for i in n:
		defs.append(pending[i])
		positions.append(cells[i])
	_battle_map.deploy_crew(defs, positions)
```

- [ ] **Step 2: 改 scenes/BattleScene.tscn 移除 BattleResultOverlay 节点**

删除 `scenes/BattleScene.tscn` 第 68-69 行的节点块：
```
[node name="BattleResultOverlay" type="Control" parent="BurstLayer"]
script = ExtResource("16_ro")
```
并删除第 18 行该脚本的 ext_resource 声明：
```
[ext_resource type="Script" path="res://src/ui/battle_result_overlay.gd" id="16_ro"]
```
（保留 `src/ui/battle_result_overlay.gd` 文件本身，留作未来单场/调试。BurstLayer 节点保留。）

- [ ] **Step 3: 导入验证**

Run: `godot --headless --import`
Expected: 无 parse / 缺失 ext_resource 错误（id "16_ro" 已无引用）。

- [ ] **Step 4: 运行全单测套件确认未回归**

Run: `godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests`
Expected: 全绿。

- [ ] **Step 5: 提交**

```bash
git add src/battle/battle_scene.gd scenes/BattleScene.tscn
git commit -m "feat(battle): roster-driven deploy; drop bootstrap/result-overlay hacks

Story: run-loop-skeleton (A)"
```

---

## F5 验收（ADVISORY，全部 Task 后人工跑一遍）

在 Godot 编辑器按 F5 运行，对照 spec 验收标准：
- **AC-1**：启动 → 自动开 run，进 ISLAND_0 战斗，场上有阿斩+梅莉。
- **AC-2**：打赢一场（非末岛）→ RouteScene 显示 3 张候选卡（职业·名·台词，职业互不相同）。
- **AC-3**：点一张 → 该 crew 入队 → 下一岛战斗场上可见新队员。
- **AC-4**：连打到第 5 岛打赢 → run-end "出航成功!" + [重新出航]。
- **AC-5**：任一场打输 → run-end "全员阵亡…" + [重新出航]；不崩。
- **AC-6**：[重新出航] → 回到 ISLAND_0 重来。
- **AC-7**：招募池抽干（可用=0）→ 跳过招募直接进下一岛，不崩。

---

## Self-Review

**Spec coverage:**
- 流程 IDLE/RECRUITING/RUN_END 分支 → Task 5 RouteScene。✓
- start_run 填 starting crew + 重置 → Task 1。✓
- get_recruit_offers 全部不变量（①pool ②非roster ③非excluded ④≤3 ⑤distinct ⑥<3 ⑦=0）→ Task 2。✓
- confirm_recruit（入队 + 其余排除 + DEPLOYING）→ Task 2。✓
- confirm_deploy（pending + island++ + BATTLE）+ get_pending_deploy → Task 3。✓
- battle_lost → RUN_END + run_completed(false)；battle_won 非末岛→RECRUITING / 末岛→RUN_END+run_completed(true)；末岛与失败均切 RouteScene 以显示 run-end（spec 隐含 AC-4/AC-5）→ Task 1。✓
- BattleScene roster 驱动部署 + 删 hack + 移除 BattleResultOverlay → Task 7。✓
- RouteScene + SceneManager 接线 + main_scene → Task 5/6。✓
- 补 pool crew + 校验 → Task 4。✓
- 测试隔离（autoload before/after 复位 + seed）→ Task 1 before_test/after_test。✓

**偏离 spec 的实现决策（已记录理由）：**
1. **导航用 RunManager 内可注入 Callable 接缝**（而非直连 SceneManager）：使 confirm_deploy / 胜负流转可在不触发真实切场景下单测（spec 测试策略要求测这些转换且 autoload 单态须可复位）。默认转调 SceneManager，行为不变。
2. **SceneManager 用 preload 常量**（而非 @export+Inspector 赋值）：script 型 autoload 无法在 Inspector 序列化 @export 值；preload 是确定性、headless 可跑的等价做法，不引入场景化 autoload 的额外文件与编辑器步骤。
3. **末岛胜利与失败都 goto_route**：原 `_on_battle_won` 末岛分支不切场景（旧靠 BattleResultOverlay 原地显示）；移除 overlay 后 run-end 必须由 RouteScene 呈现，故补 goto_route。

**Placeholder scan:** 无 TBD/TODO/"add error handling" 等占位；每个代码步骤含完整代码。✓

**Type consistency:** `_goto_battle/_goto_route`、`pending_deploy`、`get_pending_deploy`、`_last_offers`、`_excluded_offers`、`last_run_won`、`confirm_recruit/confirm_deploy/get_recruit_offers` 在 Task 1→2→3→5→7 间签名一致；crew id 全程 String；offers/roster 元素 CrewDefinition。✓

---

## Execution Handoff

见下方对话中的执行方式选择。

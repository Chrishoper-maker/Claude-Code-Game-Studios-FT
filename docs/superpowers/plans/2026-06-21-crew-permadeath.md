# 船员永久死亡 Implementation Plan

> **For agentic workers:** 用 superpowers:test-driven-development 逐步实现。Steps 用 `- [ ]`。

**Goal:** 我方船员战斗中被击倒后永久移出 roster（本 run 不再部署/招募），并记录供未来阵亡通知卡。

**Architecture:** `crew_member_downed` 改携持久 String crew id；BattleScene 桥接 `unit_downed`（我方→发 crew_member_downed）；RunManager 收到后移出 roster + 记 `_downed_this_run`(String) + 加 `_excluded_offers`。不改胜负判定/视觉。

**Tech Stack:** Godot 4.6.3 / GDScript / GdUnit4。

## Global Constraints

- Godot 4.6.3；测试前必 `godot --headless --import`；二进制 `/Applications/Godot.app/Contents/MacOS/Godot`。
- 静态类型纪律：禁 `var x := <Variant 表达式>`，用显式标注 / `as T`。
- 中文对话；标识符英文。trunk-based 在 main。
- 提交 Conventional Commits，body 带 `Story: route-recruitment (permadeath)`，结尾 `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`。

---

### Task 1: 船员永久死亡（信号改签名 + RunManager 移除 + BattleScene 桥接）

**Files:**
- Modify: `src/autoloads/event_bus.gd`（`crew_member_downed` 签名 int→String）
- Modify: `src/autoloads/run_manager.gd`（`_downed_this_run` 改 Array[String]；`_on_crew_member_downed` 移除/排除）
- Modify: `src/battle/battle_scene.gd`（_ready 连 unit_downed + `_relay_crew_downed`）
- Modify: `tests/unit/run_manager/run_manager_test.gd`（既有 `test_crew_downed_recorded_once` 改 String + 加 roster 移除断言）
- Test: `tests/integration/permadeath/permadeath_test.gd`（新建，AC-4/5）

**Interfaces:**
- Consumes: `EventBus.unit_downed(battle_id:int)`、`TurnManager.get_unit(id)->UnitInstance`、`UnitInstance.get_unit_id()->String`、`UnitInstance.definition.faction`、`BattleResolution.resolve_unit_downed(id:int)`、`RunManager.roster/_excluded_offers/get_recruit_offers/start_run/confirm_deploy`。
- Produces: `EventBus.crew_member_downed(crew_id:String)`；`RunManager._on_crew_member_downed(crew_id:String)` 永久移除语义；`BattleScene._relay_crew_downed(battle_id:int)`。

- [ ] **Step 1: 改既有单测 + 写新单测/集成测试（RED）**

在 `tests/unit/run_manager/run_manager_test.gd` 替换 `test_crew_downed_recorded_once`：

```gdscript
func test_crew_downed_recorded_once() -> void:
	var first_id: String = (RunManager.roster[0] as CrewDefinition).id
	var before := RunManager.roster.size()
	RunManager._on_crew_member_downed(first_id)
	RunManager._on_crew_member_downed(first_id)
	assert_int(RunManager._downed_this_run.size()).is_equal(1)
	assert_bool(RunManager._downed_this_run.has(first_id)).is_true()
	assert_int(RunManager.roster.size()).is_equal(before - 1)   # 永久移除
	assert_bool(RunManager._excluded_offers.has(first_id)).is_true()

func test_downed_crew_not_offered_again() -> void:
	# 标记一个 pool 船员阵亡后，清空其余排除以便观察 → offers 不含它
	var pool_id := "crew_gunner_01"
	RunManager._on_crew_member_downed(pool_id)
	var offers := RunManager.get_recruit_offers()
	for o in offers:
		assert_str((o as CrewDefinition).id).is_not_equal(pool_id)
```

创建 `tests/integration/permadeath/permadeath_test.gd`：

```gdscript
# 永久死亡集成测试：BattleScene 桥接 unit_downed→crew_member_downed→RunManager 移出 roster。
extends GdUnitTestSuite

func before_test() -> void:
	RunManager._goto_battle = func() -> void: pass
	RunManager._goto_route  = func() -> void: pass
	RunManager.start_run()
	RunManager._rng.seed = 20260621

func after_test() -> void:
	RunManager._goto_battle = RunManager._default_goto_battle
	RunManager._goto_route  = RunManager._default_goto_route

func _boot_battle() -> BattleScene:
	var ids: Array[String] = []
	for c in RunManager.get_roster():
		ids.append(c.id)
	RunManager.confirm_deploy(ids)
	var scene: BattleScene = auto_free(preload("res://scenes/BattleScene.tscn").instantiate())
	add_child(scene)
	return scene

# AC-4：我方被击倒 → 永久移出 roster。
func test_ally_downed_removed_from_roster() -> void:
	var scene := _boot_battle()
	var ally_id: int = scene._turn_manager.get_alive_allies()[0]
	var crew_id: String = scene._turn_manager.get_unit(ally_id).get_unit_id()
	var before := RunManager.roster.size()
	scene._battle_resolution.resolve_unit_downed(ally_id)
	assert_int(RunManager.roster.size()).is_equal(before - 1)
	for c in RunManager.get_roster():
		assert_str((c as CrewDefinition).id).is_not_equal(crew_id)

# AC-5：敌方被击倒 → roster 不变。
func test_enemy_downed_does_not_touch_roster() -> void:
	var scene := _boot_battle()
	var enemy_id: int = scene._turn_manager.get_alive_enemies()[0]
	var before := RunManager.roster.size()
	scene._battle_resolution.resolve_unit_downed(enemy_id)
	assert_int(RunManager.roster.size()).is_equal(before)
```

- [ ] **Step 2: 跑测试确认失败（RED）**

```bash
cd "/Users/chris/Documents/First Codex/my-game"
"/Applications/Godot.app/Contents/MacOS/Godot" --headless --import 2>&1 | tail -2
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/integration/permadeath -a res://tests/unit/run_manager 2>&1 | grep -iE "PASSED|FAILED|FAILURE|Statistics|error" | tail -15
```
Expected: 新测试 + 改后单测失败（roster 未移除 / 桥接未发信号）。

- [ ] **Step 3: 改 crew_member_downed 信号签名**

`src/autoloads/event_bus.gd` 第 50 行：
```gdscript
signal crew_member_downed(crew_id: String)
```
（原 `(unit_id: int)`）

- [ ] **Step 4: RunManager 永久移除**

`src/autoloads/run_manager.gd`：把第 43 行
```gdscript
var _downed_this_run: Array[int] = []     # 本 run 永久阵亡的运行时 id（R1 公式须排除）
```
改为
```gdscript
var _downed_this_run: Array[String] = []  # 本 run 永久阵亡的持久 crew id（roster 移除 + 招募排除）
```

把 `_on_crew_member_downed`（第 183-185 行）整体替换为：
```gdscript
# 我方永久死亡：移出 roster（本 run 不再部署）+ 记录 + 排除招募（不复活）。crew_id = 持久身份。
func _on_crew_member_downed(crew_id: String) -> void:
	if _downed_this_run.has(crew_id):
		return
	_downed_this_run.append(crew_id)
	for i in range(roster.size() - 1, -1, -1):
		if roster[i].id == crew_id:
			roster.remove_at(i)
	if not _excluded_offers.has(crew_id):
		_excluded_offers.append(crew_id)
```

- [ ] **Step 5: BattleScene 桥接**

`src/battle/battle_scene.gd` 的 `_ready()`，在第 38 行 `EventBus.battle_lost.connect(_battle_map.on_battle_lost)` 之后加：
```gdscript
	EventBus.unit_downed.connect(_relay_crew_downed)   # 我方击倒 → 永久死亡（crew_member_downed）
```

并在 `_faction_of` 之前（或文件末尾辅助区）加方法：
```gdscript
# 桥：unit_downed(battle_id) → 若我方 → crew_member_downed(持久 id)（RunManager 永久移除）。
func _relay_crew_downed(battle_id: int) -> void:
	var inst := _turn_manager.get_unit(battle_id)
	if inst != null and inst.definition.faction == "crew":
		EventBus.crew_member_downed.emit(inst.get_unit_id())
```

- [ ] **Step 6: 跑目标套件确认通过（GREEN）**

```bash
cd "/Users/chris/Documents/First Codex/my-game"
"/Applications/Godot.app/Contents/MacOS/Godot" --headless --import 2>&1 | tail -2
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/integration/permadeath -a res://tests/unit/run_manager 2>&1 | grep -iE "Statistics|FAILURE|error" | tail -8
```
Expected: 全 PASSED，0 failures。

- [ ] **Step 7: 全量回归**

```bash
cd "/Users/chris/Documents/First Codex/my-game"
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests 2>&1 | grep -iE "Overall Summary|Executed test|Abnormal|SCRIPT ERROR" | tail -6
```
Expected: `Overall Summary: 273 test cases | 0 errors | 0 failures | ... | 0 orphans`（271 + 2 集成；run_manager 套件净 +1，原 7→... 实为替换1+新增1=+1，故 271+2集成+1单测=274）。以实际运行为准，关键是 0 failures/errors/orphans 且较前仅净增新测试数。

- [ ] **Step 8: 提交**

```bash
cd "/Users/chris/Documents/First Codex/my-game"
git add src/autoloads/event_bus.gd src/autoloads/run_manager.gd src/battle/battle_scene.gd tests/unit/run_manager/run_manager_test.gd tests/integration/permadeath/
git commit -F - <<'EOF'
feat(run): crew permadeath — downed allies removed from roster

crew_member_downed now carries the persistent crew id (String) instead
of the unused per-battle int. BattleScene bridges unit_downed → emits
crew_member_downed for crew-faction units; RunManager permanently
removes the crew from roster, records it in _downed_this_run, and adds
it to _excluded_offers (no resurrection via recruit). Win/loss and
visuals unchanged. Downed-notification card (UI) deferred.

Story: route-recruitment (permadeath)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
git log --oneline -1
```

## Self-Review

- Spec Rule 1 信号改签名 → Step 3。Rule 2 桥接 → Step 5。Rule 3 移除/记录/排除 → Step 4。✓
- AC-1/2/3 → Step 1 单测（test_crew_downed_recorded_once 改 + test_downed_crew_not_offered_again）。AC-4/5 → permadeath_test。AC-6 → Step 7。✓
- Placeholder：无；每步含完整代码/命令。✓
- 类型：`_downed_this_run: Array[String]`；`crew_id: String` 全程；测试用 `as CrewDefinition`/显式 String 标注，规避 Variant 推断。✓
- 风险：移除 roster 不影响 battlefield 胜负（get_alive_* 走 TurnManager）；run_loop AC-4/5 不 down crew，快照不变，仍绿。✓

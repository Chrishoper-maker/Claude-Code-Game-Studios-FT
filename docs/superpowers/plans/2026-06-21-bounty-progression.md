# 悬赏成长系统 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 打赢末岛（通关）解锁下一名 `unlockable` 船员并跨会话持久化；已解锁者进入后续 run 的招募池。

**Architecture:** 新增 `MetaProgress` autoload（跨 run 持久化解锁集，存 `user://meta.json`，与 RunManager 的 per-run 状态解耦）。RunManager 末岛胜利触发 `MetaProgress.unlock_next()`；`get_recruit_offers` 纳入已解锁 unlockable。新增 3 名 unlockable 船员数据。

**Tech Stack:** Godot 4.6.3 / GDScript / GdUnit4。

## Global Constraints

- 引擎 Godot 4.6.3；测试前必 `godot --headless --import`；二进制 `/Applications/Godot.app/Contents/MacOS/Godot`。
- 静态类型纪律：禁 `var x := <Variant 表达式>`；用显式标注 / `as T`。typed Array 字面量赋给 typed 属性须先建 typed 局部（`var ids: Array[String] = [...]`）。
- autoload 脚本**不**声明 class_name（注册名即全局访问，否则 "hides an autoload"）。
- 中文对话；标识符英文。trunk-based 在 main。
- 持久化方法名用 `save_progress()/load_progress()`（避免与 GDScript 全局 `load()` 冲突）。
- 提交 Conventional Commits，body 带 `Story: bounty-progression (#14)`，结尾 `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`。

---

### Task 1: 3 名 unlockable 船员数据

**Files:**
- Create: `assets/data/units/crew_gunner_03.tres`
- Create: `assets/data/units/crew_medic_02.tres`
- Create: `assets/data/units/crew_swordsman_04.tres`
- Test: `tests/unit/data/unlockable_crew_data_test.gd`

**Interfaces:**
- Consumes: `UnitDataManager.get_all_units() -> Array[UnitDefinition]`（目录扫描已自动纳入新 .tres）；`CrewDefinition`（extends UnitDefinition）字段 `id/display_name/faction/unit_class/max_hp/move_range/attack_range/base_damage/class_action_id/recruit_pool_tier`。
- Produces: 3 个 `recruit_pool_tier="unlockable"` 的 CrewDefinition，id = `crew_gunner_03 / crew_medic_02 / crew_swordsman_04`。

- [ ] **Step 1: 写失败测试**

创建 `tests/unit/data/unlockable_crew_data_test.gd`：

```gdscript
# 校验 3 名 unlockable 船员存在且 tier 正确（悬赏成长解锁池）。
extends GdUnitTestSuite

const EXPECTED: Array[String] = ["crew_gunner_03", "crew_medic_02", "crew_swordsman_04"]

func test_three_unlockable_crew_exist_with_tier() -> void:
	var found: Array[String] = []
	for def in UnitDataManager.get_all_units():
		if def is CrewDefinition and (def as CrewDefinition).recruit_pool_tier == "unlockable":
			found.append((def as CrewDefinition).id)
	for id in EXPECTED:
		assert_bool(found.has(id)).is_true()
	assert_int(found.size()).is_equal(EXPECTED.size())

func test_unlockable_crew_have_valid_class_action() -> void:
	for id in EXPECTED:
		var def := UnitDataManager.get_unit(id)
		assert_bool(def is CrewDefinition).is_true()
		assert_str((def as CrewDefinition).class_action_id).is_not_equal("")
```

- [ ] **Step 2: 跑测试确认失败（RED）**

```bash
cd "/Users/chris/Documents/First Codex/my-game"
"/Applications/Godot.app/Contents/MacOS/Godot" --headless --import 2>&1 | tail -2
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/data/unlockable_crew_data_test.gd 2>&1 | grep -iE "FAILED|Statistics" | tail -5
```
Expected: 失败（unlockable 船员尚不存在，found 为空）。

- [ ] **Step 3: 创建 3 个 .tres**

`assets/data/units/crew_gunner_03.tres`：
```
[gd_resource type="Resource" script_class="CrewDefinition" load_steps=2 format=3]

[ext_resource type="Script" path="res://src/data/crew_definition.gd" id="1"]

[resource]
script = ExtResource("1")
id = "crew_gunner_03"
display_name = "重炮·铁牙"
faction = "crew"
unit_class = "gunner"
max_hp = 7
move_range = 2
attack_range = 3
base_damage = 3
class_action_id = "cannon"
title = "悬赏解锁·炮手"
battle_cry = "尝尝这一发！"
persona_line = "悬赏越高，我的炮越响。"
recruit_pool_tier = "unlockable"
portrait_id = "gunner_03"
model_id = "whitebox_gunner"
```

`assets/data/units/crew_medic_02.tres`：
```
[gd_resource type="Resource" script_class="CrewDefinition" load_steps=2 format=3]

[ext_resource type="Script" path="res://src/data/crew_definition.gd" id="1"]

[resource]
script = ExtResource("1")
id = "crew_medic_02"
display_name = "圣手·白鹭"
faction = "crew"
unit_class = "medic"
max_hp = 8
move_range = 3
attack_range = 1
base_damage = 2
class_action_id = "heal"
title = "悬赏解锁·医师"
battle_cry = "别死在我面前！"
persona_line = "我见过太多人倒下，不差你一个。"
recruit_pool_tier = "unlockable"
portrait_id = "medic_02"
model_id = "whitebox_medic"
```

`assets/data/units/crew_swordsman_04.tres`：
```
[gd_resource type="Resource" script_class="CrewDefinition" load_steps=2 format=3]

[ext_resource type="Script" path="res://src/data/crew_definition.gd" id="1"]

[resource]
script = ExtResource("1")
id = "crew_swordsman_04"
display_name = "居合·霜"
faction = "crew"
unit_class = "swordsman"
max_hp = 10
move_range = 3
attack_range = 1
base_damage = 3
class_action_id = "slash"
title = "悬赏解锁·剑客"
battle_cry = "一刀，足矣。"
persona_line = "悬赏令上的名字，迟早是我的。"
recruit_pool_tier = "unlockable"
portrait_id = "swordsman_04"
model_id = "whitebox_swordsman"
```

- [ ] **Step 4: 跑测试确认通过（GREEN）**

```bash
cd "/Users/chris/Documents/First Codex/my-game"
"/Applications/Godot.app/Contents/MacOS/Godot" --headless --import 2>&1 | tail -2
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/data/unlockable_crew_data_test.gd 2>&1 | grep -iE "Statistics|FAILED" | tail -5
```
Expected: 2/2 PASSED。

- [ ] **Step 5: 提交**

```bash
cd "/Users/chris/Documents/First Codex/my-game"
git add assets/data/units/crew_gunner_03.tres assets/data/units/crew_medic_02.tres assets/data/units/crew_swordsman_04.tres assets/data/units/*.import tests/unit/data/unlockable_crew_data_test.gd
git commit -F - <<'EOF'
feat(data): 3 unlockable crew for bounty progression

crew_gunner_03 / crew_medic_02 / crew_swordsman_04 (recruit_pool_tier
"unlockable"), stats reuse existing strength bands. Consumed by the
bounty unlock system.

Story: bounty-progression (#14)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

### Task 2: MetaProgress autoload（持久化解锁集）

**Files:**
- Create: `src/autoloads/meta_progress.gd`
- Modify: `project.godot`（[autoload] 加 MetaProgress）
- Test: `tests/unit/meta_progress/meta_progress_test.gd`
- Test: `tests/integration/meta_progress/meta_progress_persistence_test.gd`

**Interfaces:**
- Consumes: `UnitDataManager.get_all_units()`；`CrewDefinition.recruit_pool_tier/id`；`FileAccess`/`JSON`/`DirAccess`。Task 1 的 3 个 unlockable crew（使 `get_unlock_order` 非空）。
- Produces（全局 `MetaProgress`）：`unlocked_crew_ids: Array[String]`、`_save_path: String`、`get_unlock_order() -> Array[String]`、`unlock_next() -> String`、`is_unlocked(crew_id: String) -> bool`、`to_dict() -> Dictionary`、`from_dict(d: Dictionary)`、`save_progress()`、`load_progress()`。

- [ ] **Step 1: 写失败测试（单元 + 集成）**

创建 `tests/unit/meta_progress/meta_progress_test.gd`：

```gdscript
# MetaProgress 解锁逻辑 + 序列化（无文件 I/O 的纯核心）。
extends GdUnitTestSuite

const TMP := "user://test_meta_unit.json"

func before_test() -> void:
	MetaProgress.unlocked_crew_ids.clear()
	MetaProgress._save_path = TMP

func after_test() -> void:
	MetaProgress.unlocked_crew_ids.clear()
	MetaProgress._save_path = "user://meta.json"
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(TMP)

func test_unlock_next_follows_lexicographic_order() -> void:
	var order := MetaProgress.get_unlock_order()
	assert_int(order.size()).is_greater_equal(3)
	assert_str(MetaProgress.unlock_next()).is_equal(order[0])
	assert_bool(MetaProgress.is_unlocked(order[0])).is_true()
	assert_str(MetaProgress.unlock_next()).is_equal(order[1])

func test_unlock_next_empty_when_all_unlocked() -> void:
	for _i in MetaProgress.get_unlock_order().size():
		MetaProgress.unlock_next()
	var before := MetaProgress.unlocked_crew_ids.size()
	assert_str(MetaProgress.unlock_next()).is_equal("")
	assert_int(MetaProgress.unlocked_crew_ids.size()).is_equal(before)

func test_to_from_dict_roundtrip() -> void:
	var ids: Array[String] = ["a", "b"]
	MetaProgress.unlocked_crew_ids = ids
	var d := MetaProgress.to_dict()
	MetaProgress.unlocked_crew_ids.clear()
	MetaProgress.from_dict(d)
	assert_array(MetaProgress.unlocked_crew_ids).contains_exactly(["a", "b"])
```

创建 `tests/integration/meta_progress/meta_progress_persistence_test.gd`：

```gdscript
# MetaProgress 文件往返（user:// 临时文件）。
extends GdUnitTestSuite

const TMP := "user://test_meta_persist.json"

func before_test() -> void:
	MetaProgress.unlocked_crew_ids.clear()
	MetaProgress._save_path = TMP
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(TMP)

func after_test() -> void:
	MetaProgress.unlocked_crew_ids.clear()
	MetaProgress._save_path = "user://meta.json"
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(TMP)

func test_save_then_load_roundtrip() -> void:
	var ids: Array[String] = ["crew_gunner_03", "crew_medic_02"]
	MetaProgress.unlocked_crew_ids = ids
	MetaProgress.save_progress()
	MetaProgress.unlocked_crew_ids.clear()
	MetaProgress.load_progress()
	assert_array(MetaProgress.unlocked_crew_ids).contains_exactly(["crew_gunner_03", "crew_medic_02"])

func test_load_missing_file_yields_empty() -> void:
	var ids: Array[String] = ["x"]
	MetaProgress.unlocked_crew_ids = ids
	MetaProgress.load_progress()   # TMP 已确保不存在
	assert_int(MetaProgress.unlocked_crew_ids.size()).is_equal(0)
```

- [ ] **Step 2: 跑测试确认失败（RED）**

```bash
cd "/Users/chris/Documents/First Codex/my-game"
"/Applications/Godot.app/Contents/MacOS/Godot" --headless --import 2>&1 | tail -2
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/meta_progress -a res://tests/integration/meta_progress 2>&1 | grep -iE "FAILED|error|Statistics|SCRIPT ERROR" | tail -8
```
Expected: 失败（无 `MetaProgress` 全局 / 方法缺失）。

- [ ] **Step 3: 创建 MetaProgress 脚本**

`src/autoloads/meta_progress.gd`：

```gdscript
# 跨 run 持久化的 meta 解锁状态（autoload；不被 start_run 清除）。悬赏成长唯一持久层。
# 只存"已解锁 unlockable 船员 id 集"，非通用存档（进行中 run 不持久化）。
# （autoload 脚本不声明 class_name：注册名 MetaProgress 即全局单例访问）
extends Node

var unlocked_crew_ids: Array[String] = []   # 已解锁的 unlockable 船员 id（持久）
var _save_path: String = "user://meta.json" # 存盘路径（测试可注入临时路径）

func _ready() -> void:
	load_progress()

# 固定解锁顺序：全部 unlockable crew id 字典序升序（确定性，不依赖扫描顺序）。
func get_unlock_order() -> Array[String]:
	var ids: Array[String] = []
	for def in UnitDataManager.get_all_units():
		if def is CrewDefinition and (def as CrewDefinition).recruit_pool_tier == "unlockable":
			ids.append((def as CrewDefinition).id)
	ids.sort()
	return ids

# 解锁顺序中第一个未解锁者：append + 存盘 + 返回其 id；全已解锁返 ""（无副作用、不写盘）。
func unlock_next() -> String:
	for crew_id in get_unlock_order():
		if not unlocked_crew_ids.has(crew_id):
			unlocked_crew_ids.append(crew_id)
			save_progress()
			return crew_id
	return ""

func is_unlocked(crew_id: String) -> bool:
	return unlocked_crew_ids.has(crew_id)

func to_dict() -> Dictionary:
	return {"unlocked_crew_ids": unlocked_crew_ids.duplicate()}

func from_dict(d: Dictionary) -> void:
	unlocked_crew_ids.clear()
	var arr: Array = d.get("unlocked_crew_ids", [])
	for v in arr:
		unlocked_crew_ids.append(str(v))

func save_progress() -> void:
	var f := FileAccess.open(_save_path, FileAccess.WRITE)
	if f == null:
		push_error("MetaProgress.save_progress: 无法写入 %s" % _save_path)
		return
	f.store_string(JSON.stringify(to_dict()))
	f.close()

func load_progress() -> void:
	if not FileAccess.file_exists(_save_path):
		unlocked_crew_ids.clear()
		return
	var f := FileAccess.open(_save_path, FileAccess.READ)
	if f == null:
		push_error("MetaProgress.load_progress: 无法读取 %s" % _save_path)
		unlocked_crew_ids.clear()
		return
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		from_dict(parsed as Dictionary)
	else:
		push_error("MetaProgress.load_progress: 解析失败，置空")
		unlocked_crew_ids.clear()
```

- [ ] **Step 4: 注册 autoload**

`project.godot` 的 `[autoload]` 段，在 `UnitDataManager=...` 行后插入一行：
```
MetaProgress="*res://src/autoloads/meta_progress.gd"
```
使该段为：
```
[autoload]

EventBus="*res://src/autoloads/event_bus.gd"
UnitDataManager="*res://src/autoloads/unit_data_manager.gd"
MetaProgress="*res://src/autoloads/meta_progress.gd"
MapDataManager="*res://src/autoloads/map_data_manager.gd"
RunManager="*res://src/autoloads/run_manager.gd"
SceneManager="*res://src/autoloads/scene_manager.gd"
```

- [ ] **Step 5: 跑测试确认通过（GREEN）**

```bash
cd "/Users/chris/Documents/First Codex/my-game"
"/Applications/Godot.app/Contents/MacOS/Godot" --headless --import 2>&1 | tail -2
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/meta_progress -a res://tests/integration/meta_progress 2>&1 | grep -iE "Statistics|FAILED|SCRIPT ERROR" | tail -8
```
Expected: 单元 3/3 + 集成 2/2 全 PASSED。

- [ ] **Step 6: 提交**

```bash
cd "/Users/chris/Documents/First Codex/my-game"
git add src/autoloads/meta_progress.gd project.godot tests/unit/meta_progress/ tests/integration/meta_progress/
git commit -F - <<'EOF'
feat(meta): MetaProgress autoload persists unlocked crew

Cross-run unlock set persisted to user://meta.json (decoupled from
RunManager's per-run state). unlock_next() unlocks the lexicographically
next unlockable crew; to_dict/from_dict + save_progress/load_progress
handle (de)serialization with graceful missing/corrupt-file fallback.

Story: bounty-progression (#14)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

### Task 3: RunManager 集成（解锁触发 + 招募池）

**Files:**
- Modify: `src/autoloads/run_manager.gd`（`_on_battle_won` 末岛分支 + `get_recruit_offers` 过滤）
- Modify: `tests/unit/run_manager/run_manager_test.gd`（before_test 清 MetaProgress 保确定）
- Test: `tests/integration/bounty/bounty_test.gd`

**Interfaces:**
- Consumes: `MetaProgress.unlock_next()` / `is_unlocked(id)` / `get_unlock_order()` / `unlocked_crew_ids`；`RunManager.start_run/get_recruit_offers/_excluded_offers/current_island_index/ISLAND_COUNT_MAX/_goto_route`；`EventBus.battle_won/battle_lost`。
- Produces: 末岛胜利触发解锁；`get_recruit_offers` 纳入已解锁 unlockable。

- [ ] **Step 1: 写失败测试 + 既有测试隔离**

在 `tests/unit/run_manager/run_manager_test.gd` 的 `before_test`（`RunManager.start_run()` 之前）加一行清空 MetaProgress，使招募 offer 测试确定（无 unlockable 混入）：

```gdscript
	MetaProgress.unlocked_crew_ids.clear()
```
（加在 `before_test` 内、`RunManager.start_run()` 调用之前。其余不变。）

创建 `tests/integration/bounty/bounty_test.gd`：

```gdscript
# 悬赏成长集成：末岛胜触发解锁 + 招募池纳入已解锁 unlockable。
extends GdUnitTestSuite

const TMP := "user://test_bounty.json"

func before_test() -> void:
	RunManager._goto_battle = func() -> void: pass
	RunManager._goto_route  = func() -> void: pass
	MetaProgress.unlocked_crew_ids.clear()
	MetaProgress._save_path = TMP
	RunManager.start_run()
	RunManager._rng.seed = 20260621

func after_test() -> void:
	RunManager._goto_battle = RunManager._default_goto_battle
	RunManager._goto_route  = RunManager._default_goto_route
	MetaProgress.unlocked_crew_ids.clear()
	MetaProgress._save_path = "user://meta.json"
	if FileAccess.file_exists(TMP):
		DirAccess.remove_absolute(TMP)

# AC-4：末岛胜利解锁顺序首位。
func test_final_island_win_unlocks_next() -> void:
	RunManager.current_island_index = RunManager.ISLAND_COUNT_MAX - 1
	EventBus.battle_won.emit()
	assert_int(MetaProgress.unlocked_crew_ids.size()).is_equal(1)
	assert_str(MetaProgress.unlocked_crew_ids[0]).is_equal(MetaProgress.get_unlock_order()[0])

# AC-6：非末岛胜不解锁。
func test_nonfinal_win_does_not_unlock() -> void:
	RunManager.current_island_index = 0
	EventBus.battle_won.emit()
	assert_int(MetaProgress.unlocked_crew_ids.size()).is_equal(0)

# AC-6：战败不解锁。
func test_loss_does_not_unlock() -> void:
	RunManager.current_island_index = 2
	EventBus.battle_lost.emit()
	assert_int(MetaProgress.unlocked_crew_ids.size()).is_equal(0)

# AC-5：未解锁的 unlockable 不进 offer。
func test_locked_unlockable_not_offered() -> void:
	var offers := RunManager.get_recruit_offers()
	for o in offers:
		assert_str((o as CrewDefinition).recruit_pool_tier).is_not_equal("unlockable")

# AC-5：解锁后可进 offer（排除全部 pool 后只剩它）。
func test_unlocked_unlockable_can_be_offered() -> void:
	var target := "crew_gunner_03"
	var ids: Array[String] = [target]
	MetaProgress.unlocked_crew_ids = ids
	for def in UnitDataManager.get_all_units():
		if def is CrewDefinition and (def as CrewDefinition).recruit_pool_tier == "pool":
			RunManager._excluded_offers.append((def as CrewDefinition).id)
	var offers := RunManager.get_recruit_offers()
	var found := false
	for o in offers:
		if (o as CrewDefinition).id == target:
			found = true
	assert_bool(found).is_true()
```

- [ ] **Step 2: 跑测试确认失败（RED）**

```bash
cd "/Users/chris/Documents/First Codex/my-game"
"/Applications/Godot.app/Contents/MacOS/Godot" --headless --import 2>&1 | tail -2
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/integration/bounty 2>&1 | grep -iE "FAILED|Statistics" | tail -8
```
Expected：`test_final_island_win_unlocks_next` 与 `test_unlocked_unlockable_can_be_offered` 失败（未触发解锁 / offer 未纳入 unlockable）；`test_locked_unlockable_not_offered` 可能已通过（当前 offer 本就只 pool）。

- [ ] **Step 3: _on_battle_won 末岛分支触发解锁**

`src/autoloads/run_manager.gd` 的 `_on_battle_won`，在 `EventBus.run_completed.emit(true, …)` 与 `_goto_route.call()` 之间加一行：

```gdscript
func _on_battle_won() -> void:
	if current_island_index + 1 >= ISLAND_COUNT_MAX:
		last_run_won = true
		_set_run_phase(RunPhase.RUN_END)
		EventBus.run_completed.emit(true, current_island_index + 1, roster.duplicate())
		MetaProgress.unlock_next()   # 悬赏成长：通关解锁下一名 unlockable（含存盘）
		_goto_route.call()
		return
	_set_run_phase(RunPhase.RUN_RECRUITING)
	_goto_route.call()
```

- [ ] **Step 4: get_recruit_offers 纳入已解锁 unlockable**

`src/autoloads/run_manager.gd` 的 `get_recruit_offers` 中候选过滤条件：

```gdscript
			if (crew.recruit_pool_tier == "pool" \
					or (crew.recruit_pool_tier == "unlockable" and MetaProgress.is_unlocked(crew.id))) \
					and not roster_ids.has(crew.id) \
					and not _excluded_offers.has(crew.id):
				pool.append(crew)
```
（替换原 `if crew.recruit_pool_tier == "pool" \ ... ` 三行条件。）

- [ ] **Step 5: 跑目标套件确认通过（GREEN）**

```bash
cd "/Users/chris/Documents/First Codex/my-game"
"/Applications/Godot.app/Contents/MacOS/Godot" --headless --import 2>&1 | tail -2
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/integration/bounty -a res://tests/unit/run_manager 2>&1 | grep -iE "Statistics|FAILED|SCRIPT ERROR" | tail -8
```
Expected: bounty 5/5 + run_manager 全绿。

- [ ] **Step 6: 全量回归**

```bash
cd "/Users/chris/Documents/First Codex/my-game"
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests 2>&1 | grep -iE "Overall Summary|Executed test|Abnormal|SCRIPT ERROR" | tail -6
```
Expected: `Overall Summary: N test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 0 orphans`（N = 288 + 2(data) + 3(meta unit) + 2(meta persist) + 5(bounty) = 300）。以实际为准，关键 0 失败/错误/孤儿。

- [ ] **Step 7: 提交**

```bash
cd "/Users/chris/Documents/First Codex/my-game"
git add src/autoloads/run_manager.gd tests/unit/run_manager/run_manager_test.gd tests/integration/bounty/
git commit -F - <<'EOF'
feat(run): bounty unlock trigger + unlocked crew in recruit pool

Beating the final island calls MetaProgress.unlock_next() (persisted);
get_recruit_offers now includes unlockable crew once MetaProgress marks
them unlocked, subject to the same roster/excluded/distinct-class
invariants. run_manager_test before_test clears MetaProgress for
deterministic offer assertions.

Full suite green.

Story: bounty-progression (#14)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

## Self-Review

**Spec coverage:**
- Rule 1 MetaProgress（unlocked_crew_ids/_save_path/get_unlock_order/unlock_next/is_unlocked/to_dict/from_dict/save/load/_ready→load）→ Task 2 Step 3。✓（save/load 命名为 save_progress/load_progress，避全局 `load()` 冲突，见 Global Constraints）
- Rule 2 末岛胜触发 unlock_next → Task 3 Step 3。✓
- Rule 3 offer 纳入已解锁 unlockable → Task 3 Step 4。✓
- Rule 4 三名 unlockable 数据 → Task 1。✓
- AC-1 顺序解锁/全解锁返"" → Task 2 unit。AC-2 dict 往返 → Task 2 unit。AC-3 文件往返+缺文件 → Task 2 集成。AC-4 触发 → Task 3 bounty。AC-5 未解锁不出/解锁可出 → Task 3 bounty。AC-6 非末岛/战败不解锁 → Task 3 bounty。AC-7 全量 → Task 3 Step 6 + 既有测试隔离（run_manager before_test 清 MetaProgress）。✓
- 边界（全解锁返""/缺文件空/损坏置空/IO 失败 push_error/测试隔离/既有 offer 断言确定）→ MetaProgress 实现 + 测试 before/after。✓

**Placeholder scan:** 无 TBD/TODO；每步含完整代码或命令+期望。✓

**Type consistency:**
- `MetaProgress` 接口名（unlock_next/is_unlocked/get_unlock_order/to_dict/from_dict/save_progress/load_progress/unlocked_crew_ids/_save_path）在 Task 2 定义、Task 3 与测试一致引用。✓
- typed Array 赋值（`var ids: Array[String] = [...]` 再赋给 `unlocked_crew_ids`）规避 Variant；`from_dict` 用 `str(v)` 确保 String 元素。✓
- crew id（crew_gunner_03/medic_02/swordsman_04）在 Task 1 数据、Task 2/3 测试一致。✓
- autoload 注册名 MetaProgress 与脚本路径一致；插入位置在 UnitDataManager 后（get_unlock_order 运行期依赖，_ready 仅 load 无依赖）。✓

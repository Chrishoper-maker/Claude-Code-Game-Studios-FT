# run-end 解锁提示 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 末岛通关胜利后，run-end 总结页展示本航新解锁的悬赏船员（白盒文字行）。

**Architecture:** RunManager 用 `_unlocked_this_run` 记住 `_on_battle_won` 末岛胜利时 `MetaProgress.unlock_next()` 返回的解锁 id（start_run 清空），暴露 `get_unlocked_this_run()`。RouteScene `_show_run_end` 在重新出航按钮前按该 id 追加一行解锁提示。

**Tech Stack:** Godot 4.6.3 / GDScript / GdUnit4。

## Global Constraints

- 引擎 Godot 4.6.3；测试前必 `"/Applications/Godot.app/Contents/MacOS/Godot" --headless --import`；GdUnit4 须加 `--ignoreHeadlessMode`。
- 静态类型纪律：禁 `var x := <Variant 表达式>`；`Dictionary/Array` 元素先标注/`as T`。
- autoload 脚本不声明 class_name。
- `ISLAND_COUNT_MAX = 5`：末岛胜利条件 `current_island_index + 1 >= ISLAND_COUNT_MAX`（即 index ≥ 4）。
- 驱 RunManager 的测试 `before_test` 设 `_autosave_enabled=false` + no-op 导航接缝；触发解锁的测试须把 `MetaProgress._save_path` 重定向到临时文件并清 `unlocked_crew_ids`（避免污染真实 user://meta.json，after_test 清理）。
- 不持久化 `_unlocked_this_run`（不进 to_save_dict）。
- 中文对话；标识符英文。trunk-based 在 main。
- 提交 Conventional Commits，body 带 `Story: run-end-unlock-notice (#16)`，结尾 `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`。

---

### Task 1: RunManager 记录本航解锁 + 查询方法

**Files:**
- Modify: `src/autoloads/run_manager.gd`
- Test: `tests/unit/run_unlock_notice/run_unlock_notice_test.gd`

**Interfaces:**
- Consumes: `MetaProgress.unlock_next() -> String`（既有，返回新解锁 id 或 ""）、`MetaProgress.get_unlock_order() -> Array[String]`、`RunManager.ISLAND_COUNT_MAX`、`_on_battle_won()` / `_on_battle_lost()` / `start_run()`（既有）。
- Produces: `RunManager._unlocked_this_run: String`、`get_unlocked_this_run() -> String`。

- [ ] **Step 1: 写失败测试**

`tests/unit/run_unlock_notice/run_unlock_notice_test.gd`:

```gdscript
# RunManager 记录本航新解锁船员（末岛胜利捕获 unlock_next 返回值）。
extends GdUnitTestSuite

const TMP_META := "user://test_meta_unlock_notice.json"

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._goto_battle = func() -> void: pass
	RunManager._goto_route  = func() -> void: pass
	MetaProgress._save_path = TMP_META
	MetaProgress.unlocked_crew_ids.clear()
	if FileAccess.file_exists(TMP_META):
		DirAccess.remove_absolute(TMP_META)
	RunManager.start_run()

func after_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._goto_battle = RunManager._default_goto_battle
	RunManager._goto_route  = RunManager._default_goto_route
	MetaProgress.unlocked_crew_ids.clear()
	if FileAccess.file_exists(TMP_META):
		DirAccess.remove_absolute(TMP_META)
	MetaProgress._save_path = "user://meta.json"

# AC-1：末岛胜利后记录 unlock_next 解锁的 id（未全解锁时非空）。
func test_final_win_records_unlocked() -> void:
	var expected: String = MetaProgress.get_unlock_order()[0]
	RunManager.current_island_index = RunManager.ISLAND_COUNT_MAX - 1   # +1 >= MAX → 末岛胜利
	RunManager._on_battle_won()
	assert_str(RunManager.get_unlocked_this_run()).is_equal(expected)

# AC-2：全部 unlockable 已解锁 → 末岛胜利后为 ""。
func test_final_win_all_unlocked_empty() -> void:
	MetaProgress.unlocked_crew_ids = MetaProgress.get_unlock_order().duplicate()
	RunManager.current_island_index = RunManager.ISLAND_COUNT_MAX - 1
	RunManager._on_battle_won()
	assert_str(RunManager.get_unlocked_this_run()).is_equal("")

# AC-3：start_run 后为 ""。
func test_start_run_clears_unlocked() -> void:
	RunManager.current_island_index = RunManager.ISLAND_COUNT_MAX - 1
	RunManager._on_battle_won()
	RunManager.start_run()
	assert_str(RunManager.get_unlocked_this_run()).is_equal("")

# AC-4：失败结局不解锁 → "".
func test_loss_does_not_unlock() -> void:
	RunManager._on_battle_lost()
	assert_str(RunManager.get_unlocked_this_run()).is_equal("")
```

- [ ] **Step 2: 跑测试确认 RED**

```bash
cd "/Users/chris/Documents/First Codex/my-game"
"/Applications/Godot.app/Contents/MacOS/Godot" --headless --import 2>&1 | tail -1
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/run_unlock_notice/run_unlock_notice_test.gd 2>&1 | grep -iE "Statistics|FAILED|error" | tail -4
```
Expected: 运行错误（`get_unlocked_this_run` 不存在）。

- [ ] **Step 3: 加字段**

`src/autoloads/run_manager.gd`，在 `var last_run_won: bool = false ...` 行后加：

```gdscript
var _unlocked_this_run: String = ""               # 本航新解锁的悬赏船员持久 id（run-end 展示；空=无）
```

- [ ] **Step 4: start_run 清空**

`start_run()` 中 `last_run_won = false` 行后加：

```gdscript
	_unlocked_this_run = ""
```

- [ ] **Step 5: _on_battle_won 捕获返回值**

`_on_battle_won()` 末岛胜利分支，把：

```gdscript
		MetaProgress.unlock_next()   # 悬赏成长：通关解锁下一名 unlockable（含存盘）
```

改为：

```gdscript
		_unlocked_this_run = MetaProgress.unlock_next()   # 悬赏成长：通关解锁下一名 unlockable（含存盘）；记录供 run-end 展示
```

- [ ] **Step 6: 加查询方法**

在 `get_downed_this_run()` 方法之后加：

```gdscript
# 本航新解锁的悬赏船员持久 id（run-end 展示用）；无则 ""。
func get_unlocked_this_run() -> String:
	return _unlocked_this_run
```

- [ ] **Step 7: 跑测试确认 GREEN + 全量回归**

```bash
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/run_unlock_notice/run_unlock_notice_test.gd 2>&1 | grep -iE "Statistics|FAILED" | tail -3
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests 2>&1 | grep -iE "Overall Summary" | tail -1
```
Expected: 4/4 PASSED；全量绿。

- [ ] **Step 8: 提交**

```bash
git add src/autoloads/run_manager.gd tests/unit/run_unlock_notice/
git commit -F - <<'EOF'
feat(run): record crew unlocked this run for run-end notice

Story: run-end-unlock-notice (#16)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

> 注：新测试目录会生成 `.uid` 边车，`git add` 目录已含；提交前 `git status` 确认无遗漏 `.uid`。

---

### Task 2: RouteScene run-end 展示解锁行

**Files:**
- Modify: `src/ui/route_scene.gd`（`_show_run_end`）
- Test: `tests/integration/run_end_unlock_ui/run_end_unlock_ui_test.gd`

**Interfaces:**
- Consumes: `RunManager.get_unlocked_this_run() -> String`（Task 1）、`UnitDataManager.get_unit(id)`（既有）。

- [ ] **Step 1: 写失败测试**

`tests/integration/run_end_unlock_ui/run_end_unlock_ui_test.gd`:

```gdscript
# RouteScene run-end 页展示本航解锁船员行（AC-5）。直驱 RUN_END 分支。
extends GdUnitTestSuite

const UNLOCK_ID := "crew_gunner_03"   # 既有 unlockable crew

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._goto_battle = func() -> void: pass
	RunManager._goto_route  = func() -> void: pass
	RunManager.start_run()

func after_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._goto_battle = RunManager._default_goto_battle
	RunManager._goto_route  = RunManager._default_goto_route
	RunManager.start_run()

# 递归收集树下所有 Label 文本。
func _all_label_texts(node: Node) -> Array[String]:
	var out: Array[String] = []
	for child in node.get_children():
		if child is Label:
			out.append((child as Label).text)
		out.append_array(_all_label_texts(child))
	return out

# AC-5：有解锁时 run-end 含含该船员 display_name 的解锁行。
func test_run_end_shows_unlock_line() -> void:
	var def := UnitDataManager.get_unit(UNLOCK_ID)
	assert_bool(def is CrewDefinition).is_true()   # 前置：该 unlockable crew 存在
	var crew := def as CrewDefinition
	RunManager.last_run_won = true
	RunManager.current_island_index = RunManager.ISLAND_COUNT_MAX - 1
	RunManager._unlocked_this_run = UNLOCK_ID
	RunManager._phase = RunManager.RunPhase.RUN_END
	var route: RouteScene = auto_free(RouteScene.new())
	add_child(route)   # _ready → RUN_END → _notice_then(_show_run_end)（无阵亡直通）
	assert_str(route._active_screen).is_equal("run_end")
	var texts := _all_label_texts(route)
	var found := false
	for t in texts:
		if t.contains("解锁") and t.contains(crew.display_name):
			found = true
	assert_bool(found).is_true()

# AC-5（反向）：无解锁时无解锁行。
func test_run_end_no_unlock_line_when_empty() -> void:
	RunManager.last_run_won = false
	RunManager.current_island_index = 2
	RunManager._unlocked_this_run = ""
	RunManager._phase = RunManager.RunPhase.RUN_END
	var route: RouteScene = auto_free(RouteScene.new())
	add_child(route)
	var texts := _all_label_texts(route)
	var found := false
	for t in texts:
		if t.contains("解锁新船员"):
			found = true
	assert_bool(found).is_false()
```

- [ ] **Step 2: 跑测试确认 RED**

```bash
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/integration/run_end_unlock_ui/run_end_unlock_ui_test.gd 2>&1 | grep -iE "Statistics|FAILED" | tail -3
```
Expected: `test_run_end_shows_unlock_line` FAILED（run-end 尚无解锁行）。

- [ ] **Step 3: 改 _show_run_end**

`src/ui/route_scene.gd` 的 `_show_run_end()`，在 `var restart := Button.new()` 行之前插入：

```gdscript
	var unlocked_id := RunManager.get_unlocked_this_run()
	if unlocked_id != "":
		var udef := UnitDataManager.get_unit(unlocked_id)
		if udef is CrewDefinition:
			var ucrew := udef as CrewDefinition
			var unlock_line := Label.new()
			unlock_line.text = "解锁新船员：%s · %s" % [ucrew.unit_class, ucrew.display_name]
			box.add_child(unlock_line)
```

- [ ] **Step 4: 跑测试确认 GREEN + 全量回归**

```bash
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/integration/run_end_unlock_ui/run_end_unlock_ui_test.gd 2>&1 | grep -iE "Statistics|FAILED" | tail -3
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests 2>&1 | grep -iE "Overall Summary|Executed test|SCRIPT ERROR" | tail -4
```
Expected: 2/2 PASSED；全量绿、0 错误/孤儿（AC-6）。

- [ ] **Step 5: 提交**

```bash
git add src/ui/route_scene.gd tests/integration/run_end_unlock_ui/
git commit -F - <<'EOF'
feat(route): show unlocked-crew notice on run-end summary

Story: run-end-unlock-notice (#16)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

## Self-Review

**Spec coverage:**
- Rule 1 RunManager 记录（字段/start_run 清/末岛胜捕获/查询方法）→ Task 1 ✓
- Rule 2 RouteScene 展示行（位置在重新出航前/CrewDefinition 守卫/文案）→ Task 2 ✓
- 边界：全解锁→""（AC-2 Task1）/ 失败不解锁（AC-4 Task1）/ 重新出航清空（AC-3 Task1）/ 无解锁无行（Task2 反向测试）/ 解析失败守卫（Task2 `is CrewDefinition`）/ 不持久化（未改 to_save_dict）✓
- AC-1..4 → Task 1；AC-5（正反）→ Task 2；AC-6 全量回归 → 两任务 ✓

**Placeholder scan:** 无 TBD/TODO；每步完整代码+命令+期望。✓

**Type consistency:**
- `_unlocked_this_run: String` 字段（Task 1）↔ `get_unlocked_this_run() -> String`（Task 1）↔ Task 2 消费一致。
- `RunManager.RunPhase.RUN_END` / `ISLAND_COUNT_MAX` 引用与既有枚举/常量一致。
- 静态类型：`var unlocked_id := RunManager.get_unlocked_this_run()`（返回 String，推断安全）；`var udef := UnitDataManager.get_unit(...)`（返回 UnitDefinition 非 Variant）；测试内 `Array[String]` 局部、`as CrewDefinition` 守卫后转换。✓

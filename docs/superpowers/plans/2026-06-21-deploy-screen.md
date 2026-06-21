# DeployScreen 手动选人 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** roster 超过 DEPLOY_LIMIT(4) 时，玩家在 RouteScene 白盒中枢内用 toggle 按钮选最多 4 名出战、确认部署；roster ≤4 保持自动全员。

**Architecture:** 在既有白盒 `RouteScene`（class_name RouteScene extends Control）的 DEPLOYING 流程内联渲染选人界面，不新建场景。把现在"无脑全员部署"的 `_deploy_current_roster()` 改造为统一入口 `_enter_deploy()`：≤DEPLOY_LIMIT 走 `_auto_deploy_all()`（行为不变）、>DEPLOY_LIMIT 走 `_show_deploy_selection()`。后端 `RunManager.confirm_deploy(selected_ids)` 已支持子集，不改。

**Tech Stack:** Godot 4.6.3 / GDScript / GdUnit4 测试。

## Global Constraints

- 引擎 = Godot 4.6.3；测试 = GdUnit4，命令前必先 `godot --headless --import`（建全局类名缓存）。
- Godot 二进制：`/Applications/Godot.app/Contents/MacOS/Godot`。
- 全部对话/反馈中文；代码标识符/引擎 API 英文。
- **静态类型纪律（本项目把推断自 Variant / 不安全访问当错误处理）**：禁止 `var x := <Variant 表达式>`（如 `auto_free(...)`、`Array[i]` 元素、`Dictionary[k]`）——必须显式标注类型或 `as T` 强转。
- 交互"只用选项不打字"：选人界面全用按钮，不显数值。
- DEPLOY_LIMIT 单一来源 = `design/registry/entities.yaml`（值 4）；代码引用 `RunManager.DEPLOY_LIMIT`，不另立魔数。
- 提交用 Conventional Commits，body 带 `Story: route-recruitment (B)`，结尾：
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`

---

### Task 1: DeployScreen 手动选人（RouteScene 内联 DEPLOYING 分支）

**Files:**
- Modify: `src/autoloads/run_manager.gd`（加 `const DEPLOY_LIMIT := 4`）
- Modify: `src/ui/route_scene.gd`（`_deploy_current_roster` → `_enter_deploy` + 选人界面 + 处理器；更新各调用方）
- Test: `tests/integration/deploy_screen/deploy_screen_test.gd`（新建）

**Interfaces:**
- Consumes（已存在）:
  - `RunManager.get_roster() -> Array[CrewDefinition]`
  - `RunManager.confirm_deploy(selected_ids: Array)`（按 id 过滤 roster 填 pending_deploy、island++、→ BATTLE、调 `_goto_battle`）
  - `RunManager.get_pending_deploy() -> Array[CrewDefinition]`
  - `RunManager.start_run()` / `confirm_recruit(id)` / `get_recruit_offers()`
  - `RunManager._goto_battle` / `_goto_route`（可注入 Callable，测试 stub no-op）
  - `RunManager._default_goto_battle` / `_default_goto_route`
  - `CrewDefinition.id / .unit_class / .display_name / .battle_cry`
  - `UnitDataManager.get_unit(id: String) -> UnitDefinition`
- Produces（本任务定义，测试依赖其精确名）:
  - `RunManager.DEPLOY_LIMIT: int == 4`
  - `RouteScene._enter_deploy()`、`_auto_deploy_all()`、`_clear_ui()`、`_show_deploy_selection()`
  - `RouteScene._on_deploy_toggle(pressed: bool, crew_id: String)`、`_refresh_deploy_state()`、`_on_deploy_confirm()`
  - 成员：`_selected_ids: Array[String]`、`_deploy_buttons: Dictionary`（crew_id→Button）、`_deploy_status_label: Label`、`_deploy_confirm_button: Button`

- [ ] **Step 1: 写失败测试（新建测试文件，覆盖 AC-1..6）**

创建 `tests/integration/deploy_screen/deploy_screen_test.gd`：

```gdscript
# DeployScreen 手动选人集成测试（子项目 B）：实例化 RouteScene 白盒中枢，
# 经 _deploy_buttons[id].button_pressed 赋值驱动真实 toggled 接线（无头安全，非 InputEvent）。
# 导航接缝 stub 为 no-op 防真切场景；roster>4 经追加 pool crew 构造。
extends GdUnitTestSuite

const POOL_IDS: Array[String] = [
	"crew_swordsman_02", "crew_gunner_01", "crew_bulwark_02", "crew_medic_01",
	"crew_navigator_01", "crew_musician_01", "crew_gunner_02", "crew_swordsman_03",
]

func before_test() -> void:
	RunManager._goto_battle = func() -> void: pass
	RunManager._goto_route  = func() -> void: pass
	RunManager.start_run()
	RunManager._rng.seed = 20260621

func after_test() -> void:
	RunManager._goto_battle = RunManager._default_goto_battle
	RunManager._goto_route  = RunManager._default_goto_route

func _grow_roster_to(n: int) -> void:
	for pid in POOL_IDS:
		if RunManager.roster.size() >= n:
			break
		var def := UnitDataManager.get_unit(pid)
		if def is CrewDefinition:
			RunManager.roster.append(def as CrewDefinition)

func _roster_ids() -> Array[String]:
	var ids: Array[String] = []
	for c in RunManager.get_roster():
		ids.append(c.id)
	return ids

func _btn(route: RouteScene, crew_id: String) -> Button:
	return route._deploy_buttons[crew_id] as Button

# AC-1：roster ≤ DEPLOY_LIMIT 自动全员，不展示界面。
func test_ac1_small_roster_auto_deploys() -> void:
	var route: RouteScene = auto_free(RouteScene.new())
	add_child(route)   # _ready: DEPLOYING → _enter_deploy → roster=2≤4 → auto
	assert_str(RunManager.current_phase).is_equal("BATTLE")
	assert_int(RunManager.get_pending_deploy().size()).is_equal(2)
	assert_int(route._deploy_buttons.size()).is_equal(0)

# AC-2：roster > DEPLOY_LIMIT 展示选人界面，未自动确认。
func test_ac2_large_roster_shows_selection() -> void:
	_grow_roster_to(5)
	var route: RouteScene = auto_free(RouteScene.new())
	add_child(route)
	assert_int(route._deploy_buttons.size()).is_equal(5)
	assert_bool(route._deploy_confirm_button.disabled).is_true()
	assert_str(RunManager.current_phase).is_equal("DEPLOYING")

# AC-3：选满 4 人确认 → confirm_deploy 收到那 4 个 id。
func test_ac3_select_four_and_confirm() -> void:
	_grow_roster_to(5)
	var route: RouteScene = auto_free(RouteScene.new())
	add_child(route)
	var ids := _roster_ids()
	var chosen: Array[String] = [ids[0], ids[1], ids[2], ids[3]]
	for cid in chosen:
		_btn(route, cid).button_pressed = true
	route._on_deploy_confirm()
	assert_str(RunManager.current_phase).is_equal("BATTLE")
	assert_int(RunManager.get_pending_deploy().size()).is_equal(4)
	var pending_ids: Array[String] = []
	for c in RunManager.get_pending_deploy():
		pending_ids.append(c.id)
	for cid in chosen:
		assert_bool(pending_ids.has(cid)).is_true()

# AC-4：选满 4 后第 5 个被回弹拒绝。
func test_ac4_fifth_selection_rejected() -> void:
	_grow_roster_to(6)
	var route: RouteScene = auto_free(RouteScene.new())
	add_child(route)
	var ids := _roster_ids()
	for j in 4:
		_btn(route, ids[j]).button_pressed = true
	_btn(route, ids[4]).button_pressed = true   # 第 5 个
	assert_int(route._selected_ids.size()).is_equal(4)
	assert_bool(_btn(route, ids[4]).button_pressed).is_false()
	assert_bool(route._selected_ids.has(ids[4])).is_false()

# AC-5：确认键随选择数启用/禁用 + 状态标签。
func test_ac5_confirm_tracks_selection() -> void:
	_grow_roster_to(5)
	var route: RouteScene = auto_free(RouteScene.new())
	add_child(route)
	var first: String = _roster_ids()[0]
	assert_bool(route._deploy_confirm_button.disabled).is_true()
	assert_str(route._deploy_status_label.text).is_equal("已选 0/4")
	_btn(route, first).button_pressed = true
	assert_bool(route._deploy_confirm_button.disabled).is_false()
	assert_str(route._deploy_status_label.text).is_equal("已选 1/4")
	_btn(route, first).button_pressed = false
	assert_bool(route._deploy_confirm_button.disabled).is_true()
	assert_str(route._deploy_status_label.text).is_equal("已选 0/4")

# AC-6：子集部署（少于满编）成功。
func test_ac6_subset_deploy() -> void:
	_grow_roster_to(5)
	var route: RouteScene = auto_free(RouteScene.new())
	add_child(route)
	var ids := _roster_ids()
	_btn(route, ids[0]).button_pressed = true
	_btn(route, ids[1]).button_pressed = true
	route._on_deploy_confirm()
	assert_str(RunManager.current_phase).is_equal("BATTLE")
	assert_int(RunManager.get_pending_deploy().size()).is_equal(2)
```

- [ ] **Step 2: 跑测试确认失败（RED）**

Run:
```bash
cd "/Users/chris/Documents/First Codex/my-game"
"/Applications/Godot.app/Contents/MacOS/Godot" --headless --import 2>&1 | tail -2
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/integration/deploy_screen 2>&1 | tail -25
```
Expected: 失败/解析错误——`RouteScene` 无 `_deploy_buttons`/`_on_deploy_confirm`/`_show_deploy_selection` 等成员，`RunManager` 无 `DEPLOY_LIMIT`（"Cannot find member" 类脚本错误即 RED）。

- [ ] **Step 3: 加 DEPLOY_LIMIT 常量到 RunManager**

在 `src/autoloads/run_manager.gd` 的常量块（`const ISLAND_COUNT_MAX := 5` 行后）追加：

```gdscript
const DEPLOY_LIMIT := 4
```

使该块为：
```gdscript
const STARTING_CREW := 2
const RECRUIT_OFFER_COUNT := 3
const ISLAND_COUNT_MAX := 5
const DEPLOY_LIMIT := 4
```

- [ ] **Step 4: 改写 RouteScene（统一入口 + 选人界面 + 处理器）**

将 `src/ui/route_scene.gd` 整体替换为（仅 DEPLOYING 分支与部署相关为新增/改动；recruit/run-end 保持原行为）：

```gdscript
# 战斗之间的中枢（白盒，Control）。按 RunManager.current_phase 分支：
# IDLE→起航直发首岛；RECRUITING→三选一卡；RUN_END→结果页+重新出航；
# DEPLOYING→roster≤DEPLOY_LIMIT 自动全员 / >DEPLOY_LIMIT 手动选人（子项目 B）。
# 招募卡显示「职业·名·台词」、选人卡显示「职业·名」（均不显数值，GDD）。
class_name RouteScene
extends Control

var _selected_ids: Array[String] = []        # 本次部署已选 crew id
var _deploy_buttons: Dictionary = {}          # crew_id → 选人 toggle Button
var _deploy_status_label: Label = null        # "已选 X/4"
var _deploy_confirm_button: Button = null     # 「确认部署」

func _ready() -> void:
	match RunManager.current_phase:
		"IDLE":
			_begin_run()
		"RECRUITING":
			_show_recruit_offers()
		"RUN_END":
			_show_run_end()
		_:
			_enter_deploy()

# 起航：填起始编制 → 进入部署。
func _begin_run() -> void:
	RunManager.start_run()
	_enter_deploy()

# 部署统一入口：roster ≤ DEPLOY_LIMIT 自动全员；否则手动选人。
func _enter_deploy() -> void:
	_clear_ui()
	if RunManager.get_roster().size() <= RunManager.DEPLOY_LIMIT:
		_auto_deploy_all()
	else:
		_show_deploy_selection()

# 清本中枢已建子节点 + 重置选人状态（避免阶段叠加显示）。
func _clear_ui() -> void:
	for child in get_children():
		child.queue_free()
	_selected_ids.clear()
	_deploy_buttons.clear()
	_deploy_status_label = null
	_deploy_confirm_button = null

# 收集 roster 全员 id 提交部署（≤DEPLOY_LIMIT 时自动全员）。
func _auto_deploy_all() -> void:
	var ids: Array[String] = []
	for c in RunManager.get_roster():
		ids.append(c.id)
	RunManager.confirm_deploy(ids)

# 手动选人界面（白盒，只用按钮，不显数值）。roster 按招募顺序（自然序）。
func _show_deploy_selection() -> void:
	var box := VBoxContainer.new()
	add_child(box)
	box.set_anchors_preset(Control.PRESET_CENTER)   # M-3：先 add_child 再设锚点
	var title := Label.new()
	title.text = "选择出战船员（最多 %d 名）" % RunManager.DEPLOY_LIMIT
	box.add_child(title)
	for c in RunManager.get_roster():
		var btn := Button.new()
		btn.toggle_mode = true
		btn.text = "%s · %s" % [c.unit_class, c.display_name]
		btn.toggled.connect(_on_deploy_toggle.bind(c.id))
		box.add_child(btn)
		_deploy_buttons[c.id] = btn
	_deploy_status_label = Label.new()
	box.add_child(_deploy_status_label)
	_deploy_confirm_button = Button.new()
	_deploy_confirm_button.text = "确认部署"
	_deploy_confirm_button.pressed.connect(_on_deploy_confirm)
	box.add_child(_deploy_confirm_button)
	_refresh_deploy_state()

# toggle 选中/取消；已满 DEPLOY_LIMIT 时拒绝新增（回弹，不发信号防递归）。
func _on_deploy_toggle(pressed: bool, crew_id: String) -> void:
	if pressed:
		if _selected_ids.size() >= RunManager.DEPLOY_LIMIT:
			(_deploy_buttons[crew_id] as Button).set_pressed_no_signal(false)
			return
		_selected_ids.append(crew_id)
	else:
		_selected_ids.erase(crew_id)
	_refresh_deploy_state()

# 刷新「已选 X/4」与确认键可用性（0 人禁用）。
func _refresh_deploy_state() -> void:
	_deploy_status_label.text = "已选 %d/%d" % [_selected_ids.size(), RunManager.DEPLOY_LIMIT]
	_deploy_confirm_button.disabled = _selected_ids.is_empty()

# 确认部署 → 后端按所选 id 过滤 roster 填 pending_deploy → 进战斗。
func _on_deploy_confirm() -> void:
	if _selected_ids.is_empty():
		return
	RunManager.confirm_deploy(_selected_ids.duplicate())

# 三选一招募卡。候选为空 → 跳过招募直接进入部署。
func _show_recruit_offers() -> void:
	var offers := RunManager.get_recruit_offers()
	if offers.is_empty():
		_enter_deploy()
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
	_enter_deploy()

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
	_enter_deploy()
```

- [ ] **Step 5: 跑 DeployScreen 套件确认通过（GREEN）**

Run:
```bash
cd "/Users/chris/Documents/First Codex/my-game"
"/Applications/Godot.app/Contents/MacOS/Godot" --headless --import 2>&1 | tail -2
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/integration/deploy_screen 2>&1 | grep -iE "PASSED|FAILED|Statistics" | tail -10
```
Expected: 6/6 PASSED（test_ac1..test_ac6），0 failures。

- [ ] **Step 6: 跑全量回归确认无破（含 A 的 run 循环 AC-7）**

Run:
```bash
cd "/Users/chris/Documents/First Codex/my-game"
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests 2>&1 | grep -iE "Overall Summary|Executed test|Abnormal|SCRIPT ERROR" | tail -8
```
Expected: `Overall Summary: 271 test cases | 0 errors | 0 failures | 0 flaky | 0 skipped | 0 orphans`（265 + 6）。run_loop 的 AC-1..7 仍绿（其部署路径 roster 均 ≤4，走自动跳过，行为不变）。

- [ ] **Step 7: 提交**

```bash
cd "/Users/chris/Documents/First Codex/my-game"
git add src/autoloads/run_manager.gd src/ui/route_scene.gd tests/integration/deploy_screen/
git commit -F - <<'EOF'
feat(route): manual deploy selection when roster exceeds DEPLOY_LIMIT

RouteScene DEPLOYING branch: roster <= DEPLOY_LIMIT(4) auto-deploys all
(unchanged); roster > 4 renders toggle-button crew selection (recruit
order, no stats), capped at 4 with "selected X/4" + confirm. Confirm
disabled at 0 selected; 5th selection bounces back via
set_pressed_no_signal. confirm_deploy backend unchanged (already
filters roster by selected ids).

Adds RunManager.DEPLOY_LIMIT (=4, mirrors entities.yaml).
Full suite 271/271 PASSED (was 265).

Story: route-recruitment (B)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
git log --oneline -1
```

---

## Self-Review

**Spec coverage（逐条对照 spec）:**
- Rule 1 DEPLOY_LIMIT 常量 → Step 3。✓
- Rule 2 `_enter_deploy` 统一入口 + 四调用方（_begin_run/_on_recruit_chosen/_on_restart_pressed/_ready 默认分支）+ ≤/> 分流 → Step 4。✓
- Rule 3 `_show_deploy_selection`（标题/toggle 列表/状态标签/确认键 + `_deploy_buttons` 存储 + 先 add_child 后 set_anchors）→ Step 4。✓
- Rule 4 `_on_deploy_toggle`（满额回弹 set_pressed_no_signal + append/erase）→ Step 4。✓
- Rule 5 `_refresh_deploy_state`（"已选 X/4" + 0 人禁用）→ Step 4。✓
- Rule 6 `_on_deploy_confirm`（空守卫 + confirm_deploy(duplicate)）→ Step 4。✓
- F1 `roster.size() > DEPLOY_LIMIT` 分流 → `_enter_deploy`。✓
- F2 确认键可用性 → `_refresh_deploy_state`。✓
- Edge：=4 自动（≤ 含等号）/ =1 自动 / 满额回弹 / 0 确认守卫 / pending≤4 / 重入清场 → Step 4 逻辑 + AC-1/4 测试。✓
- AC-1..6 → Step 1 六测试；AC-7 回归 → Step 6。✓
- 偏离 GDD（内联/不显数值/只选人/后端不截断）→ 已在 spec 记录，计划据此实现。✓
- 清理 M-3（先 add_child 后 set_anchors，仅新建的选人 box）→ Step 4。M-2 无需（roster 元素已 CrewDefinition）。✓

**Placeholder scan:** 无 TBD/TODO/"add error handling"；每步含完整代码或完整命令+期望输出。✓

**Type consistency:**
- `DEPLOY_LIMIT` 在 RunManager 定义、RouteScene 与测试以 `RunManager.DEPLOY_LIMIT` 引用。✓
- `_on_deploy_toggle(pressed: bool, crew_id: String)` 签名与 `toggled.connect(...bind(c.id))`（toggled 传 bool + bind 追加 crew_id）一致。✓
- `_deploy_buttons` 值为 Button，测试 `_btn()` 以 `as Button` 强转后访问 `.button_pressed`（避免不安全访问）。✓
- `_selected_ids: Array[String]`、`_roster_ids() -> Array[String]`、`POOL_IDS: Array[String]`、`chosen/pending_ids: Array[String]` 全程 String 元素，无 Variant 推断。✓
- `confirm_deploy(_selected_ids.duplicate())` 传 Array，后端签名 `(selected_ids: Array)` 匹配。✓
- 测试 stub/恢复 `_goto_battle/_goto_route` 与 `_default_goto_*` 名称与 run_manager.gd 一致。✓

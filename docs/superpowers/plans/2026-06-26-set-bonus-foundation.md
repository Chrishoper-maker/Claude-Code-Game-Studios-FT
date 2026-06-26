# 套装系统地基（②b-1）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把装备从「一人最多 2 件、招募锁定」升级为「最多 9 槽、随 run 累积、能凑出 8 大套装」的成长系统，并提供套装计数器 + 人形纸娃娃获取 UI（本期不产生任何战斗加成）。

**Architecture:** 装备数据由生成器脚本批量产出 8 套 × 9 槽 = 72 件（删除旧 31 件）。RunManager 新增「起始/招募直发 3 件（80% 同套）」「战后滚 8 选 2（80% 偏向主套）」「套装计数器」「`RUN_EQUIPPING` 阶段 + `_pending_battle_equip` 存档」。RouteScene 新增 EQUIPPING 分支与纸娃娃 UI，招募改为直发 3 件通知。

**Tech Stack:** Godot 4.6.3 / GDScript / GdUnit4。autoload 单例（RunManager / EquipmentDataManager / UnitDataManager / MetaProgress / EventBus / SceneManager）。

## Global Constraints

- 引擎 Godot 4.6.3；测试 GdUnit4：先 `/Applications/Godot.app/Contents/MacOS/Godot --headless --import`，再 `/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests`。
- 命名：类 PascalCase、变量/函数 snake_case、信号过去式 snake_case、常量 UPPER_SNAKE_CASE。
- GDScript 静态类型（`:=` / 显式注解），公共 API 写中文 doc 注释。
- 数值数据驱动：装备数值进 `.tres`，不硬编码于逻辑。
- 确定性：所有随机走 `RunManager._rng`；存档 `rng_state` 复现。测试不依赖真实时间/真实 `user://run.json`（注入 `_save_path`、置 `_autosave_enabled=false`、`before_test` 设 `_rng.seed`）。
- autoload 脚本不声明 `class_name`；数据/运行时类声明 `class_name`。
- 提交用 Conventional Commits，body 引用 `Story: set-bonus-foundation`，结尾 `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`。
- 8 套 set_id：`set_ironwall`(铁壁)/`set_berserker`(狂战)/`set_healer`(医者)/`set_navigator`(航海)/`set_bloodthirst`(嗜血)/`set_thorns`(荆棘)/`set_executioner`(处决)/`set_frost`(寒霜)。
- 套装阈值 `[3,6,9]`；每套 9 件（每槽 1 件）；同套概率/偏向概率均 80。
- 本期**不实现任何套装战斗加成**（留 ②b-2/3）；不得改动 `BattleResolution`、`UnitInstance.get_*`。

## File Structure

- `src/data/equipment_definition.gd`（改）：加稀有度配色/标签静态常量 + `rarity_color`/`rarity_label`。
- `tools/gen_equipment_sets.gd`（建）：生成器，删旧 .tres + 写 72 件新 .tres。
- `assets/data/equipment/*.tres`（重生成）：72 件套装装备。
- `src/autoloads/run_manager.gd`（改）：计数器 + 直发 3 件 + 战后滚 8 + `RUN_EQUIPPING` + `_pending_battle_equip` + 存档。
- `src/ui/route_scene.gd`（改）：EQUIPPING 分支 + 纸娃娃 + 招募改直发 3 件通知。
- `tests/unit/...`、`tests/integration/...`：新增 + 迁移既有装备测试。

## 新 ID 命名方案（供测试迁移引用）

- 规则：`eq_<setshort>_<slotkey>`，`setshort` = set_id 去 `set_` 前缀，`slotkey` ∈ `[mainweapon,offweapon,head,armor,gloves,legs,boots,ring,necklace]`（对应 slot 0..8）。
- 每槽稀有度（所有套统一）`SLOT_RARITY = [2,1,0,2,0,0,1,3,1]`（slot0..8）→ 每套 普通×3 / 稀有×3 / 史诗×2 / 稀世×1。
- 全池 72 件分布：普通 24 / 稀有 24 / 史诗 16 / 稀世 8 / 传奇 0。
- 每件只给其套**主属性**一项增量；主属性：铁壁/医者/荆棘=hp、狂战/嗜血/处决=damage、航海=move、寒霜=range。
- 增量表（按 rarity 0..4）：`hp=[2,4,6,8,10]`、`damage=[1,2,3,4,5]`、`range=[1,1,2,2,3]`、`move=[1,1,2,2,3]`。
- **测试常用替换映射**（旧→新）：
  - `eq_plate`(hp+3,common,armor) → `eq_ironwall_armor`（hp+6, rarity2=史诗, slot3, set_ironwall）
  - `eq_cutlass`(dmg+1,common,mainweapon) → `eq_berserker_mainweapon`（dmg+3, rarity2, slot0, set_berserker）
  - 普通(rarity0) 样例：`eq_ironwall_head`（hp+2, rarity0, slot2, set_ironwall）
  - 史诗(rarity2) 样例：`eq_berserker_armor`（dmg+0? 不——berserker 主属性 damage → eq_berserker_armor 给 damage+3? 注意 armor 槽仍按 set 主属性给值）。**所有件按其套主属性给值，与槽无关。**

---

### Task 1: 稀有度配色/标签静态常量

**Files:**
- Modify: `src/data/equipment_definition.gd`
- Test: `tests/unit/equipment_data/equipment_color_test.gd` (create)

**Interfaces:**
- Produces:
  - `EquipmentDefinition.RARITY_LABELS: Array`（["普通","稀有","史诗","稀世","传奇"]）
  - `EquipmentDefinition.rarity_color(rarity: int) -> Color`
  - `EquipmentDefinition.rarity_label(rarity: int) -> String`

- [ ] **Step 1: 写失败测试**

创建 `tests/unit/equipment_data/equipment_color_test.gd`：

```gdscript
# 校验稀有度配色/标签静态访问器（越界钳制）。
extends GdUnitTestSuite

func test_rarity_label_maps_each_tier() -> void:
	assert_str(EquipmentDefinition.rarity_label(0)).is_equal("普通")
	assert_str(EquipmentDefinition.rarity_label(4)).is_equal("传奇")

func test_rarity_label_clamps_out_of_range() -> void:
	assert_str(EquipmentDefinition.rarity_label(-1)).is_equal("普通")
	assert_str(EquipmentDefinition.rarity_label(99)).is_equal("传奇")

func test_rarity_color_distinct_per_tier() -> void:
	var seen: Dictionary = {}
	for r in range(5):
		var c := EquipmentDefinition.rarity_color(r)
		assert_bool(seen.has(c)).is_false()
		seen[c] = true
```

- [ ] **Step 2: 跑测试确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --import` 然后 `... -a res://tests/unit/equipment_data/equipment_color_test.gd`
Expected: FAIL（`rarity_color` 未定义）

- [ ] **Step 3: 实现**

在 `src/data/equipment_definition.gd` 末尾追加：

```gdscript
# ── 稀有度展示（配色/标签，UI 共用单一真实来源）──
const RARITY_LABELS: Array = ["普通", "稀有", "史诗", "稀世", "传奇"]
const RARITY_COLORS: Array = [
	Color("c8c8c8"),  # 普通=灰白
	Color("4a90d9"),  # 稀有=蓝
	Color("9b59b6"),  # 史诗=紫
	Color("e67e22"),  # 稀世=橙
	Color("e74c3c"),  # 传奇=红
]

static func rarity_label(rarity: int) -> String:
	return RARITY_LABELS[clampi(rarity, 0, 4)]

static func rarity_color(rarity: int) -> Color:
	return RARITY_COLORS[clampi(rarity, 0, 4)]
```

- [ ] **Step 4: 跑测试确认通过**

Run: `... -a res://tests/unit/equipment_data/equipment_color_test.gd`
Expected: PASS (3/3)

- [ ] **Step 5: 提交**

```bash
git add src/data/equipment_definition.gd tests/unit/equipment_data/equipment_color_test.gd
git commit -m "feat(equipment): rarity color/label static accessors

Story: set-bonus-foundation
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: 装备数据生成器 + 重生成 72 件

**Files:**
- Create: `tools/gen_equipment_sets.gd`
- Delete: `assets/data/equipment/*.tres`（旧 31 件）
- Create: `assets/data/equipment/eq_*.tres`（生成 72 件）
- Test: `tests/unit/equipment_data/equipment_pool_smoke_test.gd`（重写既有）

**Interfaces:**
- Produces: 72 个 `EquipmentDefinition` .tres，id 遵循新命名方案，每件 `set_id` 非空、`slot` 0..8、`rarity` 0..4。

- [ ] **Step 1: 写生成器脚本**

创建 `tools/gen_equipment_sets.gd`：

```gdscript
# 一次性数据生成器：删旧装备 .tres，按 8 套 × 9 槽生成 72 件。
# 运行：godot --headless --script res://tools/gen_equipment_sets.gd
@tool
extends SceneTree

const OUT_DIR := "res://assets/data/equipment/"
const SLOT_KEYS := ["mainweapon", "offweapon", "head", "armor", "gloves", "legs", "boots", "ring", "necklace"]
const SLOT_NOUNS := ["刃", "盾", "盔", "甲", "护手", "护腿", "战靴", "戒", "坠"]
const SLOT_RARITY := [2, 1, 0, 2, 0, 0, 1, 3, 1]   # slot0..8 稀有度（所有套统一）
const STAT_BY_RARITY := {
	"hp": [2, 4, 6, 8, 10],
	"damage": [1, 2, 3, 4, 5],
	"range": [1, 1, 2, 2, 3],
	"move": [1, 1, 2, 2, 3],
}
const SETS := [
	{"id": "set_ironwall", "name": "铁壁", "stat": "hp"},
	{"id": "set_berserker", "name": "狂战", "stat": "damage"},
	{"id": "set_healer", "name": "医者", "stat": "hp"},
	{"id": "set_navigator", "name": "航海", "stat": "move"},
	{"id": "set_bloodthirst", "name": "嗜血", "stat": "damage"},
	{"id": "set_thorns", "name": "荆棘", "stat": "hp"},
	{"id": "set_executioner", "name": "处决", "stat": "damage"},
	{"id": "set_frost", "name": "寒霜", "stat": "range"},
]

func _init() -> void:
	_delete_old()
	var n := 0
	for s in SETS:
		for slot in range(9):
			var def := EquipmentDefinition.new()
			var short: String = (s["id"] as String).trim_prefix("set_")
			def.id = "eq_%s_%s" % [short, SLOT_KEYS[slot]]
			def.display_name = "%s%s" % [s["name"], SLOT_NOUNS[slot]]
			def.slot = slot
			def.rarity = SLOT_RARITY[slot]
			def.set_id = s["id"]
			var stat: String = s["stat"]
			var val: int = STAT_BY_RARITY[stat][def.rarity]
			def.hp_bonus = val if stat == "hp" else 0
			def.damage_bonus = val if stat == "damage" else 0
			def.range_bonus = val if stat == "range" else 0
			def.move_bonus = val if stat == "move" else 0
			var path := OUT_DIR + def.id + ".tres"
			var err := ResourceSaver.save(def, path)
			assert(err == OK, "保存失败 %s err=%d" % [path, err])
			n += 1
	print("生成装备 %d 件" % n)
	quit()

func _delete_old() -> void:
	var dir := DirAccess.open(OUT_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".tres") or f.ends_with(".tres.import") or f.ends_with(".tres.uid"):
			dir.remove(f)
		f = dir.get_next()
```

- [ ] **Step 2: 运行生成器**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --script res://tools/gen_equipment_sets.gd`
Expected: 输出「生成装备 72 件」，`ls assets/data/equipment/*.tres | wc -l` == 72。

- [ ] **Step 3: 重新导入并重写池冒烟测试**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --import`

重写 `tests/unit/equipment_data/equipment_pool_smoke_test.gd`：

```gdscript
extends GdUnitTestSuite

# 校验 8 套 × 9 槽 = 72 件装备池的分布与不变量。
func test_total_count_is_72() -> void:
	assert_int(EquipmentDataManager.get_all_equipment().size()).is_equal(72)

func test_rarity_distribution_24_24_16_8_0() -> void:
	assert_int(EquipmentDataManager.get_equipment_by_rarity(0).size()).is_equal(24)
	assert_int(EquipmentDataManager.get_equipment_by_rarity(1).size()).is_equal(24)
	assert_int(EquipmentDataManager.get_equipment_by_rarity(2).size()).is_equal(16)
	assert_int(EquipmentDataManager.get_equipment_by_rarity(3).size()).is_equal(8)
	assert_int(EquipmentDataManager.get_equipment_by_rarity(4).size()).is_equal(0)

func test_each_set_has_nine_distinct_slots() -> void:
	var by_set: Dictionary = {}
	for eq in EquipmentDataManager.get_all_equipment():
		assert_str(eq.set_id).is_not_equal("")
		if not by_set.has(eq.set_id):
			by_set[eq.set_id] = {}
		by_set[eq.set_id][eq.slot] = true
	assert_int(by_set.size()).is_equal(8)
	for sid in by_set:
		assert_int((by_set[sid] as Dictionary).size()).is_equal(9)

func test_all_loaded_and_unique() -> void:
	assert_bool(EquipmentDataManager.is_loaded).is_true()
	var seen: Dictionary = {}
	for eq in EquipmentDataManager.get_all_equipment():
		assert_bool(seen.has(eq.id)).is_false()
		seen[eq.id] = true
		assert_int(eq.slot).is_between(0, 8)
		assert_int(eq.rarity).is_between(0, 4)
```

- [ ] **Step 4: 跑该测试确认通过**

Run: `... -a res://tests/unit/equipment_data/equipment_pool_smoke_test.gd`
Expected: PASS (4/4)

- [ ] **Step 5: 提交**

```bash
git add tools/gen_equipment_sets.gd assets/data/equipment/ tests/unit/equipment_data/equipment_pool_smoke_test.gd
git commit -m "feat(equipment): regenerate 72-piece 8-set data via generator

Story: set-bonus-foundation
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: 迁移引用旧装备 id 的既有测试

**Files:**
- Modify: `tests/unit/equipment/equipment_data_test.gd`
- Modify: `tests/unit/equipment_data/equipment_data_query_test.gd`
- Modify: `tests/unit/unit_instance_equipment/unit_instance_equipment_test.gd`
- Modify: `tests/integration/equipment_battle/equipment_battle_test.gd`
- Modify: `tests/integration/equipment_slots/equipment_slots_e2e_test.gd`

**Interfaces:**
- Consumes: 新 id 命名方案（见顶部映射表）。

> 注：`run_equipment*`、`equipment_recruit_ui`、`run_loop`、`run_manager`、`full_route` 测试随后由 Task 5/6/7/8 改其依赖的 API 时一并迁移，不在本任务。

- [ ] **Step 1: 改 equipment_data_test.gd**

把 `test_loads_equipment_pool` 改为：

```gdscript
func test_loads_equipment_pool() -> void:
	assert_bool(EquipmentDataManager.is_loaded).is_true()
	assert_int(EquipmentDataManager.get_all_equipment().size()).is_equal(72)
	var armor := EquipmentDataManager.get_equipment("eq_ironwall_armor")
	assert_bool(armor != null).is_true()
	assert_int(armor.hp_bonus).is_equal(6)   # hp 主属性 × 史诗(rarity2)=6
	assert_int(armor.damage_bonus).is_equal(0)
```
（`test_missing_id_returns_null` 不变。）

- [ ] **Step 2: 改 equipment_data_query_test.gd**

```gdscript
func test_query_by_rarity_returns_only_that_rarity() -> void:
	var commons := EquipmentDataManager.get_equipment_by_rarity(EquipmentDefinition.Rarity.COMMON)
	assert_bool(commons.size() >= 8).is_true()
	for eq in commons:
		assert_int(eq.rarity).is_equal(EquipmentDefinition.Rarity.COMMON)

func test_query_by_slot_returns_only_that_slot() -> void:
	var weapons := EquipmentDataManager.get_equipment_by_slot(EquipmentDefinition.Slot.MAIN_WEAPON)
	var ids: Array[String] = []
	for eq in weapons:
		assert_int(eq.slot).is_equal(EquipmentDefinition.Slot.MAIN_WEAPON)
		ids.append(eq.id)
	assert_array(ids).contains(["eq_berserker_mainweapon"])

func test_existing_equipment_has_default_fields() -> void:
	var armor := EquipmentDataManager.get_equipment("eq_ironwall_armor")
	assert_object(armor).is_not_null()
	assert_int(armor.rarity).is_equal(EquipmentDefinition.Rarity.EPIC)
	assert_str(armor.set_id).is_equal("set_ironwall")
```

- [ ] **Step 3: 迁移其余三文件的旧 id 引用**

打开 `tests/unit/unit_instance_equipment/unit_instance_equipment_test.gd`、`tests/integration/equipment_battle/equipment_battle_test.gd`、`tests/integration/equipment_slots/equipment_slots_e2e_test.gd`，用 `grep -n "eq_" <file>` 定位每处旧 id，按顶部映射表替换为新 id，并把断言的增量值改为新值：
- `eq_plate` → `eq_ironwall_armor`，hp 增量 `3` → `6`
- `eq_cutlass` → `eq_berserker_mainweapon`，damage 增量 `1` → `3`
- 其余旧 id（`eq_spyglass`/`eq_boots` 等）→ 选同槽新件：望远镜(range,slot 视原值)→`eq_frost_head` 之类；以「新件实际 slot/增量」为准重写对应断言。替换后确保每个测试断言的数值取自 `EquipmentDataManager.get_equipment(新id)` 的真实字段（可在测试里直接读 `def.hp_bonus` 断言，避免硬编码漂移）。

- [ ] **Step 4: 跑这五个测试确认通过**

Run: `... -a res://tests/unit/equipment -a res://tests/unit/unit_instance_equipment -a res://tests/integration/equipment_battle -a res://tests/integration/equipment_slots`
Expected: 全 PASS。

- [ ] **Step 5: 提交**

```bash
git add tests/
git commit -m "test(equipment): migrate legacy-id tests to 72-piece set scheme

Story: set-bonus-foundation
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: 套装计数器 API

**Files:**
- Modify: `src/autoloads/run_manager.gd`
- Test: `tests/unit/run_manager/set_counter_test.gd` (create)

**Interfaces:**
- Consumes: `_roster_equipment[crew_id] = {slot:int → eid}`；`EquipmentDataManager.get_equipment(eid).set_id`。
- Produces:
  - `RunManager.get_set_counts(crew_id: String) -> Dictionary`（`{set_id → count}`，仅含 ≥1）
  - `RunManager.get_dominant_set(crew_id: String) -> String`（件数最多；并列字典序最小；无→""）
  - `RunManager.get_active_set_tier(crew_id: String, set_id: String) -> int`（0/3/6/9）
  - `RunManager.SET_TIERS: Array`（[3,6,9]）

- [ ] **Step 1: 写失败测试**

创建 `tests/unit/run_manager/set_counter_test.gd`：

```gdscript
# 套装计数器：件数 / 主套（并列字典序）/ 激活档位。
extends GdUnitTestSuite

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._roster_equipment.clear()

func test_set_counts_groups_by_set_id() -> void:
	RunManager._roster_equipment["c1"] = {
		0: "eq_ironwall_mainweapon",
		3: "eq_ironwall_armor",
		2: "eq_berserker_head",
	}
	var counts := RunManager.get_set_counts("c1")
	assert_int(int(counts.get("set_ironwall", 0))).is_equal(2)
	assert_int(int(counts.get("set_berserker", 0))).is_equal(1)

func test_dominant_set_is_most_held() -> void:
	RunManager._roster_equipment["c1"] = {
		0: "eq_ironwall_mainweapon",
		3: "eq_ironwall_armor",
		2: "eq_berserker_head",
	}
	assert_str(RunManager.get_dominant_set("c1")).is_equal("set_ironwall")

func test_dominant_set_tie_breaks_lexicographically() -> void:
	RunManager._roster_equipment["c1"] = {
		0: "eq_ironwall_mainweapon",
		2: "eq_berserker_head",
	}
	# 并列 1:1 → 字典序最小 set_berserker < set_ironwall
	assert_str(RunManager.get_dominant_set("c1")).is_equal("set_berserker")

func test_dominant_set_empty_when_no_equipment() -> void:
	assert_str(RunManager.get_dominant_set("nobody")).is_equal("")

func test_active_tier_thresholds() -> void:
	var slots: Dictionary = {}
	for i in range(6):
		slots[i] = ["eq_ironwall_mainweapon", "eq_ironwall_offweapon", "eq_ironwall_head", "eq_ironwall_armor", "eq_ironwall_gloves", "eq_ironwall_legs"][i]
	RunManager._roster_equipment["c1"] = slots
	assert_int(RunManager.get_active_set_tier("c1", "set_ironwall")).is_equal(6)
	assert_int(RunManager.get_active_set_tier("c1", "set_berserker")).is_equal(0)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `... -a res://tests/unit/run_manager/set_counter_test.gd`
Expected: FAIL（`get_set_counts` 未定义）

- [ ] **Step 3: 实现**

在 `run_manager.gd` 的 `get_equipment_for` 之后追加（并在常量区加 `const SET_TIERS := [3, 6, 9]`）：

```gdscript
# ── 套装计数器（②b-1；本期只读，供偏向逻辑/纸娃娃/未来效果引擎共用）──

# 某船员各套持有件数 {set_id → count}（仅含 ≥1；无套装件不计）。
func get_set_counts(crew_id: String) -> Dictionary:
	var counts: Dictionary = {}
	var slots: Variant = _roster_equipment.get(crew_id, {})
	if slots is Dictionary:
		for s in (slots as Dictionary):
			var def := EquipmentDataManager.get_equipment(str((slots as Dictionary)[s]))
			if def != null and def.set_id != "":
				counts[def.set_id] = int(counts.get(def.set_id, 0)) + 1
	return counts

# 主套：持有件数最多的 set_id；并列取字典序最小；无装备返回 ""。
func get_dominant_set(crew_id: String) -> String:
	var counts := get_set_counts(crew_id)
	var best := ""
	var best_n := 0
	for sid in counts:
		var n := int(counts[sid])
		if n > best_n or (n == best_n and (best == "" or str(sid) < best)):
			best = str(sid)
			best_n = n
	return best

# 该套已激活档位（≤件数的最大阈值 ∈ {0,3,6,9}）。
func get_active_set_tier(crew_id: String, set_id: String) -> int:
	var n := int(get_set_counts(crew_id).get(set_id, 0))
	for t in [9, 6, 3]:
		if n >= t:
			return t
	return 0
```

- [ ] **Step 4: 跑测试确认通过**

Run: `... -a res://tests/unit/run_manager/set_counter_test.gd`
Expected: PASS (5/5)

- [ ] **Step 5: 提交**

```bash
git add src/autoloads/run_manager.gd tests/unit/run_manager/set_counter_test.gd
git commit -m "feat(run): set counter (counts/dominant/active-tier)

Story: set-bonus-foundation
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: 起始/招募直发 3 件（80% 同套）

**Files:**
- Modify: `src/autoloads/run_manager.gd`
- Modify: `src/ui/route_scene.gd`
- Test: `tests/unit/run_equipment/initial_grant_test.gd` (create)
- Modify: `tests/integration/equipment_recruit_ui/equipment_recruit_ui_test.gd`、`tests/unit/run_equipment/run_equipment_roll_test.gd`、`tests/unit/run_equipment/run_equipment_test.gd`、`tests/unit/run_manager/run_manager_test.gd`、`tests/integration/run_loop/run_loop_test.gd`、`tests/integration/chart_course/full_route_test.gd`（凡调 `confirm_recruit(id, [...])` / `roll_recruit_equipment` 处）。

**Interfaces:**
- Produces:
  - `RunManager.INITIAL_GRANT: int`(=3)、`SAME_SET_CHANCE: int`(=80)
  - `RunManager.roll_initial_equipment() -> Array[String]`（3 个 eid，不同槽，80% 同套）
  - `RunManager.confirm_recruit(unit_id: String) -> void`（**签名变更**：移除 equip_picks；内部直发 3 件）
- Consumes: `get_set_counts`（Task 4，间接）、`_rng`。
- 删除：`roll_recruit_equipment`、`_pending_recruit_equip`、`RECRUIT_EQUIP_ROLL/PICK`、`SAME_SLOT_CAP`、`_roll_rarity`、`_equip_subpool`、`_RARITY_WEIGHTS`（招募滚装旧机制整体退役）。

- [ ] **Step 1: 写失败测试**

创建 `tests/unit/run_equipment/initial_grant_test.gd`：

```gdscript
# 起始/招募直发 3 件：不同槽、80% 同套分支可复现。
extends GdUnitTestSuite

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._roster_equipment.clear()
	RunManager._rng.seed = 12345

func test_initial_grant_returns_three_distinct_slots() -> void:
	var eids := RunManager.roll_initial_equipment()
	assert_int(eids.size()).is_equal(3)
	var slots: Dictionary = {}
	for eid in eids:
		var def := EquipmentDataManager.get_equipment(eid)
		assert_object(def).is_not_null()
		assert_bool(slots.has(def.slot)).is_false()
		slots[def.slot] = true

func test_confirm_recruit_grants_three_pieces() -> void:
	RunManager._last_offers = []
	# 取一个 pool 船员 id
	var crew_id := ""
	for def in UnitDataManager.get_all_units():
		if def is CrewDefinition and (def as CrewDefinition).recruit_pool_tier == "pool":
			crew_id = (def as CrewDefinition).id
			break
	assert_str(crew_id).is_not_equal("")
	RunManager.roster.clear()
	RunManager.confirm_recruit(crew_id)
	assert_int(RunManager.get_equipment_for(crew_id).size()).is_equal(3)
```

- [ ] **Step 2: 跑测试确认失败**

Run: `... -a res://tests/unit/run_equipment/initial_grant_test.gd`
Expected: FAIL（`roll_initial_equipment` 未定义 / `confirm_recruit` 参数不符）

- [ ] **Step 3: 实现 RunManager 改动**

在常量区：删 `RECRUIT_EQUIP_ROLL/RECRUIT_EQUIP_PICK/SAME_SLOT_CAP/_RARITY_WEIGHTS`，加：

```gdscript
const INITIAL_GRANT := 3
const SAME_SET_CHANCE := 80
```

删 `_pending_recruit_equip` 字段、`_roll_rarity`、`_equip_subpool`、`roll_recruit_equipment`（整段移除）。

加入直发逻辑（放在计数器之后）：

```gdscript
# 全部 set_id（去重排序，确定性）。
func _all_set_ids() -> Array[String]:
	var seen: Dictionary = {}
	for eq in EquipmentDataManager.get_all_equipment():
		if eq.set_id != "":
			seen[eq.set_id] = true
	var out: Array[String] = []
	for k in seen:
		out.append(str(k))
	out.sort()
	return out

# 从 pool 里挑不同槽装备追加到 result（就地改 result/used_slots），直到 want 件或耗尽。
func _fill_distinct_slots(result: Array, used_slots: Dictionary, pool: Array, want: int) -> void:
	var candidates: Array = pool.duplicate()
	# 洗牌（Fisher-Yates，走 _rng）。
	for i in range(candidates.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: Variant = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp
	for eq in candidates:
		if result.size() >= want:
			break
		if not used_slots.has(eq.slot):
			used_slots[eq.slot] = true
			result.append(eq.id)

# 起始/招募直发 3 件：80% 概率 3 件同套，否则混搭；均不同槽。
func roll_initial_equipment() -> Array[String]:
	var result: Array[String] = []
	var used_slots: Dictionary = {}
	var all := EquipmentDataManager.get_all_equipment()
	if all.is_empty():
		return result
	if _rng.randi_range(0, 99) < SAME_SET_CHANCE:
		var set_ids := _all_set_ids()
		if not set_ids.is_empty():
			var anchor := set_ids[_rng.randi_range(0, set_ids.size() - 1)]
			var pool: Array = []
			for eq in all:
				if eq.set_id == anchor:
					pool.append(eq)
			_fill_distinct_slots(result, used_slots, pool, INITIAL_GRANT)
	# 不足（含混搭分支与同套槽不够）→ 从全池补足。
	_fill_distinct_slots(result, used_slots, all, INITIAL_GRANT)
	return result

# 把若干 eid 按其 slot 写入某船员装备账本（覆盖同槽）。
func _grant_equipment(crew_id: String, eids: Array) -> void:
	var slots: Dictionary = _roster_equipment.get(crew_id, {})
	slots = slots.duplicate()
	for raw in eids:
		var def := EquipmentDataManager.get_equipment(str(raw))
		if def != null:
			slots[def.slot] = str(raw)
	if not slots.is_empty():
		_roster_equipment[crew_id] = slots
```

重写 `confirm_recruit`：

```gdscript
# 选中候选加入 roster + 直发 3 件装备（80% 同套）。→CHARTING。
func confirm_recruit(unit_id: String) -> void:
	var def := UnitDataManager.get_unit(unit_id)
	if def is CrewDefinition:
		roster.append(def as CrewDefinition)
		_grant_equipment(unit_id, roll_initial_equipment())
	else:
		push_error("RunManager.confirm_recruit: unit_id 非 CrewDefinition 或不存在 — %s" % unit_id)
	for offered_id in _last_offers:
		if offered_id != unit_id and not _excluded_offers.has(offered_id):
			_excluded_offers.append(offered_id)
	_last_offers.clear()
	_set_run_phase(RunPhase.RUN_CHARTING)
```

在 `start_run` 的 roster 填充循环后追加（起始船员发 3 件）：

```gdscript
	for c in roster:
		_grant_equipment(c.id, roll_initial_equipment())
```
（放在 `_set_run_phase(RunPhase.RUN_CHARTING)` 之前。）

并在 `start_run` 顶部删除 `_pending_recruit_equip.clear()` 行。

- [ ] **Step 4: 实现 RouteScene 招募改动**

把 `_on_recruit_chosen` 改为直发 + 通知：

```gdscript
func _on_recruit_chosen(unit_id: String) -> void:
	RunManager.confirm_recruit(unit_id)
	_show_recruit_grant_notice(unit_id)

# 招募直发通知：列出新船员获得的 3 件 + 纸娃娃 → 继续进选航。
func _show_recruit_grant_notice(unit_id: String) -> void:
	_clear_ui()
	_active_screen = "recruit_grant"
	var box := VBoxContainer.new()
	add_child(box)
	box.set_anchors_preset(Control.PRESET_CENTER)
	var title := Label.new()
	title.text = "新船员入队，获得 3 件装备"
	box.add_child(title)
	box.add_child(_build_paperdoll(unit_id))
	var cont := Button.new()
	cont.text = "继续"
	cont.pressed.connect(_show_route_offers)
	box.add_child(cont)
```

删除 `_show_equip_picks` 整个函数（已被直发取代）。`_build_paperdoll` 由 Task 8 提供；本任务先放占位实现以便编译：在文件末尾临时加

```gdscript
# 纸娃娃（Task 8 完整实现；此处临时最小版，Task 8 覆盖）。
func _build_paperdoll(crew_id: String) -> Control:
	var v := VBoxContainer.new()
	var eq := RunManager.get_equipment_for(crew_id)
	for slot in range(9):
		var l := Label.new()
		var def: EquipmentDefinition = eq.get(slot, null)
		l.text = "%s：%s" % [_SLOT_NOUNS[slot], def.display_name if def != null else "空"]
		v.add_child(l)
	return v
```
并在 route_scene 常量区加 `const _SLOT_NOUNS := ["主武器","副武器","头","护甲","手","腿","靴","戒指","项链"]`。

- [ ] **Step 5: 迁移受影响测试**

- `tests/integration/equipment_recruit_ui/equipment_recruit_ui_test.gd`：原断言「滚 8 选 2 后 get_equipment_for==2」改为「confirm_recruit 后 get_equipment_for==3」；移除任何 `roll_recruit_equipment`/`_show_equip_picks`/`equip_picks` 调用。
- `tests/unit/run_equipment/run_equipment_roll_test.gd`：测的是已删的 `roll_recruit_equipment`；**删除该文件**（其确定性/同槽≤2 不变量已随机制退役；新滚装由 initial_grant_test + Task 6 battle-roll 测覆盖）。
- `tests/unit/run_equipment/run_equipment_test.gd`、`tests/unit/run_manager/run_manager_test.gd`、`tests/integration/run_loop/run_loop_test.gd`、`tests/integration/chart_course/full_route_test.gd`：`grep -n "confirm_recruit(" <file>`，把所有 `confirm_recruit(id, [...])` 改为 `confirm_recruit(id)`；删除对 `_pending_recruit_equip` 的断言；招募后若断言装备数，从「2」改为「3」。

- [ ] **Step 6: 导入 + 跑相关测试**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --import` 然后
`... -a res://tests/unit/run_equipment -a res://tests/unit/run_manager -a res://tests/integration/equipment_recruit_ui -a res://tests/integration/run_loop -a res://tests/integration/chart_course`
Expected: 全 PASS。

- [ ] **Step 7: 提交**

```bash
git add src/autoloads/run_manager.gd src/ui/route_scene.gd tests/
git commit -m "feat(run): direct-grant 3 equipment at start/recruit (80% same-set)

退役招募滚8选2，改为直发 3 件；起始船员同样发 3 件。
Story: set-bonus-foundation
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: 战后滚 8 选 2（偏向主套）+ RUN_EQUIPPING 阶段

**Files:**
- Modify: `src/autoloads/run_manager.gd`
- Test: `tests/unit/run_equipment/battle_equip_test.gd` (create)

**Interfaces:**
- Produces:
  - `RunManager.RunPhase.RUN_EQUIPPING`（枚举新增）、`_PHASE_TO_STRING` 加 `"EQUIPPING"`
  - `RunManager.BATTLE_ROLL`(=8)、`BATTLE_PICK`(=2)、`BIAS_CHANCE`(=80)
  - `RunManager._pending_battle_equip: Dictionary`（crew_id → Array[String]）
  - `RunManager.roll_battle_equipment(crew_id: String) -> Array[String]`（8 件，80% 偏向主套空槽）
  - `RunManager.equip_piece(crew_id: String, eid: String, replace: bool) -> bool`
  - `RunManager.finish_crew_equip(crew_id: String) -> void`
  - `RunManager.get_pending_battle_equip() -> Dictionary`
- Consumes: `get_dominant_set`（Task 4）、`pending_deploy`、`roster`。

- [ ] **Step 1: 写失败测试**

创建 `tests/unit/run_equipment/battle_equip_test.gd`：

```gdscript
# 战后滚 8 选 2 + 偏向主套 + 阶段流转。
extends GdUnitTestSuite

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._roster_equipment.clear()
	RunManager._pending_battle_equip.clear()
	RunManager._rng.seed = 777

func test_roll_battle_returns_eight() -> void:
	var rolled := RunManager.roll_battle_equipment("c1")
	assert_int(rolled.size()).is_equal(8)

func test_roll_battle_biases_toward_dominant_set() -> void:
	# c1 主套 set_ironwall（2 件）
	RunManager._roster_equipment["c1"] = {0: "eq_ironwall_mainweapon", 3: "eq_ironwall_armor"}
	var rolled := RunManager.roll_battle_equipment("c1")
	var same := 0
	for eid in rolled:
		var def := EquipmentDataManager.get_equipment(eid)
		if def != null and def.set_id == "set_ironwall":
			same += 1
	assert_int(same).is_greater(4)   # 80% 偏向 → 多数同套（固定 seed 下稳定）

func test_equip_piece_fills_empty_slot() -> void:
	var ok := RunManager.equip_piece("c1", "eq_ironwall_head", false)
	assert_bool(ok).is_true()
	assert_int(RunManager.get_equipment_for("c1").size()).is_equal(1)

func test_equip_piece_rejects_occupied_without_replace() -> void:
	RunManager.equip_piece("c1", "eq_ironwall_head", false)
	# eq_berserker_head 同为 head 槽
	var ok := RunManager.equip_piece("c1", "eq_berserker_head", false)
	assert_bool(ok).is_false()
	assert_str(str(RunManager.get_equipment_for("c1")[2].id)).is_equal("eq_ironwall_head")

func test_equip_piece_replaces_when_allowed() -> void:
	RunManager.equip_piece("c1", "eq_ironwall_head", false)
	var ok := RunManager.equip_piece("c1", "eq_berserker_head", true)
	assert_bool(ok).is_true()
	assert_str(str(RunManager.get_equipment_for("c1")[2].id)).is_equal("eq_berserker_head")
```

- [ ] **Step 2: 跑测试确认失败**

Run: `... -a res://tests/unit/run_equipment/battle_equip_test.gd`
Expected: FAIL（成员/方法未定义）

- [ ] **Step 3: 实现**

枚举加 `RUN_EQUIPPING`（放在 `RUN_RECRUITING` 之后）；`_PHASE_TO_STRING` 加 `RunPhase.RUN_EQUIPPING: "EQUIPPING",`。常量加：

```gdscript
const BATTLE_ROLL := 8
const BATTLE_PICK := 2
const BIAS_CHANCE := 80
```
字段加：`var _pending_battle_equip: Dictionary = {}   # crew_id → Array[String]（战后 8 件候选）`

`_on_run_phase_entered` 的 `match phase` 加分支（紧随 RUN_RECRUITING）：

```gdscript
		RunPhase.RUN_EQUIPPING:
			EventBus.run_phase_changed.emit("EQUIPPING")
```
并把自动存档 match 的航点行改为包含 EQUIPPING：

```gdscript
			RunPhase.RUN_DEPLOYING, RunPhase.RUN_RECRUITING, RunPhase.RUN_CHARTING, RunPhase.RUN_EQUIPPING:
				save_run()
```

实现方法（放在 Task 5 的发装逻辑之后）：

```gdscript
# 某船员已占槽集合。
func _owned_slots(crew_id: String) -> Dictionary:
	var out: Dictionary = {}
	var slots: Variant = _roster_equipment.get(crew_id, {})
	if slots is Dictionary:
		for s in (slots as Dictionary):
			out[int(s)] = true
	return out

# 战后滚 8 件：每件独立 80% 偏向主套（优先未拥有空槽件），否则随机。
func roll_battle_equipment(crew_id: String) -> Array[String]:
	var out: Array[String] = []
	var all := EquipmentDataManager.get_all_equipment()
	if all.is_empty():
		return out
	var dominant := get_dominant_set(crew_id)
	var owned := _owned_slots(crew_id)
	var dom_pool: Array = []
	var dom_empty: Array = []
	if dominant != "":
		for eq in all:
			if eq.set_id == dominant:
				dom_pool.append(eq)
				if not owned.has(eq.slot):
					dom_empty.append(eq)
	for i in range(BATTLE_ROLL):
		var pick: EquipmentDefinition = null
		if dominant != "" and _rng.randi_range(0, 99) < BIAS_CHANCE:
			var src: Array = dom_empty if not dom_empty.is_empty() else dom_pool
			if not src.is_empty():
				pick = src[_rng.randi_range(0, src.size() - 1)]
		if pick == null:
			pick = all[_rng.randi_range(0, all.size() - 1)]
		out.append(pick.id)
	return out

# 装上一件：空槽直接装；已占槽需 replace=true 才覆盖（丢弃旧件）。返回是否装上。
func equip_piece(crew_id: String, eid: String, replace: bool) -> bool:
	var def := EquipmentDataManager.get_equipment(eid)
	if def == null:
		return false
	var slots: Dictionary = (_roster_equipment.get(crew_id, {}) as Dictionary).duplicate()
	if slots.has(def.slot) and not replace:
		return false
	slots[def.slot] = eid
	_roster_equipment[crew_id] = slots
	return true

# 某船员补装完成 → 出队列；空则转招募。
func finish_crew_equip(crew_id: String) -> void:
	_pending_battle_equip.erase(crew_id)
	if _pending_battle_equip.is_empty():
		_set_run_phase(RunPhase.RUN_RECRUITING)

func get_pending_battle_equip() -> Dictionary:
	return _pending_battle_equip.duplicate(true)
```

- [ ] **Step 4: 跑测试确认通过**

Run: `... -a res://tests/unit/run_equipment/battle_equip_test.gd`
Expected: PASS (5/5)。`_PHASE_TO_STRING` 完整性 assert 不触发（已同步）。

- [ ] **Step 5: 提交**

```bash
git add src/autoloads/run_manager.gd tests/unit/run_equipment/battle_equip_test.gd
git commit -m "feat(run): post-battle roll-8 (dominant-set bias) + equip + EQUIPPING phase

Story: set-bonus-foundation
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: 战后流转接缝（_on_battle_won）+ 存档持久化

**Files:**
- Modify: `src/autoloads/run_manager.gd`
- Test: `tests/unit/run_equipment/battle_equip_flow_test.gd` (create)
- Test: `tests/unit/run_equipment/run_equipment_save_test.gd`（追加用例）

**Interfaces:**
- Consumes: `roll_battle_equipment`、`pending_deploy`、`roster`、`_pending_battle_equip`（Task 6）。
- Produces: `_on_battle_won` 非末岛分支先进 `RUN_EQUIPPING`（有出战存活者时）；`to_save_dict`/`load_from_save_dict` 持久化 `_pending_battle_equip`；`_phase_from_string` 支持 `"EQUIPPING"`。

- [ ] **Step 1: 写失败测试**

创建 `tests/unit/run_equipment/battle_equip_flow_test.gd`：

```gdscript
# 战后非末岛 → 为出战存活者滚候选 → 进 EQUIPPING；全选完 → RECRUITING。
extends GdUnitTestSuite

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._roster_equipment.clear()
	RunManager._pending_battle_equip.clear()
	RunManager._goto_route = func() -> void: pass   # no-op 防切场景
	RunManager._rng.seed = 99

func _crew(id_substr_tier: String) -> CrewDefinition:
	for def in UnitDataManager.get_all_units():
		if def is CrewDefinition and (def as CrewDefinition).recruit_pool_tier == id_substr_tier:
			return def as CrewDefinition
	return null

func test_battle_won_enters_equipping_for_survivors() -> void:
	var c := _crew("starting")
	RunManager.roster = [c]
	RunManager.pending_deploy = [c]
	RunManager.current_island_index = 0   # 非末岛
	RunManager._on_battle_won()
	assert_str(RunManager.current_phase).is_equal("EQUIPPING")
	assert_bool(RunManager.get_pending_battle_equip().has(c.id)).is_true()
	assert_int((RunManager.get_pending_battle_equip()[c.id] as Array).size()).is_equal(8)

func test_finish_all_advances_to_recruiting() -> void:
	var c := _crew("starting")
	RunManager.roster = [c]
	RunManager.pending_deploy = [c]
	RunManager.current_island_index = 0
	RunManager._on_battle_won()
	RunManager.finish_crew_equip(c.id)
	assert_str(RunManager.current_phase).is_equal("RECRUITING")
```

并向 `tests/unit/run_equipment/run_equipment_save_test.gd` 追加：

```gdscript
func test_pending_battle_equip_roundtrips() -> void:
	RunManager._autosave_enabled = false
	RunManager._roster_equipment.clear()
	RunManager._pending_battle_equip = {"c1": ["eq_ironwall_head", "eq_ironwall_armor"]}
	var d := RunManager.to_save_dict()
	RunManager._pending_battle_equip.clear()
	RunManager.load_from_save_dict(d)
	assert_bool(RunManager.get_pending_battle_equip().has("c1")).is_true()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `... -a res://tests/unit/run_equipment/battle_equip_flow_test.gd -a res://tests/unit/run_equipment/run_equipment_save_test.gd`
Expected: FAIL

- [ ] **Step 3: 实现 _on_battle_won 改动**

把非末岛分支（原最后两行）替换为：

```gdscript
	# 非末岛：为本场出战且存活（仍在 roster）的船员滚战后候选。
	_pending_battle_equip.clear()
	var roster_ids: Dictionary = {}
	for c in roster:
		roster_ids[c.id] = true
	for c in pending_deploy:
		if roster_ids.has(c.id):
			_pending_battle_equip[c.id] = roll_battle_equipment(c.id)
	if not _pending_battle_equip.is_empty():
		_set_run_phase(RunPhase.RUN_EQUIPPING)
		_goto_route.call()
		return
	_set_run_phase(RunPhase.RUN_RECRUITING)
	_goto_route.call()
```

- [ ] **Step 4: 实现存档持久化**

`to_save_dict` 返回字典加一项：`"pending_battle_equip": _pending_battle_equip.duplicate(true),`

`load_from_save_dict`：在恢复 `_roster_equipment` 之后追加：

```gdscript
	# 战后候选恢复：仅保留仍在 roster 的 crew，eid 必须存在。
	_pending_battle_equip.clear()
	var pbe: Variant = d.get("pending_battle_equip", {})
	if pbe is Dictionary:
		for k in (pbe as Dictionary):
			var cid := str(k)
			if not roster_id_set.has(cid):
				continue
			var raw: Variant = (pbe as Dictionary)[k]
			var eids: Array[String] = []
			if raw is Array:
				for e in (raw as Array):
					if EquipmentDataManager.get_equipment(str(e)) != null:
						eids.append(str(e))
			if not eids.is_empty():
				_pending_battle_equip[cid] = eids
```

`_phase_from_string` 加分支：`"EQUIPPING": return RunPhase.RUN_EQUIPPING`

- [ ] **Step 5: 跑测试确认通过**

Run: `... -a res://tests/unit/run_equipment/battle_equip_flow_test.gd -a res://tests/unit/run_equipment/run_equipment_save_test.gd`
Expected: PASS

- [ ] **Step 6: 提交**

```bash
git add src/autoloads/run_manager.gd tests/unit/run_equipment/
git commit -m "feat(run): battle-won enters EQUIPPING; persist pending_battle_equip

Story: set-bonus-foundation
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 8: RouteScene EQUIPPING 分支 + 人形纸娃娃

**Files:**
- Modify: `src/ui/route_scene.gd`
- Test: `tests/integration/battle_equip_ui/battle_equip_ui_test.gd` (create)

**Interfaces:**
- Consumes: `get_pending_battle_equip`、`equip_piece`、`finish_crew_equip`、`get_equipment_for`、`get_set_counts`、`get_active_set_tier`、`EquipmentDefinition.rarity_color/rarity_label`、`SET_TIERS`。
- Produces: RouteScene `EQUIPPING` 分支渲染补装屏 + 完整 `_build_paperdoll`。

- [ ] **Step 1: 写失败测试（白盒交互）**

创建 `tests/integration/battle_equip_ui/battle_equip_ui_test.gd`：

```gdscript
# 补装屏：EQUIPPING 分支渲染候选 + 纸娃娃；equip + finish 推进。
extends GdUnitTestSuite

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._roster_equipment.clear()
	RunManager._pending_battle_equip.clear()
	RunManager._goto_route = func() -> void: pass

func test_equipping_branch_builds_paperdoll() -> void:
	var c: CrewDefinition = null
	for def in UnitDataManager.get_all_units():
		if def is CrewDefinition and (def as CrewDefinition).recruit_pool_tier == "starting":
			c = def as CrewDefinition
			break
	RunManager.roster = [c]
	RunManager.pending_deploy = [c]
	RunManager.current_island_index = 0
	RunManager._on_battle_won()   # → EQUIPPING + pending 候选
	var scene := RouteScene.new()
	add_child(scene)
	scene._ready()
	assert_str(scene._active_screen).is_equal("battle_equip")
	# 纸娃娃含 9 个槽行
	scene.queue_free()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --import` 然后 `... -a res://tests/integration/battle_equip_ui/battle_equip_ui_test.gd`
Expected: FAIL（`_active_screen != "battle_equip"`）

- [ ] **Step 3: 实现 RouteScene EQUIPPING 分支**

`_ready` 的 match 加分支（在 `"CHARTING"` 之后）：

```gdscript
		"EQUIPPING":
			_show_battle_equip()
```

替换 Task 5 临时的 `_build_paperdoll` 为完整版，并加补装屏：

```gdscript
# 战后补装屏：取 pending 第一名未完成船员，渲染 8 候选 + 纸娃娃。
func _show_battle_equip() -> void:
	var pending := RunManager.get_pending_battle_equip()
	if pending.is_empty():
		_notice_then(_show_recruit_offers)   # 兜底（无候选）
		return
	var crew_id := ""
	for k in pending:
		crew_id = str(k)
		break
	_clear_ui()
	_active_screen = "battle_equip"
	var picked: Array[String] = []     # 本船员已选 eid
	var row := HBoxContainer.new()
	add_child(row)
	row.set_anchors_preset(Control.PRESET_CENTER)
	# 左：候选
	var left := VBoxContainer.new()
	row.add_child(left)
	var crew_def := UnitDataManager.get_unit(crew_id)
	var title := Label.new()
	title.text = "为 %s 选至多 %d 件（已选 0/%d）" % [
		(crew_def as CrewDefinition).display_name if crew_def is CrewDefinition else crew_id,
		RunManager.BATTLE_PICK, RunManager.BATTLE_PICK]
	left.add_child(title)
	var doll_holder := VBoxContainer.new()
	for eid in (pending[crew_id] as Array):
		var eq := EquipmentDataManager.get_equipment(str(eid))
		if eq == null:
			continue
		var b := Button.new()
		b.text = _equipment_summary(eq) + "〔%s〕" % eq.set_id
		b.add_theme_color_override("font_color", EquipmentDefinition.rarity_color(eq.rarity))
		b.pressed.connect(func() -> void:
			if picked.size() >= RunManager.BATTLE_PICK:
				return
			var occupied := RunManager.get_equipment_for(crew_id).has(eq.slot)
			# 占槽则替换（白盒直接替换；正式版可加确认）。
			RunManager.equip_piece(crew_id, eq.id, occupied)
			picked.append(eq.id)
			b.disabled = true
			title.text = "为 %s 选至多 %d 件（已选 %d/%d）" % [
				(crew_def as CrewDefinition).display_name if crew_def is CrewDefinition else crew_id,
				RunManager.BATTLE_PICK, picked.size(), RunManager.BATTLE_PICK]
			_refresh_paperdoll(doll_holder, crew_id)
		)
		left.add_child(b)
	var done := Button.new()
	done.text = "完成"
	done.pressed.connect(func() -> void:
		RunManager.finish_crew_equip(crew_id)
		_clear_ui()
		if RunManager.current_phase == "EQUIPPING":
			_show_battle_equip()        # 下一名
		else:
			_notice_then(_show_recruit_offers)
	)
	left.add_child(done)
	# 右：纸娃娃
	row.add_child(doll_holder)
	_refresh_paperdoll(doll_holder, crew_id)

func _refresh_paperdoll(holder: VBoxContainer, crew_id: String) -> void:
	for ch in holder.get_children():
		ch.queue_free()
	holder.add_child(_build_paperdoll(crew_id))

# 人形纸娃娃：9 槽逐行（部件名 + 装备名彩色 + 套装标签）+ 顶部激活套装档位。
func _build_paperdoll(crew_id: String) -> Control:
	var v := VBoxContainer.new()
	var counts := RunManager.get_set_counts(crew_id)
	for sid in counts:
		var tier := RunManager.get_active_set_tier(crew_id, str(sid))
		var head := Label.new()
		head.text = "%s %d/9%s" % [str(sid), int(counts[sid]), "（已激活 %d）" % tier if tier > 0 else ""]
		v.add_child(head)
	var eq := RunManager.get_equipment_for(crew_id)
	for slot in range(9):
		var l := Label.new()
		var def: EquipmentDefinition = eq.get(slot, null)
		if def != null:
			l.text = "%s：%s〔%s〕" % [_SLOT_NOUNS[slot], def.display_name, def.set_id]
			l.add_theme_color_override("font_color", EquipmentDefinition.rarity_color(def.rarity))
		else:
			l.text = "%s：空" % _SLOT_NOUNS[slot]
		v.add_child(l)
	return v
```

- [ ] **Step 4: 跑测试确认通过**

Run: `... -a res://tests/integration/battle_equip_ui/battle_equip_ui_test.gd`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add src/ui/route_scene.gd tests/integration/battle_equip_ui/
git commit -m "feat(ui): post-battle equip screen with paper-doll

Story: set-bonus-foundation
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 9: 端到端集成 + 全量回归

**Files:**
- Test: `tests/integration/set_foundation/set_foundation_e2e_test.gd` (create)

**Interfaces:**
- Consumes: 全链（start_run → 战斗胜 → EQUIPPING → finish → RECRUITING → confirm_recruit → ...）。

- [ ] **Step 1: 写端到端测试**

创建 `tests/integration/set_foundation/set_foundation_e2e_test.gd`：

```gdscript
# 端到端：起航发 3 件 → 战斗胜进 EQUIPPING → 补装 → 招募发 3 件，件数随 run 增长。
extends GdUnitTestSuite

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._goto_route = func() -> void: pass
	RunManager._goto_battle = func() -> void: pass
	RunManager._rng.seed = 2026

func test_starting_crew_get_three_then_grow_after_battle() -> void:
	RunManager.start_run()
	var first := RunManager.get_roster()[0]
	assert_int(RunManager.get_equipment_for(first.id).size()).is_equal(3)
	# 模拟部署该船员并打赢首岛
	RunManager.pending_deploy = [first]
	RunManager.current_island_index = 0
	RunManager._on_battle_won()
	assert_str(RunManager.current_phase).is_equal("EQUIPPING")
	# 选 2 件
	var cands: Array = RunManager.get_pending_battle_equip()[first.id]
	RunManager.equip_piece(first.id, str(cands[0]), true)
	RunManager.equip_piece(first.id, str(cands[1]), true)
	RunManager.finish_crew_equip(first.id)
	assert_str(RunManager.current_phase).is_equal("RECRUITING")
	# 件数 ≥3（替换可能不增槽，但不应减少）
	assert_int(RunManager.get_equipment_for(first.id).size()).is_greater_equal(3)
```

- [ ] **Step 2: 跑该测试确认通过**

Run: `... -a res://tests/integration/set_foundation/set_foundation_e2e_test.gd`
Expected: PASS

- [ ] **Step 3: 全量回归**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --import` 然后
`/Applications/Godot.app/Contents/MacOS/Godot --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests`
Expected: 全 PASS，0 errors / 0 failures / 0 orphans。若有红，定位修复（多为遗漏的 `confirm_recruit` 旧签名调用或旧 eid 引用）。

- [ ] **Step 4: 提交**

```bash
git add tests/integration/set_foundation/
git commit -m "test(set): end-to-end accumulation flow + full regression green

Story: set-bonus-foundation
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage：**
- §3.1 八套/72 件/全属套/配色 → Task 1（配色）+ Task 2（数据）。✅
- §3.2 容量 9 槽 → 既有结构，Task 6 `equip_piece` 守槽。✅
- §3.3 起始/招募直发 3 件 80% 同套 → Task 5。✅
- §3.4 战后滚 8 选 2 偏向主套 + 仅出战存活者 + 槽冲突替换 → Task 6（滚/装）+ Task 7（出战存活者筛选）+ Task 8（替换 UI）。✅
- §3.5 计数器 → Task 4。✅
- §3.6 RUN_EQUIPPING + 预滚存盘 → Task 6（阶段/字段）+ Task 7（流转/存档）。✅
- §3.7 获取 UI + 纸娃娃 + 配色 → Task 5（招募通知）+ Task 8（补装屏/纸娃娃）。✅
- §5 边界（空池降级/满槽/并列/中途退档/旧档/末岛）→ Task 5/6/7 实现 + Task 4 并列测试 + Task 7 旧档兼容（既有 load 逻辑保留）。✅
- §8 AC-1..8 → Task 2(AC1)/5(AC2)/6,7(AC3,4)/4(AC5)/7(AC6)/8(AC7)/9(AC8)。✅
- §9 非目标：全程不碰 BattleResolution/UnitInstance.get_*。✅

**Placeholder 扫描：** Task 5 Step4 临时 `_build_paperdoll` 由 Task 8 Step3 显式替换为完整版（非占位，已给完整代码）。无 TBD/TODO。

**类型一致性：** `confirm_recruit(unit_id)`（Task 5 起单参）全程一致；`roll_initial_equipment`/`roll_battle_equipment`/`equip_piece`/`finish_crew_equip`/`get_set_counts`/`get_dominant_set`/`get_active_set_tier` 签名在产出任务定义、消费任务一致；`RUN_EQUIPPING`/`"EQUIPPING"` 字符串一致；`_SLOT_NOUNS`（route_scene）与生成器 `SLOT_NOUNS` 各自独立（前者展示用全称，后者文件名用短词，刻意不同）。

**风险备注（执行者注意）：**
- Task 5 删除旧滚装机制会牵动多处测试；务必 `grep -rn "roll_recruit_equipment\|_pending_recruit_equip\|confirm_recruit(" tests/ src/` 清干净再跑全量。
- 生成器写入 res:// 后必须 `--import` 再跑测试，否则新 .tres 未建类名缓存。
- `_PHASE_TO_STRING` 完整性 assert 会在漏更新映射时即时报错（Task 6 已同步）。

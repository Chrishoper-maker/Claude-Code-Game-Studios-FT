# 海图选航骨架 + 多地图（子项目①）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把战斗地图从写死单图改造成"全程选航"——每场战斗前玩家从 3 张目的地卡选 1 张，决定本岛打哪张地图/敌情，端到端走通选航循环（用现有 4 种敌人）。

**Architecture:** 新增 `CHARTING` 阶段插在（`start_run`/`confirm_recruit`）与 `DEPLOYING` 之间；RunManager 复用现有 `_rng`/招募卡架构生成 3 张地图候选（按"即将抵达岛号"映射的 `island_tier` 过滤、本 run 不重复、确定性、小池优雅降级）；`confirm_route` 记所选 `map_id`；`battle_map.load_map` 改读所选图；RouteScene 新增白盒选航分支。新作 6 张地图（island_tier 1/2/3，全用 threat_tier-1 现有敌人，难度靠数量/站位拉开）。

**Tech Stack:** Godot 4.6.3 / GDScript / GdUnit4；autoload（RunManager / MapDataManager）；`MapDefinition`/`EnemySlotDefinition`/`TerrainCell` 资源；`RouteScene`（Control 白盒）；`battle_map.gd`。

## Global Constraints

- 引擎 Godot 4.6.3；跑测试前必 `"/Applications/Godot.app/Contents/MacOS/Godot" --headless --import`；GdUnit4 须加 `--ignoreHeadlessMode`。
- Godot 二进制：`/Applications/Godot.app/Contents/MacOS/Godot`。
- 全量测试命令：`"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests`，看 `Overall Summary` / `SCRIPT ERROR`。
- 静态类型纪律：禁 `var x := <Variant 表达式>`；`Dictionary.get(...)` 结果用 `var x: Variant` + 类型守卫或显式转换。
- autoload 脚本**不声明 class_name**（RunManager / MapDataManager 注册名即全局单例）。`RouteScene` 保留 `class_name RouteScene extends Control`。
- 游戏数值数据驱动（地图走 `.tres`，不硬编码于代码）。
- 单测确定性：测前 `RunManager._rng.seed = <固定值>`、`RunManager._autosave_enabled = false`、`_goto_battle`/`_goto_route` 覆盖为 no-op。
- 交互全部按钮，无自由文字输入（项目铁律）。
- 中文注释；标识符英文。trunk-based 在 main。
- 提交 Conventional Commits，body 带 `Story: chart-course-multi-map (#19)`，结尾 `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`。
- 地图站位须过 BattleMap Rule 3 校验（F1 blocked≤16 / F3 敌数 2–6 / F4 敌人距每个部署格 Manhattan≥3 / F5 敌人 threat_tier∈_allowed_threat_tiers(island_tier) / F6 存在长度≥3 连续非 BLOCKED 行或列 / 无位置冲突 / 不落 BLOCKED）。现有敌人全 threat_tier=1；`_allowed_threat_tiers`：island_tier 1,2→[1]、3,4→[1,2]，故本期地图 `island_tier` 仅用 1/2/3。

---

### Task 1: 新作 6 张地图 + MapDataManager.get_all_maps + 校验测试

**Files:**
- Create: `assets/data/maps/battle_map_002.tres` … `battle_map_007.tres`
- Modify: `src/autoloads/map_data_manager.gd`
- Test: `tests/integration/maps/map_pool_test.gd`

**Interfaces:**
- Produces: 6 个 `MapDefinition` 资源（`map_id` = `battle_map_002`..`007`，`island_tier` = 1/1/2/2/3/3）；`MapDataManager.get_all_maps() -> Array[MapDefinition]`。Task 3 用 `get_maps_for_tier`/`get_all_maps` 抽候选。

- [ ] **Step 1: 写 6 张地图资源**

公共约定：8×8 棋盘；`deploy_zone` 复用 001（行 6–7、列 0–5 共 12 格）；敌人全部位于行 0–3（保证 F4 距部署区≥3）；非守卫 `home_pos = Vector2i(-1, -1)`，守卫 `home_pos` = 其 `grid_position`；敌人 id 取现有 `enemy_{melee,ranged,swarmer,guardian}_tier1`。

`assets/data/maps/battle_map_002.tres`（礁石浅滩 / island_tier 1 / 3 敌，无地形）：

```gdscript
[gd_resource type="Resource" script_class="MapDefinition" load_steps=6 format=3]

[ext_resource type="Script" path="res://src/data/map_definition.gd" id="1"]
[ext_resource type="Script" path="res://src/data/enemy_slot_definition.gd" id="3"]

[sub_resource type="Resource" id="s1"]
script = ExtResource("3")
unit_definition_id = "enemy_melee_tier1"
grid_position = Vector2i(2, 0)
behavior_type = "MELEE"
home_pos = Vector2i(-1, -1)

[sub_resource type="Resource" id="s2"]
script = ExtResource("3")
unit_definition_id = "enemy_melee_tier1"
grid_position = Vector2i(5, 0)
behavior_type = "MELEE"
home_pos = Vector2i(-1, -1)

[sub_resource type="Resource" id="s3"]
script = ExtResource("3")
unit_definition_id = "enemy_swarmer_tier1"
grid_position = Vector2i(4, 2)
behavior_type = "SWARMER"
home_pos = Vector2i(-1, -1)

[resource]
script = ExtResource("1")
map_id = "battle_map_002"
display_name = "礁石浅滩"
terrain_data = Array[TerrainCell]([])
deploy_zone = Array[Vector2i]([Vector2i(0, 6), Vector2i(1, 6), Vector2i(2, 6), Vector2i(3, 6), Vector2i(4, 6), Vector2i(5, 6), Vector2i(0, 7), Vector2i(1, 7), Vector2i(2, 7), Vector2i(3, 7), Vector2i(4, 7), Vector2i(5, 7)])
enemy_roster = Array[EnemySlotDefinition]([SubResource("s1"), SubResource("s2"), SubResource("s3")])
island_tier = 1
annotated_engagement_distance = {}
map_scene_id = ""
```

`assets/data/maps/battle_map_003.tres`（雾锁湾口 / island_tier 1 / 3 敌，无地形）：

```gdscript
[gd_resource type="Resource" script_class="MapDefinition" load_steps=6 format=3]

[ext_resource type="Script" path="res://src/data/map_definition.gd" id="1"]
[ext_resource type="Script" path="res://src/data/enemy_slot_definition.gd" id="3"]

[sub_resource type="Resource" id="s1"]
script = ExtResource("3")
unit_definition_id = "enemy_ranged_tier1"
grid_position = Vector2i(1, 0)
behavior_type = "RANGED"
home_pos = Vector2i(-1, -1)

[sub_resource type="Resource" id="s2"]
script = ExtResource("3")
unit_definition_id = "enemy_melee_tier1"
grid_position = Vector2i(4, 0)
behavior_type = "MELEE"
home_pos = Vector2i(-1, -1)

[sub_resource type="Resource" id="s3"]
script = ExtResource("3")
unit_definition_id = "enemy_guardian_tier1"
grid_position = Vector2i(6, 2)
behavior_type = "GUARDIAN"
home_pos = Vector2i(6, 2)

[resource]
script = ExtResource("1")
map_id = "battle_map_003"
display_name = "雾锁湾口"
terrain_data = Array[TerrainCell]([])
deploy_zone = Array[Vector2i]([Vector2i(0, 6), Vector2i(1, 6), Vector2i(2, 6), Vector2i(3, 6), Vector2i(4, 6), Vector2i(5, 6), Vector2i(0, 7), Vector2i(1, 7), Vector2i(2, 7), Vector2i(3, 7), Vector2i(4, 7), Vector2i(5, 7)])
enemy_roster = Array[EnemySlotDefinition]([SubResource("s1"), SubResource("s2"), SubResource("s3")])
island_tier = 1
annotated_engagement_distance = {}
map_scene_id = ""
```

`assets/data/maps/battle_map_004.tres`（断桅暗礁 / island_tier 2 / 4 敌 + 2 BLOCKED）：

```gdscript
[gd_resource type="Resource" script_class="MapDefinition" load_steps=9 format=3]

[ext_resource type="Script" path="res://src/data/map_definition.gd" id="1"]
[ext_resource type="Script" path="res://src/data/terrain_cell.gd" id="2"]
[ext_resource type="Script" path="res://src/data/enemy_slot_definition.gd" id="3"]

[sub_resource type="Resource" id="t1"]
script = ExtResource("2")
pos = Vector2i(2, 4)
type = "BLOCKED"

[sub_resource type="Resource" id="t2"]
script = ExtResource("2")
pos = Vector2i(5, 4)
type = "BLOCKED"

[sub_resource type="Resource" id="s1"]
script = ExtResource("3")
unit_definition_id = "enemy_melee_tier1"
grid_position = Vector2i(1, 0)
behavior_type = "MELEE"
home_pos = Vector2i(-1, -1)

[sub_resource type="Resource" id="s2"]
script = ExtResource("3")
unit_definition_id = "enemy_melee_tier1"
grid_position = Vector2i(6, 0)
behavior_type = "MELEE"
home_pos = Vector2i(-1, -1)

[sub_resource type="Resource" id="s3"]
script = ExtResource("3")
unit_definition_id = "enemy_ranged_tier1"
grid_position = Vector2i(3, 1)
behavior_type = "RANGED"
home_pos = Vector2i(-1, -1)

[sub_resource type="Resource" id="s4"]
script = ExtResource("3")
unit_definition_id = "enemy_swarmer_tier1"
grid_position = Vector2i(4, 3)
behavior_type = "SWARMER"
home_pos = Vector2i(-1, -1)

[resource]
script = ExtResource("1")
map_id = "battle_map_004"
display_name = "断桅暗礁"
terrain_data = Array[TerrainCell]([SubResource("t1"), SubResource("t2")])
deploy_zone = Array[Vector2i]([Vector2i(0, 6), Vector2i(1, 6), Vector2i(2, 6), Vector2i(3, 6), Vector2i(4, 6), Vector2i(5, 6), Vector2i(0, 7), Vector2i(1, 7), Vector2i(2, 7), Vector2i(3, 7), Vector2i(4, 7), Vector2i(5, 7)])
enemy_roster = Array[EnemySlotDefinition]([SubResource("s1"), SubResource("s2"), SubResource("s3"), SubResource("s4")])
island_tier = 2
annotated_engagement_distance = {}
map_scene_id = ""
```

`assets/data/maps/battle_map_005.tres`（锈锚墓地 / island_tier 2 / 4 敌，无地形）：

```gdscript
[gd_resource type="Resource" script_class="MapDefinition" load_steps=7 format=3]

[ext_resource type="Script" path="res://src/data/map_definition.gd" id="1"]
[ext_resource type="Script" path="res://src/data/enemy_slot_definition.gd" id="3"]

[sub_resource type="Resource" id="s1"]
script = ExtResource("3")
unit_definition_id = "enemy_ranged_tier1"
grid_position = Vector2i(0, 0)
behavior_type = "RANGED"
home_pos = Vector2i(-1, -1)

[sub_resource type="Resource" id="s2"]
script = ExtResource("3")
unit_definition_id = "enemy_ranged_tier1"
grid_position = Vector2i(7, 0)
behavior_type = "RANGED"
home_pos = Vector2i(-1, -1)

[sub_resource type="Resource" id="s3"]
script = ExtResource("3")
unit_definition_id = "enemy_guardian_tier1"
grid_position = Vector2i(4, 2)
behavior_type = "GUARDIAN"
home_pos = Vector2i(4, 2)

[sub_resource type="Resource" id="s4"]
script = ExtResource("3")
unit_definition_id = "enemy_swarmer_tier1"
grid_position = Vector2i(2, 3)
behavior_type = "SWARMER"
home_pos = Vector2i(-1, -1)

[resource]
script = ExtResource("1")
map_id = "battle_map_005"
display_name = "锈锚墓地"
terrain_data = Array[TerrainCell]([])
deploy_zone = Array[Vector2i]([Vector2i(0, 6), Vector2i(1, 6), Vector2i(2, 6), Vector2i(3, 6), Vector2i(4, 6), Vector2i(5, 6), Vector2i(0, 7), Vector2i(1, 7), Vector2i(2, 7), Vector2i(3, 7), Vector2i(4, 7), Vector2i(5, 7)])
enemy_roster = Array[EnemySlotDefinition]([SubResource("s1"), SubResource("s2"), SubResource("s3"), SubResource("s4")])
island_tier = 2
annotated_engagement_distance = {}
map_scene_id = ""
```

`assets/data/maps/battle_map_006.tres`（血色风暴 / island_tier 3 / 5 敌，无地形）：

```gdscript
[gd_resource type="Resource" script_class="MapDefinition" load_steps=8 format=3]

[ext_resource type="Script" path="res://src/data/map_definition.gd" id="1"]
[ext_resource type="Script" path="res://src/data/enemy_slot_definition.gd" id="3"]

[sub_resource type="Resource" id="s1"]
script = ExtResource("3")
unit_definition_id = "enemy_melee_tier1"
grid_position = Vector2i(1, 0)
behavior_type = "MELEE"
home_pos = Vector2i(-1, -1)

[sub_resource type="Resource" id="s2"]
script = ExtResource("3")
unit_definition_id = "enemy_melee_tier1"
grid_position = Vector2i(6, 0)
behavior_type = "MELEE"
home_pos = Vector2i(-1, -1)

[sub_resource type="Resource" id="s3"]
script = ExtResource("3")
unit_definition_id = "enemy_ranged_tier1"
grid_position = Vector2i(0, 1)
behavior_type = "RANGED"
home_pos = Vector2i(-1, -1)

[sub_resource type="Resource" id="s4"]
script = ExtResource("3")
unit_definition_id = "enemy_ranged_tier1"
grid_position = Vector2i(7, 1)
behavior_type = "RANGED"
home_pos = Vector2i(-1, -1)

[sub_resource type="Resource" id="s5"]
script = ExtResource("3")
unit_definition_id = "enemy_guardian_tier1"
grid_position = Vector2i(4, 3)
behavior_type = "GUARDIAN"
home_pos = Vector2i(4, 3)

[resource]
script = ExtResource("1")
map_id = "battle_map_006"
display_name = "血色风暴"
terrain_data = Array[TerrainCell]([])
deploy_zone = Array[Vector2i]([Vector2i(0, 6), Vector2i(1, 6), Vector2i(2, 6), Vector2i(3, 6), Vector2i(4, 6), Vector2i(5, 6), Vector2i(0, 7), Vector2i(1, 7), Vector2i(2, 7), Vector2i(3, 7), Vector2i(4, 7), Vector2i(5, 7)])
enemy_roster = Array[EnemySlotDefinition]([SubResource("s1"), SubResource("s2"), SubResource("s3"), SubResource("s4"), SubResource("s5")])
island_tier = 3
annotated_engagement_distance = {}
map_scene_id = ""
```

`assets/data/maps/battle_map_007.tres`（深渊咽喉 / island_tier 3 / 5 敌，无地形）：

```gdscript
[gd_resource type="Resource" script_class="MapDefinition" load_steps=8 format=3]

[ext_resource type="Script" path="res://src/data/map_definition.gd" id="1"]
[ext_resource type="Script" path="res://src/data/enemy_slot_definition.gd" id="3"]

[sub_resource type="Resource" id="s1"]
script = ExtResource("3")
unit_definition_id = "enemy_swarmer_tier1"
grid_position = Vector2i(2, 0)
behavior_type = "SWARMER"
home_pos = Vector2i(-1, -1)

[sub_resource type="Resource" id="s2"]
script = ExtResource("3")
unit_definition_id = "enemy_swarmer_tier1"
grid_position = Vector2i(5, 0)
behavior_type = "SWARMER"
home_pos = Vector2i(-1, -1)

[sub_resource type="Resource" id="s3"]
script = ExtResource("3")
unit_definition_id = "enemy_ranged_tier1"
grid_position = Vector2i(3, 1)
behavior_type = "RANGED"
home_pos = Vector2i(-1, -1)

[sub_resource type="Resource" id="s4"]
script = ExtResource("3")
unit_definition_id = "enemy_guardian_tier1"
grid_position = Vector2i(1, 3)
behavior_type = "GUARDIAN"
home_pos = Vector2i(1, 3)

[sub_resource type="Resource" id="s5"]
script = ExtResource("3")
unit_definition_id = "enemy_guardian_tier1"
grid_position = Vector2i(6, 3)
behavior_type = "GUARDIAN"
home_pos = Vector2i(6, 3)

[resource]
script = ExtResource("1")
map_id = "battle_map_007"
display_name = "深渊咽喉"
terrain_data = Array[TerrainCell]([])
deploy_zone = Array[Vector2i]([Vector2i(0, 6), Vector2i(1, 6), Vector2i(2, 6), Vector2i(3, 6), Vector2i(4, 6), Vector2i(5, 6), Vector2i(0, 7), Vector2i(1, 7), Vector2i(2, 7), Vector2i(3, 7), Vector2i(4, 7), Vector2i(5, 7)])
enemy_roster = Array[EnemySlotDefinition]([SubResource("s1"), SubResource("s2"), SubResource("s3"), SubResource("s4"), SubResource("s5")])
island_tier = 3
annotated_engagement_distance = {}
map_scene_id = ""
```

- [ ] **Step 2: 加 MapDataManager.get_all_maps()**

`src/autoloads/map_data_manager.gd`，在 `get_maps_for_tier` 之后加：

```gdscript
# 全部已加载地图（任意顺序）；选航降级抽取用。
func get_all_maps() -> Array[MapDefinition]:
	var out: Array[MapDefinition] = []
	for v in _cache.values():
		out.append(v as MapDefinition)
	return out
```

- [ ] **Step 3: 写校验/扫描测试**

`tests/integration/maps/map_pool_test.gd`：

```gdscript
# 多地图数据校验（子项目①）：7 张图导入、tier 索引、逐图过 BattleMap Rule 3 部署校验。
extends GdUnitTestSuite

const NEW_MAP_IDS := [
	"battle_map_002", "battle_map_003", "battle_map_004",
	"battle_map_005", "battle_map_006", "battle_map_007",
]

# AC-9：7 张图全部被 MapDataManager 扫描并缓存。
func test_all_seven_maps_loaded() -> void:
	assert_int(MapDataManager.get_all_maps().size()).is_equal(7)

# AC-9：tier 索引——tier1×3、tier2×2、tier3×2。
func test_maps_indexed_by_tier() -> void:
	assert_int(MapDataManager.get_maps_for_tier(1).size()).is_equal(3)
	assert_int(MapDataManager.get_maps_for_tier(2).size()).is_equal(2)
	assert_int(MapDataManager.get_maps_for_tier(3).size()).is_equal(2)

# AC-9：每张新图都能解析（非 null + map_id 一致）。
func test_each_new_map_resolves() -> void:
	for mid in NEW_MAP_IDS:
		var m := MapDataManager.get_map(mid)
		assert_object(m).is_not_null()
		assert_str((m as MapDefinition).map_id).is_equal(mid)

# AC-9：每张新图通过 BattleMap Rule 3 部署校验（load 返回 true、状态 MAP_READY）。
func test_each_new_map_passes_deploy_validation() -> void:
	for mid in NEW_MAP_IDS:
		var bm: BattleMap = auto_free(BattleMap.new())
		var gb: GridBoard = auto_free(GridBoard.new())
		var tm: TurnManager = auto_free(TurnManager.new())
		var ok := bm.load_map_definition(MapDataManager.get_map(mid), gb, tm)
		assert_bool(ok).override_failure_message("地图 %s 未过 Rule 3 校验" % mid).is_true()
```

- [ ] **Step 4: 导入 + 跑测试 + 全量回归**

```bash
cd "/Users/chris/Documents/First Codex/my-game"
"/Applications/Godot.app/Contents/MacOS/Godot" --headless --import 2>&1 | tail -1
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/integration/maps/map_pool_test.gd 2>&1 | grep -iE "Statistics|FAILED" | tail -3
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests 2>&1 | grep -iE "Overall Summary|SCRIPT ERROR" | tail -3
```
Expected: map_pool 4/4 PASSED；全量绿、0 错误。若 `test_each_new_map_passes_deploy_validation` 报某图失败，对照本任务 Global Constraints 的 Rule 3（多半是某敌人距部署格 <3 或敌数越界），微调该 `.tres` 敌人坐标至行 0–3、与部署区 Manhattan≥3，重跑。

- [ ] **Step 5: 提交**

```bash
git add assets/data/maps/battle_map_00{2,3,4,5,6,7}.tres src/autoloads/map_data_manager.gd tests/integration/maps/map_pool_test.gd
git commit -F - <<'EOF'
feat(maps): six new battle maps (tier 1-3) + get_all_maps + validation test

Story: chart-course-multi-map (#19)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

### Task 2: 新增 CHARTING 阶段（枚举 / 门面 / 信号 / 自动存盘 / 解析）

**Files:**
- Modify: `src/autoloads/run_manager.gd`
- Test: `tests/unit/run_manager/run_manager_test.gd`（追加）

**Interfaces:**
- Produces: `RunManager.RunPhase.RUN_CHARTING`；`current_phase == "CHARTING"` 门面；`_phase_from_string("CHARTING")` 往返；CHARTING 进入时发 `run_phase_changed("CHARTING")` 且自动存盘。Task 3/4/5/8 依赖此阶段存在。

- [ ] **Step 1: 追加失败测试**

`tests/unit/run_manager/run_manager_test.gd` 末尾追加：

```gdscript
# CHARTING 门面映射（新增阶段）。
func test_facade_maps_charting_to_CHARTING() -> void:
	RunManager._set_run_phase(RunManager.RunPhase.RUN_CHARTING)
	assert_str(RunManager.current_phase).is_equal("CHARTING")

# CHARTING 字符串解析往返。
func test_phase_from_string_charting() -> void:
	assert_int(RunManager._phase_from_string("CHARTING")).is_equal(RunManager.RunPhase.RUN_CHARTING)
```

- [ ] **Step 2: 跑测试确认 RED**

```bash
cd "/Users/chris/Documents/First Codex/my-game"
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/run_manager/run_manager_test.gd 2>&1 | grep -iE "Statistics|FAILED|error" | tail -5
```
Expected: 运行错误/失败（`RUN_CHARTING` 不存在）。

- [ ] **Step 3: 加枚举 + 门面映射**

`src/autoloads/run_manager.gd`，`enum RunPhase` 改为（在 `RUN_RECRUITING` 后加 `RUN_CHARTING`）：

```gdscript
enum RunPhase {
	RUN_IDLE,
	RUN_DEPLOYING,
	RUN_ISLAND_BATTLE,
	RUN_RECRUITING,
	RUN_CHARTING,
	RUN_END
}
```

`_PHASE_TO_STRING` 加一行：

```gdscript
const _PHASE_TO_STRING: Dictionary = {
	RunPhase.RUN_IDLE:          "IDLE",
	RunPhase.RUN_DEPLOYING:     "DEPLOYING",
	RunPhase.RUN_ISLAND_BATTLE: "BATTLE",
	RunPhase.RUN_RECRUITING:    "RECRUITING",
	RunPhase.RUN_CHARTING:      "CHARTING",
	RunPhase.RUN_END:           "RUN_END",
}
```

- [ ] **Step 4: 进入信号 + 自动存盘 + 解析**

`_on_run_phase_entered` 的 `match phase:` 段在 `RUN_RECRUITING` 分支后加：

```gdscript
		RunPhase.RUN_CHARTING:
			EventBus.run_phase_changed.emit("CHARTING")
```

同函数自动存盘段把 CHARTING 并入存盘档位：

```gdscript
	if _autosave_enabled:
		match phase:
			RunPhase.RUN_DEPLOYING, RunPhase.RUN_RECRUITING, RunPhase.RUN_CHARTING:
				save_run()
			RunPhase.RUN_END:
				delete_save()
```

`_phase_from_string` 的 `match s:` 加一行：

```gdscript
		"CHARTING": return RunPhase.RUN_CHARTING
```

- [ ] **Step 5: 跑测试确认 GREEN + 全量回归**

```bash
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/run_manager/run_manager_test.gd 2>&1 | grep -iE "Statistics|FAILED" | tail -3
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests 2>&1 | grep -iE "Overall Summary|SCRIPT ERROR" | tail -3
```
Expected: run_manager 全 PASSED（含 2 新）；全量绿、0 错误（`_ready` 的 `_PHASE_TO_STRING.size()==RunPhase.size()` 守卫满足）。

- [ ] **Step 6: 提交**

```bash
git add src/autoloads/run_manager.gd tests/unit/run_manager/run_manager_test.gd
git commit -F - <<'EOF'
feat(run): add CHARTING phase (enum, facade, signal, autosave, parse)

Story: chart-course-multi-map (#19)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

### Task 3: 选航候选生成 get_route_offers + 目标 tier 映射

**Files:**
- Modify: `src/autoloads/run_manager.gd`
- Test: `tests/unit/run_manager/route_offers_test.gd`

**Interfaces:**
- Consumes: `MapDataManager.get_maps_for_tier(int)`、`get_all_maps()`（Task 1）；`_rng`、`current_island_index`。
- Produces: 常量 `ROUTE_OFFER_COUNT := 3`；字段 `_chosen_map_id: String`、`_visited_map_ids: Array[String]`、`_last_route_offers: Array[String]`；`get_route_offers() -> Array[MapDefinition]`（写 `_last_route_offers`）；`_target_tiers_for_island(next_idx: int) -> Array[int]`。Task 4 用 `_last_route_offers`/`_chosen_map_id`/`_visited_map_ids`；Task 8 渲染候选。

- [ ] **Step 1: 写失败测试**

`tests/unit/run_manager/route_offers_test.gd`：

```gdscript
# 选航候选生成（子项目①）：数量 / tier 过滤 / 不重复 / 降级 / 确定性。
extends GdUnitTestSuite

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._goto_battle = func() -> void: pass
	RunManager._goto_route = func() -> void: pass
	RunManager.start_run()
	RunManager._rng.seed = 20260624

func after_test() -> void:
	RunManager._goto_battle = RunManager._default_goto_battle
	RunManager._goto_route = RunManager._default_goto_route

# 首岛（next_idx=0）→ 目标 tier [1]，3 张全 island_tier 1。
func test_first_island_offers_three_tier1_maps() -> void:
	RunManager.current_island_index = -1
	var offers := RunManager.get_route_offers()
	assert_int(offers.size()).is_equal(3)
	for o in offers:
		assert_int((o as MapDefinition).island_tier).is_equal(1)

# 候选写入 _last_route_offers（供 confirm_route 校验）。
func test_offers_recorded_in_last_route_offers() -> void:
	RunManager.current_island_index = -1
	var offers := RunManager.get_route_offers()
	assert_int(RunManager._last_route_offers.size()).is_equal(offers.size())
	for o in offers:
		assert_bool(RunManager._last_route_offers.has((o as MapDefinition).map_id)).is_true()

# 本 run 已访问的图不再作为候选（不重复，池足时）。
func test_visited_maps_excluded_when_pool_allows() -> void:
	RunManager.current_island_index = -1
	var first := RunManager.get_route_offers()
	var visited_id := (first[0] as MapDefinition).map_id
	RunManager._visited_map_ids.append(visited_id)
	var second := RunManager.get_route_offers()
	for o in second:
		assert_str((o as MapDefinition).map_id).is_not_equal(visited_id)

# 目标 tier 候选不足 3 时优雅降级补足（末岛 next_idx=4 → 目标 [3] 仅 2 张 → 补到 3）。
func test_degrades_when_target_tier_insufficient() -> void:
	RunManager.current_island_index = 3   # next_idx = 4
	var offers := RunManager.get_route_offers()
	assert_int(offers.size()).is_equal(3)

# 确定性：同 seed + 同 visited 重复调用得同结果（续航复现）。
func test_offers_deterministic_for_same_seed() -> void:
	RunManager.current_island_index = -1
	RunManager._rng.seed = 999
	var a := RunManager.get_route_offers()
	RunManager._rng.seed = 999
	var b := RunManager.get_route_offers()
	assert_int(a.size()).is_equal(b.size())
	for i in range(a.size()):
		assert_str((a[i] as MapDefinition).map_id).is_equal((b[i] as MapDefinition).map_id)

# 目标 tier 映射表（纯函数）。
func test_target_tiers_mapping() -> void:
	assert_array(RunManager._target_tiers_for_island(0)).is_equal([1])
	assert_array(RunManager._target_tiers_for_island(1)).is_equal([1, 2])
	assert_array(RunManager._target_tiers_for_island(2)).is_equal([1, 2])
	assert_array(RunManager._target_tiers_for_island(3)).is_equal([2, 3])
	assert_array(RunManager._target_tiers_for_island(4)).is_equal([3])
```

- [ ] **Step 2: 跑测试确认 RED**

```bash
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/run_manager/route_offers_test.gd 2>&1 | grep -iE "Statistics|FAILED|error" | tail -5
```
Expected: 运行错误（`get_route_offers`/`_target_tiers_for_island`/字段不存在）。

- [ ] **Step 3: 加常量 + 字段**

`src/autoloads/run_manager.gd`，在 `const RECRUIT_OFFER_COUNT := 3` 后加：

```gdscript
const ROUTE_OFFER_COUNT := 3
```

在 `var _last_offers: Array[String] = []` 行后加：

```gdscript
var _chosen_map_id: String = ""             # 本次选航选定的 map_id（battle_map.load_map 读）
var _visited_map_ids: Array[String] = []     # 本 run 已访问 map_id（选航不重复）
var _last_route_offers: Array[String] = []   # 本批选航候选 map_id（confirm_route 据此校验）
```

- [ ] **Step 4: 写 get_route_offers + 目标 tier 映射**

在 `get_recruit_offers` 之后（`confirm_recruit` 之前）加：

```gdscript
# 即将抵达岛号 → 目标 island_tier 集合（可调）。next_idx = current_island_index + 1。
func _target_tiers_for_island(next_idx: int) -> Array[int]:
	match next_idx:
		0: return [1]
		1, 2: return [1, 2]
		3: return [2, 3]
		_: return [3]   # 4 及之后（末岛）

# 三张选航候选：按"即将抵达岛"的目标 tier 抽 ≤ROUTE_OFFER_COUNT 张未访问地图；
# 不足则放宽 tier（全体未访问），再不足则放宽 visited（全体）。确定性（_rng + map_id 排序）。
func get_route_offers() -> Array[MapDefinition]:
	var next_idx := current_island_index + 1
	var tiers := _target_tiers_for_island(next_idx)
	var pool: Array[MapDefinition] = []
	# 主池：目标 tier 未访问
	for t in tiers:
		for m in MapDataManager.get_maps_for_tier(t):
			if not _visited_map_ids.has(m.map_id) and not pool.has(m):
				pool.append(m)
	# 降级①：放宽到全体未访问
	if pool.size() < ROUTE_OFFER_COUNT:
		for m in MapDataManager.get_all_maps():
			if not _visited_map_ids.has(m.map_id) and not pool.has(m):
				pool.append(m)
	# 降级②：仍不足则放宽 visited（允许历史重复，但本批仍去重）
	if pool.size() < ROUTE_OFFER_COUNT:
		for m in MapDataManager.get_all_maps():
			if not pool.has(m):
				pool.append(m)
	# 先按 map_id 排序消除扫描顺序差异 → 再 Fisher-Yates（确定性）
	pool.sort_custom(func(a: MapDefinition, b: MapDefinition) -> bool: return a.map_id < b.map_id)
	for i in range(pool.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	var offers: Array[MapDefinition] = []
	for m in pool:
		if offers.size() >= ROUTE_OFFER_COUNT:
			break
		offers.append(m)
	_last_route_offers.clear()
	for o in offers:
		_last_route_offers.append(o.map_id)
	return offers
```

- [ ] **Step 5: 跑测试确认 GREEN + 全量回归**

```bash
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/run_manager/route_offers_test.gd 2>&1 | grep -iE "Statistics|FAILED" | tail -3
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests 2>&1 | grep -iE "Overall Summary|SCRIPT ERROR" | tail -3
```
Expected: route_offers 7/7 PASSED；全量绿、0 错误。

- [ ] **Step 6: 提交**

```bash
git add src/autoloads/run_manager.gd tests/unit/run_manager/route_offers_test.gd
git commit -F - <<'EOF'
feat(run): generate chart-course route offers (tiered, no-repeat, deterministic)

Story: chart-course-multi-map (#19)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

### Task 4: confirm_route + get_chosen_map_id

**Files:**
- Modify: `src/autoloads/run_manager.gd`
- Test: `tests/unit/run_manager/route_offers_test.gd`（追加）

**Interfaces:**
- Consumes: Task 3 的 `_last_route_offers`、`_visited_map_ids`、`_chosen_map_id`；`MapDataManager.get_map`。
- Produces: `confirm_route(map_id: String) -> void`（记 `_chosen_map_id` + 标记 visited + 清候选 + 转 `RUN_DEPLOYING`；坏 id `push_error` 不改状态）；`get_chosen_map_id() -> String`。Task 6 读 `get_chosen_map_id`；Task 8 调 `confirm_route`。

- [ ] **Step 1: 追加失败测试**

`tests/unit/run_manager/route_offers_test.gd` 末尾追加：

```gdscript
# confirm_route：记所选图 + 标记 visited + 转 DEPLOYING。
func test_confirm_route_records_and_advances() -> void:
	RunManager.current_island_index = -1
	var offers := RunManager.get_route_offers()
	var chosen := (offers[0] as MapDefinition).map_id
	RunManager.confirm_route(chosen)
	assert_str(RunManager.get_chosen_map_id()).is_equal(chosen)
	assert_bool(RunManager._visited_map_ids.has(chosen)).is_true()
	assert_str(RunManager.current_phase).is_equal("DEPLOYING")
	assert_int(RunManager._last_route_offers.size()).is_equal(0)

# confirm_route 坏 id（不在本批候选）：push_error 且状态不变、不记图。
func test_confirm_route_invalid_id_no_change() -> void:
	RunManager.current_island_index = -1
	RunManager.get_route_offers()
	RunManager._set_run_phase(RunManager.RunPhase.RUN_CHARTING)
	RunManager.confirm_route("battle_map_999_nonexistent")
	assert_str(RunManager.get_chosen_map_id()).is_equal("")
	assert_str(RunManager.current_phase).is_equal("CHARTING")
```

- [ ] **Step 2: 跑测试确认 RED**

```bash
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/run_manager/route_offers_test.gd 2>&1 | grep -iE "Statistics|FAILED|error" | tail -5
```
Expected: 运行错误（`confirm_route`/`get_chosen_map_id` 不存在）。

- [ ] **Step 3: 写 confirm_route + get_chosen_map_id**

`src/autoloads/run_manager.gd`，在 `get_route_offers` 之后加：

```gdscript
# 选定航点：记 map_id + 标记本 run 已访问 + 清候选 → DEPLOYING。
# 坏 id（无定义或不在本批候选）：push_error 且不改状态（仿 confirm_recruit）。
func confirm_route(map_id: String) -> void:
	if MapDataManager.get_map(map_id) == null:
		push_error("RunManager.confirm_route: 未知 map_id — %s" % map_id)
		return
	if not _last_route_offers.has(map_id):
		push_error("RunManager.confirm_route: map_id 不在本批候选 — %s" % map_id)
		return
	_chosen_map_id = map_id
	if not _visited_map_ids.has(map_id):
		_visited_map_ids.append(map_id)
	_last_route_offers.clear()
	_set_run_phase(RunPhase.RUN_DEPLOYING)

# 本次选航选定的 map_id（battle_map.load_map 读）；未选则 ""。
func get_chosen_map_id() -> String:
	return _chosen_map_id
```

- [ ] **Step 4: 跑测试确认 GREEN + 全量回归**

```bash
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/run_manager/route_offers_test.gd 2>&1 | grep -iE "Statistics|FAILED" | tail -3
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests 2>&1 | grep -iE "Overall Summary|SCRIPT ERROR" | tail -3
```
Expected: route_offers 9/9 PASSED；全量绿、0 错误。

- [ ] **Step 5: 提交**

```bash
git add src/autoloads/run_manager.gd tests/unit/run_manager/route_offers_test.gd
git commit -F - <<'EOF'
feat(run): confirm_route records chosen map and advances to deploy

Story: chart-course-multi-map (#19)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

### Task 5: 翻转 start_run / confirm_recruit → CHARTING（+ 复位新字段 + 更新现有断言）

**Files:**
- Modify: `src/autoloads/run_manager.gd`
- Test: `tests/unit/run_manager/run_manager_test.gd`（改断言）、`tests/integration/run_loop/run_loop_test.gd`（改断言）

**Interfaces:**
- Consumes: Task 2 的 `RUN_CHARTING`。
- Produces: `start_run` 末转 `RUN_CHARTING` 并复位 `_chosen_map_id`/`_visited_map_ids`/`_last_route_offers`；`confirm_recruit` 末转 `RUN_CHARTING`。转阶段链：`start_run → CHARTING`、`confirm_recruit → CHARTING`、`confirm_route → DEPLOYING`、`confirm_deploy → BATTLE`。

- [ ] **Step 1: 改现有断言（先让它们表达新行为 → 此刻应 RED）**

`tests/unit/run_manager/run_manager_test.gd`：
- 第 19–20 行 `test_start_run_enters_deploying_phase`：函数名与断言改为 CHARTING：

```gdscript
func test_start_run_enters_charting_phase() -> void:
	assert_str(RunManager.current_phase).is_equal("CHARTING")
```

- `test_start_run_resets_run_state` 内（原 `assert_str(RunManager.current_phase).is_equal("DEPLOYING")`）改为：

```gdscript
	assert_str(RunManager.current_phase).is_equal("CHARTING")
```

- `test_confirm_recruit_adds_choice_excludes_rest` 内（原末尾 `assert_str(RunManager.current_phase).is_equal("DEPLOYING")`）改为：

```gdscript
	assert_str(RunManager.current_phase).is_equal("CHARTING")
```

`tests/integration/run_loop/run_loop_test.gd`：
- `test_ac1_start_run_deploys_starting_crew` 第 38 行断言改为：

```gdscript
	assert_str(RunManager.current_phase).is_equal("CHARTING")
```
（保留其余对 roster 的断言不变；可顺手把函数名改为 `test_ac1_start_run_charts_then_holds_starting_crew`，非必需。）

- `test_ac6_restart_returns_to_first_island` 第 99 行（`start_run` 后断言 DEPLOYING）改为：

```gdscript
	assert_str(RunManager.current_phase).is_equal("CHARTING")
```

- [ ] **Step 2: 跑测试确认 RED**

```bash
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/run_manager/run_manager_test.gd 2>&1 | grep -iE "Statistics|FAILED" | tail -3
```
Expected: FAILED（start_run/confirm_recruit 仍转 DEPLOYING，与新断言不符）。

- [ ] **Step 3: 翻转 start_run**

`src/autoloads/run_manager.gd` 的 `start_run`：在 `_unlocked_this_run = ""` 行后加复位：

```gdscript
	_chosen_map_id = ""
	_visited_map_ids.clear()
	_last_route_offers.clear()
```

并把末行 `_set_run_phase(RunPhase.RUN_DEPLOYING)` 改为：

```gdscript
	_set_run_phase(RunPhase.RUN_CHARTING)
```

- [ ] **Step 4: 翻转 confirm_recruit**

`confirm_recruit` 末行 `_set_run_phase(RunPhase.RUN_DEPLOYING)` 改为：

```gdscript
	_set_run_phase(RunPhase.RUN_CHARTING)
```

- [ ] **Step 5: 跑测试确认 GREEN + 全量回归**

```bash
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/run_manager/run_manager_test.gd 2>&1 | grep -iE "Statistics|FAILED" | tail -3
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests 2>&1 | grep -iE "Overall Summary|SCRIPT ERROR" | tail -3
```
Expected: run_manager / run_loop 全 PASSED；全量绿、0 错误。注：`confirm_deploy` 不守卫阶段，故现有"start_run → confirm_deploy"直推的集成测试（full_battle/bounty/run_end/permadeath/downed_notice）机制仍通；若某测试另有 DEPLOYING 阶段断言失败，按相同方式（该处现应为 CHARTING）更新。

- [ ] **Step 6: 提交**

```bash
git add src/autoloads/run_manager.gd tests/unit/run_manager/run_manager_test.gd tests/integration/run_loop/run_loop_test.gd
git commit -F - <<'EOF'
feat(run): route start_run and confirm_recruit into CHARTING phase

Story: chart-course-multi-map (#19)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

### Task 6: battle_map.load_map 读所选地图

**Files:**
- Modify: `src/battle/battle_map.gd`
- Test: `tests/unit/battle_map/battle_map_chosen_map_test.gd`

**Interfaces:**
- Consumes: `RunManager.get_chosen_map_id()`（Task 4）；`MapDataManager.get_map`。
- Produces: `load_map(_island_index)` 加载 `get_chosen_map_id()` 指定图；空则回退 `MVP_MAP_ID`。

- [ ] **Step 1: 写失败测试**

`tests/unit/battle_map/battle_map_chosen_map_test.gd`：

```gdscript
# battle_map.load_map 读 RunManager 选定的地图（子项目①）。
extends GdUnitTestSuite

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._goto_battle = func() -> void: pass
	RunManager._goto_route = func() -> void: pass
	RunManager.start_run()
	RunManager._chosen_map_id = ""

func after_test() -> void:
	RunManager._chosen_map_id = ""
	RunManager._goto_battle = RunManager._default_goto_battle
	RunManager._goto_route = RunManager._default_goto_route

func _bm() -> BattleMap: return auto_free(BattleMap.new())
func _gb() -> GridBoard: return auto_free(GridBoard.new())
func _tm() -> TurnManager: return auto_free(TurnManager.new())

# AC-5：选定图 → load_map 加载该图并就绪（map_loaded 携带其 map_id）。
func test_load_map_uses_chosen_map() -> void:
	RunManager._chosen_map_id = "battle_map_006"
	var bm := _bm()
	bm.setup(_gb(), _tm())
	var loaded_id := [""]
	EventBus.map_loaded.connect(func(mid: String) -> void: loaded_id[0] = mid)
	bm.load_map(0)
	assert_str(loaded_id[0]).is_equal("battle_map_006")

# AC-5：未选图（空）→ 回退 battle_map_001。
func test_load_map_falls_back_when_unchosen() -> void:
	RunManager._chosen_map_id = ""
	var bm := _bm()
	bm.setup(_gb(), _tm())
	var loaded_id := [""]
	EventBus.map_loaded.connect(func(mid: String) -> void: loaded_id[0] = mid)
	bm.load_map(0)
	assert_str(loaded_id[0]).is_equal("battle_map_001")
```

> 注：`bm.setup(grid_board, turn_manager)` 是 BattleMap 既有注入接口（见 `battle_map.gd`）；若签名不同，按实际 setup 注入 `_grid_board`/`_turn_manager` 后再调 `load_map`。

- [ ] **Step 2: 跑测试确认 RED**

```bash
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/battle_map/battle_map_chosen_map_test.gd 2>&1 | grep -iE "Statistics|FAILED|error" | tail -5
```
Expected: `test_load_map_uses_chosen_map` FAIL（仍恒加载 001）。

- [ ] **Step 3: 改 load_map**

`src/battle/battle_map.gd` 的 `load_map` 改为：

```gdscript
# 由 BattleScene._ready() 调用（ADR-0002 / architecture.md 4d）。需先 setup() 注入引用。
# 航线系统：加载 RunManager 选定的地图；未选（空）回退 MVP_MAP_ID（测试/异常安全）。
func load_map(_island_index: int) -> void:
	var chosen := RunManager.get_chosen_map_id()
	var map_id := chosen if chosen != "" else MVP_MAP_ID
	var map_def := MapDataManager.get_map(map_id)
	if map_def == null:
		EventBus.map_load_failed.emit(&"map_not_found")
		return
	load_map_definition(map_def, _grid_board, _turn_manager)  # unit_lookup 默认走 UnitDataManager
```

- [ ] **Step 4: 跑测试确认 GREEN + 全量回归**

```bash
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/battle_map/battle_map_chosen_map_test.gd 2>&1 | grep -iE "Statistics|FAILED" | tail -3
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests 2>&1 | grep -iE "Overall Summary|SCRIPT ERROR" | tail -3
```
Expected: chosen_map 2/2 PASSED；全量绿、0 错误。

- [ ] **Step 5: 提交**

```bash
git add src/battle/battle_map.gd tests/unit/battle_map/battle_map_chosen_map_test.gd
git commit -F - <<'EOF'
feat(battle): load player-chosen map, fall back to default when unset

Story: chart-course-multi-map (#19)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

### Task 7: 存档持久化选航字段

**Files:**
- Modify: `src/autoloads/run_manager.gd`
- Test: `tests/unit/run_save/run_save_test.gd`（追加）

**Interfaces:**
- Consumes: Task 3/4 的 `_chosen_map_id`、`_visited_map_ids`、`_last_route_offers`；既有 `_to_string_array`。
- Produces: `to_save_dict` 增 `chosen_map_id` / `visited_map_ids` / `last_route_offers`；`load_from_save_dict` 恢复三者。

- [ ] **Step 1: 追加失败测试**

`tests/unit/run_save/run_save_test.gd` 末尾追加：

```gdscript
# 选航字段往返（子项目①）。
func test_save_load_roundtrips_route_state() -> void:
	RunManager.start_run()
	RunManager._chosen_map_id = "battle_map_004"
	RunManager._visited_map_ids = ["battle_map_001", "battle_map_004"]
	RunManager._last_route_offers = ["battle_map_005", "battle_map_006"]
	var d := RunManager.to_save_dict()
	RunManager.start_run()   # 打乱清空
	RunManager.load_from_save_dict(d)
	assert_str(RunManager._chosen_map_id).is_equal("battle_map_004")
	assert_array(RunManager._visited_map_ids).is_equal(["battle_map_001", "battle_map_004"])
	assert_array(RunManager._last_route_offers).is_equal(["battle_map_005", "battle_map_006"])
```

- [ ] **Step 2: 跑测试确认 RED**

```bash
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/run_save/run_save_test.gd 2>&1 | grep -iE "Statistics|FAILED|error" | tail -5
```
Expected: FAIL（往返后三字段不等——尚未序列化）。

- [ ] **Step 3: 序列化 + 反序列化**

`to_save_dict` 的返回字典加三键（在 `"roster_equipment"` 行后）：

```gdscript
		"roster_equipment": _roster_equipment.duplicate(),
		"chosen_map_id": _chosen_map_id,
		"visited_map_ids": _visited_map_ids.duplicate(),
		"last_route_offers": _last_route_offers.duplicate(),
	}
```

`load_from_save_dict` 在 `_last_offers = _to_string_array(...)` 行后加：

```gdscript
	_chosen_map_id = str(d.get("chosen_map_id", ""))
	_visited_map_ids = _to_string_array(d.get("visited_map_ids", []))
	_last_route_offers = _to_string_array(d.get("last_route_offers", []))
```

- [ ] **Step 4: 跑测试确认 GREEN + 全量回归**

```bash
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/unit/run_save/run_save_test.gd 2>&1 | grep -iE "Statistics|FAILED" | tail -3
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests 2>&1 | grep -iE "Overall Summary|SCRIPT ERROR" | tail -3
```
Expected: run_save 全 PASSED；全量绿、0 错误。

- [ ] **Step 5: 提交**

```bash
git add src/autoloads/run_manager.gd tests/unit/run_save/run_save_test.gd
git commit -F - <<'EOF'
feat(run): persist chart-course state (chosen map, visited, offers)

Story: chart-course-multi-map (#19)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

### Task 8: RouteScene 选航 UI 分支

**Files:**
- Modify: `src/ui/route_scene.gd`
- Test: `tests/integration/chart_course/chart_course_ui_test.gd`

**Interfaces:**
- Consumes: `RunManager.get_route_offers()`/`confirm_route()`（Task 3/4）；现有 `_enter_deploy()`/`_clear_ui()`。
- Produces: `RouteScene._show_route_offers()`、`_on_route_chosen(map_id)`、`_enemy_summary(map_def) -> String`；`_active_screen == "charting"`；`_ready` 加 `"CHARTING"` 分支；`_begin_run`/`_on_recruit_chosen` 改为接选航。

- [ ] **Step 1: 写失败测试**

`tests/integration/chart_course/chart_course_ui_test.gd`：

```gdscript
# 选航 UI 分支（子项目①，白盒 ADVISORY 的可观测部分）。
extends GdUnitTestSuite

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._goto_battle = func() -> void: pass
	RunManager._goto_route = func() -> void: pass
	RunManager.start_run()              # → CHARTING
	RunManager._rng.seed = 20260624

func after_test() -> void:
	RunManager._goto_battle = RunManager._default_goto_battle
	RunManager._goto_route = RunManager._default_goto_route

# CHARTING 阶段进入 RouteScene → 渲染选航界面。
func test_charting_phase_shows_route_screen() -> void:
	var rs: RouteScene = auto_free(RouteScene.new())
	add_child(rs)
	assert_str(rs._active_screen).is_equal("charting")

# 敌情摘要：按 behavior_type 计数 + 中文标签。
func test_enemy_summary_counts_by_behavior() -> void:
	var rs: RouteScene = auto_free(RouteScene.new())
	add_child(rs)
	var summary := rs._enemy_summary(MapDataManager.get_map("battle_map_001"))
	# battle_map_001：近战×1 远程×1 突击×1 守卫×1
	assert_str(summary).contains("近战×1")
	assert_str(summary).contains("远程×1")
	assert_str(summary).contains("突击×1")
	assert_str(summary).contains("守卫×1")

# 选航后进入部署阶段（confirm_route → DEPLOYING）。
func test_choosing_route_advances_to_deploy() -> void:
	var rs: RouteScene = auto_free(RouteScene.new())
	add_child(rs)
	var chosen := RunManager._last_route_offers[0]
	rs._on_route_chosen(chosen)
	assert_str(RunManager.current_phase).is_equal("DEPLOYING")
```

- [ ] **Step 2: 跑测试确认 RED**

```bash
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/integration/chart_course/chart_course_ui_test.gd 2>&1 | grep -iE "Statistics|FAILED|error" | tail -5
```
Expected: 运行错误/失败（`_show_route_offers`/`_on_route_chosen`/`_enemy_summary` 不存在、`_active_screen != "charting"`）。

- [ ] **Step 3: _ready 加 CHARTING 分支 + 接选航**

`src/ui/route_scene.gd` 的 `_ready` 的 `match` 加分支（在 `"RECRUITING"` 后）：

```gdscript
		"CHARTING":
			_show_route_offers()
```

`_begin_run` 改为（起航后进选航而非直接部署）：

```gdscript
# 起航：填起始编制 → 选航（start_run 现进 CHARTING）。
func _begin_run() -> void:
	RunManager.start_run()
	_show_route_offers()
```

`_on_recruit_chosen` 改为（招募后进选航）：

```gdscript
func _on_recruit_chosen(unit_id: String) -> void:
	RunManager.confirm_recruit(unit_id)
	_show_route_offers()
```

- [ ] **Step 4: 写 _show_route_offers / _on_route_chosen / _enemy_summary**

在 `_on_recruit_chosen` 之后（`_equipment_summary` 之前）加：

```gdscript
# 选航界面（白盒，只用按钮）：3 张目的地卡，显示「地名 · 难度N · 敌情摘要」。
func _show_route_offers() -> void:
	var offers := RunManager.get_route_offers()
	if offers.is_empty():
		_enter_deploy()        # 无候选（极端空池）→ 直接部署，不崩
		return
	_clear_ui()
	_active_screen = "charting"
	var box := VBoxContainer.new()
	add_child(box)
	box.set_anchors_preset(Control.PRESET_CENTER)
	var title := Label.new()
	title.text = "选择下一处航点"
	box.add_child(title)
	for m in offers:
		var map_def := m as MapDefinition
		var btn := Button.new()
		btn.text = "%s · 难度%d · %s" % [map_def.display_name, map_def.island_tier, _enemy_summary(map_def)]
		btn.pressed.connect(_on_route_chosen.bind(map_def.map_id))
		box.add_child(btn)

func _on_route_chosen(map_id: String) -> void:
	RunManager.confirm_route(map_id)
	_enter_deploy()

# 敌情白盒摘要："近战×N 远程×N 突击×N 守卫×N"（仅列非零）。
func _enemy_summary(map_def: MapDefinition) -> String:
	var counts := {"MELEE": 0, "RANGED": 0, "SWARMER": 0, "GUARDIAN": 0}
	for slot in map_def.enemy_roster:
		if counts.has(slot.behavior_type):
			counts[slot.behavior_type] += 1
	var labels := {"MELEE": "近战", "RANGED": "远程", "SWARMER": "突击", "GUARDIAN": "守卫"}
	var parts: Array[String] = []
	for k in ["MELEE", "RANGED", "SWARMER", "GUARDIAN"]:
		if int(counts[k]) > 0:
			parts.append("%s×%d" % [labels[k], int(counts[k])])
	return " ".join(parts)
```

- [ ] **Step 5: 跑测试确认 GREEN + 全量回归**

```bash
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/integration/chart_course/chart_course_ui_test.gd 2>&1 | grep -iE "Statistics|FAILED" | tail -3
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests 2>&1 | grep -iE "Overall Summary|SCRIPT ERROR" | tail -3
```
Expected: chart_course_ui 3/3 PASSED；全量绿、0 错误。注：`run_loop_test.test_ac7_exhausted_pool_skips_recruit_via_route_scene` 经 RouteScene 走 RECRUITING→（空招募）→选航；选航有候选则停在 charting，原断言"→BATTLE"可能失效——若该测试 FAIL，更新其末尾断言为经 `_on_route_chosen` 后再 `confirm_deploy` 才 BATTLE（与新流程一致）。

- [ ] **Step 6: 提交**

```bash
git add src/ui/route_scene.gd tests/integration/chart_course/chart_course_ui_test.gd tests/integration/run_loop/run_loop_test.gd
git commit -F - <<'EOF'
feat(route): chart-course selection screen (whitebox cards)

Story: chart-course-multi-map (#19)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

---

### Task 9: 全程选航端到端集成测试 + F5 验收

**Files:**
- Test: `tests/integration/chart_course/full_route_test.gd`
- Modify: 仅按测试/F5 发现微调（如有）

**Interfaces:**
- Consumes: Task 1–8 全部。
- Produces: 端到端测试证明全程选航走完 5 岛（AC-6）；F5 验收清单。

- [ ] **Step 1: 写端到端测试**

`tests/integration/chart_course/full_route_test.gd`：

```gdscript
# 全程选航端到端（AC-6）：经 RunManager 驱动走完 5 岛，每岛地图由选航决定。
extends GdUnitTestSuite

func before_test() -> void:
	RunManager._autosave_enabled = false
	RunManager._goto_battle = func() -> void: pass
	RunManager._goto_route = func() -> void: pass
	MetaProgress.unlocked_crew_ids.clear()
	RunManager.start_run()              # → CHARTING（首岛）
	RunManager._rng.seed = 20260624

func after_test() -> void:
	RunManager._goto_battle = RunManager._default_goto_battle
	RunManager._goto_route = RunManager._default_goto_route

func _roster_ids() -> Array[String]:
	var ids: Array[String] = []
	for c in RunManager.get_roster():
		ids.append(c.id)
	return ids

# 选航 → 部署 → 战斗一岛的推进辅助。
func _chart_then_deploy() -> void:
	var offers := RunManager.get_route_offers()
	RunManager.confirm_route((offers[0] as MapDefinition).map_id)   # → DEPLOYING
	RunManager.confirm_deploy(_roster_ids())                        # → BATTLE（index+1）

# AC-6：首岛起航即进 CHARTING。
func test_first_island_starts_in_charting() -> void:
	assert_str(RunManager.current_phase).is_equal("CHARTING")

# AC-6：选航后进入部署、确认部署进入战斗。
func test_chart_then_deploy_reaches_battle() -> void:
	_chart_then_deploy()
	assert_str(RunManager.current_phase).is_equal("BATTLE")
	assert_int(RunManager.current_island_index).is_equal(0)

# AC-6：每岛选航记录已访问图（变化）。
func test_visited_maps_accumulate_across_islands() -> void:
	_chart_then_deploy()                        # 岛0
	assert_int(RunManager._visited_map_ids.size()).is_equal(1)
	EventBus.battle_won.emit()                  # → RECRUITING
	# 非末岛：招募（取首个候选）→ CHARTING
	var recruits := RunManager.get_recruit_offers()
	if not recruits.is_empty():
		RunManager.confirm_recruit((recruits[0] as CrewDefinition).id)
	assert_str(RunManager.current_phase).is_equal("CHARTING")
	_chart_then_deploy()                        # 岛1
	assert_int(RunManager._visited_map_ids.size()).is_equal(2)

# AC-6：全程选航打赢 5 岛 → RUN_END。
func test_full_route_win_ends_run() -> void:
	for i in range(RunManager.ISLAND_COUNT_MAX):
		_chart_then_deploy()                    # 选航 + 部署 + 进战斗
		var was_final := RunManager.current_island_index + 1 >= RunManager.ISLAND_COUNT_MAX
		EventBus.battle_won.emit()
		if not was_final:
			var recruits := RunManager.get_recruit_offers()
			if not recruits.is_empty():
				RunManager.confirm_recruit((recruits[0] as CrewDefinition).id)
	assert_str(RunManager.current_phase).is_equal("RUN_END")
	assert_bool(RunManager.last_run_won).is_true()
```

- [ ] **Step 2: 跑测试 + 全量回归**

```bash
"/Applications/Godot.app/Contents/MacOS/Godot" --headless --import 2>&1 | tail -1
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests/integration/chart_course/full_route_test.gd 2>&1 | grep -iE "Statistics|FAILED" | tail -3
"/Applications/Godot.app/Contents/MacOS/Godot" --headless -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode --continue -a res://tests 2>&1 | grep -iE "Overall Summary|Executed test|SCRIPT ERROR|orphan" | tail -5
```
Expected: full_route 4/4 PASSED；全量绿、0 错误、0 孤儿。

- [ ] **Step 3: F5 人眼验收（ADVISORY，记录不阻断）**

从 MainMenu 起航走完整流程，逐项核对（对照 spec §8 AC-8）：
- 起航后出现"选择下一处航点"页，3 张白盒卡显示地名/难度/敌情摘要。
- 选一张 → 进入部署 → 战斗加载的是所选地图（敌人布局与所选卡的敌情摘要一致）。
- 打赢后：招募 → 再次选航 → 不同地图。
- 续航：选航阶段退出再"继续航程"，回到选航页且候选一致。
记录观察到报告（`production/qa/evidence/`）。

- [ ] **Step 4: （如有微调）提交**

```bash
git add -A
git commit -F - <<'EOF'
test(route): end-to-end chart-course full-run integration + F5 acceptance

Story: chart-course-multi-map (#19)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
```

> 若 Step 2 全绿且无代码改动，仅提交新测试文件即可。

---

## Self-Review

**Spec coverage（对照 spec §8 AC）：**
- AC-1（候选数量/tier/不重复）→ Task 3 测试 ✓
- AC-2（确定性）→ Task 3 `test_offers_deterministic_for_same_seed` ✓
- AC-3（优雅降级）→ Task 3 `test_degrades_when_target_tier_insufficient` ✓
- AC-4（confirm_route 记图/转阶段/坏 id）→ Task 4 ✓
- AC-5（load_map 读所选图/回退）→ Task 6 ✓
- AC-6（全程选航端到端）→ Task 9 ✓
- AC-7（存档往返新字段 + CHARTING 自动存盘）→ Task 7（往返）+ Task 2（CHARTING 入自动存盘档位）✓
- AC-8（选航 UI F5 + 可观测断言）→ Task 8（active_screen/摘要/转阶段）+ Task 9 Step 3（F5）✓
- AC-9（6 新图导入/唯一/敌人解析/过校验）→ Task 1 ✓
- 阶段链翻转（start_run/confirm_recruit → CHARTING）→ Task 5 ✓

**Placeholder scan：** 各步含完整代码/命令/期望；地图 `.tres` 全文给出；无 TBD/TODO。视觉验收（AC-8 F5）以 active_screen/摘要/转阶段断言 + F5 清单替代像素级自动化（已显式说明，沿用项目白盒惯例）。✓

**Type consistency：**
- `RUN_CHARTING` / `"CHARTING"`（Task 2）→ Task 4/5/8 一致引用。
- `ROUTE_OFFER_COUNT`、`_chosen_map_id: String`、`_visited_map_ids: Array[String]`、`_last_route_offers: Array[String]`（Task 3）→ Task 4/5/7/8 一致。
- `get_route_offers() -> Array[MapDefinition]`、`confirm_route(map_id: String)`、`get_chosen_map_id() -> String`、`_target_tiers_for_island(int) -> Array[int]`（Task 3/4）→ Task 6/8/9 一致。
- `MapDataManager.get_all_maps() -> Array[MapDefinition]`、`get_maps_for_tier(int)`（Task 1）→ Task 3 一致。
- `RouteScene._show_route_offers()`/`_on_route_chosen(map_id)`/`_enemy_summary(MapDefinition) -> String`（Task 8）→ Task 8/9 测试一致。
- 静态类型：`pool.sort_custom(func(a: MapDefinition, b: MapDefinition) -> bool ...)`、`int(counts[k])` 显式转换、`var chosen := RunManager.get_chosen_map_id()`（String 返回，非 Variant）。✓

**风险提示（执行者注意）：**
- Task 1 地图须过 Rule 3 校验——`test_each_new_map_passes_deploy_validation` 是关；若失败按 Global Constraints 调坐标。
- Task 5/8 翻转阶段链会波及既有集成测试的阶段断言；Step 已点名 run_loop AC-1/6/7 的更新，其余若 FAIL 按"该处现为 CHARTING / 需先选航再部署"同法修正。

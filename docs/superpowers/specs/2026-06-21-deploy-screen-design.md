# DeployScreen 手动选人设计（子项目 B）

> **Status**: Approved（用户确认 2026-06-21）
> **Author**: Chris + Claude Code
> **Date**: 2026-06-21
> **Epic**: route-recruitment（A=可玩 run 循环骨架已完成 / **B=DeployScreen 手动选人（本 spec）** / C=元层打磨）
> **GDD 来源**: `design/gdd/route-recruitment-ui.md`（Rule 3 部署界面流程 / OQ-3 排序）
> **前序**: `docs/superpowers/specs/2026-06-20-run-loop-skeleton-design.md`（A 把 RouteScene 做成白盒统一中枢）

## Overview

子项目 A 实现了可玩 run 循环，但部署阶段始终**无脑全员上场**（`RouteScene._deploy_current_roster()` 招募后立即 `confirm_deploy(全部 roster)`）。当 roster 超过 `DEPLOY_LIMIT=4` 时，玩家无法选择带谁出战——"带谁是有意义的选择"的情感承诺缺失视觉载体。

本增量在 `RouteScene`（白盒统一中枢）的 DEPLOYING 流程内联渲染一个**手动选人界面**：roster 超过 4 人时，玩家用 toggle 按钮选最多 4 名出战、点确认部署；roster ≤ 4 时自动全员（行为不变）。后端 `confirm_deploy(selected_ids)` 已支持子集部署，无需改动。

本增量**只做手动选人**。GDD 的独立 `DeployScreen.tscn`（CanvasLayer=20、卡片美术、阵亡通知卡、航线进度条）作为后续故事，不在本范围。

## Player Fantasy

部署界面的情感节点比招募更紧绷：roster 里有 5–8 个人，但只能带 4 个上场。谁留下？玩家应感到"带谁是有意义的选择"，而不是"反正谁都一样"。部署确认的瞬间是战前的小庄严感。

（MVP 白盒阶段以功能正确为先：toggle 列表 + 已选计数 + 确认。视觉庄严感[金边/立绘/动画]待正式美术故事。）

## Detailed Rules

### Rule 1：DEPLOY_LIMIT 常量

`RunManager` 新增 `const DEPLOY_LIMIT := 4`（对齐 `design/registry/entities.yaml` 单一来源；现有 `STARTING_CREW/RECRUIT_OFFER_COUNT/ISLAND_COUNT_MAX` 同处声明）。RouteScene 引用此常量，不另立魔数。

### Rule 2：进入部署的统一入口 `_enter_deploy()`

所有进入部署阶段的路径都改为调用 `_enter_deploy()`（取代现 `_deploy_current_roster()` 的直接确认）：

| 路径 | 触发 | 进入时 roster |
|------|------|--------------|
| 首岛起航 | `_begin_run()`（IDLE）→ `start_run()` | STARTING_CREW=2 |
| 招募后 | `_on_recruit_chosen()`（RECRUITING）→ `confirm_recruit()` | 3..MAX_CREW(8) |
| 重新出航 | `_on_restart_pressed()`（RUN_END）→ `start_run()` | 2 |
| 防御分支 | `_ready()` 落到 DEPLOYING/BATTLE 默认分支 | 任意 |

`_enter_deploy()` 逻辑：
1. `_clear_ui()`：释放本场景已建的上一阶段子节点（招募卡 / run-end 框），避免叠加显示。
2. 若 `RunManager.get_roster().size() <= RunManager.DEPLOY_LIMIT` → 自动 `confirm_deploy(全员 id)`（**行为与 A 完全一致**，无界面，→ BATTLE）。
3. 否则 → `_show_deploy_selection()` 渲染选人界面，等玩家确认（不立即 confirm）。

> 正常 run（无永久死亡）：起 2 → 各岛 +1。第 1、2 岛后 roster=3、4（≤4 自动跳过），**第 3 岛后 roster=5 起首次触发选人界面**。

### Rule 3：选人界面 `_show_deploy_selection()`

白盒，只用按钮（符合项目"只用选项不打字"约定）。渲染一个 `VBoxContainer`（**先 add_child 再** `set_anchors_preset(PRESET_CENTER)`，修 A 遗留 M-3）：
1. 标题 `Label`："选择出战船员（最多 4 名）"
2. 每名 roster 船员一个 toggle `Button`（`toggle_mode = true`），文本 `"%s · %s" % [crew.unit_class, crew.display_name]`，**不显数值**；**按 roster 自然序**（= 招募顺序，OQ-3 裁决）。`toggled` 信号 `.bind(crew.id)` 连到 `_on_deploy_toggle(pressed, crew_id)`。每个按钮存入 `_deploy_buttons[crew.id] = btn`（供 Rule 4 回弹定位 + 测试驱动）。
3. 状态 `Label`（存 `_deploy_status_label`）："已选 0/4"（随选择更新）。
4. 「确认部署」`Button`（存 `_deploy_confirm_button`）：`pressed` 连 `_on_deploy_confirm`；初始 `disabled = true`。

内部状态：`_selected_ids: Array[String] = []`（本次部署已选）、`_deploy_buttons: Dictionary = {}`（crew_id→Button）、`_deploy_status_label`、`_deploy_confirm_button`。进入界面时（`_clear_ui` 后）全部清空/重置。

### Rule 4：选择交互 `_on_deploy_toggle(pressed: bool, crew_id: String)`

- `pressed == true`：
  - 若 `_selected_ids.size() >= DEPLOY_LIMIT`（已满 4）→ 拒绝：`_deploy_buttons[crew_id].set_pressed_no_signal(false)` 回弹（不发信号，无递归），直接 return（不加入，不刷新）。
  - 否则 → `_selected_ids.append(crew_id)`。
- `pressed == false`：`_selected_ids.erase(crew_id)`。
- 末尾调 `_refresh_deploy_state()`。

### Rule 5：状态刷新 `_refresh_deploy_state()`

- 状态标签文本 = `"已选 %d/%d" % [_selected_ids.size(), DEPLOY_LIMIT]`。
- 确认键 `disabled = (_selected_ids.size() == 0)`（0 人禁用；1–4 人可确认，允许少于满编出战，GDD Rule 3.4）。

### Rule 6：确认部署 `_on_deploy_confirm()`

- 守卫：`_selected_ids.is_empty()` → return（按钮本应已 disabled，双重保险）。
- `RunManager.confirm_deploy(_selected_ids.duplicate())` → 后端按 id 过滤 roster 填 `pending_deploy`、island++、→ BATTLE、`_goto_battle`。

## Formulas

### F1：是否展示选人界面

`show_deploy_screen = roster.size() > DEPLOY_LIMIT`

| 变量 | 类型 | 来源 | 说明 |
|------|------|------|------|
| `roster.size()` | int | `RunManager.get_roster()` | 当前编制人数 [STARTING_CREW, MAX_CREW] = [2, 8] |
| `DEPLOY_LIMIT` | int = 4 | `RunManager.DEPLOY_LIMIT` | 单场上场上限 |

输出：`false`（≤4，自动全员）/ `true`（>4，手动选）。

### F2：确认键可用性

`confirm_enabled = (1 <= selected_count <= DEPLOY_LIMIT)`

因 Rule 4 上限回弹保证 `selected_count <= DEPLOY_LIMIT` 恒成立，实现上等价于 `confirm_enabled = (selected_count >= 1)`。

## Edge Cases

- **roster.size() == DEPLOY_LIMIT（恰好 4）**：F1 为 false → 自动全员，不展示界面（4 人无需取舍）。
- **roster.size() == 1（残局单人）**：≤4 → 自动单人出战（保持 A 行为）。
- **已选满 4 再点第 5 个未选项**：Rule 4 回弹该按钮、不加入；`_selected_ids` 仍为 4。
- **0 选中点确认**：确认键 disabled + Rule 6 守卫双重拦截，不推进。
- **取消已选再选别人**：`erase` + `append` 正常增减，计数与确认键随之刷新。
- **pending_deploy 上限**：UI 保证传入 confirm_deploy 的 id 数 ≤ 4 → `BattleScene._deploy_run_crew` 的 `min(pending, 格数)` 部署 ≤4 名 → 战场上场数受控（deploy_zone 12 格充足）。
- **重复进入部署（同一 RouteScene 实例连续两次 DEPLOYING）**：`_enter_deploy()` 先 `_clear_ui()` + 重置 `_selected_ids`，无残留。

## Dependencies

### 上游（本增量依赖）

| 系统 | 接口 | 说明 |
|------|------|------|
| RunManager (#11) | `get_roster() / confirm_deploy(ids) / DEPLOY_LIMIT(新增)` | 数据源 + 部署后端；confirm_deploy 已支持子集，无需改 |
| CrewDefinition (#1) | `.id / .unit_class / .display_name` | 渲染 toggle 文本 |
| 导航接缝 | `RunManager._goto_battle`（confirm_deploy 内部调用） | 确认后切战斗；测试可 stub 为 no-op |

### 不改动

- `RunManager.confirm_deploy`：现签名 `(selected_ids: Array)` 按 id 过滤 roster，已满足；不加 DEPLOY_LIMIT 截断（UI 是唯一上限执行者，加后端截断会掩盖调用方错误）。
- `BattleScene._deploy_run_crew`：`min(pending, 格数)` 不变。
- run_loop 集成测试（A 的 AC-1..7）：触发路径 roster 均 ≤4，仍走自动跳过，行为不变。

### 下游

无新增被依赖方（独立 DeployScreen.tscn / 阵亡卡 / 进度条仍为未来故事）。

## Tuning Knobs

| 常量 | 默认 | 安全范围 | 效果 |
|------|------|---------|------|
| `DEPLOY_LIMIT` | 4 | [1, MAX_CREW=8] | 单场上场上限；同时决定是否展示选人界面（roster 超过即展示）与回弹阈值 |

## Acceptance Criteria

> 全部【集成测试】，实例化 `RouteScene` + stub `RunManager._goto_battle`/`_goto_route` 为 no-op，确定性 seed。选择经 `_deploy_buttons[id].button_pressed = true/false`（代码赋值即发 `toggled` 信号，无头安全，非 InputEvent）驱动真实接线；确认经直接调 `_on_deploy_confirm()`。roster>4 的构造：`start_run` 后向 `RunManager.roster` 追加 pool 期 `CrewDefinition`（`UnitDataManager.get_unit(id)`）。

**AC-1：roster ≤ DEPLOY_LIMIT 自动全员，不展示界面**
- Given: roster.size() ≤ 4（如首岛起航 2 人）
- When: 进入 DEPLOYING（`_enter_deploy`）
- Then: `confirm_deploy` 被自动调用、`current_phase=="BATTLE"`、`pending_deploy.size()==roster.size()`；场景内无 toggle 选人节点

**AC-2：roster > DEPLOY_LIMIT 展示选人界面，未自动确认**
- Given: roster.size() == 5
- When: 进入 DEPLOYING
- Then: 渲染 5 个 toggle 按钮 + 确认键；确认键 `disabled==true`；`current_phase` 仍为 `"DEPLOYING"`（未调 confirm_deploy）

**AC-3：选满 4 人确认 → confirm_deploy 收到那 4 个 id**
- Given: roster 5 人，界面已展示
- When: `_on_deploy_toggle` 选中其中 4 个 id → `_on_deploy_confirm`
- Then: `confirm_deploy(["..4 个 id.."])` 被调用、`pending_deploy.size()==4` 且身份与所选一致、`current_phase=="BATTLE"`

**AC-4：选满 4 后第 5 个被回弹拒绝**
- Given: roster 6 人，已选 4 个
- When: `_on_deploy_toggle(true, 第5个id)`
- Then: `_selected_ids.size()==4`、第 5 个未进入选中集、对应按钮 `button_pressed==false`

**AC-5：确认键随选择数启用/禁用**
- Given: 界面已展示（roster>4）
- When: 选 0 → 选 1 → 取消回 0
- Then: 0 人时确认键 `disabled==true`；≥1 人时 `disabled==false`；回 0 再次 `disabled==true`；状态标签随之显示"已选 X/4"

**AC-6：子集部署（少于满编）成功**
- Given: roster 5 人，只选 2 个
- When: 确认部署
- Then: `confirm_deploy` 收到 2 个 id、`pending_deploy.size()==2`、`current_phase=="BATTLE"`

**AC-7：不破 A 的 run 循环回归**
- Given: 现有 run_loop 集成测试（AC-1..7）
- When: 全量回归
- Then: 全绿（部署路径 roster 均 ≤4，走自动跳过，行为不变）

## 偏离 GDD 的实现决策（已记录理由）

1. **内联 RouteScene 而非独立 DeployScreen.tscn**：延续 A 的白盒统一中枢，避免新增场景 + SceneManager `goto_deploy` 接缝 + main 流转。GDD 的独立全屏场景（CanvasLayer=20、卡片美术、键盘焦点导航）随正式美术故事落地。
2. **toggle 列表不显数值**：白盒 + "只用选项不打字" 约定；GDD Rule 6 的倾向描述/HP 等待美术与数值展示故事。
3. **只做选人，不含阵亡通知卡 / 航线进度条**：用户裁决最小范围（YAGNI）；二者各为独立后续故事（阵亡卡依赖尚未实现的船员永久死亡机制）。
4. **confirm_deploy 后端不加 DEPLOY_LIMIT 截断**：UI 是唯一上限执行者；后端截断会掩盖调用方错误。

## 顺带清理（A 遗留 minor）

- **M-3**：选人界面 `VBoxContainer` 先 `add_child` 再 `set_anchors_preset`（A 的 route_scene 其余分支同样模式可一并校正，但仅在本次新建/触及的节点上做，不做无关重构）。
- **M-2**（`as CrewDefinition` null 守卫）：roster 元素类型已是 `Array[CrewDefinition]`，遍历渲染无 null 转换风险，无需额外守卫。

# 航线与招募 UI (Route & Recruitment UI)

> **Status**: Approved（R1 修订后放行，2026-06-17）
> **Author**: Chris + Claude Code agents
> **Last Updated**: 2026-06-17
> **Implements Pillar**: 羁绊即战术（招募选择可见性：让玩家看清构筑机会、做出有意义的阵容决策）；十分钟一场爽局（招募/部署流程 ≤ 30 秒，不拖慢战斗节奏）

## Overview

航线与招募 UI 是玩家在战斗间隙与 run 流程交互的全部视觉层。它将航线与招募系统的数据（候选船员、当前 roster、岛屿进度）转化为三类核心界面：**招募界面**（三选一卡片，玩家选择下一名船员）、**部署界面**（从 roster 中选 4 人参战）、**航线进度条**（当前位于第几岛、几岛完成，展示 run 的大局感）。此外，它承载战中阵亡通知（船员被 Downed 时的即时反馈）。本系统无任何游戏逻辑，它是航线与招募系统的只读/只写前端：订阅信号 → 更新界面 → 将玩家输入路由回后端接口。它作为独立的 Godot 场景加载于战斗场景之外，在战后由航线系统的 `run_phase_changed` 信号驱动切换。若没有它，玩家无法感知自己的阵容正在成型，"看着自己的海贼团一步步壮大"的情感承诺失去视觉载体。

## Player Fantasy

玩家在招募界面面对三张候选卡时，感受到的应该是**短暂的、有重量的犹豫**——不是分析瘫痪，而是"两个选择都有道理，但只能选一个"的微型戏剧。每张卡片展示的不是数值列表，而是一个角色的剪影：职业、倾向（是打、是守、还是辅？）、一句战意台词。玩家扫一眼三张卡，在 15–30 秒内做出决策，然后感到"这个决定我是主动做的，不是被迫的"。

部署界面的情感节点更紧绷：roster 里可能有 6 个人，但只能带 4 个上场。谁留下？玩家应该感到"带谁是有意义的选择"，而不是"反正谁都一样"。部署确认的瞬间是战前的小庄严感。

航线进度条提供宏观叙事锚点：玩家看到"第 2 岛 / 共 5 岛"，知道自己处于 run 的什么位置，知道还有几次招募机会。这是构筑思维的空间感——"我现在 4 个人，还有 2 次机会，得在第 3 岛拿一个铁壁"。

阵亡通知的情感目标是**可感知的损失**，而不是惩罚感。船员卡变灰、名字保留、留下"在第 3 岛阵亡"的印记——死亡是 run 故事的一部分，而不是纯粹的失分。

## Detailed Design

### Core Rules

**Rule 1：UI 场景架构**

本系统由两个独立 Godot 场景组成，均在战斗场景卸载后加载：

- **招募场景（RecruitScreen.tscn）**：全屏覆盖，包含三张候选卡片区、当前 roster 小图标列、航线进度条、确认按钮
- **部署场景（DeployScreen.tscn）**：全屏覆盖，包含 roster 完整列表（可交互，点击选中/取消选中）、已选编制预览（4 格）、确认部署按钮

两个场景均为**输入阻塞型**（InputLayer）——展示期间阻止所有其他输入（战斗输入、ESC 菜单等）。

**Rule 2：招募界面流程**

1. 收到航线系统 `run_phase_changed("RECRUITING")` 信号，加载 RecruitScreen.tscn
2. 调用 `route_recruitment_system.get_recruit_offers()` 获取 3 张候选卡数据
3. 渲染 3 张候选卡（每卡展示：职业图标、职业名、倾向数值带描述、`battle_cry` 个性台词，共 3 行）
4. 显示当前 roster 小图标列（最多 7 格，第 8 格为"招募中"占位）
5. 显示航线进度条（`island_index + 1` / `ISLAND_COUNT_MAX`）
6. 玩家点击某张候选卡 → 卡片高亮选中（其余两张半透明），「确认招募」按钮激活
7. 玩家点击「确认招募」→ 调用 `confirm_recruit(unit_id)` → 新成员加入 roster 小图标列（滑入动画）→ 等待 `run_phase_changed("DEPLOYING")` 信号（由航线系统进入 `RUN_DEPLOYING` 时发出）→ 进入部署阶段
8. 招募成功后 roster 小图标列显示新成员（高亮），然后过渡至 DeployScreen

**Rule 3：部署界面流程**

1. 收到 `run_phase_changed("DEPLOYING")` 信号后（由招募完成或首岛自动触发），判断是否展示 DeployScreen
2. 若 `roster.size() ≤ DEPLOY_LIMIT`：本 UI 自动确认全员（不展示 DeployScreen），直接触发战斗加载（走 Rule 5 流程）
3. 若 `roster.size() > 4`：展示 DeployScreen，玩家从 roster 列表中点选最多 4 名船员
4. 已选人数未满 4 时「确认部署」按钮显示"已选 X/4"但可点击（允许带少于 4 人参战，设计师允许此路径）
5. 玩家点击「确认部署」→ 调用 `confirm_deploy(selected_ids)` → DeployScreen 关闭 → 进入战斗加载

**Rule 4：阵亡通知**

- 监听 `crew_member_downed(unit_id)` 信号
- 在战斗结束后（`battle_won` 或 `battle_lost`）、进入招募界面之前，渲染**阵亡通知卡**（非战中弹窗；战中死亡只在战斗 HUD 层呈现）
- 通知卡内容：阵亡船员的职业图标（变灰）、姓名、"在第 N 岛阵亡"铭文
- 若无阵亡，跳过通知卡，直接进入招募界面
- 玩家点击「继续」关闭通知卡

**Rule 5：航线进度条**

- 常驻于招募界面顶部（非独立界面）
- 显示当前出发前的状态：`{island_index + 1} / {ISLAND_COUNT_MAX}` 岛，已完成岛屿着色（填充），当前岛高亮，未来岛灰色
- 末岛标记为"头目战"图标（骷髅旗 or 悬赏海报）
- 不显示具体地图名称（MVP 阶段）

**Rule 6：候选卡片信息规格**

每张候选卡片展示（顺序从上至下）：
1. 职业大图标（64×64，行为差异的第一视觉锚）
2. 职业名（中文，加粗）
3. 三行能力描述（倾向数值带文字化：如"近战重击，攻击力强，移动力中"）
4. `battle_cry`（个性台词，斜体，灰色辅助字）

MVP 阶段候选卡不显示具体数值（HP/攻击力等），仅显示倾向描述——数值显示推迟至有正式数值美术时。

**Rule 7：输入约束**

- 招募界面展示期间：阻止 ESC / 主菜单按键；允许 Tab 在三张卡片间切换焦点（键盘支持）
- 部署界面展示期间：阻止 ESC；允许 Tab 在 roster 列表中导航
- 所有确认操作需要显式点击「确认」按钮（禁止双击卡片直接确认，防止误操作）

### States and Transitions

| 状态 | 描述 | 进入条件 | 退出条件 |
|------|------|---------|---------|
| `UI_HIDDEN` | 无 UI 显示（战斗进行中或 run 未开始） | 初始态；`run_phase_changed("BATTLE")`；`run_completed` 后淡出 | 收到 `run_phase_changed("RECRUITING")` → `UI_RECRUITING`；收到 `run_phase_changed("DEPLOYING")` → `UI_DEPLOYING` |
| `UI_DOWNED_NOTIFY` | 展示阵亡通知卡 | `battle_won` / `battle_lost` 后有 `crew_member_downed` 缓存记录 | 玩家点击「继续」→ 若 `battle_won`（本轮有招募）→ `UI_RECRUITING`；若 `battle_won`（满编/无候选跳过招募）→ `UI_DEPLOYING`；若 `battle_lost` → `UI_HIDDEN`（run 已结束，等待战后结算） |
| `UI_RECRUITING` | 展示招募三选一界面 | `run_phase_changed("RECRUITING")` 且 roster 未满编 | 玩家确认招募（`confirm_recruit` 调用成功）→ `UI_DEPLOYING` |
| `UI_DEPLOYING` | 展示部署选择界面 | 招募完成后（roster>4）或 `run_phase_changed("PRE_DEPLOY")` | 玩家确认部署（`confirm_deploy` 调用成功）→ `UI_HIDDEN` |
| `UI_SKIPPED` | 本阶段跳过（满编 / 无候选，跳过招募界面）| 收到 `run_phase_changed("DEPLOYING")` 但 roster 已满编 / get_recruit_offers() 返回空 | → `UI_DEPLOYING`（若 roster > DEPLOY_LIMIT，仍需部署选择）；→ 直接调用 `confirm_deploy`（全员）→ `UI_HIDDEN`（若 roster ≤ DEPLOY_LIMIT）|

**状态守卫**：`UI_RECRUITING` 期间收到 `battle_started` → 忽略（防止系统状态竞争）；`UI_HIDDEN` 期间收到 `crew_member_downed` → 缓存 id，待下次进入 `UI_DOWNED_NOTIFY` 时渲染。

### Interactions with Other Systems

| 系统 | 接口 / 信号 | 方向 | 说明 |
|------|------------|------|------|
| 航线与招募系统 (#11) | `run_phase_changed(phase)` | 接收 | 驱动 UI 状态切换（"BATTLE"→隐藏；"RECRUITING"→招募界面；"DEPLOYING"→部署界面（或自动部署）；"RUN_END"→隐藏等待战后结算） |
| 航线与招募系统 (#11) | `get_roster() → Array[UnitInstance]` | 调用 | 获取当前存活 roster 渲染成员图标列 |
| 航线与招募系统 (#11) | `get_recruit_offers() → Array[UnitDefinition]` | 调用 | 获取三选一候选名单，渲染卡片 |
| 航线与招募系统 (#11) | `get_current_island_index() → int` | 调用 | 获取当前岛屿序号，渲染进度条 |
| 航线与招募系统 (#11) | `confirm_recruit(unit_id)` | 调用 | 玩家确认招募某候选 |
| 航线与招募系统 (#11) | `confirm_deploy(selected_ids)` | 调用 | 玩家确认本岛参战编制 |
| 航线与招募系统 (#11) | `crew_member_downed(unit_id)` | 接收 | 触发阵亡通知队列（战中收到 → 缓存；战后展示） |
| 回合管理系统 (#3) | `battle_won()` / `battle_lost()` | 接收 | 确认战斗结束，触发阵亡通知检查序列 |
| 单位数据系统 (#1) | `UnitDefinition.unit_class`, `.battle_cry` | 读取 | 渲染候选卡片所需的职业名和个性台词 |
| 战后结算系统 (#15) | `run_completed` | （被动）| 本 UI 在 `run_completed` 后淡出，由战后结算系统接管后续画面；本 UI 不渲染战后结算内容 |

## Formulas

本系统为纯 UI 层，无独立的游戏逻辑公式。所有数值计算由上游系统处理，本系统仅格式化展示。

### 公式 U1：候选卡片数量校验

`render_count = min(offers.size(), RECRUIT_OFFER_COUNT)`

| 变量 | 类型 | 来源 | 说明 |
|------|------|------|------|
| `offers.size()` | int | `get_recruit_offers()` 返回值 | 实际候选数（可能 < 3，见 Rule 2 的候选池耗尽情况） |
| `RECRUIT_OFFER_COUNT` | int = 3 | entities.yaml 常量 | 期望候选数上限 |

**输出范围**：0（无候选，跳过招募）~ 3（正常三选一）  
**用途**：UI 据此决定渲染 0、1、2、或 3 张卡片；渲染 0 张时显示"无新船员可加入"提示并自动进入部署阶段

### 公式 U2：进度条填充比例

`progress_fill = (island_index) / (ISLAND_COUNT_MAX - 1)`

| 变量 | 类型 | 范围 | 说明 |
|------|------|------|------|
| `island_index` | int | [0, ISLAND_COUNT_MAX-1] | `get_current_island_index()` 返回的当前岛屿序号（0-based） |
| `ISLAND_COUNT_MAX` | int = 5 | entities.yaml | 本 run 总岛屿数 |

**输出范围**：0.0（第 1 岛前）~ 1.0（末岛完成）  
**用途**：进度条的视觉填充比例；UI 层将其映射至进度条控件的 `value`（0.0–1.0）

## Edge Cases

- **如果 `get_recruit_offers()` 返回空数组**：显示"无新船员加入"提示文本（非错误弹窗）；「确认招募」按钮替换为「继续」按钮，直接进入部署阶段；进度条和 roster 图标正常显示
- **如果招募候选只有 1 或 2 名（候选池耗尽边界）**：卡片区仅渲染 1–2 张卡，多余卡槽留空（灰色虚框 + "（无候选）"文字）；玩家仍需点击其中一张并确认，不可跳过（不允许"不招募"除非候选为 0）
- **如果 roster.size() = MAX_CREW（=8）时收到 run_phase_changed("RECRUITING")**：本 UI 自动跳过招募界面（roster 已满），不渲染 RecruitScreen；直接判断是否需要展示 DeployScreen
- **如果玩家在招募界面时 run_completed 信号意外到达**：关闭 RecruitScreen，发出 `recruit_ui_aborted` 内部事件，由战后结算系统接管；不调用 `confirm_recruit`
- **如果 `confirm_recruit(unit_id)` 调用后航线系统返回错误（如 unit_id 不合法）**：展示错误提示（"招募失败，请重新选择"）；恢复候选卡片为可点击状态；不推进状态
- **如果 roster.size() = 1（只剩 1 名船员）进入部署阶段**：DeployScreen 跳过（roster ≤ DEPLOY_LIMIT），自动调用 `confirm_deploy([remaining_crew_id])`；UI 显示简短提示"单人出战"（而非安静略过，给玩家一个"险境"的叙事确认）
- **如果所有候选卡片字体因 battle_cry 过长超出卡片高度**：`battle_cry` 截断至 24 个中文字符加省略号；职业名和能力描述优先显示，台词后置
- **如果 `confirm_deploy` 被调用但 selected_ids 为空**：「确认部署」按钮保持禁用状态（UI 层在 selected_ids 为空时不允许点击确认，提示"请至少选择 1 名船员"）

## Dependencies

### 上游依赖（本系统依赖）

| 系统 | GDD | 依赖内容 | 硬/软 |
|------|-----|---------|------|
| 航线与招募系统 (#11) | ✓ route-recruitment-system.md | 全部数据接口和信号（`get_roster`、`get_recruit_offers`、`confirm_*`、`crew_member_downed`、`run_phase_changed`） | 硬（本 UI 无此系统则完全无数据） |
| 单位数据系统 (#1) | ✓ unit-data-system.md | `UnitDefinition.unit_class`、`battle_cry`、职业图标资产引用 | 硬 |
| 回合管理系统 (#3) | ✓ turn-management-system.md | `battle_won` / `battle_lost`（确定战斗已结束，触发阵亡通知） | 硬 |

### 下游被依赖方

| 系统 | GDD | 本 UI 的预期行为 |
|------|-----|---------------|
| 战后结算系统 (#15) | ✗ 未设计 | `run_completed` 后本 UI 淡出；战后结算系统接管 |

### 接口一致性说明

- 航线与招募系统 GDD 的 UI Requirements 节已列出本系统需消费的全部接口（`get_roster`、`get_recruit_offers`、`confirm_recruit`、`confirm_deploy`）。本 GDD 与该节内容完全对应，无冲突。
- 若航线与招募系统接口发生变更（如参数类型修改），本 GDD 的 Section C 和 AC 须同步更新。

## Tuning Knobs

| 常量名 | 默认值 | 安全范围 | 游戏效果 |
|--------|--------|---------|---------|
| `RECRUIT_CARD_REVEAL_DURATION` | 300ms | [150, 600] | 候选卡片淡入/滑入动画时长；< 150ms 过快无揭示感；> 600ms 拖慢招募节奏 |
| `DOWNED_NOTIFY_AUTO_CLOSE` | false | true/false | false=玩家手动关闭阵亡通知；true=3 秒自动关闭（仅在玩家测试快速流程时启用） |
| `DEPLOY_PREVIEW_HIGHLIGHT_DURATION` | 200ms | [100, 400] | 选中船员加入"已选编制"预览区的高亮动画时长 |
| `ROUTE_PROGRESS_FILL_DURATION` | 400ms | [200, 800] | 进度条填充动画时长（进入招募界面时触发） |
| `BATTLE_CRY_MAX_CHARS` | 24 | [16, 40] | 候选卡片 battle_cry 最大字符数（超出截断加省略号）；< 16 台词过短失去个性；> 40 可能撑破卡片布局 |
| `RECRUIT_UI_LAYER` | 20 | [15, 25] | 招募/部署场景的 CanvasLayer 层级；须高于战斗 HUD（layer=5）和爆发演出（layer=10），低于系统弹窗（layer=30） |

## Visual/Audio Requirements

> *(lean 模式：art-director 未派发。以下为设计师规范，须在垂直切片美术冲刺前与美术总监确认。)*

### 视觉规范

**候选卡片（RecruitScreen 核心视觉）：**
- 三张卡片横排，等宽，各约屏幕宽度 28%，卡间间距 4%（总占 88%，两侧各留 6% 边距）
- 未选中状态：标准不透明度；选中状态：轻微放大（scale 1.05）+ 金色边框（与爆发按钮满格金色一致，建立"高价值选择"的语言）；其余两张 opacity 降至 60%
- MVP 阶段：卡片背景为纯色（职业对应色），简单几何图形替代插画；正式美术阶段替换为半身立绘

**阵亡通知卡：**
- 单张居中显示，背景半透明黑幕（overlay）
- 船员职业图标去饱和度（灰阶）+ 细红线划过（暗示终结，参考 FTL 船员死亡卡）
- 铭文字体稍小，衬线风格（与无衬线的 HUD 形成叙事 vs 战斗的字体语言区分）

**航线进度条：**
- 位于 RecruitScreen 顶部，全宽水平条
- 已完成岛屿：实色填充（金色/铜色）；当前岛：脉冲高亮；未来岛：灰色圆圈；末岛：骷髅旗图标
- MVP 阶段：简单 ProgressBar 控件 + 图标叠加

### 音效规范

| 事件 | 音效意图 | 优先级 |
|------|---------|--------|
| 候选卡片展示（揭示） | 翻牌音（纸/木质感） | 高（MVP 即需要） |
| 选中候选卡 | 轻点击/选中音 | 高 |
| 确认招募 | 略微庄重的确认音（新角色加入感） | 高 |
| 阵亡通知展示 | 低沉单音（钟声或弦乐短句） | 高 |
| 部署确认 | 战前鼓点或短号声 | 中 |
| 进度条填充 | 滑动推进音 | 低（可暂缺） |

📌 **Asset Spec** — Visual/Audio 需求已定义。美术风格确认后，运行 `/asset-spec system:route-recruitment-ui` 生成各卡片、通知、进度条的尺寸规格和生成提示。

## UI Requirements

**RecruitScreen 布局规范（1920×1080 基准）：**

```
┌─────────────────────────────────────────┐
│  [航线进度条：第 N 岛 / 共 M 岛]  ←全宽  │
├─────────────────────────────────────────┤
│                                         │
│   [候选卡A] [候选卡B] [候选卡C]           │
│   (28%)    (28%)    (28%)               │
│   各卡含：职业图标/名/描述/台词            │
│                                         │
│   ──── 当前船员 ────                     │
│   [图标1][图标2]...[图标N][招募中占位]     │
│                                         │
│              [确认招募]                  │
└─────────────────────────────────────────┘
```

**DeployScreen 布局规范：**

```
┌──────────────────────────────────┐
│  选择出战船员（最多 4 名）          │
│                                  │
│  [名单列表（可点选，最多 8 行）]    │
│  ○ 剑豪·某某  HP:12  ✓已选       │
│  ○ 炮手·某某  HP:10  ✓已选       │
│  ○ 铁壁·某某  HP:14             │
│  ...                            │
│                                  │
│  已选编制：[头像1][头像2][_][_]   │
│  (已选 2/4)                      │
│                                  │
│           [确认部署]             │
└──────────────────────────────────┘
```

**阵亡通知卡布局（居中弹出，覆盖当前界面）：**

```
┌──────────────────────────┐
│   [灰色职业图标]           │
│   某某 · 炮手             │
│   "在第 2 岛阵亡"          │
│                          │
│        [继续]            │
└──────────────────────────┘
（背景：半透明黑幕 rgba(0,0,0,0.7)）
```

**键盘/手柄导航要求（MVP 最低标准）：**
- Tab / Shift-Tab：在候选卡片间切换焦点
- Space / Enter：确认当前高亮卡片或按钮
- 鼠标悬停替代 Tab 焦点（同等效果）

📌 **UX Flag — 航线与招募 UI**：本系统有复杂 UI 需求（3 个界面）。在 Pre-Production 阶段，运行 `/ux-design` 创建以下界面的 UX 规范后再撰写 epic：
- `design/ux/recruit-screen.md`（招募三选一）
- `design/ux/deploy-screen.md`（部署选择）
- `design/ux/downed-notification.md`（阵亡通知）

各界面的 story 应引用 `design/ux/` 对应文件，而非本 GDD。

## Acceptance Criteria

**AC-1：三张候选卡正确渲染** 【集成测试】
- Given: `get_recruit_offers()` 返回 3 名不同职业候选（A=剑豪, B=炮手, C=铁壁）
- When: 进入 `UI_RECRUITING` 状态
- Then: 屏幕渲染 3 张候选卡；每卡显示对应职业名和 battle_cry；无卡片显示错误 unit_id

**AC-2：候选为 0 时显示"无候选"提示** 【单元测试】
- Given: `get_recruit_offers()` 返回空数组
- When: 进入 `UI_RECRUITING` 状态
- Then: 招募卡片区显示"无新船员可加入"文本；显示「继续」按钮（非「确认招募」）；点击继续后进入 `UI_DEPLOYING`

**AC-3：选中卡片后确认招募触发接口调用** 【集成测试】
- Given: 三张候选卡渲染完毕；玩家点击候选卡 B（炮手）
- When: 玩家点击「确认招募」
- Then: `confirm_recruit(B.unit_id)` 被调用 1 次；B 的图标出现在 roster 小图标列；UI 状态切换至 `UI_DEPLOYING`

**AC-4：confirm_recruit 调用失败后 UI 保持可操作** 【集成测试】
- Given: `confirm_recruit` 调用被模拟为返回 false（非法 unit_id）
- When: 玩家确认招募
- Then: UI 不推进状态；显示"招募失败，请重新选择"提示；三张候选卡恢复可交互

**AC-5：roster > 4 时展示 DeployScreen，< 4 时自动跳过** 【集成测试】
- Given Case A: roster.size() = 6；Case B: roster.size() = 3
- When: 进入部署阶段
- Then A: DeployScreen 展示，列出 6 名船员可点选；Then B: `confirm_deploy` 自动被调用，传入全部 3 人；不展示 DeployScreen

**AC-6：部署界面选人后确认触发 confirm_deploy** 【集成测试】
- Given: roster 含 5 人；玩家在 DeployScreen 选中 4 人（id: a,b,c,d）
- When: 点击「确认部署」
- Then: `confirm_deploy(["a","b","c","d"])` 被调用 1 次；DeployScreen 关闭；UI 状态转为 `UI_HIDDEN`

**AC-7：部署确认按钮在 selected_ids 为空时禁用** 【单元测试】
- Given: DeployScreen 打开，未选任何人员
- When: 检查「确认部署」按钮状态
- Then: 按钮为禁用状态（disabled=true）；点击无响应；显示"请至少选择 1 名船员"提示

**AC-8：阵亡通知正确展示后渲染招募界面** 【集成测试】
- Given: 战斗结束（`battle_won`），本轮有 1 名船员阵亡（`crew_member_downed("crew_b")`）
- When: 进入战斗后流程
- Then: 先展示阵亡通知卡（`UI_DOWNED_NOTIFY`），卡片显示 "crew_b" 的职业图标和姓名（灰色）；玩家点击「继续」后进入 `UI_RECRUITING`

**AC-9：进度条显示正确岛屿进度** 【单元测试】
- Given: `get_current_island_index()` 返回 2，`ISLAND_COUNT_MAX = 5`
- When: RecruitScreen 渲染进度条
- Then: 进度条显示"第 3 岛 / 共 5 岛"（island_index+1=3）；前 2 段填充（已完成）；第 3 段高亮（当前）；第 4–5 段灰色

**AC-10：battle_cry 超过 24 字时截断** 【单元测试】
- Given: 某候选的 battle_cry = "这是一段超过二十四个中文字符的测试台词内容！！！"（28 字）
- When: 候选卡片渲染
- Then: 卡片显示前 24 字 + "…"；不溢出卡片边界

**AC-11：RECRUIT_UI_LAYER 高于战斗 HUD** 【单元测试】
- Given: 战斗 HUD CanvasLayer.layer = 5
- When: RecruitScreen.tscn 加载
- Then: RecruitScreen 的 CanvasLayer.layer = 20（> 5）；RecruitScreen 覆盖在 HUD 之上

**AC-12：battle_lost 后阵亡通知不进入招募界面** 【集成测试】
- Given: 战斗中 `unit_downed("crew_b")` 触发（缓存）；随后 `battle_lost` 信号到达
- When: 进入战斗后流程
- Then: 先展示 `UI_DOWNED_NOTIFY`（显示 crew_b 阵亡通知）；玩家点击「继续」后 UI 进入 `UI_HIDDEN`（不进入 `UI_RECRUITING` 或 `UI_DEPLOYING`）；`run_completed(won=false)` 信号触发战后结算系统接管

## Open Questions

| ID | 问题 | 负责方 | 目标解决阶段 | 影响 |
|----|------|--------|------------|------|
| OQ-1 | **阵亡通知是战中即时显示还是战后汇总显示**？当前规定战后汇总（不打断战斗流程）。若玩家偏好战中即时反馈（"我知道他刚死了"），需要评估是否在战斗 HUD 内增加一个轻量通知层 | 本 GDD + battle-hud GDD | 垂直切片用户测试 | 影响 Rule 4 和 AC-8 |
| OQ-2 | **候选卡片是否支持"查看完整数值"展开状态**？当前规定 MVP 不显示具体数值，只显示倾向描述。若玩家需要精确比较，是否增加"点击展开"查看 HP/攻击力？ | 本 GDD | 垂直切片用户测试 | 影响 Rule 6 和候选卡布局 |
| OQ-3 | **DeployScreen 的 roster 列表排序规则**：按招募顺序、按职业分组、还是按 initiative 值（力量感降序）？ | 本 GDD | MVP 实现前 | 影响 Rule 3 和 AC-5 |

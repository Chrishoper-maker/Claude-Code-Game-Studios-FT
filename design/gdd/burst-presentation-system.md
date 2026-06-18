# 爆发演出系统 (Burst Presentation System)

> **Status**: Approved
> **Author**: claude-sonnet-4-6 (autonomous)
> **Last Updated**: 2026-06-16
> **Implements Pillar**: 关键回合的爆发（每场战斗积蓄至1–2次逆转性爆发回合）

## Overview

爆发演出系统是《孤帆棋海》"juice 即假设"的实现层——当羁绊槽与爆发技系统完成力学结算后，本系统接过 `burst_presentation_requested` 信号，以**多阶段电影化演出**将那次打击具现为玩家记忆中的高光时刻。演出采用"3D 战场 + 2D 漫画分镜叠层"的混合风格：底层是 Godot 3D 低模场景，上层是 CanvasLayer 驱动的漫画格面板、角色立绘、爆发技名称闪字；配合摄像机震动与粒子效果形成完整的冲击感。本系统与力学层**松耦合**——羁绊槽系统 emit 信号后立即返回，不等待演出完成；本系统独立管理演出时长，并在开始与结束时发出信号供 HUD 锁定/解锁玩家输入。MVP 支持 2 种精英爆发演出（破阵先锋、瞄准定位）+ 通用爆发演出框架；Alpha 阶段扩展至全部 6 种精英爆发。白盒构建期提供 `USE_BURST_PRESENTATION_FALLBACK` 降级模式，无需美术资源即可验证信号链与输入锁定功能。

## Player Fantasy

玩家按下爆发键的那一刻，应该感觉到"我等了整整六回合，终于轮到我了。"

接下来的两秒钟不属于策略，属于情感。漫画格面板"啪啪啪"地切入画面——先是 lead 单位的特写，再是 partner 单位的眼神，最后是联合出击的爆炸格——这是《海贼王》原著里招式定格的节奏感。爆发技名称在画面正中用大字闪出时，玩家应该在心里默读它："——破阵先锋。" 摄像机震动不是随机噪声，是那次斩击真正落下的重量。

当演出结束、画面回到战场，几个敌人的 HP 已经归零，玩家手里还可能剩着行动点——这是双重满足：情感爆发 + 战术余韵。

本系统服务的是"挣来的"高光，而不是"随机掉落的"爽感。演出时长必须足够短，让玩家不觉得等待；足够长，让玩家来得及品味。

## Detailed Design

### Core Rules

---

#### Rule 1：信号订阅与触发

系统订阅羁绊槽与爆发技系统的 `burst_presentation_requested(lead_id, partner_id, burst_type_id)` 信号。收到信号后**立即**进入演出流程（无需延迟帧）。羁绊槽系统不等待本系统回调（松耦合契约，见 bond-gauge-burst-system.md Rule 6）。

---

#### Rule 2：输入锁定

演出开始的第一步（在任何动画帧之前）是：
```
emit burst_presentation_started(burst_type_id)
```
HUD 系统订阅此信号以禁用所有玩家输入（格子点选、行动按钮、结束回合均不可用）。演出结束的最后一步是：
```
emit burst_presentation_ended(burst_type_id)
```
HUD 收到后恢复输入。**禁止在演出中途解锁输入**——即使动画提前完成也须等待 `BURST_PRESENTATION_DURATION_*` 计时结束后才发出 ended 信号。

---

#### Rule 3：演出序列（标准模式）

演出分五个阶段，全部通过 Tween 链串行执行：

| 阶段 | 名称 | 时长（ms） | 内容 |
|------|------|------------|------|
| P1 | FREEZE | `BURST_FREEZE_DURATION`（默认 60） | 全局时间缩放到 0.05（极慢动作效果）；屏幕边缘暗化 vignette 快速闪入 |
| P2 | PANELS_IN | 500 | CanvasLayer 上漫画格面板从屏幕边缘滑入；上下电影黑边扩展；lead 与 partner 立绘载入对应格 |
| P3 | BURST_NAME | 300 | 爆发技名称文字（大号斜体）从中心扩散入场；精英爆发附加颜色描边闪光 |
| P4 | IMPACT | `BURST_IMPACT_DURATION`（默认 200） | 全局时间恢复正常；摄像机震动（过程期间恢复到 1.0 时间缩放）；屏幕闪白一帧（精英爆发）或半帧（通用爆发） |
| P5 | PANELS_OUT | 400 | 漫画格面板向外滑出；电影黑边收回；vignette 淡出 |

各阶段时长之和 = 总演出时长：
- 精英爆发：60 + **500** + **300** + 200 + **400** = 1460 ms（未缩放基准值；仅用于 Formula 1 的比例计算，不是实际播放时长）
- 通用爆发：60 + **300** + **200** + 200 + **240** = 1000 ms（同上）

**实际默认时长**（`BURST_PRESENTATION_DURATION_ELITE = 1960ms` 时，scale_factor ≈ 1.417）：P2 ≈ 709ms, P3 ≈ 425ms, P5 ≈ 567ms，总计 ≈ 1960ms。

当调参旋钮值与阶段总和不符时，**以旋钮值为准**，按比例缩放 P2/P3/P5（P1/P4 保持绝对值，因其与物理感知紧密相关）。

---

#### Rule 4：演出资产查表（PRESENTATION_TABLE）

`burst_type_id` 对应演出配置从 PRESENTATION_TABLE 中取得：

| burst_type_id | 精英 | 面板数 | 爆发技全名 | lead立绘组 | partner立绘组 | sfx_id | 里程碑 |
|---|---|---|---|---|---|---|---|
| `"破阵先锋"` | ✓ | 3 | "破阵先锋" | swordsman_burst | bulwark_burst | `burst_sakigake` | MVP |
| `"瞄准定位"` | ✓ | 3 | "瞄准定位" | gunner_burst | navigator_burst | `burst_targeting` | MVP |
| `"热血演奏"` | ✓ | 3 | "热血演奏" | swordsman_burst | musician_burst | `burst_bardic` | Alpha |
| `"轰鸣序曲"` | ✓ | 3 | "轰鸣序曲" | gunner_burst | musician_burst | `burst_thunder` | Alpha |
| `"护持突破"` | ✓ | 3 | "护持突破" | swordsman_burst | medic_burst | `burst_lifeline` | Alpha |
| `"铁甲同心"` | ✓ | 3 | "铁甲同心" | bulwark_burst | medic_burst | `burst_ironheart` | Alpha |
| `"generic"` | ✗ | 1 | "协力强击！" | lead职业通用 | partner职业通用 | `burst_generic` | MVP |

若 `burst_type_id` 不在表中（未来新增爆发），退化为 `"generic"` 条目。

---

#### Rule 5：摄像机震动

P4（IMPACT）阶段触发摄像机震动：
1. 在 Camera3D 节点上通过 Godot Tween 对 `position` 施加往复偏移（不修改 global_transform，仅修改 local position offset）
2. 震动波形：正弦衰减（振幅从 `BURST_CAMERA_SHAKE_INTENSITY` 线性衰减至 0）
3. 频率：12 Hz（每 83ms 一个周期）
4. 持续：`BURST_CAMERA_SHAKE_DURATION`（默认 300ms）
5. 精英爆发：强度 ×1.5（`BURST_CAMERA_SHAKE_INTENSITY × 1.5`）

摄像机震动结束后 **position offset 归零**（不留残差）。

---

#### Rule 6：降级模式（USE_BURST_PRESENTATION_FALLBACK = true）

白盒构建期激活，跳过所有 2D 面板与立绘资产：
1. 输入锁定仍正常执行（Rule 2 不变）
2. P2/P3 阶段替换为：全屏黑色半透明蒙版 + 中央白色大字显示 burst_type_id 字符串，持续 600ms
3. P4 摄像机震动正常执行
4. P5 淡出到正常战场画面
5. `burst_presentation_started` / `burst_presentation_ended` 正常发出

此模式用于在美术资产就绪前验证信号链、输入锁定、时序行为。

---

#### Rule 7：队列化（同场战斗中爆发不叠加）

MVP 范围内每场战斗至多触发 1 次爆发（槽清零后需重新充能）。若因系统边界异常导致 `burst_presentation_requested` 连续发出两次，演出系统采用**后发优先（Last-Wins）**：正在播放的演出立即跳出（skip），新演出从 P1 开始。此边界情况不应发生，但需有防护。

### States and Transitions

| 状态 | 描述 | 进入条件 | 退出条件 |
|------|------|---------|---------|
| `IDLE` | 等待触发；CanvasLayer 隐藏 | 初始化；PANELS_OUT 完成 | 收到 `burst_presentation_requested` |
| `P1_FREEZE` | 时间缩放 + vignette 闪入 | 收到 `burst_presentation_requested` | 计时 `BURST_FREEZE_DURATION` 结束 |
| `P2_PANELS_IN` | 面板滑入 + 黑边扩展 | P1 完成 | 动画完成 |
| `P3_BURST_NAME` | 爆发名称入场 | P2 完成 | 动画完成 |
| `P4_IMPACT` | 时间恢复 + 摄像机震动 + 屏幕闪白 | P3 完成 | `BURST_IMPACT_DURATION` 结束 |
| `P5_PANELS_OUT` | 面板滑出 + 黑边收回 | P4 完成 | 动画完成 → emit `burst_presentation_ended` → `IDLE` |

降级模式（FALLBACK）使用同一状态机，P2/P3 内容替换为文字蒙版，其余不变。

状态转换全部由 Tween 链串行驱动（`.chain()` 或 `.parallel()` 按需组合）；中途 skip 时通过 `tween.kill()` 强制终止并立即进入 P5（规则 7 的 skip 逻辑）。

### Interactions with Other Systems

| 系统 | 接口 / 信号 | 方向 | 说明 |
|------|------------|------|------|
| 羁绊槽与爆发技系统 (#6) | `burst_presentation_requested(lead_id, partner_id, burst_type_id)` | 接收信号 | 主触发信号；羁绊槽系统 emit 后不等待回调（松耦合） |
| 战斗 HUD 系统 (#9) | `burst_presentation_started(burst_type_id)` | 发出信号 | HUD 订阅后禁用所有玩家输入；在任何动画帧之前发出 |
| 战斗 HUD 系统 (#9) | `burst_presentation_ended(burst_type_id)` | 发出信号 | HUD 订阅后恢复玩家输入；演出完整播完后发出 |
| 单位数据系统 (#1) | `UnitInstance.class_id`（via lead_id / partner_id） | 读取 | 查表获取立绘组 ID（portrait_ids），对应 PRESENTATION_TABLE 中的 lead/partner立绘组 |
| 音频系统 (#17) | `sfx_id`（字符串，通过信号或直接调用） | 调用 | P3 入场时播放对应爆发 SFX；音频系统订阅或本系统直接调用 AudioManager |
| 战斗场景 Camera3D | Camera3D.position 偏移 | 写入（直接引用） | P4 阶段摄像机震动；仅修改 local position offset，不修改 global_transform |

**松耦合说明**：本系统不反向调用羁绊槽系统，不影响 bond_gauge_current 或任何力学状态。演出期间若战斗状态发生变化（理论上不应发生，因输入已锁定），本系统仍完成演出后才解锁。

**输入锁定合约（接收方约束）**：`burst_presentation_started` 与 `burst_presentation_ended` 必须被接收方（HUD 系统等）作为**幂等布尔切换**处理（set lock=true / set lock=false），不可作为引用计数对（counter++ / counter--）使用。Rule 7 的 skip 路径会连续发出两次 started 但仅发出一次 ended——计数器模式将导致输入永久锁定。

**关闭 bond-gauge-burst-system.md OQ-2**：bond-gauge OQ-2 询问"爆发演出期间是否暂停游戏逻辑"。本系统通过 Rule 2 的输入锁定机制回答：演出期间玩家输入被禁用，而《孤帆棋海》为回合制架构，所有游戏逻辑推进的唯一入口为玩家输入，因此演出期间游戏状态天然静止。bond-gauge 系统 emit `burst_presentation_requested` 后立即返回、不等待回调的松耦合设计与此相容。

## Formulas

### 公式 1：演出总时长（精英爆发）

```
total_ms_elite = BURST_FREEZE_DURATION + P2_ms + P3_ms + BURST_IMPACT_DURATION + P5_ms
```

调参方式：调整 `BURST_PRESENTATION_DURATION_ELITE`，系统按比例缩放 P2/P3/P5：
```
scale_factor = (BURST_PRESENTATION_DURATION_ELITE - BURST_FREEZE_DURATION - BURST_IMPACT_DURATION) / (P2_base + P3_base + P5_base)
P2_ms = round(500 × scale_factor)
P3_ms = round(300 × scale_factor)
P5_ms = round(400 × scale_factor)
```

**Variables:**
| 变量 | 默认值 | 单位 | 说明 |
|------|--------|------|------|
| `BURST_PRESENTATION_DURATION_ELITE` | 1960 | ms | 精英爆发总时长旋钮 |
| `BURST_FREEZE_DURATION` | 60 | ms | P1 时长（固定值，不参与缩放） |
| `BURST_IMPACT_DURATION` | 200 | ms | P4 时长（固定值，不参与缩放） |
| P2_base | 500 | ms | 基准面板入场时长 |
| P3_base | 300 | ms | 基准名称入场时长 |
| P5_base | 400 | ms | 基准面板出场时长 |

**Output Range:** `BURST_FREEZE_DURATION + BURST_IMPACT_DURATION ≤ total ≤ 5000 ms`（上限由安全范围约束）
**Example:** 默认值 → scale_factor = (1960 - 60 - 200) / (500+300+400) = 1700/1200 ≈ 1.417 → P2=709ms, P3=425ms, P5=567ms，总计 1961ms

---

### 公式 2：演出总时长（通用爆发）

同公式 1 结构，使用 `BURST_PRESENTATION_DURATION_BASE` 和更小的基准面板数（base_panels = 1）：
```
P2_base_generic = 300   # 单格面板，入场更快
P3_base_generic = 200
P5_base_generic = 240
```

**Output Range:** 最短 `BURST_FREEZE_DURATION + BURST_IMPACT_DURATION + (300+200+240)×min_scale`；默认 1000ms

---

### 公式 3：摄像机震动偏移

```
shake_offset(t) = SHAKE_INTENSITY × sin(2π × SHAKE_FREQUENCY × t) × (1 - t / SHAKE_DURATION)
```

**Variables:**
| 变量 | 符号 | 默认值 | 单位 | 说明 |
|------|------|--------|------|------|
| 震动强度 | `BURST_CAMERA_SHAKE_INTENSITY` | 8.0 | pixels（3D 逻辑单位换算见注） | 峰值偏移量 |
| 震动频率 | `SHAKE_FREQUENCY` | 12 | Hz | 正弦周期数/秒 |
| 震动时长 | `BURST_CAMERA_SHAKE_DURATION` | 300 | ms | 包络总时长 |
| 时间变量 | t | [0, DURATION] | s | 时间流逝量 |

精英爆发修正：`SHAKE_INTENSITY_ELITE = BURST_CAMERA_SHAKE_INTENSITY × 1.5`（默认 = 12.0 pixels）

**Output Range:** `shake_offset ∈ [-SHAKE_INTENSITY, +SHAKE_INTENSITY]`，线性衰减至 0
**Note:** "pixels" 在 Godot 3D 语境中指 Camera3D.position 的 x/y 局部单位偏移，需在实现时换算为恰当比例（→ ADR 待立项）

---

### 公式 4：时间缩放（P1 Freeze Effect）

```
Engine.time_scale = BURST_TIME_SCALE_FREEZE   # P1 期间
Engine.time_scale = 1.0                       # P4 时恢复
```

**Variables:**
| 变量 | 默认值 | 安全范围 | 说明 |
|------|--------|---------|------|
| `BURST_TIME_SCALE_FREEZE` | 0.05 | [0.01, 0.2] | 接近0=近乎静止，越高=冻结感越弱 |

**注**：Godot 中 `Engine.time_scale` 影响所有 `_process` / `_physics_process`；本系统的 Tween 须使用 `TweenProcessMode.TWEEN_PROCESS_IDLE` 且挂接到不受 time_scale 影响的节点（或使用 `unscaled_delta`）——此为实现层约束，→ ADR 待确认。

## Edge Cases

**EC-1：burst_type_id 不在 PRESENTATION_TABLE 中**
若 `burst_type_id` 未匹配任何已知条目（未来新增爆发尚未配置），退化为 `"generic"` 配置执行。emit `burst_presentation_started` 和 `burst_presentation_ended` 正常发出，不因未知 ID 中断演出。在 debug 构建中打印警告："Unknown burst_type_id: [id], falling back to generic"

**EC-2：演出开始时 CanvasLayer 已可见（意外残留）**
系统进入 P1_FREEZE 时若检测到 CanvasLayer 已处于可见状态（上一次演出因崩溃未完成），立即强制隐藏所有子节点并重置所有动画状态，然后正常开始新演出。`burst_presentation_ended` 不重复 emit（仅当前演出结束时发出一次）。

**EC-3：battle_won 或 battle_lost 信号在演出期间触发**
战斗解算和 AI 系统在爆发执行时已完成结算，战斗胜负信号最早在本回合的 ROUND_END（或即时胜利条件触发）发出。若 `battle_won` 恰好在演出期间通过 Godot 同步信号到达：系统**不中断演出**，完整播完后 emit `burst_presentation_ended`，然后正常进入胜利流程（HUD 收到 ended 解锁输入，胜利界面随即展示）。

**EC-4：玩家在演出期间尝试跳过（快捷键）**
MVP 范围内**不支持跳过**。输入锁定期间所有输入均被忽略。Alpha 阶段可选添加 `BURST_ALLOW_SKIP` 旋钮（按任意键跳至 P5）——当前不实现。

**EC-5：连续两次爆发（Rule 7 skip 路径）**
正在播放演出（状态非 IDLE）时再次收到 `burst_presentation_requested`：
1. `tween.kill()` 强制终止当前 Tween 链
2. 立即恢复 `Engine.time_scale = 1.0`（防止冻结残留）
3. CanvasLayer 强制隐藏
4. 不 emit `burst_presentation_ended`（已 skip 的演出不发结束信号）
5. 重新 emit `burst_presentation_started(new_burst_type_id)` 并从 P1 开始新演出

**EC-6：Camera3D 节点引用丢失（场景切换）**
若战斗场景被卸载时演出仍在播放，Tween 引用的 Camera3D 节点变为无效引用 → Tween 内部应使用 `is_instance_valid(camera)` 前置检查。若检查失败，跳过摄像机震动步骤但继续 CanvasLayer 动画和信号发出。

**EC-7：降级模式 + 精英爆发**
当 `USE_BURST_PRESENTATION_FALLBACK = true` 且 burst_type_id 为精英配对时，显示精英爆发名称的大字（从 PRESENTATION_TABLE 取 burst_name 字段），持续时间仍使用 `BURST_PRESENTATION_DURATION_ELITE`。降级模式不区分精英与通用，但时长保持差异。

**EC-8：`BURST_TIME_SCALE_FREEZE = 0` 极端值**
若配置为 0，`Engine.time_scale = 0` 将完全冻结所有 `_process` 节点。本系统 Tween 须使用 `unscaled_delta`（→ ADR），否则 P1 阶段将永不结束。校验：加载时若 `BURST_TIME_SCALE_FREEZE < 0.01`，强制钳制至 0.01 并打印警告。

## Dependencies

### 上游依赖

| 系统 | GDD | 依赖内容 | 状态 |
|------|-----|---------|------|
| 羁绊槽与爆发技系统 (#6) | bond-gauge-burst-system.md | 信号 `burst_presentation_requested(lead_id, partner_id, burst_type_id)` 的定义与触发时机；松耦合契约（#6 不等待回调） | Approved |
| 单位数据系统 (#1) | unit-data-system.md | `UnitInstance.class_id` — 演出系统通过 lead_id 和 partner_id 查询职业以选立绘组 | Approved |

### 下游依赖（本系统发出信号供下游消费）

| 系统 | GDD | 依赖内容 | 状态 |
|------|-----|---------|------|
| 战斗 HUD 系统 (#9) | — | 订阅 `burst_presentation_started` 禁用输入；订阅 `burst_presentation_ended` 恢复输入 | Not Started |
| 音频系统 (#17) | — | 订阅 `burst_presentation_started(burst_type_id)` 触发对应 sfx_id 音效 | Not Started (Full Vision) |

### 运行时依赖（场景节点）

| 节点 | 类型 | 说明 |
|------|------|------|
| 战斗场景 Camera3D | Camera3D | P4 摄像机震动的目标节点；通过场景引用（非信号）直接访问 |
| BurstPresentationLayer | CanvasLayer | 本系统拥有和管理的 2D 叠层节点；渲染漫画格、立绘、名称文字 |

### 技术实现约束（→ ADR 待立项）

- **Tween 时间模式**：P1 阶段修改 `Engine.time_scale`，本系统自身 Tween 须使用 `TWEEN_PROCESS_IDLE` + `unscaled` delta 或对应的 Godot 4.x API，否则 P1 计时失效（→ ADR-BURST-TWEEN-MODE）
- **Camera3D 震动坐标系**：pixel 单位到 3D 空间单位换算需通过相机 FOV 和目标距离推导（→ ADR-BURST-CAMERA-SHAKE）
- **CanvasLayer + Forward+**：2D 叠层渲染在 Forward+ + D3D12 后端的行为已在 4.6 中与 4.3 保持一致（Low Risk），但应在目标平台（Windows/Steam）实机验证

## Tuning Knobs

| 常量名 | 默认值 | 安全范围 | 游戏效果 | 注册位置 |
|--------|--------|---------|---------|---------|
| `BURST_PRESENTATION_DURATION_ELITE` | 1960 | [1000, 3000] ms | 精英爆发演出总时长；低=节奏快但感觉廉价，高=感觉厚重但流程变慢 | entities.yaml（建议） |
| `BURST_PRESENTATION_DURATION_BASE` | 1000 | [600, 1800] ms | 通用爆发演出总时长；应明显短于精英以体现稀有度差异 | entities.yaml（建议） |
| `BURST_FREEZE_DURATION` | 60 | [0, 150] ms | P1 冻结帧时长；0=无冻结效果；超过150ms会感觉卡帧而非电影感 | entities.yaml（建议） |
| `BURST_IMPACT_DURATION` | 200 | [100, 400] ms | P4 冲击阶段时长（摄像机震动窗口） | entities.yaml（建议） |
| `BURST_CAMERA_SHAKE_INTENSITY` | 8.0 | [0.0, 20.0] pixels | 摄像机震动峰值偏移；0=无震动（无障碍友好选项前提）；精英自动 ×1.5 | entities.yaml（建议） |
| `BURST_CAMERA_SHAKE_DURATION` | 300 | [100, 600] ms | 震动持续时长；不应超过 P4 时长 + P5 前200ms | entities.yaml（建议） |
| `BURST_TIME_SCALE_FREEZE` | 0.05 | [0.01, 0.3] | P1 阶段时间缩放系数；0.05 = 20倍慢动作；越高越"快速定格"感 | entities.yaml（建议） |
| `USE_BURST_PRESENTATION_FALLBACK` | false | true/false | 白盒降级模式开关；true=跳过所有美术资产，仅显示文字 | project settings / 构建标记 |

**互动约束：**
- `BURST_CAMERA_SHAKE_DURATION` 不应超过 `BURST_IMPACT_DURATION + BURST_PRESENTATION_DURATION_BASE × 0.3`（否则震动会延续到 P5 面板出场期间，视觉混乱）
- `BURST_FREEZE_DURATION + BURST_IMPACT_DURATION < min(BURST_PRESENTATION_DURATION_BASE, BURST_PRESENTATION_DURATION_ELITE)`（固定阶段必须小于总时长，剩余时间才能分配给可缩放阶段）
- 无障碍模式下建议将 `BURST_CAMERA_SHAKE_INTENSITY = 0.0` 并提供用户开关（→ Alpha 阶段设置菜单）

## Visual/Audio Requirements

### 视觉资产（MVP）

| 资产 ID | 类型 | 规格 | 用途 | 里程碑 |
|---------|------|------|------|--------|
| `panel_frame_elite` | Texture2D（PNG） | 960×540 px，透明背景 | 精英爆发漫画格外框 | MVP |
| `panel_frame_generic` | Texture2D（PNG） | 960×540 px，透明背景 | 通用爆发漫画格外框（简化） | MVP |
| `swordsman_burst` | TextureRect / AnimatedTexture | 立绘尺寸 TBD（建议 512×512） | 剑豪爆发专用立绘 | MVP |
| `bulwark_burst` | TextureRect / AnimatedTexture | 同上 | 铁壁爆发专用立绘 | MVP |
| `gunner_burst` | TextureRect / AnimatedTexture | 同上 | 炮手爆发专用立绘 | MVP |
| `navigator_burst` | TextureRect / AnimatedTexture | 同上 | 航海士爆发专用立绘 | MVP |
| `{class}_burst_generic` | TextureRect（6张） | 同上 | 各职业通用爆发立绘（低质量OK） | MVP |
| `vignette_overlay` | Texture2D | 全屏 UV 渐变纹理 | P1 暗化边缘效果 | MVP |
| `flash_white` | ColorRect / Shader | 全屏白色蒙版 | P4 屏幕闪白 | MVP |
| `letterbox_bars` | ColorRect（上/下两条） | 各 90px 高，全宽 | P2 电影黑边 | MVP |

### 字体与文字

| 元素 | 字体风格 | 字号（建议） | 说明 |
|------|---------|-----------|------|
| 爆发技名称 | 粗体斜体，描边 | 72–96pt | 从中心扩散入场；精英爆发附加颜色描边（职业主色） |
| 降级模式文字 | 等宽常规体 | 48pt | `USE_BURST_PRESENTATION_FALLBACK` 下显示，白色 |

### 视觉资产（Alpha 追加）

Alpha 阶段新增 4 种精英爆发（热血演奏、轰鸣序曲、护持突破、铁甲同心）时，追加：
- `musician_burst`、`medic_burst` 立绘
- 对应职业主色描边配置（注册于 PRESENTATION_TABLE 扩展字段）

### 音频资产（MVP）

| sfx_id | 类型 | 时长（建议） | 触发时机 | 里程碑 |
|--------|------|-----------|---------|--------|
| `burst_sakigake` | SFX（MP3 / OGG） | 0.8–1.2s | P3 爆发技名称入场时 | MVP |
| `burst_targeting` | SFX | 0.8–1.2s | P3 爆发技名称入场时 | MVP |
| `burst_generic` | SFX | 0.5–0.8s | P3 入场时（通用，规格略低） | MVP |
| `camera_shake_impact` | SFX（短促） | 0.1–0.2s | P4 摄像机震动启动时 | MVP |

**音频触发规则**：`burst_sakigake` / `burst_targeting` / `burst_generic` 在 P3（BURST_NAME）阶段开始时由本系统直接调用 AudioManager（或 emit `burst_presentation_started` 供音频系统订阅）。`camera_shake_impact` 在 P4（IMPACT）阶段开始时触发。

**降级模式音频**：`USE_BURST_PRESENTATION_FALLBACK = true` 时音频正常播放（不受影响）。

### 粒子效果（可选，MVP 低优先级）

精英爆发 P3 阶段可附加 2D 粒子（CPUParticles2D）在爆发名称周围散射——由美术主导实现，本 GDD 不锁定参数，留至 Alpha 调整。

## UI Requirements

### CanvasLayer 层级

| 层级名 | CanvasLayer.layer 值 | 内容 | 说明 |
|--------|---------------------|------|------|
| `BurstPresentationLayer` | 10（建议；高于 HUD 层） | 漫画格面板、立绘、爆发名称、vignette、黑边 | 演出期间覆盖全屏，不干扰 HUD 的 `burst_presentation_ended` 订阅 |
| HUD Layer（外部） | ≤ 5（HUD 系统自行管理） | 血条、槽量、意图图标 | HUD 在演出期间仍可见（被 BurstPresentationLayer 覆盖时部分被遮）；MVP 不要求 HUD 在演出中完全隐藏 |

### BurstPresentationLayer 节点结构（参考）

```
BurstPresentationLayer (CanvasLayer, layer=10)
├── LetterboxTop      (ColorRect, 全宽 × 90px, top)
├── LetterboxBottom   (ColorRect, 全宽 × 90px, bottom)
├── VignetteRect      (TextureRect, 全屏, vignette_overlay)
├── PanelContainer    (HBoxContainer or manual positioning)
│   ├── Panel_0       (TextureRect — panel_frame_elite 或 generic)
│   │   └── Portrait_0 (TextureRect — lead立绘)
│   ├── Panel_1       (TextureRect — 可选，精英爆发第2格)
│   │   └── Portrait_1 (TextureRect — partner立绘)
│   └── Panel_2       (TextureRect — 可选，精英爆发第3格联合出击格)
├── BurstNameLabel    (Label / RichTextLabel, 居中叠层)
└── FlashRect         (ColorRect, 全屏白色, modulate.a=0 时不可见)
```

降级模式下 `PanelContainer` 替换为全屏黑色半透明 `ColorRect` + `BurstNameLabel`；其余节点保留（动画仅运行 P4/P5）。

### 输入锁定（UI 层职责边界）

- **本系统职责**：emit `burst_presentation_started` / `burst_presentation_ended`
- **HUD 系统职责**（#9 GDD 中规定）：收到 started 后禁用所有交互控件；收到 ended 后恢复
- **本系统不直接操作 HUD 控件**——通过信号解耦，HUD 可独立处理"演出中显示什么提示"的问题

### 无障碍考量（Alpha 阶段）

| 选项 | 实现方式 | 优先级 |
|------|---------|--------|
| 关闭摄像机震动 | 设置菜单 `BURST_CAMERA_SHAKE_INTENSITY = 0.0` | Alpha |
| 缩短演出时长 | 设置菜单将 `BURST_PRESENTATION_DURATION_*` 减半（×0.5 速度模式） | Alpha |
| 关闭屏幕闪白 | 设置菜单 `BURST_DISABLE_FLASH = true`（P4 跳过 FlashRect） | Alpha |

MVP 阶段不实现上述选项，但 Tuning Knobs 的设计已为其预留参数位置。

## Acceptance Criteria

### 功能验收（MVP）

**AC-1（信号订阅）**：触发爆发技后，`burst_presentation_requested` 在同帧内被本系统接收并进入 `P1_FREEZE` 状态。验证：信号 emit 后下一帧 `BurstPresentationLayer.visible == true`。

**AC-2（输入锁定先于动画）**：`burst_presentation_started` 在任何 CanvasLayer 动画帧之前发出。验证：使用信号监听器记录 `burst_presentation_started` 的发出帧号；确认 `BurstPresentationLayer` 的 `CanvasItem.draw` 首次调用发生在同帧或更晚帧（而非更早帧）。替代验证：在信号处理函数中断言 `BurstPresentationLayer.visible == false`（CanvasLayer 尚未激活动画）或 `BurstPresentationLayer.modulate.a == 0`。

**AC-3（输入解锁后于动画）**：`burst_presentation_ended` 仅在演出完整播放完毕后发出，不早于 `BURST_PRESENTATION_DURATION_ELITE`（精英）或 `BURST_PRESENTATION_DURATION_BASE`（通用）ms。验证：记录 started 时间戳与 ended 时间戳差值 ≥ 配置值的 95%。

**AC-4（时间缩放）**：P1 阶段期间 `Engine.time_scale == BURST_TIME_SCALE_FREEZE`（默认 0.05）；P4 阶段结束时 `Engine.time_scale == 1.0`。验证：在 P1 / P4 分别查询 `Engine.time_scale`。

**AC-5（五阶段串行）**：演出按 P1 → P2 → P3 → P4 → P5 顺序执行，无阶段跳过或乱序。验证：状态机 `current_state` 日志在单次演出中依次经过 5 个状态。

**AC-6（精英爆发查表）**：`burst_type_id = "破阵先锋"` 时，Panel_0 显示剑豪立绘组（`swordsman_burst`）、Panel_1 显示铁壁立绘组（`bulwark_burst`），面板数 = 3。验证：目视或节点属性检查。

**AC-7（通用爆发查表）**：`burst_type_id = "generic"` 时，面板数 = 1，文字显示 "协力强击！"，使用 `BURST_PRESENTATION_DURATION_BASE` 时长。

**AC-8（未知 ID 降级）**：`burst_type_id = "不存在的ID"` 时，退化执行 generic 配置，控制台打印警告，演出正常完成。

**AC-9（摄像机震动范围）**：P4 阶段 Camera3D.position 偏移幅值在 `[0, BURST_CAMERA_SHAKE_INTENSITY × 1.5]` 之间（精英爆发），P4 结束后 position offset 归零（|offset| < 0.01 单位）。

**AC-10（降级模式可用）**：`USE_BURST_PRESENTATION_FALLBACK = true` 时，演出不加载任何立绘纹理，仅显示黑色蒙版 + burst_type_id 文字；`burst_presentation_started` 和 `burst_presentation_ended` 正常发出；摄像机震动正常执行。

### 边界验收（MVP）

**AC-11（重复触发防护）**：演出进行中第二次触发 `burst_presentation_requested` 时，当前演出立即 kill，`Engine.time_scale` 恢复 1.0，新演出从 P1 开始；旧演出不发出 `burst_presentation_ended`。验证：注入两次 emit 并观察状态机跳转。

**AC-12（EC-2 残留清理）**：进入 P1_FREEZE 时若 CanvasLayer 已可见，强制隐藏所有子节点后再执行正常演出流程。验证：手动置 `BurstPresentationLayer.visible = true` 后触发爆发，演出正常。

**AC-13（时间缩放钳制）**：若 `BURST_TIME_SCALE_FREEZE` 配置为 0 或负值，系统将其钳制至 0.01 并打印警告，不出现 P1 永不结束的情况。

**AC-14（Camera3D 无效引用）**：若 Camera3D 节点在演出期间被释放（`is_instance_valid == false`），摄像机震动静默跳过，演出其余阶段正常完成，`burst_presentation_ended` 正常发出。

### 演出质量验收（Alpha）

**AC-15（情感节拍）**：内部试玩评审：连续触发 5 次爆发演出后，团队对"打击感"的平均评分 ≥ 4/5（5点量表）。——Alpha 阶段主观验收。

**AC-16（演出时长主观感受）**：内部试玩评审：精英爆发演出不让玩家感觉"太长想跳过"（评分 ≤ 2/5 的比率 < 20%）。——Alpha 阶段主观验收。

## Open Questions

**OQ-1（Camera3D 单位换算）**：`BURST_CAMERA_SHAKE_INTENSITY = 8.0` 的 "pixels" 在 3D 视口中如何换算为 Camera3D.position 偏移量？换算系数依赖摄像机 FOV 和战场深度——需在实现阶段通过实测确定，立项为 ADR-BURST-CAMERA-SHAKE。→ 实现阶段决策。

**OQ-2（Tween unscaled delta API）**：Godot 4.6.3 中实现不受 `Engine.time_scale` 影响的 Tween 的推荐 API 是 `create_tween().set_process_mode(Tween.TWEEN_PROCESS_IDLE)` + 手动 `delta` 参数，还是有更简洁的 unscaled_delta 路径？需查证引擎文档，立项为 ADR-BURST-TWEEN-MODE。→ 实现阶段决策。

**OQ-3（跳过功能）**：是否在 Alpha 阶段为玩家提供"按任意键跳过演出"（直接跳到 P5）？原型测试显示演出时长可接受，但长期重复游玩（多 run 后）可能产生疲劳。→ Alpha 试玩后决策；当前 MVP 不实现（见 EC-4）。

**OQ-4（HUD 在演出期间的可见性）**：演出期间 HUD 应全隐藏还是仅锁定输入（仍可见）？当前设计为"仍可见，被 BurstPresentationLayer 部分覆盖"。若用户测试中显得视觉混乱，可在 Alpha 阶段让 HUD 系统订阅 `burst_presentation_started` 后淡出。→ Alpha 试玩后决策。

**OQ-5（精英爆发描边颜色）**：各精英爆发的职业主色配置（P3 爆发名称描边颜色）——是在 PRESENTATION_TABLE 中扩展 `accent_color` 字段，还是由单位数据系统（#1）的 `class_color` 派生？→ 战斗 HUD 系统（#9）GDD 阶段统一决策（职业颜色注册表在 HUD 层更自然）。

# ADR-0008: Burst Presentation Timing — Tween 与 Engine.time_scale 解耦

## Status
Accepted

## Date
2026-06-18（Accepted 2026-06-18 — /architecture-review rerun CONCERNS；set_ignore_time_scale 列编码前 Verification Required，回退方案已备）

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6.3 |
| **Domain** | Animation / Core（Tween + Engine.time_scale） |
| **Knowledge Risk** | **HIGH** — 架构评审标注「Engine.time_scale + Tween：4.5 改动 Tween PROCESS_IDLE 模式行为」，后于 LLM 训练截止（~4.3）。`Tween.set_ignore_time_scale()` 的 4.6.3 确切行为无法仅凭训练数据断言 |
| **References Consulted** | `docs/engine-reference/godot/modules/animation.md`, `docs/engine-reference/godot/breaking-changes.md`, `docs/engine-reference/godot/deprecated-apis.md`, `design/gdd/burst-presentation-system.md`（OQ-2） |
| **Post-Cutoff APIs Used** | `Tween.set_ignore_time_scale(true)` — 须验证 4.6.3 行为（见 Verification Required）；`create_tween()` / `tween_property` / `tween_interval` / `chain` / `parallel` / `kill` 均 stable since 4.0 |
| **Verification Required** | **（HIGH，编码前必做实测）** ① 确认 `create_tween().set_ignore_time_scale(true)` 在 4.6.3 下以 unscaled delta 推进，不受 `Engine.time_scale` 影响；② 确认 4.5 的「Tween PROCESS_IDLE 模式行为调整」不改变上述结论；③ 实测 P1 在 `Engine.time_scale=0.05` 下仍按 ~60ms 墙钟结束（AC-4 + EC-8）；④ 若 `set_ignore_time_scale` 行为不符，回退到 Alternative 2（自管 unscaled delta 控制器） |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001（EventBus — BurstPresentation 订阅 `burst_presentation_requested`，emit `burst_presentation_started/ended`） |
| **Enables** | ADR-0009（Camera Shake — P4 IMPACT 阶段的相机震动，复用本 ADR 确立的 unscaled 计时基线与 time_scale 恢复时序） |
| **Blocks** | burst-presentation-system 全部实现故事（五阶段状态机、P1 计时、skip 清理） |
| **Ordering Note** | 须在任何爆发演出实现前 Accepted；与 ADR-0007 单位移动 Tween 相容（世界 Tween 走 scaled，FREEZE 期减速 = 期望定格效果），无相互阻塞 |

## Context

### Problem Statement

爆发演出（`burst-presentation-system.md`）P1 FREEZE 阶段将 `Engine.time_scale` 设为 `0.05`
制造 20× 慢动作定格效果。但在 Godot 中 `Engine.time_scale` 影响**所有** `_process`/`_physics_process`
节点——包括演出自身用于串接五个阶段（P1→P5）的 Tween 链。若演出 Tween 也被减速，P1 的
60ms 计时会被拉长 20 倍（1200ms），整套演出时序崩坏，极端值（`time_scale=0`）下 P1 永不结束。

本 ADR 决定：**演出 Tween 如何与 `Engine.time_scale` 解耦**，使世界获得慢动作背景的同时，
演出自身按真实墙钟时间推进。关闭 `burst-presentation-system.md` OQ-2 / ADR-BURST-TWEEN-MODE。

### Constraints

- P1 期间 `Engine.time_scale == BURST_TIME_SCALE_FREEZE`（默认 0.05），P4 起恢复 1.0（GDD AC-4，硬约束）
- 演出五阶段全部由 Tween 链串行驱动（GDD 规则；`.chain()`/`.parallel()` 组合）
- 回合制架构：演出期间游戏逻辑天然静止（输入锁定），无需暂停 SceneTree
- skip / 重入时须立即恢复 `Engine.time_scale=1.0`，防止冻结残留（GDD 规则 7 / EC-2）
- `BURST_TIME_SCALE_FREEZE` 可配为 0：须钳制至 ≥0.01 防止 P1 永不结束（GDD AC-13 / EC-8）
- Godot 4.6.3，HIGH RISK 引擎域（4.5 改动了 Tween PROCESS_IDLE 行为）

### Requirements

- P1 在 `Engine.time_scale=0.05` 下仍按 `BURST_FREEZE_DURATION≈60ms` 墙钟结束
- 世界对象（棋盘、单位移动 Tween[ADR-0007]、环境动画）在 FREEZE 期可见地减速（定格观感）
- skip / 重入路径必有 `Engine.time_scale=1.0` 恢复，无残留冻结
- 极端配置（`BURST_TIME_SCALE_FREEZE≤0`）不致死锁

## Decision

**演出自身的 Tween 走 unscaled 时间（`set_ignore_time_scale(true)` + `TWEEN_PROCESS_IDLE`），
按真实墙钟推进；`Engine.time_scale=0.05` 仅作用于游戏世界（scaled 处理），形成慢动作背景。
P4 起恢复 `time_scale=1.0`，skip/重入立即恢复。**

```
                          Engine.time_scale 时间轴
真实墙钟  ──────────────────────────────────────────────────▶
          │ P1 FREEZE │ P2 PANELS_IN │ P3 NAME │ P4 IMPACT │ P5 OUT │
ts 设置:   0.05────────┘(P2 起可恢复 1.0 或维持，按 GDD)        1.0 恢复@P4
                                                            （AC-4：P4 末 ts==1.0）

演出 Tween（CanvasLayer BurstPresentationLayer）:
  set_ignore_time_scale(true) → 全程 unscaled，real-time
  → P1 仍 60ms 墙钟结束，不被 ts=0.05 拉长

世界对象（GridBoard / UnitView 移动 Tween[ADR-0007] / 环境 AnimationPlayer）:
  scaled（默认）→ FREEZE 期减速至 0.05× = 定格观感
```

### 阶段驱动 Tween（unscaled）

```gdscript
# BurstPresentation（CanvasLayer layer=10）的阶段链
func _start_presentation(is_elite: bool) -> void:
    Engine.time_scale = _freeze_scale()          # P1: 钳制后的 BURST_TIME_SCALE_FREEZE
    _tween = create_tween()
    _tween.set_ignore_time_scale(true)           # ★ 演出按 unscaled 墙钟推进（须验证 4.6.3 行为）
    _tween.set_process_mode(Tween.TWEEN_PROCESS_IDLE)

    # P1 FREEZE：仅计时（vignette 闪入并行）
    _tween.tween_interval(BURST_FREEZE_DURATION / 1000.0)
    _tween.tween_callback(func(): Engine.time_scale = 1.0)   # 退出 FREEZE 恢复世界时间
    # P2/P3/P5 面板动画 + P4 IMPACT（IMPACT 内的相机震动归 ADR-0009）
    # ... tween_property(panel,...) / tween_callback(...) 按 GDD 五阶段串接
    _tween.finished.connect(_on_presentation_finished)
```

### time_scale 钳制（加载期）

```gdscript
func _freeze_scale() -> float:
    # GDD AC-13 / EC-8：≤0 会导致 P1 永不结束（即便 unscaled Tween，也防御世界处理死冻结）
    if BURST_TIME_SCALE_FREEZE < 0.01:
        push_warning("BURST_TIME_SCALE_FREEZE %f < 0.01，钳制至 0.01" % BURST_TIME_SCALE_FREEZE)
        return 0.01
    return BURST_TIME_SCALE_FREEZE
```

### skip / 重入清理（GDD 规则 7 / EC-2）

```gdscript
func skip_or_restart() -> void:
    if is_instance_valid(_tween):
        _tween.kill()                # ① 终止当前链
    Engine.time_scale = 1.0          # ② 立即恢复，防冻结残留（AC-11）
    # ③ 重入：若 CanvasLayer 已可见（上次崩溃残留），强制隐藏子节点后重启（EC-2/AC-12）
    # ④ 旧演出不 emit burst_presentation_ended
```

### Key Interfaces

| 接口/信号 | 签名 | 来源 |
|----------|------|------|
| 订阅 | `burst_presentation_requested(lead_id: int, partner_id: int, effect_id: StringName)` | ADR-0001（权威） |
| emit | `burst_presentation_started()` / `burst_presentation_ended()` | ADR-0001（权威，无参） |
| time_scale 约定 | P1 期间 `Engine.time_scale = clamp(BURST_TIME_SCALE_FREEZE, 0.01, …)`；P4 末 == 1.0 | 本 ADR |

> **GDD 同步注**：`burst-presentation-system.md` 正文将启动信号写作 `burst_presentation_started(burst_type_id)`，而 ADR-0001（Accepted）定为**无参** `burst_presentation_started()`。以 ADR-0001 为权威——`effect_id` 已随 `burst_presentation_requested` 传入，BurstPresentation 自身持有，音频触发（GDD 音频规则）直接调用 AudioManager 即可，无需信号携带 `burst_type_id`。建议 `/architecture-review` 时在 GDD 标注此对齐。

## Alternatives Considered

### Alternative 1: 不使用 Engine.time_scale，仅 vignette 视觉覆盖

- **Description**: P1 不改 `time_scale`，仅做边缘暗化 vignette
- **Pros**: 彻底规避 Tween/time_scale 耦合
- **Cons**: 与 GDD AC-4（P1 期间 `Engine.time_scale==0.05`）直接冲突；丧失世界慢动作定格——单位移动/环境动画无法"凝固"，电影感骤降
- **Rejection Reason**: 违反 GDD 已批准的硬约束 AC-4；定格观感是爆发演出核心卖点

### Alternative 2: 自管 unscaled delta 控制器（GDD OQ-2 后备路径）

- **Description**: 不依赖 `set_ignore_time_scale`，用一个 `_process(delta)` 节点（`PROCESS_MODE_ALWAYS`）按 `delta / Engine.time_scale` 反算未缩放时间，手动推进阶段计时
- **Pros**: 完全不依赖 `set_ignore_time_scale` 的 4.6.3 确切行为，可控性最高
- **Cons**: 重新实现 Tween 的插值/链式逻辑，代码量大、易错；失去 Tween 的 `.chain()`/`.parallel()` 表达力
- **Rejection Reason**: 仅作为 Verification Required ④ 的**回退方案**——若实测 `set_ignore_time_scale(true)` 在 4.6.3 不产生 unscaled 推进，则切换至本方案

### Alternative 3: 暂停 SceneTree（`get_tree().paused = true`）+ PROCESS_ALWAYS 演出

- **Description**: 用 SceneTree 暂停冻结世界，演出节点设 `PROCESS_MODE_ALWAYS`
- **Pros**: 世界彻底静止，演出独立运行
- **Cons**: 暂停是"全停"非"慢放"，无 0.05× 慢动作过渡感；与回合制"输入锁=逻辑静止"机制重复；`paused` 全局副作用面更大
- **Rejection Reason**: 需要的是慢动作（0.05×）而非全暂停；time_scale 更贴合定格美术意图

## Consequences

### Positive

- 世界慢动作（0.05×）与演出真实墙钟计时并存，P1 时序精确
- 复用 Godot Tween 的链式表达（`.chain()`/`.parallel()`），实现简洁
- 与 ADR-0007 单位移动 Tween 天然相容：世界 Tween 走 scaled，FREEZE 期自动减速即定格
- 钳制 + skip 清理双重防御，杜绝 `time_scale` 残留与 P1 死锁

### Negative

- 强依赖 `set_ignore_time_scale(true)` 的 4.6.3 行为，须编码前实测（HIGH RISK 验证项）
- 任何在演出期新增的世界视觉效果须明确选择 scaled / unscaled，否则慢动作表现不一致
- `Engine.time_scale` 是全局副作用：所有 time_scale 写入必须经 BurstPresentation 单点管理，避免多源竞争

### Risks

- **`set_ignore_time_scale` 4.6.3 行为不符预期**（4.5 改过 PROCESS_IDLE 行为）。
  缓解：列为 Verification Required ①②④；回退方案 Alternative 2 已备。
- **time_scale 残留冻结**：skip/崩溃后未恢复 1.0，整局游戏卡慢动作。
  缓解：skip/重入路径强制 `Engine.time_scale=1.0`（AC-11）；钳制下限 0.01（AC-13）。
- **多源写 time_scale 竞争**：若其他系统也改 `Engine.time_scale`，冲突。
  缓解：登记禁止模式——`Engine.time_scale` 仅由 BurstPresentation 写；其他系统不得触碰。
- **演出期场景卸载致 Tween 引用失效**（EC：Camera3D 失效）。
  缓解：Tween 回调内 `is_instance_valid()` 前置检查（相机震动具体处理归 ADR-0009）。

## GDD Requirements Addressed

| GDD 系统 | TR ID | 需求摘要 | 此 ADR 如何满足 |
|---------|-------|---------|--------------|
| burst-presentation-system.md | TR-BPS-003 | P1 操作 `Engine.time_scale=0.05`；Tween 须用 unscaled delta（HIGH RISK，立项 ADR-0008） | 演出 Tween `set_ignore_time_scale(true)`+`TWEEN_PROCESS_IDLE` 走 unscaled；世界走 scaled；**关闭 OQ-2** |
| burst-presentation-system.md | （AC-4） | P1 期间 `time_scale==0.05`，P4 末 ==1.0 | P1 设钳制后 freeze scale，FREEZE 退出/IMPACT 恢复 1.0 |
| burst-presentation-system.md | （AC-13/EC-8） | `BURST_TIME_SCALE_FREEZE≤0` 钳制至 0.01，P1 不死锁 | `_freeze_scale()` 加载期钳制 + warning |
| burst-presentation-system.md | （规则7/AC-11/EC-2） | skip/重入 kill + 立即恢复 time_scale | `skip_or_restart()` kill→ts=1.0→残留清理 |

## Performance Implications

- **CPU**: Tween unscaled 推进与普通 Tween 同级，可忽略；time_scale 写入为单次属性赋值
- **Memory**: 单条阶段 Tween + CanvasLayer 子节点；无额外驻留开销
- **Load Time**: 无影响（运行期机制）
- **Frame**: FREEZE 期世界处理量随 time_scale 下降而下降；演出 unscaled Tween 维持 60fps 演出帧

## Migration Plan

首次实现，无现有演出计时需迁移。

1. BurstPresentation（CanvasLayer layer=10）订阅 `EventBus.burst_presentation_requested`
2. `_freeze_scale()` 加载期钳制 `BURST_TIME_SCALE_FREEZE` 至 ≥0.01
3. 阶段链 `create_tween().set_ignore_time_scale(true).set_process_mode(TWEEN_PROCESS_IDLE)`，按 GDD 五阶段串接
4. P1 进入设 `Engine.time_scale=_freeze_scale()`；FREEZE 退出回调恢复 1.0（满足 AC-4：P4 末==1.0）
5. `skip_or_restart()`：`kill()` → `Engine.time_scale=1.0` → EC-2 残留隐藏；旧演出不 emit ended
6. **编码前执行 Verification Required ①–③ 实测**；若 ① 不符，切换 Alternative 2
7. 登记禁止模式：`Engine.time_scale` 仅 BurstPresentation 写

## Validation Criteria

1. **P1 unscaled 计时**（实测/集成）：`Engine.time_scale=0.05` 下，从进入 P1 到退出 FREEZE 的墙钟耗时 ≈ `BURST_FREEZE_DURATION`（60ms ±一帧），不被放大 20×
2. **AC-4 time_scale 时序**（单测/集成）：P1 期间查询 `Engine.time_scale==_freeze_scale()`；P4 末查询 `==1.0`
3. **AC-13 钳制**（单测）：`BURST_TIME_SCALE_FREEZE=0` → `_freeze_scale()==0.01` 且 `push_warning` 触发
4. **AC-11 skip 恢复**（集成）：演出中触发 skip/二次请求 → `Engine.time_scale==1.0`，旧演出不 emit `burst_presentation_ended`
5. **单点 time_scale 写**（代码审查）：`grep -rn "Engine.time_scale" src/` 仅 BurstPresentation 命中
6. **回退就绪**（文档/代码审查）：Alternative 2 的自管控制器接口已在注释中预留，若验证失败可切换

## Related Decisions

- ADR-0001 — EventBus（`burst_presentation_requested/started/ended` 信号权威定义）
- ADR-0007 — Unit Rendering（单位移动 Tween 走 scaled，FREEZE 期减速即定格，与本 ADR 相容）
- ADR-0009 — Camera Shake（P4 IMPACT 相机震动；pixel→3D 单位换算；复用本 ADR 的 unscaled 计时基线）
- `design/gdd/burst-presentation-system.md` — 五阶段演出权威来源，OQ-2 / ADR-BURST-TWEEN-MODE 已关闭

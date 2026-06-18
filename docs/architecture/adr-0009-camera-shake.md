# ADR-0009: Camera Shake — P4 IMPACT 相机震动与 pixel→世界单位换算

## Status
Accepted

## Date
2026-06-18（Accepted 2026-06-18 — /architecture-review rerun CONCERNS，无阻断，F-1 引用已修；viewport 高度待工程建立后重算）

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6.3 |
| **Domain** | Rendering / Animation（Camera3D + Tween） |
| **Knowledge Risk** | MEDIUM — `Camera3D.position` + `Tween` 均 stable since 4.0；主要风险继承自 ADR-0008（unscaled Tween 计时）。pixel→世界换算为数学，非引擎 API |
| **References Consulted** | `docs/engine-reference/godot/modules/rendering.md`, `docs/engine-reference/godot/modules/animation.md`, `docs/architecture/adr-0006-3d-board-rendering.md`, `docs/architecture/adr-0008-burst-presentation-timing.md`, `design/gdd/burst-presentation-system.md`（OQ-1） |
| **Post-Cutoff APIs Used** | None — `Tween.tween_property`/`set_ignore_time_scale`（验证项继承 ADR-0008）、`Camera3D.position`、`Node3D.transform.basis` 均 stable since 4.0 |
| **Verification Required** | ① 确认工程 `project.godot` 的 viewport 高度（换算公式分母），按实际值重算 `world_per_pixel`；② 目视确认 8px 强度在 fov=60/distance≈21.9 下震动幅度合适（不过猛/不过弱）；③ 确认震动结束相机精确回弹至 rest position（无累积漂移）；④ unscaled 计时行为继承 ADR-0008 验证项 |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0006（Camera3D 配置：fov、position、look_at；换算依赖相机到棋盘深度），ADR-0008（unscaled Tween 计时基线；P4 时 `Engine.time_scale` 已恢复 1.0） |
| **Enables** | None（爆发演出视觉的末端效果） |
| **Blocks** | burst-presentation-system P4 IMPACT 阶段实现故事 |
| **Ordering Note** | 须在 ADR-0006、ADR-0008 Accepted 之后；与 ADR-0008 同属爆发演出，建议同批 Accept |

## Context

### Problem Statement

爆发演出 P4 IMPACT 阶段（`BURST_IMPACT_DURATION≈200ms`）触发相机震动制造冲击感。GDD 指定
机制为「对 Camera3D 施加往复 local position 偏移」，但留下未决换算（OQ-1）：强度常量
`BURST_CAMERA_SHAKE_INTENSITY=8.0` 以 **pixels** 表达，而 Camera3D.position 偏移以**世界单位**
计量。没有确定的 pixel→世界单位换算，震动幅度无法落地，且会因视口分辨率不同而漂移。

本 ADR 决定：**（1）震动机制（Tween 往复 local 偏移）；（2）pixel→世界单位换算公式（FOV+深度推导）。**
关闭 `burst-presentation-system.md` OQ-1 / ADR-BURST-CAMERA-SHAKE。

### Constraints

- 仅修改 Camera3D 的 **local position offset**，不动 `global_transform`，不改变 look_at 朝向（GDD 硬约束）
- 震动期间 `Engine.time_scale==1.0`（P4 已恢复，ADR-0008）
- `BURST_CAMERA_SHAKE_DURATION ≤ BURST_IMPACT_DURATION + BURST_PRESENTATION_DURATION_BASE × 0.3`（GDD 旋钮约束，防止震动延续到 P5 面板出场）
- 场景卸载致 Camera3D 失效时须 `is_instance_valid()` 守卫，跳过震动但继续后续演出（GDD EC）
- 强度以 pixel 表达，须与视口分辨率解耦（换算时按 viewport 高度归一）
- 确定性：无随机偏移（项目「无随机」偏好；Tween 往复为确定波形）

### Requirements

- 8px 强度在 ADR-0006 相机配置下产生视觉合适、可感知但不晕眩的震动
- 震动结束相机精确回到 rest position，无累积漂移
- 换算公式以单一函数封装，viewport 高度变化时只需重算一处
- look_at 目标朝向不受震动影响（偏移在视图局部空间施加）

## Decision

**震动 = Tween 对 Camera3D 在其局部空间施加衰减往复偏移；强度 pixel 经
`world_per_pixel`（由相机 FOV + 到棋盘深度推导）换算为世界单位偏移；结束精确回弹至 rest。**

### pixel → 世界单位换算（关闭 OQ-1）

```gdscript
# 在棋盘平面深度处，1 像素对应的世界单位长度
# world_per_pixel = (2 · distance · tan(fov_vertical / 2)) / viewport_height
#   distance        = 相机到 look_at 目标(棋盘中心)的距离
#   fov_vertical    = Camera3D.fov（Godot 默认 KEEP_HEIGHT，fov 为垂直视角）
#   viewport_height = 视口像素高度（project.godot 设定；换算分母）

static func world_per_pixel(camera: Camera3D, target: Vector3, viewport_height: float) -> float:
    var distance := camera.global_position.distance_to(target)
    var half_fov := deg_to_rad(camera.fov) * 0.5
    return (2.0 * distance * tan(half_fov)) / viewport_height

# 算例（ADR-0006 相机 + 1080p）：
#   distance = |(7,16,22) - (7,0,7)| = sqrt(0 + 16² + 15²) = sqrt(481) ≈ 21.93
#   half_fov = 30° → tan = 0.5774
#   world_per_pixel ≈ (2 · 21.93 · 0.5774) / 1080 ≈ 0.02344 世界单位/像素
#   BURST_CAMERA_SHAKE_INTENSITY 8px → 偏移幅度 ≈ 0.1875 世界单位
```

> `viewport_height` 默认按 1080 给算例；工程 `project.godot` 建立后须用实际值重算（Verification Required ①）。

### 震动机制（Tween 往复 local 偏移）

```gdscript
const SHAKE_OSCILLATIONS: int = 6   # 往复次数（衰减包络分段数，旋钮）

func _shake_camera(camera: Camera3D, target: Vector3) -> void:
    if not is_instance_valid(camera):
        return  # 场景卸载守卫（GDD EC）：跳过震动，演出继续
    var rest := camera.position                      # 记录 rest local position
    var amp := BURST_CAMERA_SHAKE_INTENSITY * world_per_pixel(
        camera, target, get_viewport().size.y)       # px → 世界单位

    var t := create_tween()
    t.set_ignore_time_scale(true)                    # 计时基线继承 ADR-0008（P4 时 ts=1.0，等价）
    var step := (BURST_CAMERA_SHAKE_DURATION / 1000.0) / float(SHAKE_OSCILLATIONS)
    for i in SHAKE_OSCILLATIONS:
        var decay := 1.0 - float(i) / float(SHAKE_OSCILLATIONS)   # 线性衰减包络
        # 在相机局部空间施加偏移（basis 变换 → 不改变 look_at 朝向）
        var local_off := camera.transform.basis * Vector3(amp * decay, amp * decay, 0.0)
        var sign := 1.0 if i % 2 == 0 else -1.0
        t.tween_property(camera, "position", rest + local_off * sign, step)
    t.tween_property(camera, "position", rest, step) # ★ 精确回弹归位，无累积漂移
```

### Architecture Diagram

```
P4 IMPACT（ADR-0008 阶段链触发）
  └── BurstPresentation._shake_camera(camera, BOARD_CENTER)
        ├── is_instance_valid(camera) ? 否 → return（跳过，演出继续）
        ├── world_per_pixel(camera, target, viewport.size.y)   ← FOV+深度换算
        └── Tween(set_ignore_time_scale) 往复 camera.position（局部空间偏移）
              → 末段 tween 回 rest position（精确归位）

约束：
  ✗ 修改 Camera3D.global_transform（须仅改 local position offset）
  ✗ 震动改变 look_at 朝向（偏移经 transform.basis 在视图空间施加）
  ✗ 随机偏移（确定性往复波形）
```

## Alternatives Considered

### Alternative 1: FastNoiseLite 噪声驱动偏移

- **Description**: 每帧用 `FastNoiseLite` 采样生成连续偏移，trauma 值随时间衰减
- **Pros**: 手感柔和自然，无机械往复感
- **Cons**: 偏离 GDD 明文（Tween 往复）；需噪声资源 + 种子管理；非确定性（与项目「无随机」偏好冲突），单测难写
- **Rejection Reason**: GDD 已指定 Tween 往复；确定性波形可测试，符合项目偏好

### Alternative 2: 每帧随机 trauma 偏移（Nystrom 式）

- **Description**: `_process` 中按 `trauma²` 每帧施加随机方向偏移，trauma 逐帧衰减
- **Pros**: 业界常见，冲击手感好
- **Cons**: 随机性破坏确定性单测；需 `_process` 循环（而非 Tween 链）；与 ADR-0008 的 Tween 链架构不一致
- **Rejection Reason**: 随机 + 独立 process 循环与项目确定性偏好和演出 Tween 架构均不契合

### Alternative 3: 强度直接以世界单位定义（弃 pixel 语义）

- **Description**: 把 `BURST_CAMERA_SHAKE_INTENSITY` 重定义为世界单位，跳过换算
- **Pros**: 无需换算公式
- **Cons**: 改变 GDD 常量含义（pixel→world，须改 GDD + entities.yaml）；失去与分辨率无关的直观语义（美术按屏幕像素思考震动幅度）
- **Rejection Reason**: 保留 pixel 语义对美术更直观，换算公式单点封装成本低

## Consequences

### Positive

- 震动幅度与视口分辨率解耦（pixel 语义经 viewport 高度归一）
- 确定性往复波形可单元测试（给定相机+viewport，偏移序列可预测）
- 偏移在视图局部空间施加，look_at 朝向不受影响，无需额外 pivot 节点
- 末段精确回弹，杜绝累积漂移；`is_instance_valid` 守卫场景卸载边界

### Negative

- 换算依赖 viewport 高度，工程建立后须以实际值校准（一处常量重算）
- 往复波形手感不如噪声柔和——若垂直切片试玩觉得机械，可在 Alternative 1/2 间再权衡（旋钮 `SHAKE_OSCILLATIONS` 可调缓解）

### Risks

- **viewport 高度未定**（project.godot 未脚手架）：换算分母暂以 1080 估算。
  缓解：列 Verification Required ①；公式参数化，建立工程后重算一处。
- **相机 distance 假设**：换算用 ADR-0006 固定相机位。若爆发演出期相机被 Tween 缩放（ADR-0006 允许），distance 变化致换算偏差。
  缓解：震动在 P4 IMPACT，相机已回到 rest 位（演出后段）；换算用实时 `global_position.distance_to(target)`，非硬编码 distance。
- **累积漂移**：往复未精确归位致相机偏移残留。
  缓解：末段 tween 强制回 rest position；Verification ③ 目视确认。
- **unscaled 计时**：继承 ADR-0008；P4 时 `time_scale==1.0`，scaled/unscaled 等价，风险极低。

## GDD Requirements Addressed

| GDD 系统 | TR ID | 需求摘要 | 此 ADR 如何满足 |
|---------|-------|---------|--------------|
| burst-presentation-system.md | TR-BPS-005 | P4 IMPACT 相机震动（Camera3D local offset，pixel→3D 换算待 ADR） | Tween 往复局部偏移 + `world_per_pixel` FOV/深度换算，**关闭 OQ-1** |
| burst-presentation-system.md | （EC：相机失效） | 场景卸载时 `is_instance_valid` 守卫，跳过震动续演出 | `_shake_camera` 入口 guard |
| burst-presentation-system.md | （旋钮约束） | 震动时长 ≤ IMPACT + BASE×0.3 | `BURST_CAMERA_SHAKE_DURATION` 钳制由 GDD 旋钮约束承载 |

## Performance Implications

- **CPU**: 单条 Tween，6–7 段属性插值，开销可忽略
- **Memory**: 无额外驻留；rest position 为局部变量
- **Frame**: 震动期相机 position 每帧更新，单节点变换，无可测帧影响
- **Load Time**: 无影响（运行期效果）

## Migration Plan

首次实现，无现有震动逻辑需迁移。

1. `world_per_pixel(camera, target, viewport_height)` 静态工具函数（封装换算）
2. `_shake_camera()` 在 ADR-0008 阶段链 P4 IMPACT 回调中调用
3. 入口 `is_instance_valid(camera)` 守卫；记录 rest local position
4. Tween `set_ignore_time_scale(true)`，往复偏移经 `transform.basis` 施加，末段回 rest
5. 工程建立后用实际 viewport 高度重算并目视校准 8px 幅度（Verification ①②③）
6. 旋钮 `SHAKE_OSCILLATIONS` 暴露供试玩调手感

## Validation Criteria

1. **换算正确性**（单测）：`world_per_pixel(cam, center, 1080)` 在 distance≈21.93/fov=60 下 ≈ 0.02344；8px → ≈0.1875 世界单位
2. **精确回弹**（单测/目视）：震动 Tween 完成后 `camera.position == rest`（容差 < 1e-4），无累积漂移
3. **朝向不变**（单测）：震动期任意帧 `camera` 的 look 方向（-Z basis）与 rest 一致（偏移仅平移，不旋转）
4. **失效守卫**（集成）：传入已 `queue_free` 的 camera → `_shake_camera` 直接返回，不报错，演出继续
5. **分辨率解耦**（单测）：viewport 高度 720 vs 1080 时，同 8px 强度产生不同世界偏移但屏幕视觉幅度一致
6. **无随机**（代码审查）：`grep -n "randf\|randi\|FastNoiseLite" ` 在震动实现中无结果

## Related Decisions

- ADR-0006 — 3D Board Rendering（相机 fov/position/look_at；换算依赖到棋盘深度）
- ADR-0008 — Burst Presentation Timing（P4 IMPACT 阶段链触发震动；unscaled 计时基线）
- ADR-0001 — EventBus（爆发演出信号链上游）
- `design/gdd/burst-presentation-system.md` — 爆发演出权威来源，OQ-1 / ADR-BURST-CAMERA-SHAKE 已关闭

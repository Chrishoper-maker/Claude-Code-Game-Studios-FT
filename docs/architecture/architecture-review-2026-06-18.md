# Architecture Review Report — 孤帆棋海 (Grand Line Gambit)

> **Date**: 2026-06-18（rerun，覆盖同日早先报告）
> **Mode**: Lean
> **Engine**: Godot 4.6.3
> **Skill**: `/architecture-review` (full)
> **Focus**: 验证 ADR-0006~0009 对 GDD 需求覆盖 + ADR-0001 retrofit 信号一致性
> **独立性**: ✓ 本报告在全新 session 完成，独立于 ADR-0006~0009 撰写上下文

---

## Scope

| Field | Value |
|-------|-------|
| GDDs Reviewed | 12 |
| ADRs Reviewed | 8（ADR-0001~0004 Accepted；ADR-0006~0009 Proposed；无 ADR-0005） |
| TR Registry | v2 — 68 条（本轮 +3：TR-BPS-005 / TR-BHS-008 / TR-BMS-007） |
| Reference | `engine-reference/godot/VERSION.md` + `modules/{rendering,animation}.md` + `breaking-changes.md` + `deprecated-apis.md` |

---

## 1. 核心结论：4 个 HIGH RISK ADR 已成稿且技术健全

上轮 gate FAIL 的实质技术阻断（TD/PR 口径："4 个 HIGH RISK 引擎域各需 Accepted ADR"）现已全部成稿：

| HIGH RISK 域 | ADR | 状态 | 关键裁决 |
|---|---|---|---|
| 3D 渲染管线 / 坐标映射 | ADR-0006 | Proposed | `GridCoordMapper` 唯一坐标源；透视相机；CELL_SIZE=2.0；forward_plus+D3D12 |
| 单位渲染 | ADR-0007 | Proposed | 纯 `UnitView` Node3D 零物理体；白盒图元 + art-bible 配色；离散 Tween |
| Tween + Engine.time_scale | ADR-0008 | Proposed | 演出 Tween unscaled / 世界 scaled 解耦；钳制+skip 清理；回退方案已备 |
| Camera Shake | ADR-0009 | Proposed | Tween 往复局部偏移；pixel→世界换算公式；精确回弹 |

**ADR-0001 retrofit 验证通过**：ADR-0006~0009 引用的全部信号（`unit_downed` / `unit_moved` / `terrain_changed` / `burst_presentation_requested(…effect_id)` / `burst_presentation_started`·`ended` 无参）在 retrofit 后的 ADR-0001 中**均存在且签名一致** → 上轮 BLOCKER-1（8 处签名冲突）与 BLOCKER-2（4 个缺失信号）确认 **RESOLVED**。

---

## 2. Traceability Summary

可追溯索引（同日早先版本）已陈旧——它早于 ADR-0001 retrofit 与 4 个新 ADR。重算后：

| 状态 | 上轮 | 本轮 | 比例 |
|------|------|------|------|
| ✅ 完全覆盖 | 18 | **~31** | ~46% |
| ⚠️ 部分覆盖 | 9 | ~3 | ~4% |
| ❌ 无覆盖 | 40 | ~34 | ~50% |
| **总计** | 67 | **68** | 100% |

**本轮新增覆盖**：
- retrofit 关闭 6 处签名冲突 partial → ✅：TR-TMS-006 / TR-BRS-006 / TR-ABS-003 / TR-BGBS-007 / TR-EAIS-005 / TR-RRS-004
- ADR-0006：TR-GBS-006（❌→✅，关闭 OQ-1）、TR-GBS-001（⚠️→✅）、TR-BHS-008（新，格子高亮对齐）、TR-BMS-007（新，地形视觉对齐）
- ADR-0007：TR-UDS-001/003 视觉实现层、TR-BHS-008
- ADR-0008：TR-BPS-003（❌→✅，关闭 OQ-2）
- ADR-0009：TR-BPS-005（新，相机震动，关闭 OQ-1 / ADR-BURST-CAMERA-SHAKE）

剩余 ❌ 均为 Pre-Production / Production 立项范围（ADR-0005 战斗解算 TR-BRS-001~008、Dual-focus UI、AI 行为原型、招募规则等），**非阶段入口阻断**。

---

## 3. Cross-ADR Conflicts — 无阻断性冲突

- **ADR-0007 ↔ ADR-0008**（Tween/time_scale 交互）：单位移动 Tween 走 scaled、演出 Tween 走 unscaled，两侧均显式互证 → 互补，无冲突。
- **ADR-0008 ↔ ADR-0009**：0009 继承 0008 unscaled 计时基线（P4 时 `time_scale==1.0`，scaled/unscaled 等价）。
- **ADR-0006 ↔ ADR-0007**：坐标映射所有权清晰（0006 拥有 `GridCoordMapper`，0007 消费）；命名 F-4 已修正。
- **time_scale 单写者约定**：ADR-0008 声明 `Engine.time_scale` 仅 BurstPresentation 写入；无其他 ADR 写入 → 应登记为 forbidden_pattern（实现期落地）。

---

## 4. ADR Dependency Order（拓扑排序）

```
Foundation（已 Accepted）:
  ADR-0001 EventBus（含 retrofit 信号）/ ADR-0002 Scene / ADR-0003 Data / ADR-0004 State Machine

可立即 Accept（依赖均 Accepted）:
  ADR-0006 3D Board Rendering        (requires ADR-0002 ✅)
  ADR-0008 Burst Presentation Timing (requires ADR-0001 ✅)

需上层先 Accept:
  ADR-0007 Unit Rendering            (requires ADR-0006, 0002, 0003)
  ADR-0009 Camera Shake              (requires ADR-0006, 0008)

推荐 Accept 顺序: 0006 → {0007, 0008} → 0009    无依赖环
```

---

## 5. 需修订项（CONCERNS — 不阻断 Accept）

| # | 问题 | 处置 |
|---|---|---|
| **F-1** | ADR-0009 引用 TR-BPS-006（注册表只到 004） | ✅ 已修：注册 TR-BPS-005；ADR-0009 引用校正为 TR-BPS-005 |
| **F-2** | ADR-0006/0007 引用 TR-BHS-002（实为羁绊槽显示）描述"格子高亮/站位可读" | ✅ 已修：注册 TR-BHS-008（格子高亮对齐）；两 ADR 引用校正 |
| **F-3** | ADR-0006 引用 TR-BMS-004（实为远程走廊检测）描述"地形视觉对齐" | ✅ 已修：注册 TR-BMS-007（地形视觉对齐）；ADR-0006 引用校正 |
| **F-4** | ADR-0006 Migration 步骤 5 仍写 `UnitInstance3D` | ✅ 已修：改为 `UnitView`（ADR-0007 权威命名） |
| **F-5** | ADR-0007 自荐登记 unit-rendering 视觉契约 TR | 记录建议（ADR-0007 已映射既有 TR，TR-REN-001 非必需，留待需要时登记） |
| **F-6** | ADR-0008 列 `set_ignore_time_scale` 为 HIGH RISK，依据"4.5 改 Tween PROCESS_IDLE"未被引擎参考佐证 | 见 §6 引擎审计；ADR 处置正确，不阻断 |

---

## 6. Engine Compatibility Audit

### 版本与废弃 API
- 全部 4 ADR 标注 Godot 4.6.3 ✅
- 无废弃 API 引用（核对 deprecated-apis.md）✅
- 坐标/相机/材质/Tween API（`PROJECTION_PERSPECTIVE`、`look_at`、`roundi`、`MeshInstance3D`、图元、`StandardMaterial3D`、`transform.basis`、`tween_property`）均 stable since 4.0 ✅

### Post-Cutoff API 风险

| ADR | Risk | 关键 API | 状态 |
|-----|------|---------|------|
| ADR-0006 | LOW | PROJECTION_PERSPECTIVE / look_at | ✅ stable；forward_plus 显式声明，D3D12 驱动要求已标注 |
| ADR-0007 | LOW | MeshInstance3D / 图元 / StandardMaterial3D | ✅ 不写自定义 shader，规避 4.4 纹理类型变更 |
| ADR-0008 | **HIGH** | `set_ignore_time_scale(true)` | ⚠️ 见下；处置正确（Verification Required + 回退 Alternative 2） |
| ADR-0009 | MEDIUM | Camera3D.position / Tween | ✅ 计时风险继承 0008，P4 时 ts=1.0 风险极低 |

### F-6 引擎参考校正（注意项，不阻断）

ADR-0008 把 `set_ignore_time_scale` 列为 HIGH RISK 的依据是「4.5 改动 Tween PROCESS_IDLE 行为」，但项目自有 `engine-reference/animation.md`（2026-02-12 核实）**未记录任何此类 Tween 变化**（仅记录 IK/BoneConstraint3D 等骨骼动画变化）。该 API 实为 4.0+ stable，语义即"使 Tween 忽略 Engine.time_scale"。

- ADR 的「编码前实测 + 回退方案」处置**仍正确且稳妥**（保守对待后截止版本）。
- 建议：核对 4.5 是否确有 Tween 计时变化 —— 属实则补录 `animation.md`；不属实则可将 ADR-0008 风险从 HIGH 下调。
- **不阻断 ADR-0008 Accept**：HIGH RISK 验证项的语义是"编码前实测"，而非"立项前阻断"。

### Engine Specialist Consultation
godot-specialist 专精子代理本会话不在 harness 代理名册中，无法 spawn。引擎核验在主会话内完成（与 ADR-0007/0008/0009 撰写 session 处理方式一致）。无新增专精发现。

---

## 7. GDD Revision Flags

**无 GDD 修订旗标** — 所有 GDD 假设与已验证的引擎行为一致。两处 GDD↔ADR 信号差异已由 ADR 自行标注对齐（不需改 GDD）：
- `burst_presentation_started(burst_type_id)`（GDD）→ ADR-0001 无参版为权威（effect_id 经 requested 信号携带）
- 相机震动 pixel 语义保留，换算由 ADR-0009 封装

---

## 8. Architecture Document Coverage

- ✅ 全部 12 系统出现在 architecture.md 层级图
- ✅ Foundation ADR 0001~0004 全部 Accepted
- ✅ 无孤立架构 / 无孤立 GDD
- ✅ ADR-0006~0009 现已成稿（架构文档原标注 Required，符合推进预期）

---

## Verdict

```
┌──────────────────────────────────────────────────────────┐
│  VERDICT: CONCERNS（较上轮显著改善）                       │
│                                                            │
│  • 4 个 HIGH RISK 域 ADR 全部成稿、技术健全、无阻断冲突     │
│  • ADR-0001 retrofit 信号一致性确认 → BLOCKER-1/2 RESOLVED  │
│  • 依赖可拓扑排序、无环 → 0006~0009 可推进 Accept           │
│  • F-1~F-4 已于本轮写回修复；F-5/F-6 为非阻断记录           │
│  • 剩余 ❌ gap 全属 Pre-Production/Production 立项范围       │
│                                                            │
│  → 关闭 gate 阻断项 B2 的条件已满足                         │
└──────────────────────────────────────────────────────────┘
```

---

## Next Steps

1. 按依赖序将 ADR-0006 → {0007, 0008} → 0009 的 Status 推进至 Accepted
2. 重跑 `/gate-check vertical-slice`（预期 READY；B4 测试框架/CI 为已知 deferred，留待 Pre-Production sprint 1）
3. Pre-Production：立项 ADR-0005（战斗解算）+ Dual-focus UI ADR；编码前执行 ADR-0008 Verification Required ①–④ 实测

> ⚠️ 永远不要在同一 session 内运行 `/architecture-review` 与 `/architecture-decision`。

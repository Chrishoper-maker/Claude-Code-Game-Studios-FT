# Cross-GDD Review Report

**Date**: 2026-06-17  
**Skill**: /review-all-gdds (consistency + design-theory)  
**Registry pre-loaded**: design/registry/entities.yaml (17 entries — 1 entity, 5 formulas, 16 constants; just updated by /consistency-check)  
**GDDs Reviewed**: 12  
**Systems Covered**: unit-data, grid-board, turn-management, battle-resolution, adjacency-bond, bond-gauge-burst, enemy-ai-intent, burst-presentation, battle-hud, battle-map, route-recruitment-system, route-recruitment-ui

**Four Pillars**: 羁绊即战术 / 关键回合的爆发 / 小棋盘大组合 / 十分钟一场爽局  
**Anti-Pillars**: NOT 剧情 JRPG / NOT 收集图鉴 / NOT 完全信息象棋谜题 / NOT 多人对战

---

## Consistency Issues

### Blocking (must resolve before architecture begins)

*None.*

### Warnings (should resolve, but won't block)

---

#### ⚠️ W-01: 上游依赖表中的 GDD 状态标签过期

**涉及 GDD**: battle-hud-system.md, battle-map-system.md  
**现象**:
- `battle-hud-system.md` Dependencies 表中将 `battle-resolution-system.md` 状态标为 "In Review"（实为 Approved）；`burst-presentation-system.md` 标为 "Not Started"（实为 Approved）
- `battle-map-system.md` 的下游表中将 `route-recruitment-system.md` 标为 "Not Started"（实为 Approved）

**影响**: 状态标签仅为追踪信息，不影响接口契约；但会误导后续阅读者判断依赖的稳定性。  
**建议**: 架构阶段编写 ADR 前，将上述状态标签更新为 "Approved"。

---

#### ⚠️ W-02: Foundation 层 GDD 的下游依赖表不完整

**涉及 GDD**: turn-management-system.md, unit-data-system.md, grid-board-system.md  
**现象**:
- `turn-management-system.md` 下游表仅列出 battle-resolution (#4) 和 enemy-ai (#7)，但实际还被 bond-gauge-burst (#6)、battle-hud (#9)、route-recruitment-system (#11)、route-recruitment-ui (#12) 依赖（订阅其信号或调用其接口）
- `grid-board-system.md` 下游表仅列出 adjacency-bond (#5) 和 battle-resolution (#4)，但 turn-management (#3)、enemy-ai (#7)、battle-map (#10)、bond-gauge-burst (#6) 均调用其接口
- `unit-data-system.md` 下游表同样不完整（只显示 battle-resolution 一行）

**影响**: 不影响功能设计；但架构阶段需要完整的消费者列表来选择初始化顺序和信号路由策略。  
**建议**: 在 /create-architecture 阶段更新三个 GDD 的下游表，或在 Master Architecture Document 中维护完整消费者图。

---

#### ⚠️ W-03: 战斗中同时主动注意力需求在边界

**涉及系统**: turn-management (#3), adjacency-bond (#5), bond-gauge-burst (#6), enemy-ai-intent (#7), battle-resolution (#4)  
**分析**:
玩家在一个行动回合内的并发主动认知负荷：
1. 先攻队列与行动顺序（读队列，低负荷）
2. 移动位置决策（去哪能凑相邻羁绊？）← **主动**
3. 动词选择（普通攻击 vs 职业动词）← **主动**
4. 相邻羁绊效果判断（谁在我旁边？加什么？）← **主动**
5. 羁绊槽状态判断（要不要现在引爆爆发？）← **主动**
6. 敌人意图阅读（下回合敌人怎么走？）← **主动（但全明示，转为确定性规划）**

并发主动系统 ≈ 5，处于研究建议的 3-4 边界上方。

**缓解因素**（已在设计中）:
- 棋盘 8×8 小，视野扫描快
- 敌人意图全明示（不是"猜测"，而是"规划"）
- 羁绊槽是可见进度条（不需要心算）
- 相邻矩阵确定性（6 职业固定组合，可记忆）

**建议**: 垂直切片阶段用真实试玩数据验证认知负荷；若发现新玩家在第 1-3 场战斗中经常看不清相邻羁绊效果，考虑在 UI 层添加"悬停预览当前单位的相邻加成"快捷提示。这是 Pillar 4（十分钟爽局）的潜在张力点——不建议修改系统，建议优先靠 UI 缓解。

---

#### ⚠️ W-04: 第 5 岛（头目战）机制未定义

**涉及 GDD**: route-recruitment-system.md, battle-map-system.md, enemy-ai-intent-system.md  
**现象**:
- route-recruitment-system.md 定义了 ISLAND_N（末岛）战后直接进入 RUN_END（无招募）
- battle-map-system.md 的 MapDefinition 结构支持 `island_tier` 分级，但没有"头目战地图"的特化规则
- enemy-ai-intent-system.md 定义了 tier 1-3 行为原型，但未设计头目敌人

**影响**: 垂直切片需要一场真实的头目战才能验证完整 run。当前 GDD 集下，第 5 岛将是一场"普通 tier-2/3 战斗"而非设计中的"高悬赏头目战"——差异是功能性的，不仅仅是美术。  
**建议**: 在 Alpha 阶段（#13–#18 系统）添加头目战 GDD 或将头目规则纳入 route-recruitment-system 扩展节。**VS 阶段可先用 tier-3 敌人组合模拟头目，不阻断架构开始。**

---

### Info

#### ℹ️ I-01: 满编/无候选的 RECRUITING 信号触发时序隐式

**涉及 GDD**: route-recruitment-system.md, route-recruitment-ui.md  
**现象**: route-recruitment-ui.md 的 UI_SKIPPED 状态设计前提是"先收到 run_phase_changed('RECRUITING') 再判断跳过"。但 route-recruitment-system.md 对"满编时跳过"的处理方式未明确说明是否仍然进入 RUN_RECRUITING 状态（从而触发信号）。  
**影响**: 若系统直接从 RUN_ISLAND_BATTLE → RUN_DEPLOYING 跳过 RUN_RECRUITING，UI 将永远不进入 UI_SKIPPED 而是从 UI_HIDDEN 收到 DEPLOYING 信号——行为正确，路径不同。  
**推荐处理**: 架构阶段实现时，明确 RUN_RECRUITING 的进入条件：始终进入状态并在状态内判断 skip，而非在进入前判断。这与 UI GDD 的设计假设一致。此信息级别，不阻断任何工作。

---

## Game Design Theory Issues

### Blocking

*None.*

### Warnings

已列于上方：W-03（认知负荷边界）、W-04（头目战设计缺口）。

---

## Cross-System Scenario Walkthrough

**Scenarios walked**: 5

1. ISLAND_0 首战 → 招募 → 部署
2. 战斗胜利时羁绊槽恰好充满
3. battle_lost + 阵亡通知（两路径）
4. 无候选招募跳过
5. 第 5 岛头目战完整 run

---

### Info

#### ℹ️ Scenario 1 — ISLAND_0 首战 → 招募 → 部署（正常路径）

Systems: route-recruitment-system (#11), route-recruitment-ui (#12), turn-management (#3), battle-resolution (#4)

```
run_started → RUN_DEPLOYING
  roster.size()=2 ≤ DEPLOY_LIMIT=4 → 系统 auto confirm_deploy
  → RUN_ISLAND_BATTLE → run_phase_changed("BATTLE")
  → 战斗过程（#3 + #4 + #5 + #6）
  → battle_won (非末岛) → RUN_RECRUITING → run_phase_changed("RECRUITING")
  → UI: UI_HIDDEN → UI_RECRUITING (offers=3)
  → 玩家选择 → confirm_recruit(id) → UI_HIDDEN
  → RUN_DEPLOYING → run_phase_changed("DEPLOYING")
  → UI: UI_HIDDEN → roster.size()=3 ≤ DEPLOY_LIMIT → auto → UI_HIDDEN
  → battle_started (ISLAND_1)
```

**结果**: 路径无歧义，信号链完整。✓

---

#### ℹ️ Scenario 2 — 羁绊槽在 kill 瞬间充满

Systems: bond-gauge-burst (#6), battle-resolution (#4), turn-management (#3)

```
攻击者发动普通攻击 → attack_executed(attacker, target)
→ battle-resolution: target.hp=0 → unit_downed(target_id)
→ turn-management: alive_enemies=0 → battle_won()
→ bond-gauge-burst: 同时收到 attack_executed → 充能 → bond_gauge_current=10 → bond_gauge_full()

关键时序: battle_won 在 attack_executed 信号链结束后 dispatch（同帧内）
→ battle_won 到达时，bond_gauge_full 已 emit，但输入已锁定（battle 已结束）
→ 爆发按钮永远不会在战斗结束帧被激活（turn-management 在 battle_won 后停止接受输入）
→ 槽值保留至下一场战斗开始前被清零（bond-gauge-burst 在 battle_started 重置槽）
```

**结果**: 行为一致，无 undefined behavior。玩家会看到"槽满但战斗已结束"——这是合理体验（错过爆发时机的小遗憾感）。✓

---

#### ℹ️ Scenario 3 — battle_lost + 阵亡通知

Systems: route-recruitment-ui (#12), route-recruitment-system (#11), turn-management (#3)

```
battle_lost → RUN_END → run_phase_changed("RUN_END")
→ route-recruitment-ui: 若有 crew_member_downed 未确认
  → UI_DOWNED_NOTIFY → 玩家确认 → UI_HIDDEN (exit: battle_lost)
  （R1 修订已确保 UI_DOWNED_NOTIFY 在 battle_lost 路径下不进入 UI_RECRUITING）
→ route-recruitment-system: RUN_END → run_completed(won=false, ...) → RUN_IDLE
```

**结果**: 路径在 #12 R1 修订中已验证。✓

---

#### ℹ️ Scenario 4 — 无候选跳过招募

Systems: route-recruitment-system (#11), route-recruitment-ui (#12)

```
battle_won → RUN_RECRUITING → run_phase_changed("RECRUITING")
→ route-recruitment-ui: UI_HIDDEN → 收到 RECRUITING 信号 → 调用 get_recruit_offers()
  → offers=[] → 进入 UI_SKIPPED
→ route-recruitment-system: RUN_RECRUITING 内部检查 offers=0 → auto-skip → RUN_DEPLOYING
→ run_phase_changed("DEPLOYING")
→ UI_SKIPPED → 收到 DEPLOYING 信号 → roster ≤ DEPLOY_LIMIT? → 分支正常
```

**见 I-01**: 若系统跳过 RUN_RECRUITING 状态直接到 RUN_DEPLOYING，UI 收不到 RECRUITING 信号，进入 UI_HIDDEN → 收到 DEPLOYING → 正常部署。功能不破，但与 UI_SKIPPED 路径不同。实现时需明确。

---

#### ⚠️ Scenario 5 — 第 5 岛头目战完整 run

Systems: route-recruitment-system (#11), battle-map (#10), enemy-ai (#7)

```
island_index=4 (ISLAND_COUNT_MAX-1) → battle_won → RUN_END (无招募)
→ run_completed(won=true, ...)
```

**问题**: 第 5 岛当前等价于一场 tier-3 普通战斗。battle-map-system 无"头目战"地图分类；enemy-ai 无"boss"行为原型。run_completed(won=true) 信号能正确触发，但玩家体验到的是"终点站没有头目"。

**见 W-04**: 不阻断 VS 开发，但实现时须先定义 tier-3 boss 占位地图和敌人配置。

---

## GDDs Flagged for Revision

| GDD | 原因 | 类型 | 优先级 |
|-----|------|------|-------|
| battle-hud-system.md | W-01: 依赖状态标签过期（"In Review" / "Not Started"） | Consistency | 低（架构前修复） |
| battle-map-system.md | W-01: 依赖状态标签过期（route-recruitment "Not Started"） | Consistency | 低 |
| turn-management-system.md | W-02: 下游消费者表不完整 | Consistency | 中（架构阶段补完） |
| unit-data-system.md | W-02: 下游消费者表不完整 | Consistency | 中 |
| grid-board-system.md | W-02: 下游消费者表不完整 | Consistency | 中 |
| route-recruitment-system.md | I-01: 满编 skip 的状态进入时序建议明确 | Consistency | 低（实现前确认） |

---

## Verdict: CONCERNS

**PASS**: 无阻断性一致性问题；/consistency-check 已解决唯一数值冲突。  
**CONCERNS**: 6 项 Warning / Info 问题不影响架构开始，建议在以下阶段修复：
- W-01（状态标签）：架构阶段开始时顺手更新
- W-02（下游表）：Master Architecture Document 会汇总消费者图，GDD 层无需优先修复
- W-03（认知负荷）：试玩验证，VS 阶段 UI 调优
- W-04（头目战）：Alpha GDD 阶段设计，VS 阶段用 tier-3 占位
- I-01（skip 时序）：架构 / 实现决策，不阻断 GDD 阶段

**Required actions before re-running**: None（Verdict 已为 CONCERNS，不需要 re-run 后重过）

---

## Session Note

本报告由 /consistency-check（当日早些时候运行）+ 本次 /review-all-gdds inline 综合产出。
/consistency-check 已解决：ISLAND_COUNT_MAX 安全范围修正、BOND_GAUGE_MAX 注册。
本报告不再重复列出已解决的数值冲突。

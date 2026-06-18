# Systems Index: 孤帆棋海 (Grand Line Gambit)

> **Status**: Approved
> **Created**: 2026-06-13
> **Last Updated**: 2026-06-17
> **Source Concept**: design/gdd/game-concept.md

---

## Overview

战棋肉鸽：核心循环是"站位充能 → 相邻爆发"（原型已验证 PROCEED）。机械范围围绕四根支柱展开——羁绊即战术（相邻系统是一切的中心）、关键回合的爆发（槽与演出）、小棋盘大组合（数据驱动的组合矩阵 + 敌人行为多样性）、十分钟一场爽局（回合/地图/航线的节奏约束）。战斗侧 7 个系统构成 MVP 主体，run 结构（航线/招募/meta）在垂直切片与 Alpha 阶段接入；爆发演出属 MVP——juice 是核心假设的一部分，不是抛光项。

---

## Systems Enumeration

| # | System Name | Category | Priority | Status | Design Doc | Depends On |
|---|-------------|----------|----------|--------|------------|------------|
| 1 | 单位数据系统 (inferred) | Core | MVP | Approved | [unit-data-system.md](unit-data-system.md) | — |
| 2 | 网格棋盘系统 | Core | MVP | Approved | [grid-board-system.md](grid-board-system.md) | 单位数据 |
| 3 | 回合管理系统 (inferred) | Core | MVP | Approved | [turn-management-system.md](turn-management-system.md) | 单位数据, 网格棋盘 |
| 4 | 战斗解算系统 (inferred) | Gameplay | MVP | Approved | [battle-resolution-system.md](battle-resolution-system.md) | 单位数据, 网格棋盘, 回合管理, 相邻羁绊（修正器注入） |
| 5 | 相邻羁绊系统 | Gameplay | MVP | Approved | [adjacency-bond-system.md](adjacency-bond-system.md) | 单位数据, 网格棋盘 |
| 6 | 羁绊槽与爆发技系统 | Gameplay | MVP | Approved | [bond-gauge-burst-system.md](bond-gauge-burst-system.md) | 战斗解算, 相邻羁绊 |
| 7 | 敌人 AI 与意图系统 | Gameplay | MVP | Approved | [enemy-ai-intent-system.md](enemy-ai-intent-system.md) | 单位数据, 网格棋盘, 回合管理, 战斗解算 |
| 8 | 爆发演出系统 | Presentation | MVP | Approved | [burst-presentation-system.md](burst-presentation-system.md) | 羁绊槽与爆发技（事件订阅） |
| 9 | 战斗 HUD 系统 (inferred) | UI | MVP | Approved | [battle-hud-system.md](battle-hud-system.md) | 战斗解算, 羁绊槽, 敌人 AI（意图显示） |
| 10 | 战斗地图系统 (inferred) | Gameplay | Vertical Slice | Approved | [battle-map-system.md](battle-map-system.md) | 网格棋盘, 单位数据, 敌人 AI |
| 11 | 航线与招募系统 | Progression | Vertical Slice | Approved | [route-recruitment-system.md](route-recruitment-system.md) | 单位数据, 战斗地图 |
| 12 | 航线与招募 UI (inferred) | UI | Vertical Slice | Approved | [route-recruitment-ui.md](route-recruitment-ui.md) | 航线与招募 |
| 13 | 存档系统 (inferred) | Persistence | Alpha | Not Started | — | 航线与招募, 悬赏成长 |
| 14 | 悬赏成长系统 | Progression | Alpha | Not Started | — | 航线与招募 |
| 15 | 战后结算系统 (inferred) | UI | Alpha | Not Started | — | 战斗解算, 羁绊槽与爆发技 |
| 16 | 教学系统 (inferred) | Meta | Alpha | Not Started | — | 全部 MVP 战斗系统 |
| 17 | 音频系统 (inferred) | Audio | Full Vision | Not Started | — | 爆发演出（事件钩子） |
| 18 | 主菜单与设置 (inferred) | UI | Full Vision | Not Started | — | 存档系统 |

---

## Categories

| Category | Description | Systems Here |
|----------|-------------|--------------|
| **Core** | 一切依赖的基础 | 单位数据、网格棋盘、回合管理 |
| **Gameplay** | 让游戏好玩的系统 | 战斗解算、相邻羁绊、羁绊槽与爆发技、敌人 AI 与意图、战斗地图 |
| **Progression** | 玩家随时间的成长 | 航线与招募、悬赏成长 |
| **Persistence** | 存档与连续性 | 存档系统 |
| **UI** | 面向玩家的信息显示 | 战斗 HUD、航线与招募 UI、战后结算、主菜单与设置 |
| **Presentation** | 演出与 juice（本作自定义类目——MVP 级重要性） | 爆发演出 |
| **Audio** | 声音与音乐 | 音频系统 |
| **Meta** | 核心循环之外 | 教学系统 |

---

## Priority Tiers

| Tier | Definition | Target Milestone | Design Urgency |
|------|------------|------------------|----------------|
| **MVP** | 核心循环成立所必需（含爆发演出——juice 是假设本体） | 白盒首个可玩版（1–2 周） | Design FIRST |
| **Vertical Slice** | 3 岛短航线 + 招募 + 3D 管线跑通 | 垂直切片（4–6 周） | Design SECOND |
| **Alpha** | 全功能粗糙版 | Alpha（2–3 月） | Design THIRD |
| **Full Vision** | 抛光与内容完整 | 发售（3–6 月） | Design as needed |

---

## Dependency Map

### Foundation Layer (no dependencies)

1. 单位数据系统 — 船员/敌人/职业/羁绊标签的数据驱动定义；编码标准要求数值外置，21 配对矩阵必须由数据表驱动
2. 网格棋盘系统 — 8×8 棋盘、格子、地形阻挡、移动范围（BFS）；一切空间逻辑的载体
3. 回合管理系统 — 回合状态机、行动顺序、胜负判定；原型中隐藏在代码流程里，生产版必须显式化

### Core Layer (depends on foundation)

1. 战斗解算系统 — depends on: 单位数据, 网格棋盘, 回合管理；受击充能上限规则在此落地
2. 相邻羁绊系统 — depends on: 单位数据, 网格棋盘；以**单向修正器**注入战斗解算（架构约定，防循环依赖）
3. 羁绊槽与爆发技系统 — depends on: 战斗解算（充能事件）, 相邻羁绊（相邻倍率）
4. 敌人 AI 与意图系统 — depends on: 单位数据, 网格棋盘, 回合管理, 战斗解算

### Feature Layer (depends on core)

1. 战斗地图系统 — depends on: 网格棋盘, 单位数据, 敌人 AI（波次/摆放）
2. 航线与招募系统 — depends on: 单位数据（招募池）, 战斗地图（每岛战斗）
3. 悬赏成长系统 — depends on: 航线与招募（解锁注入招募池）
4. 存档系统 — depends on: 航线与招募（run 状态）, 悬赏成长（meta 进度）

### Presentation Layer (depends on features)

1. 爆发演出系统 — depends on: 羁绊槽与爆发技（事件订阅，松耦合）
2. 战斗 HUD 系统 — depends on: 战斗解算, 羁绊槽, 敌人 AI（意图显示）
3. 航线与招募 UI — depends on: 航线与招募
4. 战后结算系统 — depends on: 战斗解算, 羁绊槽与爆发技（统计数据）

### Polish Layer (depends on everything)

1. 教学系统 — depends on: 全部 MVP 战斗系统（脚本化残局）
2. 音频系统 — depends on: 爆发演出（事件钩子）
3. 主菜单与设置 — depends on: 存档系统

---

## Recommended Design Order

| Order | System | Priority | Layer | Agent(s) | Est. Effort |
|-------|--------|----------|-------|----------|-------------|
| 1 | 单位数据系统 | MVP | Foundation | systems-designer | S |
| 2 | 网格棋盘系统 | MVP | Foundation | game-designer | S |
| 3 | 回合管理系统 | MVP | Foundation | systems-designer | S |
| 4 | 战斗解算系统 | MVP | Core | systems-designer | M |
| 5 | 相邻羁绊系统 | MVP | Core | game-designer + systems-designer | M |
| 6 | 羁绊槽与爆发技系统 | MVP | Core | game-designer + systems-designer | M |
| 7 | 敌人 AI 与意图系统 | MVP | Core | game-designer + ai-programmer | M |
| 8 | 爆发演出系统 | MVP | Presentation | game-designer + technical-artist | M |
| 9 | 战斗 HUD 系统 | MVP | Presentation | ux-designer | S |
| 10 | 战斗地图系统 | Vertical Slice | Feature | level-designer | M |
| 11 | 航线与招募系统 | Vertical Slice | Feature | game-designer + economy-designer | M |
| 12 | 航线与招募 UI | Vertical Slice | Presentation | ux-designer | S |
| 13 | 存档系统 | Alpha | Feature | systems-designer | S |
| 14 | 悬赏成长系统 | Alpha | Feature | economy-designer | S |
| 15 | 战后结算系统 | Alpha | Presentation | game-designer | S |
| 16 | 教学系统 | Alpha | Polish | game-designer | S |
| 17 | 音频系统 | Full Vision | Polish | audio-director | S |
| 18 | 主菜单与设置 | Full Vision | Polish | ux-designer | S |

---

## Circular Dependencies

- None found。关键架构约定：**相邻羁绊系统以单向"效果修正器"注入战斗解算**（解算依赖羁绊的输出，羁绊不回头引用解算）——此约定写入双方 GDD 的 Dependencies 节，违反即引入循环。

---

## High-Risk Systems

| System | Risk Type | Risk Description | Mitigation |
|--------|-----------|-----------------|------------|
| 相邻羁绊系统 | Design | 21 种职业配对的覆盖规则未定；通用效果可能缺乏记忆点（概念书已标风险） | GDD 阶段定义矩阵覆盖策略；垂直切片试玩验证情感温度 |
| 敌人 AI 与意图系统 | Design + Scope | 意图可见性契约未决（Open Question #3）；行为原型易超时（概念书已警告）；交战距离经济需修复远程身份（原型发现） | GDD 必须给出明确可见性规则；行为原型锁 3–4 种基线；远程课题与战斗地图（地形）联动设计 |
| 爆发演出系统 | Technical | 首作开发者的 juice 功力未经引擎验证；3D 低模 + 2D 分镜混合管线是新技能栈 | MVP 白盒阶段最先攻克；2D 像素回退方案已留（视觉锚点） |
| 单位数据系统 | Technical | 全局瓶颈——几乎所有系统读它；schema 一旦返工全线受灾 | 最先设计；schema 评审通过后才开后续 GDD；预留羁绊标签扩展位 |
| 战斗地图系统 | Design | 地形是修复远程身份的主要工具——地图即平衡，设计失误会复发原型问题 | 与敌人 AI GDD 联动；每张地图标注预期交战距离 |

---

## Progress Tracker

| Metric | Count |
|--------|-------|
| Total systems identified | 18 |
| Design docs started | 12 |
| Design docs reviewed | 12 |
| Design docs approved | 12 |
| MVP systems designed | 9/9 |
| Vertical Slice systems designed | 3/3 (全部 Approved，2026-06-17) |

---

## Next Steps

- [x] Review and approve this systems enumeration（2026-06-13 用户批准；TD-SYSTEM-BOUNDARY / PR-SCOPE / CD-SYSTEMS gates skipped — Lean mode）
- [ ] Design MVP-tier systems first (use `/design-system 单位数据系统`)
- [ ] Run `/design-review` on each completed GDD
- [ ] Run `/gate-check pre-production` when MVP systems are designed
- [ ] Validate the highest-risk systems with `/vertical-slice` before committing to Production

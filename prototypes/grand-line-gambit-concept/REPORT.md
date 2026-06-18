# Concept Prototype Report: 孤帆棋海 (Grand Line Gambit)

> **Date**: 2026-06-13
> **Prototype Path**: HTML
> **Concept File**: design/gdd/game-concept.md

---

## Hypothesis

如果玩家在网格上移动船员、为凑相邻而权衡站位、攒满羁绊槽后引爆组合技——他们会感到"计算得到了热血回报"。
验证信号：玩家主动为羁绊站位放弃安全站位 ≥2 次/局，且爆发回合后主动重开一局。

---

## Riskiest Assumption Tested

"站位充能 → 时机引爆"节奏有张力，不会退化为"无脑攒满就放"。

**结果：A 模式（共享羁绊槽）下成立。** 玩家主动冒险凑相邻、爆发后主动重开。
B 模式（单位独立槽，双满才能引爆）充能太慢，张力消失。
**概念书 Open Question #2（共享 vs 独立槽）由此关闭：采用共享槽。**

---

## Approach

8×8 DOM 网格战棋：4 名固定船员（剑豪×2 / 炮手×2）、5 个贪心追击敌人、
移动 + 攻击 + 相邻羁绊加成（+1 伤害 / +2 充能）+ 两种爆发组合技
（双刀乱舞 / 炮剑协奏）+ 基础演出（分镜横幅、闪白、震屏、飘字）。
内置 A/B 开关对比共享槽与独立槽。

**Path chosen:** HTML（单文件，浏览器双击即玩）
**Reason for path:** 回合制战棋验证的是规则与决策逻辑，不依赖输入时序手感，浏览器延迟不影响结论。

**Shortcuts taken (intentional):**
- 硬编码全部数值；emoji 代替美术；DOM 网格代替渲染
- 无菜单、存档、音效、教学、招募、航线、meta
- 敌人 AI 仅贪心追击最近船员；无错误处理

---

## Result

- **假设判定：PARTIALLY CONFIRMED。** A 模式产生了假设预言的两个行为信号
  （冒险凑相邻 + 爆发后重开）；B 模式未通过——"B 模式攒得太慢"（玩家原话）。
- **最佳时刻**（玩家原话）："双刀乱舞清掉三个敌人那一下最爽"（A 模式第二局）。
  多杀爆发是已验证的乐趣峰值。
- **最差时刻**：远程攻击存在感太弱。敌人每回合移动 2 格扑脸，炮手 3 格射程的
  优势窗口只有约一回合，远程职业的战术身份没有立起来。经确认这是设计问题
  （远程的存在价值不足），不是 bug 也不是 UX 可发现性问题。
- **意外**：无。行为符合设计预期——同时说明贪心 AI 过于单调，不会制造涌现时刻。

---

## Metrics

| Metric | Value |
|--------|-------|
| Path used | HTML |
| Iterations to playable | 1（一次成型，无报错） |
| Prototype duration | 1 个会话日 |
| Playtesters | 1 internal（开发者本人；A/B 双模式各多局） |
| Feel assessment | 回合逻辑清晰；爆发演出（横幅+闪白+震屏+变色背景）在占位美术下仍有效传达"热血感"；B 模式充能节奏明显过慢 |
| Hypothesis verdict | PARTIALLY CONFIRMED |

---

## Recommendation: PROCEED

A 模式下核心循环（站位→充能→引爆）产生了假设预言的两个行为信号：玩家主动放弃
安全站位去凑相邻，并在爆发回合后主动重开。乐趣峰值明确（组合技多杀），已知的
失败模式（B 模式节奏、远程存在感弱、AI 单调）都属于可在 GDD 阶段修正的参数与
系统设计问题，而非概念层面的否定。值得投入完整设计文档。

---

## If Proceeding

- **Core tuning values discovered:** 共享槽上限 10；相邻充能 +2 / 单独 +1；
  相邻伤害加成 +1；双刀乱舞 6 伤（任一剑豪切比雪夫 2 格内）；炮剑协奏 5 伤
  （与任一单位同行/同列）；B 模式单位槽上限 5 仍太慢——独立槽路线整体放弃
- **Assumptions confirmed:** 相邻触发机制确实驱动站位决策；爆发演出是情绪核心，
  即使占位美术也成立（支持"2D 分镜演出层"的视觉锚点决策）
- **Assumptions disproved:** 单位独立槽不可行（充能太慢）——Open Question #2 关闭，
  概念书该项需更新为"共享槽（原型已验证）"
- **Emergent mechanics:** 无涌现行为——敌人纯贪心 AI 不制造惊喜，
  垂直切片需要敌人行为多样性

**需正面解决的设计课题（带入 /design-system）：**
1. **远程职业身份**：敌人逼近速度 vs 射程优势窗口。候选方向：降低部分敌人移速、
   给炮手风筝/击退工具、地形阻挡、混合远近敌人构成
2. **敌人 AI 多样性**：贪心追击之外至少需要 1-2 种行为原型（守卫、包抄、集火）
3. **炮+炮组合技缺位**：原型刻意留空，GDD 阶段决定补全或保留为职业搭配的取舍点

> Note: HTML 路径无法验证最终爆发演出的"手感"——保留给引擎垂直切片，
> 用真实 3D 低模舞台 + 2D 分镜叠加验证。

**Next steps:**
1. `/design-review design/gdd/game-concept.md`
2. `/gate-check`
3. `/map-systems`
4. `/design-system [mechanic]`（把上面的调参值写入 Tuning Knobs 和 Formulas 章节）

---

## If Pivoting

N/A — 判定为 PROCEED。

---

## If Killing

N/A — 判定为 PROCEED。

---

## Lessons Learned

- **What assumptions were broken by actually building this?**
  独立槽方案在纸面上看似"更有单位个性"，实际充能节奏直接杀死了爆发循环。
  远程射程优势在小棋盘 + 快速敌人下几乎不存在——射程数值必须和敌人移速、
  棋盘尺寸一起设计，不能孤立调参。

- **What surprised us that didn't show up in the brainstorm?**
  没有涌现惊喜本身是发现：贪心 AI + 全明示信息让对局完全可预测，
  "小棋盘大组合"支柱需要敌人侧的变化来兑现。

- **What would we test differently next time?**
  在原型里内置行为计数器（冒险站位次数、爆发后重开率）而非依赖玩家自述回忆；
  垂直切片阶段找外部试玩者（itch.io / r/playmygame）获取新手困惑数据。

---

> *Prototype code location: `prototypes/grand-line-gambit-concept/`*
> *This code is throwaway. Never refactor into production.*

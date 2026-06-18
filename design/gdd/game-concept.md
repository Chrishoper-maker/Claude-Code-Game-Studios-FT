# Game Concept: 孤帆棋海 (Grand Line Gambit)

*Created: 2026-06-13*
*Status: Approved（概念已批准；核心循环经原型验证 PROCEED——见 `prototypes/grand-line-gambit-concept/REPORT.md`）*
*Last design review: 2026-06-13 — NEEDS REVISION → 本版已修订*

---

## Elevator Pitch

> 一款战棋肉鸽：你是无名小海贼，每到一座岛招募一名怪人船员（每名船员是一种独特的"棋子"），在单屏网格海战中靠站位积攒羁绊槽，在关键回合引爆相邻船员的羁绊必杀技，逆转战局、击败悬赏头目。
>
> 10 秒测试：「海贼版战棋肉鸽——招怪人船员当棋子，站位充能，关键回合相邻二人合体必杀。」

---

## Core Identity

| Aspect | Detail |
| ---- | ---- |
| **Genre** | 战棋（Tactics）+ 肉鸽（Roguelike run 结构） |
| **Platform** | PC (Steam / Epic) |
| **Target Audience** | 策略精通型玩家 + 热血动漫情怀战棋玩家（见 Target Player Profile） |
| **Player Count** | Single-player |
| **Session Length** | 单场战斗目标 5–8 分钟（硬上限 10，原型 5–8 回合支持此值）；单次出航（一个 run）30–60 分钟 |
| **Monetization** | Premium（买断制） |
| **Estimated Scope** | Medium（3–6 个月，单人开发） |
| **Comparable Titles** | Into the Breach、FTL: Faster Than Light、Wargroove |

---

## Core Fantasy

海贼王式的"我的船员各个是怪才，合体时天下无敌"。

玩家的情感承诺：你不是在操控一支军队，而是在组建**一艘船上的一家人**。每名船员都是有怪癖的独特棋子；当两名羁绊船员并肩而立、在你精心铺垫的关键回合同时爆发时，那一刻既是战术计算的回报，也是热血动漫的跨页分镜。别的战棋给你士兵，这款游戏给你**伙伴**。

---

## Unique Hook

像《FTL》的船员收集，**而且**任意两名相邻船员都能触发羁绊组合效果——站位本身就是羁绊系统。

- 一句话可解释 ✅
- 真正新颖：羁绊不是菜单里的数值加成，而是**棋盘几何**——你把谁排在谁旁边，就是在做战术与情感的双重决策
- 与核心幻想直接相连：机制即情感（伙伴并肩 = 力量爆发）
- 影响玩法而非纯装饰 ✅

---

## Player Experience Analysis (MDA Framework)

### Target Aesthetics (What the player FEELS)

| Aesthetic | Priority | How We Deliver It |
| ---- | ---- | ---- |
| **Sensation** (sensory pleasure) | 4 | 羁绊爆发的漫画分镜演出：切入框、速度线、闪白、震屏 |
| **Fantasy** (make-believe, role-playing) | 3 | 无名小海贼成长为传奇船长的身份幻想 |
| **Narrative** (drama, story arc) | N/A | 反支柱：不做剧情 JRPG |
| **Challenge** (obstacle course, mastery) | **1** | 站位几何 + 羁绊槽引爆时机的深度计算；悬赏等级递增 |
| **Fellowship** (social connection) | **2** | 单机的"伙伴情谊"拟态：船员个性、羁绊技名、并肩作战 |
| **Discovery** (exploration, secrets) | 5 | 发现新船员组合与相邻效果协同 |
| **Expression** (self-expression, creativity) | 3 | 每次出航的船员阵容 = 玩家的独特"船" |
| **Submission** (relaxation, comfort zone) | N/A | 反支柱：这是挑战向游戏 |

### Key Dynamics (Emergent player behaviors)

- 玩家会为了凑相邻羁绊而冒险走位——在"安全站位"与"羁绊站位"间反复权衡
- 玩家会刻意保留羁绊槽，等待敌人聚集的"完美爆发回合"
- 玩家会围绕已有船员规划下一座岛招募谁（构筑思维自然涌现）
- 玩家会在败北后立刻重航，尝试不同的船员组合路线

### Core Mechanics (Systems we build)

1. **网格战棋系统**——单屏小棋盘（约 8×8），回合制移动与攻击，敌人意图部分明示
2. **相邻羁绊系统**——任意两名相邻船员按职业类型触发通用羁绊效果（6 种职业 → 组合效果矩阵线性可控）
3. **羁绊槽与爆发技**——普通攻击与受击积攒共享羁绊槽；槽满后可指定一对相邻船员发动清屏级羁绊必杀（漫画分镜演出）
4. **航线与招募系统**——肉鸽 run 结构：**2 人起航**，4–6 座岛连航，每岛三选一招募新船员（6 岛终局恰好 8 人满编），终点悬赏头目战
5. **悬赏成长系统**——通关解锁新船员类型进入招募池（meta 进度仅此一条，防范围蔓延）

---

## Player Motivation Profile

### Primary Psychological Needs Served

| Need | How This Game Satisfies It | Strength |
| ---- | ---- | ---- |
| **Autonomy** (freedom, meaningful choice) | 招募谁、上场谁、阵型怎么摆、羁绊槽何时引爆 | Core |
| **Competence** (mastery, skill growth) | 相邻几何与爆发时机的精通曲线；悬赏等级是可见的技术天花板 | Core |
| **Relatedness** (connection, belonging) | 船员个性与羁绊技直接绑定情感；"我的船"的归属感 | Supporting |

### Player Type Appeal (Bartle Taxonomy)

- [x] **Achievers** (goal completion, collection, progression) — How: 击败更高悬赏头目、解锁全部船员类型
- [x] **Explorers** (discovery, understanding systems, finding secrets) — How: 试遍职业相邻组合，发现最优协同
- [ ] **Socializers** — 单机游戏，仅通过船员拟态满足（非核心受众）
- [x] **Killers/Competitors** (domination, mastery) — How: 挑战向难度曲线、完美通关的精通追求

### Flow State Design

- **Onboarding curve**: 首场战斗 = 教学残局：2 名起始船员（即起航编制，无缝衔接）、3 个敌人、预设一次必然触发的羁绊爆发——10 分钟内体验完整核心循环
- **Difficulty scaling**: 悬赏等级制——敌人数量/种类随航线推进递增；高悬赏航线解锁更复杂的敌人意图
- **Feedback clarity**: 伤害数字、羁绊槽可视化、战后结算（回合数/爆发效率评分）
- **Recovery from failure**: 败北即重航，单 run ≤1 小时，损失有限；每次失败都暴露阵容构筑或站位习惯的具体问题（教育性失败）

---

## Core Loop

### Moment-to-Moment (30 seconds)

移动船员抢占相邻站位 → 普通攻击积攒羁绊槽 → 槽满时相邻二人发动羁绊爆发技（必杀演出：分镜切入、喊招式名、清屏效果）。满足感来源：站位几何的算计 + 爆发时刻的演出爽感——计算本身制造热血。

### Short-Term (5-15 minutes)

一场悬赏战 = 5–8 回合的单屏网格战。决策：上场哪 4 名船员、阵型怎么摆、羁绊槽何时引爆。"再来一局"钩子：打完这座岛，下一座岛有新船员等着入伙。

### Session-Level (30-120 minutes)

一次出航（run）= 4–6 座岛连航：每岛三选一招募 → 船员池逐渐成型 → 终点高悬赏头目战。胜利或败北都是自然停顿点；战后解锁进度给出回归理由。

### Long-Term Progression

成长在于**知识与选项**而非数值：解锁新船员类型进入招募池、摸透各职业相邻效果的几何学、挑战更高悬赏航线。长期目标：击败最高悬赏的"海上皇帝"。

### Retention Hooks

- **Curiosity**: 还没试过的船员组合；还没见过的羁绊爆发演出
- **Investment**: 招募池解锁进度；对船员角色的喜爱
- **Social**: 无（单机，反支柱）
- **Mastery**: 更高悬赏等级；更少回合通关；爆发效率评分

---

## Game Pillars

### Pillar 1: 羁绊即战术

一切情感元素必须落地为棋盘机制——羁绊不在菜单里，在站位里。

*Design test*: 纠结某功能时：若它只是风味、不影响棋盘决策，砍掉或合并进机制。

### Pillar 2: 关键回合的爆发

每场战斗都向 1–2 个逆转性爆发回合积蓄；爆发是计算的回报，不是按钮的奖励。

*Design test*: 节奏取舍时：选让爆发回合**更炸**的那个方案。

### Pillar 3: 小棋盘大组合

内容极简，深度来自元素间互动——8 名船员、6 种相邻效果足以产生组合爆炸。

*Design test*: 「加内容」vs「加互动」时：永远选互动。

### Pillar 4: 十分钟一场爽局

单场战斗 ≤10 分钟，单次出航 ≤1 小时——节奏是首作规模的护城河。

*Design test*: 范围争议时：砍掉任何拖长节奏的东西。

> 支柱张力：2↔3（演出爽感 vs 极简内容）、1↔4（羁绊深度 vs 快节奏）——互相牵制的支柱才能真正约束决策。

### Anti-Pillars (What This Game Is NOT)

- **NOT 剧情 JRPG**：不做长过场动画与对话树——违背「十分钟一场爽局」
- **NOT 收集图鉴游戏**：不做 50 人大船员表——违背「小棋盘大组合」，平衡成本失控
- **NOT 完全信息象棋谜题**：保留戏剧性与爆发演出——本作核心是热血计算，不是冷酷残局
- **NOT 多人对战**：平衡成本会吞掉整个几周开发预算

---

## Visual Identity Anchor

*（草案——AD-CONCEPT-VISUAL 总监评审已跳过（Lean 模式），待 `/art-bible` 细化确认）*

**方向名称**：热血分镜 × 低模舞台（Shōnen Panel × Low-Poly Stage）

**一句话视觉规则**：3D 低模角色站上战棋舞台，但每一次羁绊爆发依然是一格 2D 跨页漫画分镜（参考《女神异闻录》《Hi-Fi Rush》的 3D+2D 混合演出语言）。

**支撑视觉原则**：

1. **低模但剪影鲜明**——每名角色 ≤2000 三角面，靠体块、配色与标志性道具区分。
   *Design test*: 缩略图剪影能认出是哪名船员吗？不能 → 重做体块设计。
2. **演出靠 2D 分镜叠加，不靠复杂骨骼动画**——切入框、速度线、闪白、镜头冲击替代精细动作捕捉级动画。
   *Design test*: 新演出需要复杂骨骼动画吗？若是 → 改用分镜手法实现。
3. **爆发即变色**——平时低饱和海蓝基调，爆发瞬间切换高饱和暖色冲击。
   *Design test*: 爆发画面截图与普通回合截图能否一眼区分？不能 → 加强对比。

**色彩哲学**：海蓝灰为底（冷静计算），羁绊爆发用橙红金（热血释放）——色彩本身讲述「积蓄 → 爆发」的核心循环。

**资产策略**：角色基于现成低模素材库（Synty / Quaternius / Kenney）+ Blender 改色换件做差异化——**不从零雕角色**。这是 3–6 个月时间线成立的前提。

---

## Inspiration and References

| Reference | What We Take From It | What We Do Differently | Why It Matters |
| ---- | ---- | ---- | ---- |
| Into the Breach | 单屏小棋盘 + 深度战术 + 极简内容哲学 | 加入羁绊槽爆发节奏与热血演出，信息不完全透明 | 证明微型棋盘战棋有稳定 PC 受众 |
| FTL: Faster Than Light | 船员收集 + 肉鸽航线结构 + "我的船"归属感 | 战斗从实时管理改为回合战棋；船员关系机制化 | 证明船员情感投资能驱动重玩 |
| 海贼王 / 数码宝贝（动漫） | 伙伴羁绊、招式喊名、跨页分镜的热血语言 | 将情感语言完全机制化为相邻系统 | 本作的情感底色与演出风格来源 |

**Non-game inspirations**: 少年漫画的分镜语言（跨页大格、速度线、定格）；《海贼王》"伙伴"叙事——力量来自羁绊而非个体。

---

## Target Player Profile

| Attribute | Detail |
| ---- | ---- |
| **Age range** | 18–35 |
| **Gaming experience** | Mid-core～Hardcore（战棋/肉鸽经验玩家） |
| **Time availability** | 工作日 30–60 分钟单 run；周末连续多 run |
| **Platform preference** | PC (Steam) |
| **Current games they play** | Into the Breach、Slay the Spire、Wargroove |
| **What they're looking for** | 短局深度战术 + 动漫情怀的情感温度（市面战棋大多冷峻） |
| **What would turn them away** | 数值膨胀、长剧情强制观看、内容注水拖时长 |

---

## Technical Considerations

| Consideration | Assessment |
| ---- | ---- |
| **Recommended Engine** | **Godot 4.6.3 + GDScript**（`/setup-engine` 已执行；详见 CLAUDE.md 与 `.claude/docs/technical-preferences.md`） |
| **Key Technical Challenges** | ①爆发演出的 juice 实现（分镜、震屏、时停）；②羁绊槽节奏的手感调试；③简单敌人 AI（意图系统）；④3D 资产管线（素材导入/材质/光照）对首作开发者是新技能栈 |
| **Art Style** | 风格化低模 3D（角色 ≤2000 三角面）+ 2D 漫画分镜爆发演出（见 Visual Identity Anchor） |
| **Art Pipeline Complexity** | Medium（低模素材库 + Blender 改色换件，不从零建模；演出靠程序化分镜而非美术量） |
| **Audio Needs** | Minimal～Moderate（爆发音效是重点投资项；BGM 用授权素材） |
| **Networking** | None |
| **Content Volume** | 8 名船员、6 种职业相邻效果、1 条 4–6 岛航线、3 个头目、敌人行为原型 3–4 种（基线，战斗 GDD 定稿——「小棋盘大组合」依赖敌侧变化，原型已证纯贪心 AI 单调）、约 3–5 小时单周目 + 重玩 |
| **Procedural Systems** | 轻度：航线岛屿排列与敌人波次组合随机；战斗地图手工设计（小棋盘，约 10 张） |

---

## Risks and Open Questions

### Design Risks

- ~~羁绊槽节奏若调不好，爆发会变成"无脑攒满就放"~~ → **原型已部分排除**：共享槽（上限 10）节奏成立；独立槽方案已证不可行并放弃
- 相邻通用效果可能不如专属配对有记忆点——情感温度不足，沦为普通 buff
- **远程职业身份**（原型发现）：敌人 2 格/回合逼近 vs 炮手 3 格射程，优势窗口仅约一回合——交战距离经济必须在战斗 GDD 中整体设计（候选：敌人移速分层、风筝/击退工具、地形阻挡、远近混编敌人）
- **受击充能的退化策略**（原型机制）：受击 +1 充能可能催生"故意挨打攒槽"最优解——战斗 GDD 需设边界规则（如受击充能每回合上限）
- **组合技矩阵覆盖**：6 职业 = 21 种配对（15 异职业 + 6 同职业），每对都做专属必杀不现实——GDD 阶段必须定义覆盖规则（原型仅 2 种，炮+炮刻意留空）

### Technical Risks

- 首作开发者实现爆发演出 juice（分镜、时停、震屏）的功力未经验证——MVP 阶段必须优先攻克
- 敌人 AI 哪怕做"简单意图"也可能超预期耗时

### Market Risks

- 战棋肉鸽小品类竞品密集（Into the Breach 珠玉在前），差异化全靠羁绊系统与热血演出
- 无 IP 授权——海贼王/数码宝贝只能做"精神致敬"，美术与文本必须完全原创规避侵权

### Scope Risks

- 肉鸽 meta 系统极易越做越大——已用反支柱锁死（仅"解锁招募池"一条 meta 线）
- 船员数量诱惑（"再加 2 个船员吧"）会让羁绊矩阵膨胀——8 人封顶
- 3D 资产管线（素材导入/材质/光照）对首作开发者是全新技能栈——已用"素材库 + 低模 + 分镜演出"策略缓解；若垂直切片阶段管线仍失控，回退 2D 像素方案（视觉锚点保留了该退路）

### Open Questions

- ~~"站位充能 → 相邻爆发"循环单场是否好玩？~~ **已回答（2026-06-13 原型，PROCEED）**：PARTIALLY CONFIRMED——共享槽模式下玩家主动冒险凑相邻并在爆发后重开，循环成立
- ~~羁绊槽是共享一条还是每对船员独立？~~ **已回答：共享槽**。独立槽充能太慢、张力消失，放弃
- 敌人意图全明示还是部分隐藏？——**仍未决**，留给战斗 GDD。约束：必须给出明确的可见性规则，不可折中含糊（对标 Into the Breach 的棋感恰恰来自全明示——"部分隐藏"是在改变品类契约，需自觉为之）

### 原型验证的初始调参基线（GDD Tuning Knobs 起点）

| 参数 | 原型验证值 |
|------|-----------|
| 共享羁绊槽上限 | 10 |
| 相邻攻击充能 / 单独攻击充能 | +2 / +1 |
| 相邻伤害加成 | +1 |
| 爆发组合伤害（剑+剑 / 剑+炮） | 6 / 5 |
| 单场回合数 | 5–8 |

---

## MVP Definition

**Core hypothesis**: "站位充能 → 相邻羁绊爆发"的单场战斗循环本身就足够好玩（无需航线、招募、meta 进度的支撑）。

**Required for MVP**:
1. 8×8 单屏网格战斗：移动、攻击、敌人简单意图
2. 4 名固定船员（2 种职业 × 2）+ 共享羁绊槽 + 至少 2 种相邻爆发技
3. 爆发演出第一版（分镜切入 + 震屏 + 变色）——juice 是假设的一部分，不可省略

**Explicitly NOT in MVP** (defer to later):
- 航线/岛屿/招募系统（垂直切片阶段再做）
- 船员解锁 meta 进度
- 头目战、音效音乐、菜单美术

### Scope Tiers (if budget/time shrinks)

| Tier | Content | Features | Timeline |
| ---- | ---- | ---- | ---- |
| **MVP** | 1 场战斗、4 名固定船员（白盒方块，无需 3D 资产） | 核心循环 + 爆发演出 v1 | 1–2 周 |
| **Vertical Slice** | 3 岛短航线、6 名船员（低模素材）、1 个头目 | 核心 + 招募 + run 结构 + 3D 管线跑通 | 4–6 周 |
| **Alpha** | 完整 4–6 岛航线、8 名船员、3 头目 | 全部功能（粗糙）、6 种相邻效果 | 2–3 个月 |
| **Full Vision** | 全内容打磨、音效音乐、Steam 页面 | 全部功能（抛光）、招募池解锁 | 3–6 个月 |

---

## Next Steps

- [x] Get concept approval（用户批准；CD gate skipped — Lean mode）
- [x] Fill in CLAUDE.md technology stack based on engine choice (`/setup-engine`) — Godot 4.6.3 + GDScript
- [x] Concept validated by `/design-review`（2026-06-13，本版已按评审修订）
- [x] **Prototype core idea** — **PROCEED**（HTML 原型，见 `prototypes/grand-line-gambit-concept/REPORT.md`）
- [ ] Decompose concept into systems (`/map-systems`) ← **下一步**
- [ ] Design each system (`/design-system [system-name]`) — use prototype learnings in Tuning Knobs and Formulas sections
- [ ] Build vertical slice in Pre-Production (`/vertical-slice`) — validate full game loop before committing to Production
- [ ] Validate core loop with playtest (`/playtest-report`)
- [ ] Plan first milestone (`/sprint-plan new`)

# Review Log: unit-data-system.md

## Review — 2026-06-13 — Verdict: APPROVED (Round 4 — user accepted R3 revisions)
Scope signal: M
Specialists: user decision (skipped R4 formal review)
Blocking items: 0 | Recommended: 0
Summary: 用户在 R3 修订落地后选择直接标记 Approved，跳过第四轮正式评审。R3 四个阻断项均为合约语言修复（无新设计决策），修订质量经用户确认后视同通过。文档状态从 In Review 更新为 Approved。
Prior verdict resolved: Yes — R3 NEEDS REVISION (4B+10C), all resolved

---

## Review — 2026-06-13 — Verdict: NEEDS REVISION (Round 3)
Scope signal: M
Specialists: game-designer, systems-designer, qa-lead, creative-director
Blocking items: 4 | Recommended: 10
Summary: 第三轮发现四个阻断项，均为合约语言问题（无新设计决策）：bond_tags "首个匹配"语义未定义（字典序已补）；named_pair_overrides 单向查找方向未指定（双向扫描规则已补）；AC-8/9a 的 MAX_CREW/DEPLOY_LIMIT 标注"TBD owner"无强制路径（改为声明性约束，归 deployment-system 执行）；DEPLOY_LIMIT 意图段误导读者以为本系统承接留守机制（Interactions 表加 deployment-system 行，措辞修正）。10 个 CHANGE 项涵盖 AC 节结构重组（AC-13–18 移入 fail-fast 节、AC-19 移入数据驱动节）、AC-5 补浮点边界用例、AC-6 改写构建产物依赖措辞、AC-7 补公式引用、AC-12 sentinel 加暂定值声明、AC-13 澄清对称声明歧义、grid_position 类型声明、航海士区间 action_weight 条件标注、错误处理顺序声明、Interactions 表补炮手依赖注释。全部修订已落地，状态维持 In Review 等待 Round 4。
Prior verdict resolved: Yes — R2 NEEDS REVISION (4B+12C), all resolved

---

## Review — 2026-06-13 — Verdict: NEEDS REVISION (Round 2)
Scope signal: M
Specialists: game-designer, systems-designer, qa-lead, creative-director
Blocking items: 4 | Recommended: 12
Summary: 第二轮发现四个阻断项：bond_tags 多标签触发语义未定义（Foundation 层接口泄漏）；load_all_units() 返回契约无法区分错误类型，且 11 条 fail-fast AC 使用不可测试的运行时语言；DEPLOY_LIMIT=4 设计意图未声明；航海士 power_score 范围 [12.5, 17.5] 导致合法配置例行触发平衡警告。12 个 CHANGE 项涵盖 AC 语言标准化（全部重写）、base_damage 负值校验、current_hp 下界声明、named_pair_overrides 类型定义、action_weight 临时状态标注、炮手行动经济说明、Open Question #1 升级为设计分叉声明等。全部修订已落地，状态维持 In Review 等待 Round 3。
Prior verdict resolved: Yes — R1 NEEDS REVISION (5B+13C), all resolved

---

## Review — 2026-06-13 — Verdict: NEEDS REVISION (Round 1)
Scope signal: M
Specialists: game-designer, systems-designer, qa-lead, creative-director
Blocking items: 5 | Recommended: 13
Summary: 首轮评审发现五个阻断项：attack_range 描述与 grid-board-system 已锁规则不一致（Foundation 层须为权威源）；乐手 dmg=1 最低组合 11.0 系统性出带（锁 2）；铁壁 HP=11 组合 12.5 出带（HP 锁 12）；is_alive 字段契约缺失（全系统须统一用 `is_alive==false` 检测 Downed）；Edge Cases 缺少 AC-13–AC-17 五类结构错误测试。13 个 CHANGE 项涵盖 AC 拆分/改写、Player Fantasy FTL 宣称收窄、named_pair_overrides MVP 说明、接口契约与日志级别声明、羁绊标签约束依据、医师乐手招募博弈说明、Open Questions 补充等。全部修订已落地，状态更新为 In Review。
Prior verdict resolved: N/A — First review

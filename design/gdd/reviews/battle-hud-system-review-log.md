# 战斗 HUD 系统 设计评审日志

## Review — 2026-06-16 — Verdict: APPROVED（R1 修订后放行，无需 R2）
Scope signal: L
Specialists: 无（lean mode）
Blocking items: 4（均为接口/信号缺口，无设计方向问题）| Recommended: 3 | Advisory: 1
Summary: 首次评审。6 类显示区域（单位面板、槽量/爆发按钮、意图叠层、先攻队列、轮次计数、浮字）覆盖全面；状态机、输入锁定（幂等布尔）、信号订阅架构清晰。4 条 BLOCK：①`round_ended()` 遗漏于 Interactions 表（补入订阅条目）；②GUARDED/AURA_BONUS mid-turn 消耗无信号——决策添加 `status_consumed(unit_id, status_type)` 并回填 battle-resolution Interactions 表；③状态机 HUD_ENEMY_TURN 退出条件写 `enemy_actions_completed` 但 Interactions 表无此信号——改为 `unit_turn_ended`（已有信号，统一处理友方/敌方）；④has_moved pip 无信号——在 grid-board GDD 添加 `unit_moved(unit_id, from_pos, to_pos)` 信号并回填。3 条 RECOMMENDED 均已修复：displacement 浮字规范补入 Rule 7、爆发效果预览补入 Rule 3、grid-board 只读接口补入 Interactions。MVP 全 9 个系统 GDD 已全部 Approved。
Prior verdict resolved: No — 首次评审

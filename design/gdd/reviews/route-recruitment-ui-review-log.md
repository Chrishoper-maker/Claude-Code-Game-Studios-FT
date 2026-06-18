# Review Log: 航线与招募 UI (Route & Recruitment UI)

## Review — 2026-06-17 — Verdict: APPROVED（NEEDS REVISION → R1 当场修订放行）

Scope signal: M
Specialists: lean 模式（单会话分析）
Blocking items: 1（已修复）| Recommended: 4（已修复）
Summary: 首次评审发现一项阻断：Rule 2 Step 7 和状态机引用 run_phase_changed("PRE_DEPLOY") 相位，但 #11 GDD 未定义此相位。修复方案：在 #11 添加 "DEPLOYING" 相位（进入 RUN_DEPLOYING 状态时发出），#12 中 "PRE_DEPLOY" 全部改为 "DEPLOYING"。同轮修复：Rule 3 Step 2 常量引用（≤4 → ≤DEPLOY_LIMIT）、UI_DOWNED_NOTIFY 在 battle_lost 路径的明确退出条件、UI_SKIPPED 状态退出分支说明、新增 AC-12（battle_lost + 阵亡通知路径）。修订完成后无剩余阻断，一轮放行。
Prior verdict resolved: No — 首次评审

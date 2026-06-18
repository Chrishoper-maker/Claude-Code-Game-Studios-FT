# Vertical Slice: 孤帆棋海 (Grand Line Gambit) — 单场战斗核心循环

> **Date**: 2026-06-18
> **Engine**: Godot 4.6.3（Forward+ / D3D12）
> **Status**: 🟡 in-progress — 脚手架已成型，待首次在 Godot 中运行 + 报错迭代
> **Concept verdict**: [概念原型 PROCEED](../grand-line-gambit-concept/REPORT.md)

---

## Hypothesis（验证问题）

新玩家在 ~3 分钟内、无引导即可触发一次"相邻爆发"（定格 + 分镜横幅 + 震屏），
并感到"伙伴并肩 = 战术热血回报"——**同时**验证 ADR-0006~0009 在真实 Godot 4.6.3
中能落地，尤其是最高风险的 `set_ignore_time_scale` 墙钟计时（ADR-0008）。

## Riskiest Assumption（最高风险假设）

`set_ignore_time_scale(true)` 在 Godot 4.6.3 中能让演出 Tween 按**墙钟**推进，
不被 `Engine.time_scale = 0.05`（世界定格）拖慢 20×。
→ 若失效，整个"世界定格 / 演出照常播"的爆发演出方案需走 ADR-0008 回退方案 2。

---

## How to Run

1. Godot 4.6.3 打开本目录（`project.godot`），或在编辑器中 Import 此文件夹。
2. F5 运行（主场景 `scenes/Main.tscn`）。
3. 操作：
   - **点击**己方船员选中 → 青色格 = 可移动，红色格 = 可攻击的敌人。
   - 凑相邻（八向切比雪夫=1）攻击：+1 伤害、+2 充能（单独 +1）。
   - 羁绊槽满 10 → 按 **B**（或点"羁绊爆发"）→ 点 lead 船员 → 点相邻 partner → 触发爆发。
   - **Space** = 结束回合（敌方 MELEE 贪心逼近，意图在 HUD 明示）。
   - 目标：清空 3 名敌人即胜利（回合上限 8）。

## 范围（Scope A）

- 1×8×8 地图 / 4 白盒船员（剑×2 + 炮 + 铁壁）/ 3 近战敌（明示意图）
- 共享羁绊槽 10 / 2 个爆发组合（剑剑=6、剑炮=5，其余 generic=4）
- 架构落地：EventBus(0001) + GridCoordMapper(0006) + UnitView(0007)
  + BurstPresentation unscaled(0008) + CameraShake(0009) + enum 状态机(0004)

### 范围切（deferred，非本切片验证目标）

- **ADR-0003 .tres 目录扫描管线** → 降级为代码内 `UnitDefinition` 实例化（`battle_controller._def()`）。
- 无音频 / 无存档 / 无关卡数据 / 美术为白盒图元（art-bible §4 配色 + 职业形状区分）。
- 单一 MELEE 敌人行为原型；无招募 / 无路线 / 无地形效果。

---

## Validation Checklist（运行时逐项核对）

| # | 成功判据 | 怎么看 |
|---|----------|--------|
| ① | 3–5 min 完成一局且**主动**触发爆发 | 实际试玩计时 |
| ② | `set_ignore_time_scale` 按墙钟（P1 不被 20× 拉长） | 看屏幕左上 `[VS验证]` 调试条 / 控制台 print：P1→P4 墙钟应 **≈960 ms**，失效则 ≈19200 ms |
| ③ | 震屏精确回弹、无累积漂移 | 爆发后相机回到原位，无偏移残留 |
| ④ | 白盒单位可辨识（职业 + 阵营冷暖） | 剑=红箱 / 炮=橙柱 / 铁壁=青箱；敌方压暗 + 冷 rim |

> ⚠️ ADR-0008 标注 `set_ignore_time_scale` 为编码前 Verification Required——判据 ②
> 即为该实测。引擎参考未佐证"4.5 Tween PROCESS_IDLE 变化"，若 ② 通过可据此下调 ADR-0008 风险。

---

## Pre-Run Audit（首跑前留痕 — 2026-06-18）

首跑前已做两层离线核查，结论：**脚手架就绪，无已知阻断；唯一未知数为验证条 ② 的实机墙钟。**

- **静态走查**（14 文件 / 1215 行）：信号契约与 `event_bus.gd`（ADR-0001 子集）签名逐一对齐；`class_name` 常量交叉引用无环；核心循环闭合（部署→移动/攻击→充能→引爆→清场→胜负）。
- **引擎兼容性**（对照 `docs/engine-reference/godot/` breaking-changes / deprecated-apis，2026-02-12 核实，覆盖 4.4–4.6）：
  - 主动规避 4.6 三大破坏性变更——零物理体（Jolt 默认无关）、未启用 glow（glow-before-tonemap 无关）、无自定义 shader（4.4 纹理类型变更无关）。
  - API 形式全部非废弃：`Time.get_ticks_msec()`、`signal.connect(callable)`、类型化容器、`await ...timeout`。`StandardMaterial3D` rim/emission、Mesh 图元、`Camera3D` 投影/`look_at`/`project_ray_*`、`roundi()` 均 4.0+ stable。
  - **F-6 交叉印证**：godot 参考目录中**无任何** Tween / `set_ignore_time_scale` / `TWEEN_PROCESS_IDLE` / `time_scale` 变更记录 → ADR-0008 的 HIGH RISK 属保守标注，该 API 实为 4.0+ stable。验证条 ② 通过即可据此下调 ADR-0008 风险。

## Findings（2026-06-18，Godot 4.6.3 实跑）

技术验证部分 **PASS**;手感类判据(①③④)仍待人工试玩。

- **验证条 ②（最高风险，ADR-0008）= ✅ PASS。** 无头实测 `set_ignore_time_scale(true)` 在 `Engine.time_scale=0.05` 下墙钟 = **920 ms**（期望≈960 / 若失效≈19200）——离失效值差一个数量级,确证演出 Tween 按墙钟推进。**ADR-0008 的 HIGH RISK 可据此下调**(F-6 同时印证:4.6.3 参考无任何 Tween/PROCESS_IDLE 计时变更)。命令见 `verify_time_scale.gd` 头部。
- **整工程无头冒烟 = ✅ PASS。** `--quit-after 120` 跑完真实 `battle_controller._ready()`(相机/棋盘/64 格/7 单位/HUD/信号/PLAYER_PHASE 全构建),**零 SCRIPT ERROR、零 warning、退出码 0**。
- **⚠️ Godot 首次导入陷阱(重要,影响 CI):** 工程从未在编辑器打开时,`.godot/global_script_class_cache.cfg` 未生成 → 所有 `class_name` 全局类型报 "Could not find type"。**无头/CI 运行前必须先跑一次** `godot --headless --import --path <proj>`(或在编辑器打开一次)。`.godot/` 已 gitignore,故每个新 clone 的无头运行都需此步——建 CI 时务必在测试命令前加导入。编辑器内 F5 不受影响(打开即自动导入)。

### 待人工试玩核对（需显示器,无法无头）
- ① 3–5 min 完成一局且主动触发爆发　③ 震屏精确回弹无漂移　④ 白盒职业/阵营可辨识
- 在编辑器打开本工程 → F5 → 攻击攒满羁绊槽 → B 选 lead+相邻 partner 触发爆发,看左上 `[VS验证]` 条(in-context 应同样 ≈960ms)。

> 三项手感判据通过后,整理为 `REPORT.md` 并把 `../index.md` Verdict 升为 PROCEED/结论。

# Accessibility Requirements: 《孤帆棋海》

> **Status**: Committed
> **Author**: ux-design skill（lean，主会话内撰写——ux-designer 专精代理本会话不可用）
> **Last Updated**: 2026-06-18
> **Accessibility Tier Target**: **Standard**（MVP/垂直切片底线 = Basic，目标 = Standard）
> **Platform(s)**: PC（Steam / Epic）
> **External Standards Targeted**:
> - WCAG 2.1 Level AA（倾向，非正式认证）
> - AbleGamers / CVAA：参考，未正式承诺
> - Xbox / PlayStation Accessibility：N/A（PC 首发）
> **Accessibility Consultant**: None engaged
> **Linked Documents**: `design/gdd/systems-index.md`、`design/art/art-bible.md`（§4.6 色盲）、`design/ux/interaction-patterns.md`、`.claude/docs/technical-preferences.md`

> **本文件作用**：项目级无障碍承诺、跨系统特性矩阵、测试计划与审计历史的权威源。
> 若某特性与此处承诺冲突，**以本文件为准——改特性，不改承诺**（除非制作人正式批准修订）。
> 更新时机：每次 `/gate-check` 通过后、任何无障碍审计后、systems-index 新增系统时。

---

## 等级定义（本项目口径）

| 等级 | 含义 | 本项目 |
|------|------|--------|
| **Basic** | 不因可避免的设计排除玩家：色非唯一线索、可读字号、无强制操作时限 | MVP/垂直切片**底线** |
| **Standard** | Basic + 键位可重映射、文本缩放、高对比选项、全视觉反馈备援 | **承诺目标** |
| Comprehensive | Standard + 屏幕阅读器支持、全音频视觉化、细粒度难度/辅助开关 | 超出 MVP 范围 |
| Exemplary | 行业标杆级（专职无障碍顾问 + 认证） | 不承诺 |

**承诺理由**：回合制战棋天然有利——无操作时限、无 twitch、可随时停顿思考；项目 options-only 交互（无自由输入）、键盘快捷键既定需求、art-bible §4.6 已设计色盲备援。这些使 Standard 成为低增量成本的合理目标。

---

## 项目级无障碍承诺（特性矩阵）

### 视觉（Visual）
- **色非唯一线索**（Basic，已落地于设计）：所有语义信息必有形状/图标/位置/文字备援——见 art-bible §4.6。红绿盲高风险色对（敌伤红↔治疗绿、友伤橙↔敌伤红）已有 `+/-` 前缀、图标、浮动源格位置备援。
- **职业/阵营辨识不靠单一色相**：职业靠剪影+标志道具（art-bible §3），阵营靠冷暖 rim+明度（§4.5）——色盲下仍可经形状/明度区分。
- **文本缩放**（Standard）：UI 字号支持 ≥125% 缩放档位；关键浮字/HUD 文本不溢出。
- **高对比选项**（Standard）：提供高对比 UI 主题档（加粗描边、提高 HUD 与世界对比）。
- **悬停提示不承载关键信息**（已定，technical-preferences）：所有关键信息有常驻呈现，不依赖 hover。

### 输入（Input / Motor）
- **完整键盘支持**（Standard）：所有 UI 与棋盘操作可纯键盘完成（网格光标方向键导航 + 确认/取消快捷键）。
- **键位可重映射**（Standard）：主要操作键可在设置中重映射。
- **无操作时限 / 无 twitch**（Basic，机制内禀）：回合制，玩家可无限思考；无 QTE、无精确计时输入。
- **点选目标 ≥ 一个棋盘格**（Basic）：交互热区不小于格子，降低精确点击负担。
- **手柄**：Partial，非 MVP（technical-preferences）；网格光标导航为后期适配预留，UI 不得依赖鼠标独有交互。

### 听觉（Audio）
- **无纯音频关键信息**（Basic）：所有音频信号（爆发、受击、槽满）均有视觉备援（HUD/浮字/演出）。
- **字幕**：N/A（MVP 无语音对白）；若后续加入语音须配字幕。

### 认知（Cognitive）
- **意图全明示**（已落地，enemy-ai-intent-system）：敌方意图 Full Reveal，降低记忆/预测负担。
- **Options-only 交互**（已落地，项目协议）：所有决策通过选项按钮，无自由文本输入——降低认知与输入门槛。
- **可停顿**（机制内禀）：回合制，任意时刻可暂停思考；无时间压力（末轮预警是策略信号非操作时限）。
- **一致的反馈语汇**：浮字/高亮/演出语义全项目统一（art-bible §4.3 语义色权威表）。

---

## 跨系统特性矩阵（对照 systems-index）

| 系统 | 无障碍关切 | 承诺 |
|------|-----------|------|
| 战斗 HUD (#9) | 槽/意图/浮字可读性 | 色+形状+位置三重备援；文本缩放；高对比档 |
| 敌人 AI 意图 (#7) | 认知负担 | 意图全明示（已落地） |
| 爆发演出 (#8) | 闪光/震动诱发不适 | 提供"减弱演出"档（降低闪白强度/关闭震动）— Standard 待实现 |
| 航线招募 UI (#12) | 三选一/选4 的纯键盘可达 | 键盘导航 + options-only（已落地） |
| 网格棋盘 (#2) | 光标导航 | 方向键网格光标 + 鼠标点选并行 |
| 单位渲染 (ADR-0007) | 职业/阵营色盲辨识 | 剑剪影+道具+冷暖 rim（art-bible §3/4.5） |

> ⚠️ **爆发演出闪光/震动**：P4 IMPACT 闪白 + 相机震动可能诱发光敏不适。Standard 承诺提供「减弱演出」可选项（降低闪白强度、可关相机震动）——须在 burst-presentation / ADR-0008/0009 实现时纳入旋钮（`USE_BURST_PRESENTATION_FALLBACK` 已为白盒降级预留，可复用为可访问性降级入口）。

---

## 测试计划

- **色盲模拟**：垂直切片用色盲模拟器（protanopia/deuteranopia/tritanopia）截图核对 art-bible §4.6 高风险色对仍可区分。
- **纯键盘走查**：每个界面（招募/部署/战斗/爆发）纯键盘完成一局，无鼠标依赖死点。
- **文本缩放**：125% 档下关键文本不溢出/不遮挡。
- **光敏检查**：爆发演出闪白频率/强度对照 WCAG 2.1（三闪/秒以下）。

## 审计历史

| 日期 | 范围 | 结果 |
|------|------|------|
| — | 尚未审计（垂直切片后首次） | — |

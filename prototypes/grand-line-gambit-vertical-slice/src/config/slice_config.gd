# VERTICAL SLICE - NOT FOR PRODUCTION
# Validation Question: 核心循环与爆发演出调参基线（来自原型 + GDD Tuning Knobs）
# Date: 2026-06-18
#
# 切片调参旋钮单一来源。所有玩法数值在此，禁止散落硬编码（控制清单 Global 规则）。
class_name SliceConfig

# ── 棋盘（ADR-0006）──
const BOARD_SIZE: int = 8
const CELL_SIZE: float = 2.0

# ── 羁绊槽与充能（原型基线）──
const BOND_GAUGE_MAX: int = 10
const CHARGE_ADJACENT: int = 2      # 相邻攻击充能
const CHARGE_SOLO: int = 1          # 单独攻击充能
const ADJACENCY_DAMAGE_BONUS: int = 1

# ── 爆发伤害（原型基线：剑+剑=6 / 剑+炮=5）──
const BURST_DAMAGE := {
	"sword_sword": 6,
	"sword_gunner": 5,
	"generic": 4,                   # 通用协力强击框架
}
const BURST_RADIUS: int = 2         # 爆发命中 lead 周围切比雪夫半径内全部敌人（清屏级）

# ── 回合 ──
const ROUND_LIMIT: int = 8

# ── 攻击距离 ──
const GUNNER_MIN_RANGE: int = 2     # 炮手最小射程（GDD TR-BRS-005）

# ── 爆发演出计时（burst-presentation GDD / ADR-0008）──
const BURST_FREEZE_DURATION_MS: float = 60.0
const BURST_IMPACT_DURATION_MS: float = 200.0
const BURST_PANELS_IN_MS: float = 300.0
const BURST_NAME_MS: float = 600.0
const BURST_PANELS_OUT_MS: float = 240.0
const BURST_TIME_SCALE_FREEZE: float = 0.05

# ── 相机震动（ADR-0009）──
const BURST_CAMERA_SHAKE_INTENSITY: float = 8.0    # pixels
const BURST_CAMERA_SHAKE_DURATION_MS: float = 300.0
const SHAKE_OSCILLATIONS: int = 6

# ── 单位移动补间（ADR-0007）──
const MOVE_TWEEN_DURATION: float = 0.2

# ── 职业身份色（art-bible §4.4）+ 阵营 rim（§4.5）──
const CLASS_COLOR := {
	"swordsman": Color("#B23A48"),  # 绯红钢
	"gunner":    Color("#C0703A"),  # 火药褐橙
	"bulwark":   Color("#5E7488"),  # 钢青灰
	"medic":     Color("#4FA68A"),  # 薄荷青绿
}
const CLASS_SHAPE := {
	"swordsman": "box",
	"gunner":    "cylinder",
	"bulwark":   "box",
	"medic":     "capsule",
}
const CREW_RIM := Color("#FFE0B0")   # 暖
const ENEMY_RIM := Color("#7FAFFF")  # 冷
const ENEMY_DARKEN: float = 0.7      # albedo 压暗 ~30%

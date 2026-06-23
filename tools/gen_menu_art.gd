# 一次性原创美术生成器（程序化，零外部素材/零 IP）。
# 生成主菜单 5 张 PNG 到 assets/art/menu/：冰原雪山背景 + 三英雄发光剪影。
# 运行：godot --headless --script res://tools/gen_menu_art.gd
# 风格化（非写实立绘）；全部几何/渐变/剪影/发光由本脚本原创绘制。
extends SceneTree

const OUT_DIR := "res://assets/art/menu/"

func _initialize() -> void:
	_gen_background()
	_gen_midground()
	_gen_hero("hero_center.png", 600, 880, Color(1.0, 0.62, 0.28), "center")
	_gen_hero("hero_left.png", 480, 760, Color(0.45, 0.85, 0.45), "left")
	_gen_hero("hero_right.png", 480, 760, Color(0.45, 0.65, 1.0), "right")
	print("menu art generated -> ", OUT_DIR)
	quit()

# ── 工具 ──────────────────────────────────────────────────────

func _blend(img: Image, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	var dst := img.get_pixel(x, y)
	var a := c.a
	var out := Color(
		dst.r * (1.0 - a) + c.r * a,
		dst.g * (1.0 - a) + c.g * a,
		dst.b * (1.0 - a) + c.b * a,
		dst.a + a * (1.0 - dst.a))
	img.set_pixel(x, y, out)

func _save(img: Image, name: String) -> void:
	var err := img.save_png(OUT_DIR + name)
	if err != OK:
		push_error("save_png failed: %s (%d)" % [name, err])

# ── 背景：冰原雪山天际 ───────────────────────────────────────

func _gen_background() -> void:
	var w := 1280
	var h := 720
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	# 冷色天空渐变（上深蓝 → 地平线雪雾）
	var sky_top := Color(0.06, 0.12, 0.21)
	var sky_low := Color(0.66, 0.75, 0.82)
	for y in h:
		var t := pow(float(y) / float(h), 1.25)
		var sky := sky_top.lerp(sky_low, t)
		for x in w:
			img.set_pixel(x, y, sky)
	# 三层山脉（远→近，近层后绘=正确遮挡）
	var ranges := [
		{"base": 0.46, "amp": 0.09, "col": Color(0.52, 0.62, 0.72), "f": 0.013, "seed": 1.0},
		{"base": 0.55, "amp": 0.12, "col": Color(0.34, 0.43, 0.55), "f": 0.019, "seed": 5.0},
		{"base": 0.66, "amp": 0.15, "col": Color(0.19, 0.26, 0.37), "f": 0.027, "seed": 9.0},
	]
	for r in ranges:
		var base: float = r["base"]
		var amp: float = r["amp"]
		var col: Color = r["col"]
		var f: float = r["f"]
		var seed: float = r["seed"]
		for x in w:
			var rx := float(x)
			var ridge := base - amp * (0.5 * sin(rx * f + seed) + 0.3 * sin(rx * f * 2.3 + seed * 1.7) + 0.2 * sin(rx * f * 0.5 + seed))
			var ry := int(ridge * h)
			for y in range(maxi(ry, 0), h):
				# 山顶向天空略带雾化（深度感）+ 雪线提亮顶部
				var depth := clampf(float(y - ry) / (float(h) * 0.45), 0.0, 1.0)
				var snow := clampf(1.0 - depth * 4.0, 0.0, 1.0) * 0.35
				var c := col.lerp(sky_low, (1.0 - depth) * 0.35)
				c = c.lerp(Color(0.92, 0.95, 1.0), snow)
				img.set_pixel(x, y, c)
	# 前景雪地
	var ground := int(h * 0.9)
	for y in range(ground, h):
		var gt := float(y - ground) / float(h - ground)
		var snow_col := Color(0.74, 0.81, 0.88).lerp(Color(0.55, 0.63, 0.72), gt)
		for x in w:
			img.set_pixel(x, y, snow_col)
	# 暗角
	_vignette(img, 0.55)
	_save(img, "bg_far.png")

# ── 中景：遗迹巨碑轮廓 + 雾（透明 PNG）────────────────────────

func _gen_midground() -> void:
	var w := 1280
	var h := 720
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))   # 透明
	# 两座神秘巨碑/遗迹轮廓（深色 + 顶部冷光描边）
	_monolith(img, int(w * 0.5), int(h * 0.16), 120, int(h * 0.5))
	_monolith(img, int(w * 0.27), int(h * 0.34), 70, int(h * 0.32))
	_monolith(img, int(w * 0.73), int(h * 0.32), 80, int(h * 0.34))
	# 低空雾带
	var fog_y := int(h * 0.58)
	for y in range(fog_y, h):
		var ft := 1.0 - absf(float(y - fog_y) / float(h - fog_y) - 0.3)
		var a := clampf(ft, 0.0, 1.0) * 0.22
		for x in w:
			_blend(img, x, y, Color(0.82, 0.88, 0.94, a))
	_save(img, "bg_mid.png")

# 巨碑：深色竖矩形 + 顶部冷青描边 + 红色符纹点缀。
func _monolith(img: Image, cx: int, top: int, half_w: int, height: int) -> void:
	var dark := Color(0.09, 0.13, 0.19, 0.92)
	for y in range(top, top + height):
		for x in range(cx - half_w, cx + half_w):
			_blend(img, x, y, dark)
	# 顶部冷光描边
	for x in range(cx - half_w, cx + half_w):
		_blend(img, x, top, Color(0.5, 0.8, 0.95, 0.6))
		_blend(img, x, top + 1, Color(0.5, 0.8, 0.95, 0.35))
	# 中线红色符纹
	for y in range(top + int(height * 0.2), top + int(height * 0.7), 6):
		_blend(img, cx, y, Color(0.85, 0.25, 0.2, 0.7))
		_blend(img, cx - 1, y, Color(0.85, 0.25, 0.2, 0.4))

# ── 英雄剪影（透明 PNG，发光 + 暖/绿/蓝边光 + 武器暗示）──────

func _gen_hero(name: String, w: int, h: int, tint: Color, kind: String) -> void:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx := float(w) * 0.5
	var body_top := Color(0.16, 0.18, 0.23)
	var body_bot := Color(0.07, 0.08, 0.11)
	for y in h:
		var ny := float(y) / float(h)
		var hw := _hero_halfwidth(ny, float(w))
		for x in w:
			var dx := absf(float(x) - cx)
			# 外发光（剪影外侧柔光）
			var glow_band := hw + float(w) * 0.07
			if dx > hw and dx <= glow_band and hw > 0.0:
				var ga := (1.0 - (dx - hw) / (glow_band - hw)) * 0.22
				_blend(img, x, y, Color(tint.r, tint.g, tint.b, ga))
			# 剪影本体
			if dx <= hw and hw > 0.0:
				var body := body_top.lerp(body_bot, ny)
				# 边缘描边上色（冷暖/职业色）
				var edge := clampf((dx - (hw - float(w) * 0.05)) / (float(w) * 0.05), 0.0, 1.0)
				body = body.lerp(tint, edge * 0.55)
				_blend(img, x, y, Color(body.r, body.g, body.b, 1.0))
	_hero_weapon(img, w, h, tint, kind)
	_save(img, name)

# 英雄轮廓半宽（按归一化 y）：头 + 肩 + 斗篷/铠甲下摆。
func _hero_halfwidth(ny: float, w: float) -> float:
	var hw := 0.0
	# 头部圆
	var head_y := 0.11
	var head_r := 0.085
	if ny >= head_y - head_r and ny <= head_y + head_r:
		var dyh := (ny - head_y) / head_r
		hw = maxf(hw, sqrt(maxf(0.0, 1.0 - dyh * dyh)) * head_r * w)
	# 躯干/铠甲（颈→肩→下摆）
	if ny >= 0.17:
		var body := 0.0
		if ny < 0.30:
			body = lerpf(0.06, 0.20, (ny - 0.17) / 0.13)   # 颈到肩展宽
		elif ny < 0.55:
			body = lerpf(0.20, 0.16, (ny - 0.30) / 0.25)   # 收腰
		else:
			body = lerpf(0.16, 0.22, clampf((ny - 0.55) / 0.43, 0.0, 1.0))  # 下摆外扩
		if ny > 0.97:
			body *= maxf(0.0, (1.0 - ny) / 0.03)            # 收底
		hw = maxf(hw, body * w)
	return hw

# 武器暗示：中央暖剑、左侧绿弓弧、右侧蓝法杖 + 球。
func _hero_weapon(img: Image, w: int, h: int, tint: Color, kind: String) -> void:
	var cx := float(w) * 0.5
	if kind == "center":
		# 暖色长剑（斜向）+ 辉光
		var x0 := cx + w * 0.20
		var y0 := h * 0.42
		var x1 := cx + w * 0.34
		var y1 := h * 0.96
		_glow_line(img, x0, y0, x1, y1, Color(1.0, 0.72, 0.32), 5.0)
	elif kind == "left":
		# 绿色弓弧
		for i in 80:
			var t := float(i) / 79.0
			var yy := h * (0.30 + 0.42 * t)
			var xx := cx - w * 0.26 + sin(t * PI) * w * 0.10
			_glow_dot(img, xx, yy, Color(0.5, 1.0, 0.5), 4.0)
	else:
		# 蓝色法杖 + 顶端能量球
		_glow_line(img, cx + w * 0.22, h * 0.22, cx + w * 0.22, h * 0.95, Color(0.6, 0.8, 1.0), 4.0)
		_glow_dot(img, cx + w * 0.22, h * 0.18, Color(0.7, 0.85, 1.0), 16.0)
		_glow_dot(img, cx + w * 0.22, h * 0.18, Color(0.95, 0.4, 0.4), 7.0)

func _glow_dot(img: Image, cx: float, cy: float, col: Color, radius: float) -> void:
	var r := int(ceil(radius))
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var d := sqrt(float(dx * dx + dy * dy))
			if d <= radius:
				var a := (1.0 - d / radius) * col.a
				_blend(img, int(cx) + dx, int(cy) + dy, Color(col.r, col.g, col.b, a))

func _glow_line(img: Image, x0: float, y0: float, x1: float, y1: float, col: Color, width: float) -> void:
	var steps := int(maxf(absf(x1 - x0), absf(y1 - y0))) + 1
	for i in steps:
		var t := float(i) / float(steps)
		var x := lerpf(x0, x1, t)
		var y := lerpf(y0, y1, t)
		_glow_dot(img, x, y, col, width)

func _vignette(img: Image, strength: float) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var cx := float(w) * 0.5
	var cy := float(h) * 0.5
	var maxd := sqrt(cx * cx + cy * cy)
	for y in h:
		for x in w:
			var d := sqrt(pow(float(x) - cx, 2.0) + pow(float(y) - cy, 2.0)) / maxd
			var a := clampf((d - 0.55) / 0.45, 0.0, 1.0) * strength
			if a > 0.0:
				_blend(img, x, y, Color(0.02, 0.04, 0.07, a))

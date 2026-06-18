# VERTICAL SLICE - HEADLESS VERIFICATION（无需交互试玩）
# 单独实测 ADR-0008 最高风险假设：Engine.time_scale=0.05（世界定格）时，
# 带 set_ignore_time_scale(true) 的演出 Tween 是否仍按【墙钟】推进，不被拖慢 20×。
#
# 这是 [VS验证] 墙钟条背后的同一个判定，抽成可自动化的无头测试。
# 运行（需 Godot 4.6.3）：
#   godot --headless --path prototypes/grand-line-gambit-vertical-slice --script res://verify_time_scale.gd
# 退出码：0 = PASS，1 = FAIL/不确定（便于 CI 接入）。
extends SceneTree

# 与 slice_config.gd 一致的演出时长（P1 FREEZE + P2 PANELS_IN + P3 BURST_NAME）
const FREEZE_MS := 60.0
const PANELS_IN_MS := 300.0
const NAME_MS := 600.0
const TIME_SCALE_FREEZE := 0.05

func _initialize() -> void:
	var runner := Node.new()
	root.add_child(runner)          # 入树后才能 create_tween()
	_verify(runner)

func _verify(runner: Node) -> void:
	var expected_ms := int(FREEZE_MS + PANELS_IN_MS + NAME_MS)   # 960
	var if_broken_ms := int(expected_ms / TIME_SCALE_FREEZE)     # 19200

	Engine.time_scale = TIME_SCALE_FREEZE   # 世界减速（定格）
	var t0 := Time.get_ticks_msec()

	var tw := runner.create_tween()
	tw.set_ignore_time_scale(true)                      # ★ 被测 API
	tw.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	tw.tween_interval((FREEZE_MS + PANELS_IN_MS + NAME_MS) / 1000.0)
	await tw.finished

	var elapsed := Time.get_ticks_msec() - t0
	Engine.time_scale = 1.0

	print("[VS验证·headless] set_ignore_time_scale 墙钟=%d ms（期望≈%d ms / 若失效≈%d ms）" % [
		elapsed, expected_ms, if_broken_ms])
	print("  引擎版本：%s" % Engine.get_version_info().get("string", "unknown"))

	var code := 1
	if elapsed >= int(expected_ms * 0.6) and elapsed <= int(expected_ms * 3.0):
		print("  结果：✅ PASS — Tween 按墙钟推进，未被 time_scale=0.05 拖慢 → ADR-0008 风险可下调")
		code = 0
	elif elapsed >= int(if_broken_ms * 0.6):
		print("  结果：❌ FAIL — 演出被 time_scale 拖慢约 20× → 须走 ADR-0008 回退方案 2（手动 unscaled delta）")
	else:
		print("  结果：⚠️ 不确定 elapsed=%d ms — 人工核对（既不接近 960 也不接近 19200）" % elapsed)

	quit(code)

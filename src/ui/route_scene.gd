# 战斗之间的中枢（白盒，Control）。按 RunManager.current_phase 分支：
# IDLE→起航直发首岛；RECRUITING→三选一卡；RUN_END→结果页+重新出航。
# 招募卡只显示「职业 · 名 · 台词」（不显数值，GDD）。
class_name RouteScene
extends Control

func _ready() -> void:
	match RunManager.current_phase:
		"IDLE":
			_begin_run()
		"RECRUITING":
			_show_recruit_offers()
		"RUN_END":
			_show_run_end()
		_:
			# DEPLOYING/BATTLE 不应停留于此；防御性直接部署当前 roster。
			_deploy_current_roster()

# 起航：填起始编制 → 直接部署首岛（无招募）。
func _begin_run() -> void:
	RunManager.start_run()
	_deploy_current_roster()

# 收集 roster 全员 id 提交部署（A 全员自动部署）。
func _deploy_current_roster() -> void:
	var ids: Array = []
	for c in RunManager.get_roster():
		ids.append((c as CrewDefinition).id)
	RunManager.confirm_deploy(ids)

# 三选一招募卡。候选为空 → 跳过招募直接部署下一岛。
func _show_recruit_offers() -> void:
	var offers := RunManager.get_recruit_offers()
	if offers.is_empty():
		_deploy_current_roster()
		return
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	add_child(box)
	var title := Label.new()
	title.text = "选择一名船员加入"
	box.add_child(title)
	for o in offers:
		var crew := o as CrewDefinition
		var btn := Button.new()
		btn.text = "%s · %s · %s" % [crew.unit_class, crew.display_name, crew.battle_cry]
		btn.pressed.connect(_on_recruit_chosen.bind(crew.id))
		box.add_child(btn)

func _on_recruit_chosen(unit_id: String) -> void:
	RunManager.confirm_recruit(unit_id)
	_deploy_current_roster()

# run-end：出航成功 / 全员阵亡 + 重新出航。
func _show_run_end() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	add_child(box)
	var result := Label.new()
	result.text = "出航成功!" if RunManager.last_run_won else "全员阵亡…"
	box.add_child(result)
	var restart := Button.new()
	restart.text = "重新出航"
	restart.pressed.connect(_on_restart_pressed)
	box.add_child(restart)

func _on_restart_pressed() -> void:
	RunManager.start_run()
	_deploy_current_roster()

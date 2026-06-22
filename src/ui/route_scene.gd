# 战斗之间的中枢（白盒，Control）。按 RunManager.current_phase 分支：
# IDLE→起航直发首岛；RECRUITING→三选一卡；RUN_END→结果页+重新出航；
# DEPLOYING→roster≤DEPLOY_LIMIT 自动全员 / >DEPLOY_LIMIT 手动选人（子项目 B）。
# 招募卡显示「职业·名·台词」、选人卡显示「职业·名」（均不显数值，GDD）。
class_name RouteScene
extends Control

var _selected_ids: Array[String] = []        # 本次部署已选 crew id
var _deploy_buttons: Dictionary = {}          # crew_id → 选人 toggle Button
var _deploy_status_label: Label = null        # "已选 X/4"
var _deploy_confirm_button: Button = null     # 「确认部署」
var _notice_continue_button: Button = null    # 阵亡通知卡「继续」
var _active_screen := ""                       # 当前展示界面（notice/recruit/run_end/deploy；测试可观测）

func _ready() -> void:
	match RunManager.current_phase:
		"IDLE":
			_begin_run()
		"RECRUITING":
			_notice_then(_show_recruit_offers)
		"RUN_END":
			_notice_then(_show_run_end)
		_:
			_enter_deploy()

# 起航：填起始编制 → 进入部署。
func _begin_run() -> void:
	RunManager.start_run()
	_enter_deploy()

# 部署统一入口：roster ≤ DEPLOY_LIMIT 自动全员；否则手动选人。
func _enter_deploy() -> void:
	_clear_ui()
	if RunManager.get_roster().size() <= RunManager.DEPLOY_LIMIT:
		_auto_deploy_all()
	else:
		_show_deploy_selection()

# 清本中枢已建子节点 + 重置选人状态（避免阶段叠加显示）。
func _clear_ui() -> void:
	for child in get_children():
		child.queue_free()
	_selected_ids.clear()
	_deploy_buttons.clear()
	_deploy_status_label = null
	_deploy_confirm_button = null
	_notice_continue_button = null
	_active_screen = ""

# 收集 roster 全员 id 提交部署（≤DEPLOY_LIMIT 时自动全员）。
func _auto_deploy_all() -> void:
	var ids: Array[String] = []
	for c in RunManager.get_roster():
		ids.append(c.id)
	RunManager.confirm_deploy(ids)

# 手动选人界面（白盒，只用按钮，不显数值）。roster 按招募顺序（自然序）。
func _show_deploy_selection() -> void:
	_active_screen = "deploy"
	var box := VBoxContainer.new()
	add_child(box)
	box.set_anchors_preset(Control.PRESET_CENTER)   # M-3：先 add_child 再设锚点
	var title := Label.new()
	title.text = "选择出战船员（最多 %d 名）" % RunManager.DEPLOY_LIMIT
	box.add_child(title)
	for c in RunManager.get_roster():
		var btn := Button.new()
		btn.toggle_mode = true
		btn.text = "%s · %s" % [c.unit_class, c.display_name]
		btn.toggled.connect(_on_deploy_toggle.bind(c.id))
		box.add_child(btn)
		_deploy_buttons[c.id] = btn
	_deploy_status_label = Label.new()
	box.add_child(_deploy_status_label)
	_deploy_confirm_button = Button.new()
	_deploy_confirm_button.text = "确认部署"
	_deploy_confirm_button.pressed.connect(_on_deploy_confirm)
	box.add_child(_deploy_confirm_button)
	_refresh_deploy_state()

# toggle 选中/取消；已满 DEPLOY_LIMIT 时拒绝新增（回弹，不发信号防递归）。
func _on_deploy_toggle(pressed: bool, crew_id: String) -> void:
	if pressed:
		if _selected_ids.size() >= RunManager.DEPLOY_LIMIT:
			(_deploy_buttons[crew_id] as Button).set_pressed_no_signal(false)
			return
		_selected_ids.append(crew_id)
	else:
		_selected_ids.erase(crew_id)
	_refresh_deploy_state()

# 刷新「已选 X/4」与确认键可用性（0 人禁用）。
func _refresh_deploy_state() -> void:
	_deploy_status_label.text = "已选 %d/%d" % [_selected_ids.size(), RunManager.DEPLOY_LIMIT]
	_deploy_confirm_button.disabled = _selected_ids.is_empty()

# 确认部署 → 后端按所选 id 过滤 roster 填 pending_deploy → 进战斗。
func _on_deploy_confirm() -> void:
	if _selected_ids.is_empty():
		return
	RunManager.confirm_deploy(_selected_ids.duplicate())

# 战后门控：本场有阵亡 → 先弹折损通知卡，「继续」后再进 next；否则直接 next。
func _notice_then(next: Callable) -> void:
	if RunManager.get_pending_downed_notice().is_empty():
		next.call()
	else:
		_show_downed_notice(next)

# 折损通知卡（白盒）：列出本场阵亡船员「职业·名 在第 N 岛阵亡」+「继续」。
func _show_downed_notice(next: Callable) -> void:
	_active_screen = "notice"
	var box := VBoxContainer.new()
	add_child(box)
	box.set_anchors_preset(Control.PRESET_CENTER)
	var title := Label.new()
	title.text = "折损通知"
	box.add_child(title)
	var island_no := RunManager.current_island_index + 1
	for crew_id in RunManager.get_pending_downed_notice():
		var def := UnitDataManager.get_unit(crew_id)
		if def is CrewDefinition:
			var crew := def as CrewDefinition
			var line := Label.new()
			line.text = "%s · %s 在第 %d 岛阵亡" % [crew.unit_class, crew.display_name, island_no]
			box.add_child(line)
	_notice_continue_button = Button.new()
	_notice_continue_button.text = "继续"
	_notice_continue_button.pressed.connect(_on_notice_continue.bind(next))
	box.add_child(_notice_continue_button)

func _on_notice_continue(next: Callable) -> void:
	RunManager.clear_downed_notice()
	_clear_ui()
	next.call()

# 三选一招募卡。候选为空 → 跳过招募直接进入部署。
func _show_recruit_offers() -> void:
	var offers := RunManager.get_recruit_offers()
	if offers.is_empty():
		_enter_deploy()
		return
	_active_screen = "recruit"
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	add_child(box)
	var title := Label.new()
	title.text = "选择一名船员加入"
	box.add_child(title)
	for o in offers:
		var crew := o as CrewDefinition
		var btn := Button.new()
		var eq := RunManager.get_offer_equipment(crew.id)
		var eq_text := ("" if eq == null else " · " + _equipment_summary(eq))
		btn.text = "%s · %s · %s%s" % [crew.unit_class, crew.display_name, crew.battle_cry, eq_text]
		btn.pressed.connect(_on_recruit_chosen.bind(crew.id))
		box.add_child(btn)

func _on_recruit_chosen(unit_id: String) -> void:
	RunManager.confirm_recruit(unit_id)
	_enter_deploy()

# 装备白盒摘要："名 +N攻 +N血 ..."（仅列非零增量）。
func _equipment_summary(eq: EquipmentDefinition) -> String:
	var parts: Array[String] = []
	if eq.hp_bonus != 0:
		parts.append("%+d血" % eq.hp_bonus)
	if eq.damage_bonus != 0:
		parts.append("%+d攻" % eq.damage_bonus)
	if eq.range_bonus != 0:
		parts.append("%+d射程" % eq.range_bonus)
	if eq.move_bonus != 0:
		parts.append("%+d移动" % eq.move_bonus)
	return "%s %s" % [eq.display_name, " ".join(parts)]

# run-end：结果 + 运行总结（抵达岛数 / 幸存 / 本航阵亡）+ 重新出航。
func _show_run_end() -> void:
	_active_screen = "run_end"
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	add_child(box)
	var result := Label.new()
	result.text = "出航成功!" if RunManager.last_run_won else "全员阵亡…"
	box.add_child(result)
	var reached := Label.new()
	reached.text = "抵达第 %d 岛 / 共 %d" % [RunManager.current_island_index + 1, RunManager.ISLAND_COUNT_MAX]
	box.add_child(reached)
	var survivors := Label.new()
	survivors.text = "幸存船员：%d 名" % RunManager.get_roster().size()
	box.add_child(survivors)
	for c in RunManager.get_roster():
		var line := Label.new()
		line.text = "  %s · %s" % [c.unit_class, c.display_name]
		box.add_child(line)
	var fallen := RunManager.get_downed_this_run()
	if not fallen.is_empty():
		var fallen_title := Label.new()
		fallen_title.text = "本航阵亡：%d 名" % fallen.size()
		box.add_child(fallen_title)
		for fid in fallen:
			var def := UnitDataManager.get_unit(fid)
			if def is CrewDefinition:
				var crew := def as CrewDefinition
				var line := Label.new()
				line.text = "  %s · %s" % [crew.unit_class, crew.display_name]
				box.add_child(line)
	var restart := Button.new()
	restart.text = "重新出航"
	restart.pressed.connect(_on_restart_pressed)
	box.add_child(restart)

func _on_restart_pressed() -> void:
	RunManager.start_run()
	_enter_deploy()

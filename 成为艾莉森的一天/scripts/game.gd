extends Node2D

## 游戏主控制器 — 区域切换、地形与道具（SceneLayout 生成）、时段色调、
## 蘑菇刷新、午夜流程、结局路由。

## preload 而非全局类名：避免依赖全局脚本类缓存（headless/编辑器刷新前不注册）
const SceneLayout := preload("res://scripts/systems/scene_layout.gd")
const HeavenSession := preload("res://scripts/systems/ai_heaven_session.gd")

@onready var player: CharacterBody2D = $Player
@onready var daylight: CanvasModulate = $DaylightModulate
@onready var areas: Node2D = $Areas

var _world_rect: Rect2
var _mushroom_timer: Timer
var _auto_advance_timer: Timer
var _pending_action: String = ""
var _midnight_panel: CanvasLayer
var _midnight_label: Label
var _midnight_btn: Button
var _door_cooldown: bool = false
## 午夜两阶段：false=待审判（点入睡先跑天复盘），true=已展示回顾（再点才真的睡）
var _judgment_shown: bool = false
var _judgment_running: bool = false


func _ready() -> void:
	# 烘焙工具实例化本场景仅用于序列化，跳过游戏初始化
	if SceneLayout.baking:
		return

	_world_rect = Rect2(0, 0, SceneLayout.WORLD_W * SceneLayout.TILE_SIZE, SceneLayout.WORLD_H * SceneLayout.TILE_SIZE)

	# 地形与道具：已烘焙（main.tscn 有内容）则跳过，空白区域运行时兜底生成
	SceneLayout.paint_area_grounds(areas)
	SceneLayout.build_all_props(areas)

	if player and player.has_method("setup_camera_limits"):
		player.setup_camera_limits(_world_rect)

	var bus = get_node("/root/EventBus")
	bus.time_changed.connect(_on_time_changed)
	bus.loop_reset.connect(_on_loop_reset)
	bus.door_entered.connect(func(area_id: String, spawn: String) -> void: switch_area(area_id, spawn, true))
	bus.game_action.connect(_on_game_action)
	bus.sell_requested.connect(_on_sell_requested)
	bus.dialogue_ended.connect(_on_dialogue_ended)
	bus.day_started.connect(_on_day_started)
	bus.midnight_reached.connect(_on_midnight)
	# 午夜开始对话（如塔楼问答）时收起入睡面板，避免遮挡
	bus.dialogue_started.connect(func() -> void:
		if _midnight_panel:
			_midnight_panel.hide())

	_mushroom_timer = Timer.new()
	_mushroom_timer.one_shot = true
	_mushroom_timer.timeout.connect(_spawn_mushroom)
	add_child(_mushroom_timer)
	_schedule_next_mushroom()

	_auto_advance_timer = Timer.new()
	_auto_advance_timer.one_shot = false
	_auto_advance_timer.wait_time = 60.0
	_auto_advance_timer.timeout.connect(_auto_advance)
	add_child(_auto_advance_timer)
	_auto_advance_timer.start()

	_build_midnight_panel()
	switch_area("plaza", "PlayerSpawn")
	_switch_background("morning")

	# 第一天清晨：塔罗占卜
	get_node("TarotUI").open.call_deferred()


# ---------------------------------------------------------------------------
# 区域切换
# ---------------------------------------------------------------------------
func switch_area(area_id: String, spawn_name: String = "", from_door: bool = false) -> void:
	# 切换瞬间玩家坐标可能同时落在两扇门的感应圈内，加冷却防止连锁触发
	if _door_cooldown:
		return
	_door_cooldown = true
	get_tree().create_timer(0.5).timeout.connect(func() -> void: _door_cooldown = false)
	for area in areas.get_children():
		var is_current: bool = area.name.to_snake_case() == area_id or area.name == area_id
		area.visible = is_current
		# 物理回调中禁用碰撞体会报错，必须延迟到帧末
		area.set_deferred("process_mode",
			Node.PROCESS_MODE_INHERIT if is_current else Node.PROCESS_MODE_DISABLED)
	print("[game] switch_area -> ", area_id, " spawn=", spawn_name)

	var area := _find_area(area_id)
	if area == null:
		return
	if spawn_name != "":
		var spawn := area.get_node_or_null(spawn_name) as Marker2D
		if spawn and player:
			player.velocity = Vector2.ZERO
			player.global_position = spawn.global_position

	var gm = get_node("/root/GameManager")
	# visit 打点：只记玩家主动穿门（循环重置/开局传送不算"访问"，否则 visit 型预言会被白送顺从）
	if from_door and gm.current_area != area_id:
		gm.record_heaven_event("visit", "玩家穿过门，来到了 %s" % area_id, [area_id])
	gm.current_area = area_id
	get_node("/root/EventBus").area_changed.emit(area_id)


func _find_area(area_id: String) -> Node2D:
	for area in areas.get_children():
		if area.name.to_snake_case() == area_id or area.name == area_id:
			return area
	return null


# ---------------------------------------------------------------------------
# 时段色调
# ---------------------------------------------------------------------------
func _switch_background(time_id: String) -> void:
	if not daylight:
		return
	var color: Color
	match time_id:
		"morning":   color = Color(1.0, 0.92, 0.85, 1.0)
		"afternoon": color = Color(1.0, 1.0, 1.0, 1.0)
		"evening":   color = Color(1.0, 0.70, 0.48, 1.0)
		"night":     color = Color(0.30, 0.30, 0.55, 1.0)
		"midnight":  color = Color(0.15, 0.15, 0.30, 1.0)
	var tween = create_tween()
	tween.tween_property(daylight, "color", color, 1.0)


# ---------------------------------------------------------------------------
# 蘑菇
# ---------------------------------------------------------------------------
func _schedule_next_mushroom() -> void:
	_mushroom_timer.wait_time = randf_range(3.0, 8.0)
	_mushroom_timer.start()


func _mushroom_pool() -> Node2D:
	return areas.get_node_or_null("Plaza/Mushrooms")


func _spawn_mushroom() -> void:
	var pool := _mushroom_pool()
	if pool:
		var candidates: Array[Node] = []
		for child in pool.get_children():
			if child is Area2D and not child.visible:
				candidates.append(child)
		if not candidates.is_empty():
			var shroom: Area2D = candidates.pick_random()
			var rx := randf_range(_world_rect.position.x + 64, _world_rect.end.x - 64)
			var ry := randf_range(_world_rect.position.y + 64, _world_rect.end.y - 64)
			shroom.global_position = Vector2(rx, ry)
			shroom.show()
			shroom.monitoring = true
	_schedule_next_mushroom()


# ---------------------------------------------------------------------------
# 时间与午夜
# ---------------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("advance_time"):
		if player and player._movement_locked:
			return
		_advance_time()


func _advance_time() -> void:
	get_node("/root/TimeManager").advance_time()
	_auto_advance_timer.stop()
	_auto_advance_timer.start()


func _auto_advance() -> void:
	var tm = get_node("/root/TimeManager")
	if not tm.is_midnight():
		tm.advance_time()


func _on_time_changed(time_id: String) -> void:
	_switch_background(time_id)
	if time_id == "midnight":
		_auto_advance_timer.stop()


func _on_midnight() -> void:
	# 重置两阶段状态：先审判复盘，再入睡
	_judgment_shown = false
	_judgment_running = false
	_refresh_midnight_panel()
	_midnight_panel.show()


## 午夜面板状态（设计门控：必须租了树屋才能入睡结束今天）。
## 未租房：提示 + 禁用按钮；午夜仍可去树屋区现场租房，租后对话结束面板自动刷新解锁。
func _refresh_midnight_panel() -> void:
	var gm = get_node("/root/GameManager")
	if gm.treehouse_rented:
		_midnight_label.text = "—— 午夜已至 ——\n石巢塔楼的方向传来钟声……"
		_midnight_btn.text = "入睡（结束今天）"
		_midnight_btn.disabled = false
	else:
		_midnight_label.text = "—— 午夜已至 ——\n你没有可归的住处，无法入睡。\n（去树屋区租一间树屋吧。）"
		_midnight_btn.text = "入睡（需要一间树屋）"
		_midnight_btn.disabled = true


func _build_midnight_panel() -> void:
	_midnight_panel = CanvasLayer.new()
	_midnight_panel.layer = 15
	add_child(_midnight_panel)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.offset_left = -220
	panel.offset_right = 220
	panel.offset_top = 52
	panel.offset_bottom = 130
	_midnight_panel.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	_midnight_label = Label.new()
	_midnight_label.text = "—— 午夜已至 ——\n石巢塔楼的方向传来钟声……"
	_midnight_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_midnight_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_midnight_label.custom_minimum_size = Vector2(400, 0)
	_midnight_label.add_theme_font_size_override("font_size", 15)
	vbox.add_child(_midnight_label)

	_midnight_btn = Button.new()
	_midnight_btn.text = "入睡（结束今天）"
	_midnight_btn.focus_mode = Control.FOCUS_NONE
	_midnight_btn.pressed.connect(_do_sleep)
	vbox.add_child(_midnight_btn)

	_midnight_panel.hide()


## 入睡按钮：两阶段。第一次点击 → 审判面具复盘（加载态→展示天的回顾）；
## 第二次点击 → 真正结束今天。AI 不可用时 judgment 内部回落固定文案。
func _do_sleep() -> void:
	if _judgment_running:
		return
	if not get_node("/root/GameManager").treehouse_rented:
		return   # 设计门控：未租房不能入睡（按钮已禁用，此处兜底）
	if not _judgment_shown:
		_run_judgment()
	else:
		_finish_sleep()


func _run_judgment() -> void:
	_judgment_running = true
	_midnight_panel.show()   # 对话内 pass_night 路径也会走到这里，确保面板可见
	_midnight_label.text = "—— 天在审视这一天…… ——"
	_midnight_btn.disabled = true
	var gm = get_node("/root/GameManager")
	var session := HeavenSession.new()
	session.setup(self)
	var result: Dictionary = await session.judgment()
	_judgment_running = false
	_judgment_shown = true
	var text := str(result.get("day_summary", ""))
	# 终结提示（终局裁决切片将接管真正的结局流程，当前仅提示）
	if bool(result.get("should_end_approved", false)):
		text += "\n\n—— 天低语：这场循环，该迎来终章了。"
	elif int(gm.current_day) >= gm.HARD_DAY_CAP:
		text += "\n\n—— 第 20 天的钟声格外沉重。循环已抵达它的尽头。"
	_midnight_label.text = text
	_midnight_btn.text = "入睡（结束今天）"
	_midnight_btn.disabled = false


func _finish_sleep() -> void:
	_midnight_panel.hide()
	_judgment_shown = false
	var gm = get_node("/root/GameManager")
	# 午夜结算：态度平移规则表（§3.4，纯 Godot 计算，AI 已离场）
	gm.apply_heaven_rules()
	gm.reset_loop()


# ---------------------------------------------------------------------------
# 剧情动作路由 / 结局
# ---------------------------------------------------------------------------
## 对话内玩家主动提出卖东西：记下动作并结束当前对话，
## 走 _on_dialogue_ended 的 "sell" 分支打开售卖面板。
func _on_sell_requested() -> void:
	_pending_action = "sell"
	get_node("/root/EventBus").dialogue_exit_requested.emit()


func _on_game_action(action_id: String) -> void:
	if action_id.begins_with("rental:"):
		get_node("RentalUI").open(action_id.trim_prefix("rental:"))
	else:
		# ending:* / pass_night 等对话结束后统一处理
		_pending_action = action_id


func _on_dialogue_ended() -> void:
	if _pending_action != "":
		var action := _pending_action
		_pending_action = ""
		if action.begins_with("ending:"):
			get_node("EndingUI").show_ending(action.trim_prefix("ending:"))
			return
		elif action == "pass_night":
			_do_sleep()
			return
		elif action == "sell":
			get_node("SellPanel").open()
			return
	# 午夜入睡面板会被 dialogue_started 顶掉（任何对话/界面打开都触发），
	# 对话结束后若仍是午夜则补回——否则玩家卡死在午夜（T 键无效、自动推进已停）。
	# 补回时刷新面板状态：午夜现场租房后，入睡按钮应即时解锁。
	var gm = get_node("/root/GameManager")
	if gm.current_time == "midnight" and not _judgment_running and _midnight_panel:
		if not _judgment_shown:
			_refresh_midnight_panel()
		_midnight_panel.show()


# ---------------------------------------------------------------------------
# 循环重置
# ---------------------------------------------------------------------------
func _on_day_started(_day: int) -> void:
	# 每天清晨抽塔罗牌
	await get_tree().create_timer(0.6).timeout
	get_node("TarotUI").open()


func _on_loop_reset() -> void:
	_midnight_panel.hide()
	get_node("/root/TimeManager").reset_to_morning()
	_auto_advance_timer.stop()
	_auto_advance_timer.start()
	_refresh_collectibles()
	switch_area("plaza", "PlayerSpawn")
	_switch_background("morning")


func _refresh_collectibles() -> void:
	# 蘑菇（随机刷）与浆果丛（固定点）两个池都在每日循环重置时重新出现
	for pool_name in ["Mushrooms", "Berries"]:
		var pool := areas.get_node_or_null("Plaza/%s" % pool_name)
		if pool:
			for child in pool.get_children():
				if child is Area2D and child.is_in_group("collectible"):
					child.show()
					child.monitoring = true

extends Node2D

## 游戏主场景控制器 — 初始化、时间推进、午夜循环、蘑菇刷新、背景切换

@onready var player: CharacterBody2D = $Player
@onready var padwin: CharacterBody2D = $Padwin

var _world_rect: Rect2 = Rect2()
var _mushroom_timer: Timer
var _auto_advance_timer: Timer


func _ready() -> void:
	# 计算世界边界（基于背景精灵的实际位置和缩放）
	var bg: Sprite2D = $Plaza/Background
	if bg and bg.texture:
		var tex_size: Vector2 = bg.texture.get_size()
		var scaled: Vector2 = tex_size * bg.scale
		_world_rect = Rect2(bg.position, scaled)

	# 设定玩家和相机边界
	if player and player.has_method("setup_camera_limits"):
		player.setup_camera_limits(_world_rect)

	# 放置玩家和 NPC
	var spawn = $Plaza/PlayerSpawn
	if spawn and player:
		player.global_position = spawn.global_position
	var npc_spawn = $Plaza/NPCSpawn
	if npc_spawn and padwin:
		padwin.global_position = npc_spawn.global_position

	# 监听时间信号
	get_node("/root/EventBus").time_changed.connect(_on_time_changed)
	get_node("/root/EventBus").loop_reset.connect(_on_loop_reset)

	# 将对话选择路由到 Padwin NPC
	var bus = get_node("/root/EventBus")
	if padwin and padwin.has_method("on_choice_made"):
		bus.dialogue_choice_made.connect(padwin.on_choice_made)

	# 蘑菇随机刷新定时器
	_mushroom_timer = Timer.new()
	_mushroom_timer.one_shot = true
	_mushroom_timer.timeout.connect(_spawn_mushroom)
	add_child(_mushroom_timer)
	_schedule_next_mushroom()

	# 30 秒自动推进时间定时器
	_auto_advance_timer = Timer.new()
	_auto_advance_timer.one_shot = false
	_auto_advance_timer.wait_time = 30.0
	_auto_advance_timer.timeout.connect(_auto_advance)
	add_child(_auto_advance_timer)
	_auto_advance_timer.start()

	# 初始背景
	_switch_background("morning")


func _switch_background(time_id: String) -> void:
	var bg: Sprite2D = $Plaza/Background
	if not bg:
		return
	# 当前所有时段统一使用 forest_draft.png
	# 后续替换为不同时段的纹理时，在此 match 分支中指定不同 texture
	match time_id:
		"morning", "afternoon":
			pass  # 保持当前纹理
		"evening", "night":
			pass
		"midnight":
			pass


func _schedule_next_mushroom() -> void:
	_mushroom_timer.wait_time = randf_range(3.0, 10.0)
	_mushroom_timer.start()


func _spawn_mushroom() -> void:
	var candidates: Array[Node] = []
	for child in $Plaza/Mushrooms.get_children():
		if child is Area2D and not child.visible:
			candidates.append(child)
	if candidates.is_empty():
		_schedule_next_mushroom()
		return

	var shroom: Area2D = candidates.pick_random()
	var rx := randf_range(_world_rect.position.x + 48, _world_rect.end.x - 48)
	var ry := randf_range(_world_rect.position.y + 48, _world_rect.end.y - 48)
	shroom.global_position = Vector2(rx, ry)
	shroom.show()
	shroom.monitoring = true
	_schedule_next_mushroom()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("advance_time"):
		_advance_time()


func _advance_time() -> void:
	get_node("/root/TimeManager").advance_time()
	# 重置 30 秒计时器
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
		await get_tree().create_timer(3.0).timeout
		get_node("/root/GameManager").reset_loop()


func _on_loop_reset() -> void:
	# 重置 TimeManager 的索引 + 30 秒计时器
	get_node("/root/TimeManager").reset_to_morning()
	_auto_advance_timer.stop()
	_auto_advance_timer.start()
	# 刷新采集物
	_refresh_collectibles()
	# 放回出生点
	var spawn = $Plaza/PlayerSpawn
	if spawn and player:
		player.global_position = spawn.global_position
	# 背景切回清晨
	_switch_background("morning")


func _refresh_collectibles() -> void:
	for child in $Plaza/Mushrooms.get_children():
		if child is Area2D and child.is_in_group("collectible"):
			child.show()
			child.monitoring = true
	_schedule_next_mushroom()

extends Node2D

## 游戏主场景控制器 — 初始化、时间推进、午夜循环、蘑菇刷新

@onready var player: CharacterBody2D = $Player
@onready var padwin: CharacterBody2D = $Padwin

var _world_rect: Rect2 = Rect2()
var _mushroom_timer: Timer
var _mushroom_scene: PackedScene


func _ready() -> void:
	# 计算世界边界（基于背景精灵的实际位置和缩放）
	var bg: Sprite2D = $Plaza/Background
	if bg and bg.texture:
		var tex_size: Vector2 = bg.texture.get_size()
		var scaled: Vector2 = tex_size * bg.scale
		_world_rect = Rect2(bg.position, scaled)
	else:
		_world_rect = Rect2(0, 0, 3456, 648)

	# 设定玩家和相机边界
	if player and player.has_method("setup_camera_limits"):
		player.setup_camera_limits(_world_rect)

	# 将玩家放到出生点
	var spawn = $Plaza/PlayerSpawn
	if spawn and player:
		player.global_position = spawn.global_position

	# 将 Padwin 放到 NPC 出生点
	var npc_spawn = $Plaza/NPCSpawn
	if npc_spawn and padwin:
		padwin.global_position = npc_spawn.global_position

	# 监听时间信号
	get_node("/root/EventBus").time_changed.connect(_on_time_changed)
	get_node("/root/EventBus").loop_reset.connect(_on_loop_reset)

	# 启动蘑菇随机刷新定时器
	_mushroom_timer = Timer.new()
	_mushroom_timer.one_shot = true
	_mushroom_timer.timeout.connect(_spawn_mushroom)
	add_child(_mushroom_timer)
	_schedule_next_mushroom()


func _schedule_next_mushroom() -> void:
	# 随机 3~10 秒后刷新
	_mushroom_timer.wait_time = randf_range(3.0, 10.0)
	_mushroom_timer.start()


func _spawn_mushroom() -> void:
	# 随机找一个已隐藏的蘑菇，随机位置重新出现
	var candidates: Array[Node] = []
	for child in $Plaza/Mushrooms.get_children():
		if child is Area2D and not child.visible:
			candidates.append(child)

	if candidates.is_empty():
		_schedule_next_mushroom()
		return

	var shroom: Area2D = candidates.pick_random()

	# 在世界范围内随机位置（留 48px 边距避免贴边）
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


func _on_time_changed(time_id: String) -> void:
	if time_id == "midnight":
		await get_tree().create_timer(3.0).timeout
		get_node("/root/GameManager").reset_loop()


func _on_loop_reset() -> void:
	_refresh_collectibles()
	var spawn = $Plaza/PlayerSpawn
	if spawn and player:
		player.global_position = spawn.global_position


func _refresh_collectibles() -> void:
	# 循环重置时刷新所有蘑菇
	for child in $Plaza/Mushrooms.get_children():
		if child is Area2D and child.is_in_group("collectible"):
			child.show()
			child.monitoring = true
	# 立即 spawn 一颗
	_schedule_next_mushroom()

extends Node2D

## 游戏主场景控制器
##
## 负责：初始化所有子场景、时间推进触发、午夜循环

@onready var player: CharacterBody2D = $Player
@onready var padwin: CharacterBody2D = $Padwin


func _ready() -> void:
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


func _input(event: InputEvent) -> void:
	# T 键手动推进时间（调试用 / 事件驱动开发阶段）
	if event.is_action_pressed("advance_time"):
		_advance_time()


func _advance_time() -> void:
	var tm = get_node("/root/TimeManager")
	tm.advance_time()


func _on_time_changed(time_id: String) -> void:
	# 午夜自动触发循环重置
	if time_id == "midnight":
		# 等待 3 秒让玩家看到"午夜"，然后重置
		await get_tree().create_timer(3.0).timeout
		get_node("/root/GameManager").reset_loop()


func _on_loop_reset() -> void:
	# 循环重置后，把玩家放回出生点
	var spawn = $Plaza/PlayerSpawn
	if spawn and player:
		player.global_position = spawn.global_position
	# 重新刷新可采集物
	_refresh_collectibles()


func _refresh_collectibles() -> void:
	for child in $Plaza.get_children():
		if child.is_in_group("collectible"):
			child.show()
			var area = child.get_node_or_null("Area2D")
			if area:
				area.monitoring = true

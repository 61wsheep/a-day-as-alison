extends CharacterBody2D

## 玩家控制器 — 俯视角八向移动 + AnimatedSprite2D 动画 + Camera2D 边界

@export var speed: float = 200.0

var _movement_locked: bool = false

@onready var _anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var _camera: Camera2D = $Camera


func _ready() -> void:
	add_to_group("player")
	get_node("/root/EventBus").dialogue_started.connect(func(_a,_b,_c): _movement_locked = true)
	get_node("/root/EventBus").dialogue_ended.connect(func(_a): _movement_locked = false)


func setup_camera_limits(world_rect: Rect2) -> void:
	_camera.limit_left = int(world_rect.position.x)
	_camera.limit_top = int(world_rect.position.y)
	_camera.limit_right = int(world_rect.end.x)
	_camera.limit_bottom = int(world_rect.end.y)


func _physics_process(_delta: float) -> void:
	if _movement_locked:
		velocity = Vector2.ZERO
		_anim.stop()
		_anim.frame = 0
		return

	var direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	velocity = direction * speed

	if direction.length() > 0.01:
		if abs(direction.x) > abs(direction.y):
			_play_anim("walk_right" if direction.x > 0 else "walk_left")
		else:
			_play_anim("walk_down" if direction.y > 0 else "walk_up")
	else:
		_anim.stop()
		_anim.frame = 0

	move_and_slide()

	# Clamp 在 camera 界限内（留 24px 边距避免角色半身出界）
	global_position.x = clamp(global_position.x, _camera.limit_left + 24, _camera.limit_right - 24)
	global_position.y = clamp(global_position.y, _camera.limit_top + 24, _camera.limit_bottom - 24)


func _play_anim(anim_name: String) -> void:
	if _anim.sprite_frames and _anim.sprite_frames.has_animation(anim_name):
		if _anim.animation != anim_name:
			_anim.play(anim_name)
	else:
		if _anim.animation != "walk_down":
			_anim.play("walk_down")

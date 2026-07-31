extends CharacterBody2D

## 玩家控制器 — 俯视角八向移动 + AnimatedSprite2D 动画 + Camera2D 跟随

@export var speed: float = 200.0

@onready var _anim: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	add_to_group("player")


func _physics_process(_delta: float) -> void:
	var direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	velocity = direction * speed

	# 根据移动方向切换动画
	if direction.length() > 0.01:
		if abs(direction.x) > abs(direction.y):
			_play_anim("walk_right" if direction.x > 0 else "walk_left")
		else:
			_play_anim("walk_down" if direction.y > 0 else "walk_up")
	else:
		# 无输入 → 停止动画，停在当前方向第一帧
		_anim.stop()
		_anim.frame = 0

	move_and_slide()


func _play_anim(anim_name: String) -> void:
	if _anim.sprite_frames and _anim.sprite_frames.has_animation(anim_name):
		if _anim.animation != anim_name:
			_anim.play(anim_name)
	else:
		# 该方向没有帧时回退到 walk_down
		if _anim.animation != "walk_down":
			_anim.play("walk_down")

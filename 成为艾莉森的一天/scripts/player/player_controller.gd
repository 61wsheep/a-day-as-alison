extends CharacterBody2D

## 玩家控制器 — 俯视角八向移动 + Camera2D 跟随
##
## 使用 WASD / 方向键移动。
## Camera2D 作为子节点自动跟随玩家位置。

@export var speed: float = 200.0


func _physics_process(_delta: float) -> void:
	# WASD + 方向键 → 八向移动
	var direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	velocity = direction * speed
	move_and_slide()

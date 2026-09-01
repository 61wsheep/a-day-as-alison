extends Area2D
class_name Collectible

## 可采集物品 — 玩家靠近显示右下角提示「按 E 采集 XX」，按 E 才进背包。
## 与普通灌木丛/地形装饰区分：采集物带轻微浮动动画 + 头顶金色◆标记。
## 拾取成功才消失；背包满（超 stack_max）拒收并保留，弹 toast 提示。
## 循环重置时通过 game.gd 的 _refresh_collectibles() 重新出现。

## preload 而非全局类名：避免依赖全局脚本类缓存（headless/编辑器刷新前不注册）
const SceneLayout := preload("res://scripts/systems/scene_layout.gd")
const ItemDB := preload("res://scripts/systems/item_db.gd")

## 采到的物品 id（items.json 里的 id），替代原来的 gold_value 直加金币。
@export var item_id: String = "mushroom"

var _in_range := false


func _ready() -> void:
	add_to_group("collectible")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_apply_icon()
	_add_marker()
	_start_bob()


## 图标从 ItemDB 切图（items.json 的 icon.region + 占位改色）；失败则程序红块兜底。
func _apply_icon() -> void:
	if not has_node("Icon") or $Icon is not Sprite2D:
		return
	var icon: Sprite2D = $Icon
	var tex := ItemDB.get_icon(item_id)
	if tex:
		icon.texture = tex
		icon.modulate = ItemDB.icon_tint(item_id)
		icon.scale = Vector2(1.5, 1.5)   # 放大一点，避免与地形小贴图混淆
		return
	var rect := ColorRect.new()
	rect.color = Color(0.75, 0.15, 0.15, 1.0)
	rect.size = Vector2(16, 16)
	rect.position = Vector2(-8, -8)
	add_child(rect)
	rect.owner = self


## 头顶金色 ◆ 标记：一眼区分「这是可采集物」vs 普通灌木丛/地形装饰。
func _add_marker() -> void:
	var marker := Label.new()
	marker.name = "Marker"
	marker.text = "◆"
	marker.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	marker.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	marker.add_theme_constant_override("shadow_offset_x", 1)
	marker.add_theme_constant_override("shadow_offset_y", 1)
	marker.add_theme_font_size_override("font_size", 14)
	marker.position = Vector2(-6, -30)
	add_child(marker)


## 轻微上下浮动（随机相位，避免全场同步），提示它是活的、可交互的。
func _start_bob() -> void:
	_bob_phase = randf() * TAU
	var tween := create_tween()
	tween.set_loops()
	tween.tween_method(_set_bob, 0.0, TAU, 2.4)


var _bob_phase := 0.0


func _set_bob(t: float) -> void:
	var icon := get_node_or_null("Icon")
	if icon:
		(icon as Node2D).position.y = sin(t + _bob_phase) * 3.0
	var marker := get_node_or_null("Marker")
	if marker:
		(marker as Control).position.y = -30.0 + sin(t + _bob_phase) * 3.0


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_in_range = true
	get_node("/root/EventBus").collect_hint_show.emit(ItemDB.name_of(item_id))


func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_in_range = false
	get_node("/root/EventBus").collect_hint_hide.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not _in_range or not visible:
		return
	if _player_locked():
		return
	if event.is_action_pressed("ui_accept"):
		_try_collect()
		get_viewport().set_input_as_handled()


func _player_locked() -> bool:
	var p := get_tree().get_first_node_in_group("player")
	return p != null and bool(p._movement_locked)


## 真正的拾取入口：尝试进背包，成功才消失。
func _try_collect() -> void:
	if not visible:
		return
	var inv: Node = get_node("/root/Inventory")
	if inv.add(item_id):
		hide()
		set_deferred("monitoring", false)
		get_node("/root/EventBus").collect_hint_hide.emit()
	else:
		get_node("/root/EventBus").toast.emit("背包满了！")

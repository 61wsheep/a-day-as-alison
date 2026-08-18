extends Node2D

## 游戏主控制器 — 区域切换、Cainos 地形绘制、道具布置、时段色调、
## 蘑菇刷新、午夜流程、结局路由。

const TILE_SIZE := 32
const WORLD_W := 40
const WORLD_H := 24

const TEX_DIR := "res://assets/tilesets/cainos/"

## 道具贴图区域（AtlasTexture region）
const R_TREES := [
	Rect2(22, 12, 96, 138),
	Rect2(150, 22, 95, 123),
	Rect2(265, 37, 105, 98),
]
const R_BUSHES := [
	Rect2(37, 197, 25, 20),
	Rect2(95, 195, 30, 22),
	Rect2(152, 187, 42, 35),
	Rect2(210, 180, 50, 45),
	Rect2(277, 187, 42, 37),
	Rect2(345, 190, 50, 35),
]
const R_DOOR := Rect2(28, 103, 39, 50)
const R_SIGN := Rect2(98, 163, 29, 29)
const R_PILLAR := Rect2(30, 30, 65, 95)
const R_PILLAR_MOSSY := Rect2(30, 160, 65, 95)
const R_ARCH := Rect2(410, 25, 80, 65)
const R_ROCK_BIG := Rect2(5, 475, 55, 35)
const R_ROCK_SMALL := Rect2(70, 488, 36, 22)
const R_BARREL := Rect2(160, 150, 30, 38)
const R_VASE := Rect2(167, 218, 25, 22)

@onready var player: CharacterBody2D = $Player
@onready var daylight: CanvasModulate = $DaylightModulate
@onready var areas: Node2D = $Areas

var _world_rect: Rect2
var _mushroom_timer: Timer
var _auto_advance_timer: Timer
var _pending_action: String = ""
var _midnight_panel: CanvasLayer
var _door_cooldown: bool = false


func _ready() -> void:
	_world_rect = Rect2(0, 0, WORLD_W * TILE_SIZE, WORLD_H * TILE_SIZE)

	var tileset := _build_tileset()
	_paint_area_grounds(tileset)
	_build_all_props()

	if player and player.has_method("setup_camera_limits"):
		player.setup_camera_limits(_world_rect)

	var bus = get_node("/root/EventBus")
	bus.time_changed.connect(_on_time_changed)
	bus.loop_reset.connect(_on_loop_reset)
	bus.door_entered.connect(switch_area)
	bus.game_action.connect(_on_game_action)
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
# TileSet & 地形
# ---------------------------------------------------------------------------
func _build_tileset() -> TileSet:
	## 每次启动在内存中构建 Cainos TileSet：
	## source 0 = 草地（8x4 纯草 + 过渡块），source 1 = 石地
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	for tex_path in [TEX_DIR + "grass.png", TEX_DIR + "stone.png"]:
		var tex := load(tex_path) as Texture2D
		var atlas := TileSetAtlasSource.new()
		atlas.texture = tex
		atlas.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
		var tw := int(tex.get_size().x) / TILE_SIZE
		var th := int(tex.get_size().y) / TILE_SIZE
		for y in th:
			for x in tw:
				atlas.create_tile(Vector2i(x, y))
		ts.add_source(atlas)
	return ts


func _grass_tile() -> Vector2i:
	# 上半部分是纯草（含少量小花），左侧 4 列最干净
	if randf() < 0.85:
		return Vector2i(randi() % 4, randi() % 4)
	return Vector2i(4 + randi() % 4, randi() % 4)


func _stone_tile() -> Vector2i:
	# 石板填充块：第 4 列前 4 行是干净填充
	return Vector2i(4, randi() % 4)


func _paint_area_grounds(ts: TileSet) -> void:
	# --- 广场：草地 + 中央十字石板路 ---
	var plaza: TileMapLayer = areas.get_node_or_null("Plaza/Ground")
	if plaza:
		plaza.tile_set = ts
		if plaza.get_used_cells().size() == 0:
			for y in WORLD_H:
				for x in WORLD_W:
					var coord := Vector2i(x, y)
					if y >= 11 and y <= 13:
						plaza.set_cell(coord, 1, _stone_tile())  # 东西向主路（连接两侧门）
					elif x >= 18 and x <= 21 and y >= 4 and y <= 19:
						plaza.set_cell(coord, 1, _stone_tile())  # 南北向中路
					else:
						plaza.set_cell(coord, 0, _grass_tile())

	# --- 树屋区：草地 + 横路 + 三条入户小径 ---
	var tree: TileMapLayer = areas.get_node_or_null("TreehouseDistrict/Ground")
	if tree:
		tree.tile_set = ts
		if tree.get_used_cells().size() == 0:
			for y in WORLD_H:
				for x in WORLD_W:
					var coord := Vector2i(x, y)
					if y >= 11 and y <= 13:
						tree.set_cell(coord, 1, _stone_tile())
					elif y >= 8 and y <= 10 and (x == 9 or x == 20 or x == 30):
						tree.set_cell(coord, 1, _stone_tile())
					else:
						tree.set_cell(coord, 0, _grass_tile())

	# --- 石巢塔楼：全石板地面 ---
	var tower: TileMapLayer = areas.get_node_or_null("StoneNestTower/Ground")
	if tower:
		tower.tile_set = ts
		if tower.get_used_cells().size() == 0:
			for y in WORLD_H:
				for x in WORLD_W:
					tower.set_cell(Vector2i(x, y), 1, _stone_tile())


# ---------------------------------------------------------------------------
# 道具布置（程序化）
# ---------------------------------------------------------------------------
func _make_prop(parent: Node, tex_name: String, region: Rect2, pos: Vector2,
		collider_r: float = 0.0) -> Sprite2D:
	var at := AtlasTexture.new()
	at.atlas = load(TEX_DIR + tex_name)
	at.region = region
	var spr := Sprite2D.new()
	spr.texture = at
	spr.centered = true
	# 锚定底部中心
	spr.offset = Vector2(0, -region.size.y / 2.0)
	spr.position = pos
	parent.add_child(spr)
	if collider_r > 0.0:
		var body := StaticBody2D.new()
		body.position = Vector2(pos.x, pos.y - 8)
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = collider_r
		shape.shape = circle
		body.add_child(shape)
		parent.add_child(body)
	return spr


func _scatter_bushes(parent: Node, count: int) -> void:
	for i in count:
		var pos := Vector2(randf_range(80, 1200), randf_range(80, 700))
		_make_prop(parent, "plant.png", R_BUSHES[randi() % R_BUSHES.size()], pos)


func _tree_ring(parent: Node, skip_west: bool = false, skip_east: bool = false) -> void:
	# 沿四边种一圈树，留出门的缺口
	for x in range(80, 1250, 130):
		_make_prop(parent, "plant.png", R_TREES[randi() % 3], Vector2(x, 70), 10.0)
		_make_prop(parent, "plant.png", R_TREES[randi() % 3], Vector2(x, 730), 10.0)
	for y in range(160, 700, 130):
		if not skip_west or abs(y - 384) > 90:
			_make_prop(parent, "plant.png", R_TREES[randi() % 3], Vector2(40, y), 10.0)
		if not skip_east or abs(y - 384) > 90:
			_make_prop(parent, "plant.png", R_TREES[randi() % 3], Vector2(1240, y), 10.0)


func _build_all_props() -> void:
	_build_plaza_props()
	_build_treehouse_props()
	_build_tower_props()


func _build_plaza_props() -> void:
	var props: Node2D = areas.get_node("Plaza/Props")
	_tree_ring(props, true, true)
	_scatter_bushes(props, 10)
	# 路牌：东门→树屋区，西门→石巢塔楼
	_make_prop(props, "props.png", R_SIGN, Vector2(1190, 340))
	_make_prop(props, "props.png", R_SIGN, Vector2(80, 340))
	# 广场中央装饰：大岩石 + 木桶
	_make_prop(props, "props.png", R_ROCK_BIG, Vector2(760, 260), 12.0)
	_make_prop(props, "props.png", R_BARREL, Vector2(480, 300), 10.0)


func _build_treehouse_props() -> void:
	var props: Node2D = areas.get_node("TreehouseDistrict/Props")
	_tree_ring(props, true, false)
	_scatter_bushes(props, 8)
	# 三栋树屋：大树 + 木门 + 门牌（与 tscn 中 DoorOak/Cedar/Willow 对齐）
	var houses := [
		{"tree": Vector2(300, 260), "door": Vector2(300, 312)},
		{"tree": Vector2(640, 240), "door": Vector2(640, 292)},
		{"tree": Vector2(960, 260), "door": Vector2(960, 312)},
	]
	for h in houses:
		_make_prop(props, "plant.png", R_TREES[0], h["tree"], 14.0)
		_make_prop(props, "props.png", R_DOOR, h["door"])
		_make_prop(props, "props.png", R_SIGN, h["door"] + Vector2(52, 4))
	# 杂物点缀
	_make_prop(props, "props.png", R_BARREL, Vector2(420, 350), 10.0)
	_make_prop(props, "props.png", R_VASE, Vector2(880, 350))


func _build_tower_props() -> void:
	var props: Node2D = areas.get_node("StoneNestTower/Props")
	# 石柱阵
	_make_prop(props, "struct.png", R_PILLAR, Vector2(300, 210), 16.0)
	_make_prop(props, "struct.png", R_PILLAR, Vector2(980, 210), 16.0)
	_make_prop(props, "struct.png", R_PILLAR_MOSSY, Vector2(300, 520), 16.0)
	_make_prop(props, "struct.png", R_PILLAR_MOSSY, Vector2(980, 520), 16.0)
	# 南侧入口拱门
	_make_prop(props, "struct.png", R_ARCH, Vector2(640, 700))
	# 碎石
	_make_prop(props, "props.png", R_ROCK_BIG, Vector2(420, 400), 12.0)
	_make_prop(props, "props.png", R_ROCK_SMALL, Vector2(860, 380))
	_make_prop(props, "props.png", R_ROCK_SMALL, Vector2(500, 560))


# ---------------------------------------------------------------------------
# 区域切换
# ---------------------------------------------------------------------------
func switch_area(area_id: String, spawn_name: String = "") -> void:
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

	get_node("/root/GameManager").current_area = area_id
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
	_midnight_panel.show()


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

	var label := Label.new()
	label.text = "—— 午夜已至 ——\n石巢塔楼的方向传来钟声……"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 15)
	vbox.add_child(label)

	var btn := Button.new()
	btn.text = "入睡（结束今天）"
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(_do_sleep)
	vbox.add_child(btn)

	_midnight_panel.hide()


func _do_sleep() -> void:
	_midnight_panel.hide()
	get_node("/root/GameManager").reset_loop()


# ---------------------------------------------------------------------------
# 剧情动作路由 / 结局
# ---------------------------------------------------------------------------
func _on_game_action(action_id: String) -> void:
	if action_id.begins_with("rental:"):
		get_node("RentalUI").open(action_id.trim_prefix("rental:"))
	else:
		# ending:* / pass_night 等对话结束后统一处理
		_pending_action = action_id


func _on_dialogue_ended() -> void:
	if _pending_action == "":
		return
	var action := _pending_action
	_pending_action = ""
	if action.begins_with("ending:"):
		get_node("EndingUI").show_ending(action.trim_prefix("ending:"))
	elif action == "pass_night":
		_do_sleep()


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
	var pool := _mushroom_pool()
	if pool:
		for child in pool.get_children():
			if child is Area2D and child.is_in_group("collectible"):
				child.show()
				child.monitoring = true

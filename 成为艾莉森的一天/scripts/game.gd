extends Node2D

## Game scene controller — init, time, midnight loop, mushrooms, terrain tint

@onready var player: CharacterBody2D = $Player
@onready var padwin: CharacterBody2D = $Padwin
@onready var terrain_ground: TileMapLayer = $Plaza/Ground
@onready var terrain_plants: TileMapLayer = $Plaza/Plants
@onready var terrain_canopy: TileMapLayer = $Plaza/Canopy

const TILE_SIZE := 32
const WORLD_W := 40
const WORLD_H := 24

var _world_rect: Rect2
var _mushroom_timer: Timer
var _auto_advance_timer: Timer
var _tileset_ready: bool = false


func _ready() -> void:
	_world_rect = Rect2(0, 0, WORLD_W * TILE_SIZE, WORLD_H * TILE_SIZE)

	_setup_tileset()

	if player and player.has_method("setup_camera_limits"):
		player.setup_camera_limits(_world_rect)

	var spawn = $Plaza/PlayerSpawn
	if spawn and player:
		player.global_position = spawn.global_position
	var npc_spawn = $Plaza/NPCSpawn
	if npc_spawn and padwin:
		padwin.global_position = npc_spawn.global_position

	get_node("/root/EventBus").time_changed.connect(_on_time_changed)
	get_node("/root/EventBus").loop_reset.connect(_on_loop_reset)
	var bus = get_node("/root/EventBus")
	if padwin and padwin.has_method("on_choice_made"):
		bus.dialogue_choice_made.connect(padwin.on_choice_made)

	_mushroom_timer = Timer.new()
	_mushroom_timer.one_shot = true
	_mushroom_timer.timeout.connect(_spawn_mushroom)
	add_child(_mushroom_timer)
	_schedule_next_mushroom()

	_auto_advance_timer = Timer.new()
	_auto_advance_timer.one_shot = false
	_auto_advance_timer.wait_time = 30.0
	_auto_advance_timer.timeout.connect(_auto_advance)
	add_child(_auto_advance_timer)
	_auto_advance_timer.start()

	_switch_background("morning")


# ---------------------------------------------------------------------------
# TileSet setup
# ---------------------------------------------------------------------------
func _setup_tileset() -> void:
	_tileset_ready = false

	var ts_path := "res://assets/tilesets/plaza_tiles.tres"
	var tex_path := "res://assets/tilesets/tile_plaza.png"

	if not FileAccess.file_exists(ts_path):
		var ts := TileSet.new()
		ResourceSaver.save(ts, ts_path)

	var ts := load(ts_path) as TileSet
	if ts.get_source_count() == 0:
		var tex := load(tex_path) as Texture2D
		if tex:
			var atlas := TileSetAtlasSource.new()
			atlas.texture = tex
			atlas.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
			var tw := int(tex.get_size().x) / TILE_SIZE
			var th := int(tex.get_size().y) / TILE_SIZE
			for y in th:
				for x in tw:
					atlas.create_tile(Vector2i(x, y))
			ts.add_source(atlas)
			ResourceSaver.save(ts, ts_path)

	ts = load(ts_path) as TileSet
	terrain_ground.tile_set = ts
	terrain_plants.tile_set = ts
	terrain_canopy.tile_set = ts

	# Paint ground if never painted
	if terrain_ground.get_used_cells().size() == 0:
		_paint_ground()

	_tileset_ready = true


func _paint_ground() -> void:
	for y in WORLD_H:
		for x in WORLD_W:
			var coord := Vector2i(x, y)
			if x < 3 or x >= WORLD_W - 3 or y < 2 or y >= WORLD_H - 2:
				terrain_ground.set_cell(coord, 0, Vector2i(0, 2))
			elif x > WORLD_W / 2 - 4 and x < WORLD_W / 2 + 4 and y > 6 and y < 18:
				terrain_ground.set_cell(coord, 0, Vector2i(0, 1))
			else:
				terrain_ground.set_cell(coord, 0, Vector2i(x % 2, y % 2))


# ---------------------------------------------------------------------------
# Time-of-day tint
# ---------------------------------------------------------------------------
func _switch_background(time_id: String) -> void:
	var color: Color
	match time_id:
		"morning":   color = Color(1.0, 0.92, 0.85, 1.0)
		"afternoon": color = Color(1.0, 1.0, 1.0, 1.0)
		"evening":   color = Color(1.0, 0.70, 0.48, 1.0)
		"night":     color = Color(0.30, 0.30, 0.55, 1.0)
		"midnight":  color = Color(0.15, 0.15, 0.30, 1.0)

	var layers: Array[TileMapLayer] = []
	if terrain_ground: layers.append(terrain_ground)
	if terrain_plants: layers.append(terrain_plants)
	if terrain_canopy: layers.append(terrain_canopy)

	for layer in layers:
		var tween = create_tween()
		tween.tween_property(layer, "self_modulator", color, 1.0)


# ---------------------------------------------------------------------------
# Mushrooms
# ---------------------------------------------------------------------------
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
	var rx := randf_range(_world_rect.position.x + 64, _world_rect.end.x - 64)
	var ry := randf_range(_world_rect.position.y + 64, _world_rect.end.y - 64)
	shroom.global_position = Vector2(rx, ry)
	shroom.show()
	shroom.monitoring = true
	_schedule_next_mushroom()


# ---------------------------------------------------------------------------
# Input / time
# ---------------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("advance_time"):
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
		await get_tree().create_timer(3.0).timeout
		get_node("/root/GameManager").reset_loop()


func _on_loop_reset() -> void:
	get_node("/root/TimeManager").reset_to_morning()
	_auto_advance_timer.stop()
	_auto_advance_timer.start()
	_refresh_collectibles()
	var spawn = $Plaza/PlayerSpawn
	if spawn and player:
		player.global_position = spawn.global_position
	_switch_background("morning")


func _refresh_collectibles() -> void:
	for child in $Plaza/Mushrooms.get_children():
		if child is Area2D and child.is_in_group("collectible"):
			child.show()
			child.monitoring = true
	_schedule_next_mushroom()

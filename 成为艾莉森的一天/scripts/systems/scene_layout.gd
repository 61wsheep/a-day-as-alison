class_name SceneLayout
extends Object

## 场景布局 —— 地形与道具的程序化生成（从 game.gd 抽取，静态类）。
##
## 两个用途：
##   1. 运行时兜底：game.gd _ready 调用 paint_area_grounds / build_all_props，
##      每个区域判空（已有内容跳过），保证新区域 / 空白场景也能自动铺地。
##   2. 烘焙工具：scenes/tools/bake_terrain.tscn 调用本类把生成结果固化进
##      main.tscn，之后编辑器可直接看到、拖动、保存。
##
## 节点 owner 在创建时同步为 parent.owner（烘焙时被场景根拥有），
## 运行时设置 owner 无害（仅在场景序列化时生效）。

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

## 蘑菇视觉：Cainos plant.png 里的灌木丛（蘑菇藏在草丛里）
const MUSHROOM_ICON_REGION := Rect2(33, 190, 38, 34)

## 烘焙工具置位：game.gd _ready 检测到后跳过游戏初始化（仅序列化用）
static var baking: bool = false


static func build_tileset() -> TileSet:
	## 每次在内存中构建 Cainos TileSet：
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


static func _grass_tile() -> Vector2i:
	# 上半部分是纯草（含少量小花），左侧 4 列最干净
	if randf() < 0.85:
		return Vector2i(randi() % 4, randi() % 4)
	return Vector2i(4 + randi() % 4, randi() % 4)


static func _stone_tile() -> Vector2i:
	# 石板填充块：第 4 列前 4 行是干净填充
	return Vector2i(4, randi() % 4)


## 给 areas 下三个区域的 Ground 铺地。已有 cell 的区域跳过（烘焙后不再重铺）。
static func paint_area_grounds(areas: Node2D) -> void:
	var targets := ["Plaza", "TreehouseDistrict", "StoneNestTower"]
	# 先确认是否有区域需要铺地，避免无条件重建 tileset
	var need_paint := false
	for area_name in targets:
		var ground: TileMapLayer = areas.get_node_or_null(area_name + "/Ground")
		if ground and ground.get_used_cells().size() == 0:
			need_paint = true
			break
	if not need_paint:
		return
	var ts := build_tileset()
	for area_name in targets:
		var ground: TileMapLayer = areas.get_node_or_null(area_name + "/Ground")
		if ground and ground.get_used_cells().size() == 0:
			ground.tile_set = ts
			match area_name:
				"Plaza":
					_paint_plaza(ground)
				"TreehouseDistrict":
					_paint_treehouse(ground)
				"StoneNestTower":
					_paint_tower(ground)


static func _paint_plaza(ground: TileMapLayer) -> void:
	# 广场：草地 + 中央十字石板路
	for y in WORLD_H:
		for x in WORLD_W:
			var coord := Vector2i(x, y)
			if y >= 11 and y <= 13:
				ground.set_cell(coord, 1, _stone_tile())  # 东西向主路（连接两侧门）
			elif x >= 18 and x <= 21 and y >= 4 and y <= 19:
				ground.set_cell(coord, 1, _stone_tile())  # 南北向中路
			else:
				ground.set_cell(coord, 0, _grass_tile())


static func _paint_treehouse(ground: TileMapLayer) -> void:
	# 树屋区：草地 + 横路 + 三条入户小径
	for y in WORLD_H:
		for x in WORLD_W:
			var coord := Vector2i(x, y)
			if y >= 11 and y <= 13:
				ground.set_cell(coord, 1, _stone_tile())
			elif y >= 8 and y <= 10 and (x == 9 or x == 20 or x == 30):
				ground.set_cell(coord, 1, _stone_tile())
			else:
				ground.set_cell(coord, 0, _grass_tile())


static func _paint_tower(ground: TileMapLayer) -> void:
	# 石巢塔楼：全石板地面
	for y in WORLD_H:
		for x in WORLD_W:
			ground.set_cell(Vector2i(x, y), 1, _stone_tile())


## 给 areas 下三个区域的 Props 生成道具。已有子节点的区域跳过。
static func build_all_props(areas: Node2D) -> void:
	_build_plaza_props(areas.get_node_or_null("Plaza/Props"))
	_build_treehouse_props(areas.get_node_or_null("TreehouseDistrict/Props"))
	_build_tower_props(areas.get_node_or_null("StoneNestTower/Props"))


static func _make_prop(parent: Node, tex_name: String, region: Rect2, pos: Vector2,
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
	spr.owner = parent.owner
	if collider_r > 0.0:
		var body := StaticBody2D.new()
		body.position = Vector2(pos.x, pos.y - 8)
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = collider_r
		shape.shape = circle
		# 先接进 parent（树内），再设 owner —— owner 必须是树内祖先
		parent.add_child(body)
		body.owner = parent.owner
		body.add_child(shape)
		shape.owner = parent.owner
	return spr


static func _scatter_bushes(parent: Node, count: int) -> void:
	for i in count:
		var pos := Vector2(randf_range(80, 1200), randf_range(80, 700))
		_make_prop(parent, "plant.png", R_BUSHES[randi() % R_BUSHES.size()], pos)


static func _tree_ring(parent: Node, skip_west: bool = false, skip_east: bool = false) -> void:
	# 沿四边种一圈树，留出门的缺口
	for x in range(80, 1250, 130):
		_make_prop(parent, "plant.png", R_TREES[randi() % 3], Vector2(x, 70), 10.0)
		_make_prop(parent, "plant.png", R_TREES[randi() % 3], Vector2(x, 730), 10.0)
	for y in range(160, 700, 130):
		if not skip_west or abs(y - 384) > 90:
			_make_prop(parent, "plant.png", R_TREES[randi() % 3], Vector2(40, y), 10.0)
		if not skip_east or abs(y - 384) > 90:
			_make_prop(parent, "plant.png", R_TREES[randi() % 3], Vector2(1240, y), 10.0)


static func _build_plaza_props(props: Node) -> void:
	if props == null or props.get_child_count() > 0:
		return
	_tree_ring(props, true, true)
	_scatter_bushes(props, 10)
	# 路牌：东门→树屋区，西门→石巢塔楼
	_make_prop(props, "props.png", R_SIGN, Vector2(1190, 340))
	_make_prop(props, "props.png", R_SIGN, Vector2(80, 340))
	# 广场中央装饰：大岩石 + 木桶
	_make_prop(props, "props.png", R_ROCK_BIG, Vector2(760, 260), 12.0)
	_make_prop(props, "props.png", R_BARREL, Vector2(480, 300), 10.0)


static func _build_treehouse_props(props: Node) -> void:
	if props == null or props.get_child_count() > 0:
		return
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


static func _build_tower_props(props: Node) -> void:
	if props == null or props.get_child_count() > 0:
		return
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

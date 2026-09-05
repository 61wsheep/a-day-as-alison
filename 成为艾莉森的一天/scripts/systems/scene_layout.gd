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

## 薄封装：地形语义查询统一走 TerrainQuery（v0.2 契约②），此处只转发。
## preload 而非类名引用，避免依赖全局脚本类缓存（headless / 编辑器刷新前未注册）。
const TerrainQuery := preload("res://scripts/systems/terrain_query.gd")

const TEX_DIR := "res://assets/tilesets/cainos/"

## 森林广场瓦片集（384x1040，32px 网格：地形区 y0-384，下方为道具素材）
## 布局：草 y0-3 / 石子路 y4-7 / 土路 y8-11；每种地形 3 个 4x4 块：
##   左块=带草边界的孤岛（外角+边+填充）、中块=纯填充、右块=草心环（内角）
## (10,1) 是全透明空瓦片，建图集时跳过
const GROUND_SHEET := "res://assets/tilesets/forest_plaza.png"
const SHEET_COLS := 12
const SHEET_GROUND_ROWS := 12   # 地形区行数（y 384 以下不建瓦片）
const EMPTY_TILES: Array[Vector2i] = [Vector2i(10, 1)]

const TERRAIN_STONE := 0
const TERRAIN_DIRT := 1
## 烘焙进 main.tscn 的广场瓦片集把「草地」也做成 terrain 2（石子路0/土路1/草地2，
## 全在同一 terrain_set 0 内）。运行时判定草坪须查 td.terrain == TERRAIN_GRASS，
## 而不是 terrain_set == -1（那套只存在于未烘焙的动态 tileset）。
const TERRAIN_GRASS := 2

## peering 位全表（配置地形瓦片时遍历用）
const _ALL_BITS: Array[TileSet.CellNeighbor] = [
	TileSet.CELL_NEIGHBOR_RIGHT_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER,
	TileSet.CELL_NEIGHBOR_BOTTOM_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER,
	TileSet.CELL_NEIGHBOR_LEFT_SIDE, TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER,
	TileSet.CELL_NEIGHBOR_TOP_SIDE, TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER,
]

## 道具贴图区域（AtlasTexture region）
## —— 森林广场瓦片集（GROUND_SHEET）道具区（y>=384，程序检测的精确包围盒）——
const N_TREES := [
	Rect2(10, 482, 100, 126),   # 圆冠大树（浅绿）
	Rect2(10, 610, 100, 130),   # 圆冠大树（深绿）
	Rect2(10, 740, 100, 124),   # 针叶树
]
const N_BUSHES := [
	Rect2(1, 385, 30, 30), Rect2(33, 385, 30, 30),
	Rect2(65, 385, 30, 30), Rect2(97, 385, 30, 30),
]
const N_FLOWERS := [
	Rect2(5, 421, 20, 23), Rect2(38, 421, 20, 23), Rect2(70, 421, 20, 23),
]
const N_STUMP := Rect2(2, 868, 29, 27)
const N_LOG := Rect2(34, 868, 28, 27)
const N_BENCH := Rect2(7, 899, 50, 27)
const N_LAMP := Rect2(8, 930, 16, 61)
const N_SIGN := Rect2(0, 993, 32, 46)

## —— Cainos 包（新瓦片集无对应物：门/石柱/拱门/岩石/木桶/花瓶保留）——
const R_DOOR := Rect2(28, 103, 39, 50)
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
	## 在内存中构建地形 TileSet（森林广场瓦片集）：
	## source 0 = 整张图集（仅地形区 12x12，跳过空瓦片）
	## 地形集 0：terrain 0=石子路、terrain 1=土路（过渡对象=无地形的草地背景）
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	var tex := load(GROUND_SHEET) as Texture2D
	var atlas := TileSetAtlasSource.new()
	atlas.texture = tex
	atlas.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	for y in SHEET_GROUND_ROWS:
		for x in SHEET_COLS:
			if Vector2i(x, y) in EMPTY_TILES:
				continue
			atlas.create_tile(Vector2i(x, y))
	ts.add_source(atlas, 0)

	ts.add_terrain_set(0)
	ts.set_terrain_set_mode(0, TileSet.TERRAIN_MODE_MATCH_CORNERS_AND_SIDES)
	ts.add_terrain(0)
	ts.set_terrain_name(0, TERRAIN_STONE, "石子路")
	ts.set_terrain_color(0, TERRAIN_STONE, Color(0.75, 0.72, 0.65))
	ts.add_terrain(0)
	ts.set_terrain_name(0, TERRAIN_DIRT, "土路")
	ts.set_terrain_color(0, TERRAIN_DIRT, Color(0.72, 0.55, 0.35))

	_setup_road_terrain(atlas, TERRAIN_STONE, 4)   # 石子路在 y4-7
	_setup_road_terrain(atlas, TERRAIN_DIRT, 8)    # 土路在 y8-11
	return ts


## 给一种路面地形配置 peering bits。row0 = 该地形首行（石子路 4 / 土路 8）。
## 每种地形 3 个 4x4 块：列0-3 孤岛块（外角+边+填充）、列4-7 纯填充、列8-11 环块（内角）。
static func _setup_road_terrain(atlas: TileSetAtlasSource, tid: int, row0: int) -> void:
	# -- 孤岛块（列 0-3）：外角只把严格朝外的角设为 -1；边瓦片两个朝外的角为 -1 --
	for ly in 4:
		for lx in 4:
			var outside := _island_outside_bits(lx, ly)
			_set_tile_terrain(atlas, Vector2i(lx, row0 + ly), tid, outside)
	# -- 填充块（列 4-7）：全部位 = 自身地形 --
	for ly in 4:
		for lx in range(4, 8):
			_set_tile_terrain(atlas, Vector2i(lx, row0 + ly), tid, [])
	# -- 环块（列 8-11）：只配四个内角（角位 -1，其余全 T），环的其余瓦片不配地形 --
	var inner := {
		Vector2i(8, row0): TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER,
		Vector2i(11, row0): TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER,
		Vector2i(8, row0 + 3): TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER,
		Vector2i(11, row0 + 3): TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER,
	}
	for coord in inner:
		_set_tile_terrain(atlas, coord, tid, [inner[coord]])


## 孤岛块 (lx,ly) 处瓦片的「朝外」peering 位列表（这些位 = 草地背景 -1）。
static func _island_outside_bits(lx: int, ly: int) -> Array:
	var bits: Array = []
	if lx == 0:
		bits.append(TileSet.CELL_NEIGHBOR_LEFT_SIDE)
	elif lx == 3:
		bits.append(TileSet.CELL_NEIGHBOR_RIGHT_SIDE)
	if ly == 0:
		bits.append(TileSet.CELL_NEIGHBOR_TOP_SIDE)
	elif ly == 3:
		bits.append(TileSet.CELL_NEIGHBOR_BOTTOM_SIDE)
	# 外角：仅严格朝外的那一个角
	if lx == 0 and ly == 0:
		bits.append(TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER)
	elif lx == 3 and ly == 0:
		bits.append(TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER)
	elif lx == 0 and ly == 3:
		bits.append(TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER)
	elif lx == 3 and ly == 3:
		bits.append(TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER)
	# 边瓦片：两个朝外的角
	if ly in [1, 2]:
		if lx == 0:
			bits.append(TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER)
			bits.append(TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER)
		elif lx == 3:
			bits.append(TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER)
			bits.append(TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER)
	if lx in [1, 2]:
		if ly == 0:
			bits.append(TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER)
			bits.append(TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER)
		elif ly == 3:
			bits.append(TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER)
			bits.append(TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER)
	return bits


static func _set_tile_terrain(atlas: TileSetAtlasSource, coord: Vector2i, tid: int, outside: Array) -> void:
	var td := atlas.get_tile_data(coord, 0)
	if td == null:
		return
	td.terrain_set = 0   # 必须先指定地形集，才能设 terrain 与 peering 位
	td.set_terrain(tid)
	for bit in _ALL_BITS:
		td.set_terrain_peering_bit(bit, -1 if bit in outside else tid)


static func _grass_tile() -> Vector2i:
	# 草地填充：中块中心 2x2（(5,1)(6,1)(5,2)(6,2)）是唯一干净无缝的纯草纹理；
	# 中块其余瓦片边缘带浅草补丁（用于向浅草地过渡），平铺会出现折线残影
	return Vector2i(5 + randi() % 2, 1 + randi() % 2)


## 世界坐标是否落在「纯草地」（非路面）。烘焙地面以 td.terrain == TERRAIN_GRASS 为准；
## 采集物只在草坪刷新，避免刷在石子路/土路上（地形刷铺出的过渡带 terrain 也不是草地）。
static func is_grass_tile(ground: TileMapLayer, world_pos: Vector2) -> bool:
	return TerrainQuery.terrain_type_at(ground, world_pos) == TERRAIN_GRASS


static func _stone_tile() -> Vector2i:
	# 石子路纯填充变体：中块（列 4-7，行 4-7）
	return Vector2i(4 + randi() % 4, 4 + randi() % 4)


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


## 草地全铺 + 地形刷铺路。ignore_empty_terrains=false：草地瓦片无地形，
## 路面边缘才会刷出过渡块（草皮收边）。
static func _paint_grass_base(ground: TileMapLayer) -> void:
	for y in WORLD_H:
		for x in WORLD_W:
			ground.set_cell(Vector2i(x, y), 0, _grass_tile())


static func _paint_terrain(ground: TileMapLayer, cells: Array, terrain: int) -> void:
	if cells.is_empty():
		return
	ground.set_cells_terrain_connect(cells, 0, terrain, false)


static func _paint_plaza(ground: TileMapLayer) -> void:
	# 广场：草地 + 中央十字石子路（地形刷自动过渡）
	_paint_grass_base(ground)
	var road: Array[Vector2i] = []
	for y in WORLD_H:
		for x in WORLD_W:
			if y >= 11 and y <= 13:
				road.append(Vector2i(x, y))   # 东西向主路（连接两侧门）
			elif x >= 18 and x <= 21 and y >= 4 and y <= 19:
				road.append(Vector2i(x, y))   # 南北向中路
	_paint_terrain(ground, road, TERRAIN_STONE)


static func _paint_treehouse(ground: TileMapLayer) -> void:
	# 树屋区：草地 + 横路 + 三条入户小径（土路，地形刷自动过渡）
	_paint_grass_base(ground)
	var road: Array[Vector2i] = []
	for y in WORLD_H:
		for x in WORLD_W:
			if y >= 11 and y <= 13:
				road.append(Vector2i(x, y))
			elif y >= 8 and y <= 10 and (x == 9 or x == 20 or x == 30):
				road.append(Vector2i(x, y))
	_paint_terrain(ground, road, TERRAIN_DIRT)


static func _paint_tower(ground: TileMapLayer) -> void:
	# 石巢塔楼：全石板地面（100% 覆盖无需过渡，直接铺填充块，
	# 避免地图边界被地形刷刷出草皮收边）
	for y in WORLD_H:
		for x in WORLD_W:
			ground.set_cell(Vector2i(x, y), 0, _stone_tile())


## 给 areas 下三个区域的 Props 生成道具。已有子节点的区域跳过。
static func build_all_props(areas: Node2D) -> void:
	_build_plaza_props(areas.get_node_or_null("Plaza/Props"))
	_build_treehouse_props(areas.get_node_or_null("TreehouseDistrict/Props"))
	_build_tower_props(areas.get_node_or_null("StoneNestTower/Props"))


static func _make_prop(parent: Node, tex_path: String, region: Rect2, pos: Vector2,
		collider_r: float = 0.0) -> Sprite2D:
	var at := AtlasTexture.new()
	at.atlas = load(tex_path)
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


## 灌木 + 花点缀（新瓦片集；蘑菇仍是 Cainos 红灌木，视觉上与装饰草丛区分）
static func _scatter_bushes(parent: Node, count: int) -> void:
	for i in count:
		var pos := Vector2(randf_range(80, 1200), randf_range(80, 700))
		_make_prop(parent, GROUND_SHEET, N_BUSHES[randi() % N_BUSHES.size()], pos)
	var flower_count := count / 2
	for i in flower_count:
		var pos := Vector2(randf_range(80, 1200), randf_range(80, 700))
		_make_prop(parent, GROUND_SHEET, N_FLOWERS[randi() % N_FLOWERS.size()], pos)


static func _tree_ring(parent: Node, skip_west: bool = false, skip_east: bool = false) -> void:
	# 沿四边种一圈树，留出门的缺口
	for x in range(80, 1250, 130):
		_make_prop(parent, GROUND_SHEET, N_TREES[randi() % 3], Vector2(x, 70), 12.0)
		_make_prop(parent, GROUND_SHEET, N_TREES[randi() % 3], Vector2(x, 730), 12.0)
	for y in range(160, 700, 130):
		if not skip_west or abs(y - 384) > 90:
			_make_prop(parent, GROUND_SHEET, N_TREES[randi() % 3], Vector2(40, y), 12.0)
		if not skip_east or abs(y - 384) > 90:
			_make_prop(parent, GROUND_SHEET, N_TREES[randi() % 3], Vector2(1240, y), 12.0)


static func _build_plaza_props(props: Node) -> void:
	if props == null or props.get_child_count() > 0:
		return
	_tree_ring(props, true, true)
	_scatter_bushes(props, 10)
	# 路牌：东门→树屋区，西门→石巢塔楼
	_make_prop(props, GROUND_SHEET, N_SIGN, Vector2(1190, 340))
	_make_prop(props, GROUND_SHEET, N_SIGN, Vector2(80, 340))
	# 路灯：东西主路两端
	_make_prop(props, GROUND_SHEET, N_LAMP, Vector2(1140, 352), 6.0)
	_make_prop(props, GROUND_SHEET, N_LAMP, Vector2(140, 352), 6.0)
	# 长椅：中央路口旁
	_make_prop(props, GROUND_SHEET, N_BENCH, Vector2(700, 330), 10.0)
	# 广场中央装饰：大岩石 + 木桶 + 树桩
	_make_prop(props, TEX_DIR + "props.png", R_ROCK_BIG, Vector2(760, 260), 12.0)
	_make_prop(props, TEX_DIR + "props.png", R_BARREL, Vector2(480, 300), 10.0)
	_make_prop(props, GROUND_SHEET, N_STUMP, Vector2(560, 250))


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
		_make_prop(props, GROUND_SHEET, N_TREES[0], h["tree"], 14.0)
		_make_prop(props, TEX_DIR + "props.png", R_DOOR, h["door"])
		_make_prop(props, GROUND_SHEET, N_SIGN, h["door"] + Vector2(52, 4))
	# 杂物点缀
	_make_prop(props, TEX_DIR + "props.png", R_BARREL, Vector2(420, 350), 10.0)
	_make_prop(props, TEX_DIR + "props.png", R_VASE, Vector2(880, 350))
	_make_prop(props, GROUND_SHEET, N_LOG, Vector2(520, 330))


static func _build_tower_props(props: Node) -> void:
	if props == null or props.get_child_count() > 0:
		return
	# 石柱阵
	_make_prop(props, TEX_DIR + "struct.png", R_PILLAR, Vector2(300, 210), 16.0)
	_make_prop(props, TEX_DIR + "struct.png", R_PILLAR, Vector2(980, 210), 16.0)
	_make_prop(props, TEX_DIR + "struct.png", R_PILLAR_MOSSY, Vector2(300, 520), 16.0)
	_make_prop(props, TEX_DIR + "struct.png", R_PILLAR_MOSSY, Vector2(980, 520), 16.0)
	# 南侧入口拱门
	_make_prop(props, TEX_DIR + "struct.png", R_ARCH, Vector2(640, 700))
	# 碎石
	_make_prop(props, TEX_DIR + "props.png", R_ROCK_BIG, Vector2(420, 400), 12.0)
	_make_prop(props, TEX_DIR + "props.png", R_ROCK_SMALL, Vector2(860, 380))
	_make_prop(props, TEX_DIR + "props.png", R_ROCK_SMALL, Vector2(500, 560))

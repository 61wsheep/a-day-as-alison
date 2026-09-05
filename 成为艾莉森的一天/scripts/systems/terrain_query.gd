class_name TerrainQuery
extends Object

## 地形语义查询 —— 把「这格是什么地」从单一 is_grass_tile 泛化为任意 terrain_id 查询。
##
## 与「移动阻挡」分开：这里只回答「这格是什么地」，不回答「能不能走」。
## 可走性由瓦片物理碰撞负责（场景重构工程文档 v0.2 §2.2 契约②）。
## terrain_id 跨区语义一致（id 2 永远是草），具体数值由各区 tileset 定义；
## 语义用名字常量（TERRAIN_*），不用魔法数字。


## 返回 world_pos 所在格子的 terrain_id；空 / 无地形返回 -1。
## 草坪判定 = terrain_type_at(...) == TERRAIN_GRASS（常量在调用方如 SceneLayout 定义，
## 此处不重复持有，避免两处数值漂移）。
static func terrain_type_at(ground: TileMapLayer, world_pos: Vector2) -> int:
	if ground == null:
		return -1
	var cell := ground.local_to_map(ground.to_local(world_pos))
	var td := ground.get_cell_tile_data(cell)
	if td == null:
		return -1
	return td.terrain

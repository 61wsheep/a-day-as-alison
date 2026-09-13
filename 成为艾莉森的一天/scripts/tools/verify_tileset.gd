extends SceneTree
## 校验一份外部 TileSet .tres 能否被 Godot 正常加载，并打印其实际内容。
##
## 用途：场景拆分把内联 TileSet 抽成外部 .tres 之后，先单独确认这份资源本身
## 是好的，再去改场景引用——否则一旦出错，分不清是 .tres 坏了还是场景改写坏了。
##
## 用法：
##   godot --headless --path . --script res://scripts/tools/verify_tileset.gd
## （默认校验 assets/tilesets/forest_plaza.tres）

const TARGET := "res://assets/tilesets/forest_plaza.tres"


func _init() -> void:
	_check(TARGET)
	quit()


func _check(path: String) -> void:
	if not ResourceLoader.exists(path):
		push_error("资源不存在：%s" % path)
		return

	var ts: TileSet = load(path)
	if ts == null:
		push_error("加载失败：%s" % path)
		return

	print("加载成功：%s" % path)
	print("  tile_size = %s" % ts.tile_size)
	print("  图集源 %d 个：" % ts.get_source_count())
	for i in ts.get_source_count():
		var src := ts.get_source(i)
		var tex := ""
		if src is TileSetAtlasSource:
			var t: Texture2D = (src as TileSetAtlasSource).texture
			tex = t.resource_path if t else "<无纹理>"
		print("    [%d] id=%d %s  %s" % [i, ts.get_source_id(i), src.get_class(), tex])
	print("  地形集 %d 个：" % ts.get_terrain_sets_count())
	for s in ts.get_terrain_sets_count():
		print("    terrain_set%d（%d 个地形）" % [s, ts.get_terrains_count(s)])
		for t in ts.get_terrains_count(s):
			print("      terrain%d = %-12s %s" % [t, ts.get_terrain_name(s, t), ts.get_terrain_color(s, t)])

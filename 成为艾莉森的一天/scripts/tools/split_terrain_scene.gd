extends SceneTree
## C2 —— 把关卡场景里的地形 TileMapLayer 拆成独立子场景。
##
## 为什么拆：美工要负责搭地图，但整份关卡场景里还混着门 / 出生点 / 采集池 / NPC
## 这些只有主程能动的逻辑节点，双方改同一个 .tscn 无法合并。拆出地形子场景后，
## 该子场景只有美工一个写入者，可以整份接收、零合并。
##
## 拆分后 ABI 不变：父场景里实例节点仍命名为 Ground，路径 <区名>/Ground 照旧，
## 类型仍是 TileMapLayer，全部按路径寻址的代码无需改动。
##
## 本工具只负责「造出地形子场景」——交给 Godot 生成，保证 .tscn 格式与 uid 正确。
## 父场景侧的引用改写另做（手工精修，保持 diff 最小）。
##
## 用法：
##   godot --headless --path . --script res://scripts/tools/split_terrain_scene.gd \
##         -- <区名> <层级名> [输出名]
## 例：
##   ... --script res://scripts/tools/split_terrain_scene.gd -- plaza Ground
##   ... --script res://scripts/tools/split_terrain_scene.gd -- alison_room Walls alison_room_walls
##
## 输出名默认是 <区名>_terrain。同一区要拆第二层时（如 alison_room 的 Walls）
## 必须显式给出，否则会覆盖第一层的产物。


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("用法：-- <区名> <层级名> [输出名]，例如：-- plaza Ground")
		quit()
		return
	_run(args[0], args[1], args[2] if args.size() > 2 else "")
	quit()


func _run(zone: String, layer_name: String, out_name: String) -> void:
	var src := "res://scenes/levels/%s.tscn" % zone
	if out_name.is_empty():
		out_name = "%s_terrain" % zone
	var out := "res://scenes/levels/%s.tscn" % out_name

	var ps: PackedScene = load(src)
	if ps == null:
		push_error("无法加载 %s" % src)
		return

	var root := ps.instantiate()
	var layer := root.get_node_or_null(layer_name)
	if layer == null:
		push_error("%s 顶层找不到 %s 节点" % [src, layer_name])
		root.free()
		return
	if not (layer is TileMapLayer):
		push_error("%s 不是 TileMapLayer，实际是 %s" % [layer_name, layer.get_class()])
		root.free()
		return

	var used := (layer as TileMapLayer).get_used_cells().size()
	var ts: TileSet = (layer as TileMapLayer).tile_set
	print("取出 %s/%s：已铺 %d 格 · tile_set = %s"
		% [zone, layer_name, used, ts.resource_path if ts else "<无>"])

	if layer.get_child_count() > 0:
		push_warning("%s 有 %d 个子节点，拆分后它们会一并进入子场景"
			% [layer_name, layer.get_child_count()])

	# 从原场景摘出该节点，重新打包成一个只含它的场景。
	layer.get_parent().remove_child(layer)
	layer.owner = null

	var sub := PackedScene.new()
	var pack_err := sub.pack(layer)
	if pack_err != OK:
		push_error("打包失败，错误码 %d" % pack_err)
		root.free()
		return

	var save_err := ResourceSaver.save(sub, out)
	if save_err != OK:
		push_error("保存失败，错误码 %d" % save_err)
		root.free()
		return

	print("已写出 %s" % out)
	# --script 模式不走编辑器保存流程，不会给新场景分配 uid。
	# 这里吐一个合法的出来，由调用方写进文件（与项目其他场景一致）。
	print("新场景 uid：%s" % ResourceUID.id_to_text(ResourceUID.create_id()))
	root.free()

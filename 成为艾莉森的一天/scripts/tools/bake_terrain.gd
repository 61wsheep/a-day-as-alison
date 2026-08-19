extends Node

## 地形/道具烘焙工具 —— 把程序化生成的地形与道具固化进 main.tscn。
##
## 用法：godot --headless scenes/tools/bake_terrain.tscn --quit
## 重复运行 = 重新随机布局（会覆盖手动摆放的位置）。
##
## 原理：实例化 main.tscn（不进场景树，不触发 _ready）→ 清空 Ground cell 与
## Props 子节点 → SceneLayout 重新生成 → 蘑菇图标补纹理 → 设置 owner →
## PackedScene.pack() → ResourceSaver.save() 覆盖 main.tscn。
## 之后编辑器打开 main.tscn 即可直接看到 / 拖动 / 保存；运行时 game.gd 判空跳过。

const MAIN_SCENE := "res://scenes/main.tscn"

## preload 而非全局类名：避免依赖全局脚本类缓存（headless/编辑器刷新前不注册）
const SceneLayout := preload("res://scripts/systems/scene_layout.gd")


func _ready() -> void:
	_bake()


func _bake() -> void:
	var packed: PackedScene = load(MAIN_SCENE)
	if packed == null:
		printerr("[BAKE] 无法加载 %s" % MAIN_SCENE)
		get_tree().quit(1)
		return
	var root: Node2D = packed.instantiate()
	if root == null:
		printerr("[BAKE] 无法实例化 %s" % MAIN_SCENE)
		get_tree().quit(1)
		return

	# 置位烘焙标志：game.gd _ready 检测后跳过游戏初始化（仅序列化用）。
	# 进入场景树：Node::set_owner 要求 owner 是"树内"祖先（is_ancestor_of 需 in-tree）。
	SceneLayout.baking = true
	add_child(root)

	var areas: Node2D = root.get_node_or_null("Areas")
	if areas == null:
		printerr("[BAKE] 找不到 Areas 节点")
		remove_child(root)
		root.free()
		get_tree().quit(1)
		return

	# 1. 清空旧的地形与道具（保留 Area2D 门 / 玩家 / NPC / 标记点等原有节点）
	_clear_areas(areas)

	# 2. 重新生成地形与道具（SceneLayout 内新建节点已设置 owner = 场景根）
	SceneLayout.paint_area_grounds(areas)
	SceneLayout.build_all_props(areas)

	# 3. 给蘑菇的 Icon 补上视觉纹理 + owner（collectible.gd 的 _ready 已进树，可能已设纹理）
	_set_mushroom_icons(areas)

	# 4. 只给 Areas 下三个区的节点补 owner（跳过 instanced 子场景根，
	#    避免破坏 Player/NPC 等子场景的实例化）
	_set_area_owners(areas)

	# 5. 打包保存
	var scene := PackedScene.new()
	var err := scene.pack(root)
	if err != OK:
		printerr("[BAKE] pack 失败: %s" % error_string(err))
		remove_child(root)
		root.free()
		get_tree().quit(1)
		return
	err = ResourceSaver.save(scene, MAIN_SCENE)
	if err != OK:
		printerr("[BAKE] 保存失败: %s" % error_string(err))
		remove_child(root)
		root.free()
		get_tree().quit(1)
		return

	remove_child(root)
	root.free()
	SceneLayout.baking = false
	print("[BAKE] 烘焙完成，已覆盖 %s" % MAIN_SCENE)
	get_tree().quit(0)


func _clear_areas(areas: Node2D) -> void:
	for area_name in ["Plaza", "TreehouseDistrict", "StoneNestTower"]:
		var ground: TileMapLayer = areas.get_node_or_null(area_name + "/Ground")
		if ground:
			ground.clear()
		var props: Node2D = areas.get_node_or_null(area_name + "/Props")
		if props:
			for child in props.get_children():
				child.free()


func _set_mushroom_icons(areas: Node2D) -> void:
	var pool: Node2D = areas.get_node_or_null("Plaza/Mushrooms")
	if pool == null:
		return
	var tex := load("res://assets/tilesets/cainos/plant.png") as Texture2D
	var owner_node := areas.owner if areas.owner else areas
	for shroom in pool.get_children():
		if shroom is Area2D:
			var icon := shroom.get_node_or_null("Icon") as Sprite2D
			if icon:
				# 纹理可能已被 collectible.gd 的 _ready 兜底设置（无 owner），这里补 owner；
				# 若仍为空则直接设置，保证编辑器可见
				if icon.texture == null and tex:
					var at := AtlasTexture.new()
					at.atlas = tex
					at.region = SceneLayout.MUSHROOM_ICON_REGION
					icon.texture = at
				icon.owner = owner_node


func _set_area_owners(areas: Node2D) -> void:
	for child in areas.get_children():
		if child.name in ["Plaza", "TreehouseDistrict", "StoneNestTower"]:
			_set_owner_recursive(child, areas.owner if areas.owner else areas)


## 递归设置 owner；instanced 子场景根（scene_file_path 非空）整棵跳过，
## 避免把 owner 指向主场景根而破坏子场景实例化。
func _set_owner_recursive(node: Node, owner_node: Node) -> void:
	if not node.scene_file_path.is_empty():
		return
	node.owner = owner_node
	for child in node.get_children():
		_set_owner_recursive(child, owner_node)

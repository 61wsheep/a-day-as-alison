extends Node

## 地形烘焙工具 —— 重新生成三区地形并固化进各自的地形子场景。
##
## 用法：godot --headless scenes/tools/bake_terrain.tscn
## 重复运行 = 重新随机布局（会覆盖手动摆的地形，包括美工画的）。
##
## 写回目标：scenes/levels/<区>_terrain.tscn （C2 拆分后归美工所有）
##
## ⚠️ 它不再写关卡场景，也不再烘焙道具 —— 见下面两条，都是实测出来的硬限制。
##
## 【限制一】PackedScene.pack() 只为「owner == 打包根」的节点序列化内容。
## 子场景实例节点只记一行 instance=，内容整个丢弃。所以地形必须先从关卡场景
## 摘下来、单独当打包根。本工具自 M1 把 Plaza 拆到 scenes/levels/plaza.tscn
## 起失效至今，原因就是这个——main.tscn 里零 tile_map_data 即为证。
##
## 【限制二】这个 Godot 构建的 pack() 不能用来重写已有的 .tscn：
##   · 对实例节点无条件写出整份属性。即使一格没改，Ground 的 2.8 万字符
##     tile_map_data 也会被当作「实例覆盖」灌进关卡场景——正是 C2 要消灭的东西。
##   · 产物的 ext_resource 全部丢失 uid（实测 plaza.tscn：14 条 → 0 条）。
## 两条叠加，pack() 重写关卡场景既会灌回巨串、又会打断全工程的 uid 引用，
## 故本工具只写地形子场景（那里外部引用通常只有 TileSet 一条，可安全补回 uid）。
## 道具因此不再烘焙：Props 由 game.gd 在运行时对空 Props 节点生成，
## 要固化请在编辑器里摆好保存。

const LEVELS_DIR := "res://scenes/levels/"

## 区名（SceneLayout 用的名字）→ 关卡场景文件名（不含扩展名）
const ZONES := {
	"Plaza": "plaza",
	"TreehouseDistrict": "treehouse_district",
	"StoneNestTower": "stone_nest_tower",
}

## preload 而非全局类名：避免依赖全局脚本类缓存（headless/编辑器刷新前不注册）
const SceneLayout := preload("res://scripts/systems/scene_layout.gd")


func _ready() -> void:
	_run()


func _run() -> void:
	# SceneLayout 的接口是「一个 areas 容器，下面挂 <区名>/Ground」。
	# 现造一个只含这三区的容器即可复用，不必改 SceneLayout。
	var areas := Node2D.new()
	areas.name = "Areas"

	var roots := {}        # 区名 -> 关卡场景根节点
	var shared_ts := {}    # 区名 -> 原子场景的 tile_set（须保住，见 _save_terrain）

	for area_name in ZONES:
		var base: String = ZONES[area_name]
		var level_path := "%s%s.tscn" % [LEVELS_DIR, base]
		var packed: PackedScene = load(level_path)
		if packed == null:
			printerr("[BAKE] 无法加载 %s" % level_path)
			get_tree().quit(1)
			return

		var root: Node2D = packed.instantiate()
		var ground: TileMapLayer = root.get_node_or_null("Ground")
		if ground == null:
			printerr("[BAKE] %s 顶层找不到 Ground" % level_path)
			root.free()
			get_tree().quit(1)
			return

		root.name = area_name
		areas.add_child(root)
		roots[area_name] = root
		shared_ts[area_name] = ground.tile_set

	# 清空旧地形，让 paint_area_grounds 的「已有 cell 就跳过」守卫放行
	for area_name in roots:
		var g: TileMapLayer = roots[area_name].get_node("Ground")
		g.clear()

	SceneLayout.paint_area_grounds(areas)

	var failed := 0
	for area_name in roots:
		var base: String = ZONES[area_name]
		if not _save_terrain(base, roots[area_name], shared_ts[area_name]):
			failed += 1

	areas.free()

	if failed > 0:
		printerr("[BAKE] %d 个区写回失败" % failed)
		get_tree().quit(1)
		return
	print("[BAKE] 三区地形烘焙完成 → scenes/levels/*_terrain.tscn")
	get_tree().quit(0)


## 地形写回自己的子场景。必须把 Ground 摘下来当打包根——见文件头【限制一】。
func _save_terrain(base: String, root: Node2D, keep_ts: TileSet) -> bool:
	var out := "%s%s_terrain.tscn" % [LEVELS_DIR, base]
	var old_uid := _read_uid(out)

	var ground: TileMapLayer = root.get_node_or_null("Ground")
	if ground == null:
		printerr("[BAKE] %s 找不到 Ground" % base)
		return false

	# build_tileset() 是 C1 抽共享 .tres 之前的遗留：只含 1 个图集源与 terrain 0/1，
	# 而共享 .tres 有 6 个图集源 + terrain 0~4 + terrain_set 1。直接落盘会把这份
	# 残缺 TileSet 内联进子场景、把 C1 的成果覆盖掉，所以恢复原 tile_set。
	if keep_ts != null:
		ground.tile_set = keep_ts
	else:
		push_warning("[BAKE] %s 原本没有 tile_set，落盘的会是运行期构造的那份" % base)

	ground.get_parent().remove_child(ground)
	ground.owner = null

	var sub := PackedScene.new()
	var err := sub.pack(ground)
	if err == OK:
		err = ResourceSaver.save(sub, out)
	ground.free()
	if err != OK:
		printerr("[BAKE] 写地形失败 %s：%s" % [out, error_string(err)])
		return false

	_restore_uids(out, old_uid)
	return true


## 把 pack() 丢掉的 uid 补回去（见文件头【限制二】）。
func _restore_uids(path: String, scene_uid: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		printerr("[BAKE] 读不回 %s" % path)
		return
	var txt := f.get_as_text()
	f.close()

	var lines := txt.split("\n")
	var re := RegEx.new()
	re.compile('^\\[ext_resource type="([^"]+)" path="([^"]+)" id="([^"]+)"\\]$')
	for i in lines.size():
		var m := re.search(lines[i])
		if m == null:
			continue
		var u := _resource_uid(m.get_string(2))
		if u != "":
			lines[i] = '[ext_resource type="%s" uid="%s" path="%s" id="%s"]' % [
				m.get_string(1), u, m.get_string(2), m.get_string(3)]

	# 场景自身的 uid：丢了的话父场景的 instance=ExtResource 全断
	if scene_uid != "" and lines.size() > 0 and lines[0].begins_with("[gd_scene") \
			and not lines[0].contains("uid="):
		lines[0] = lines[0].replace("format=4", 'format=4 uid="%s"' % scene_uid)

	var w := FileAccess.open(path, FileAccess.WRITE)
	if w == null:
		printerr("[BAKE] 写不回 %s" % path)
		return
	w.store_string("\n".join(lines))
	w.close()


## 按资源类型找它的 uid：导入资源在伴生 .import 里，文本资源在首行，脚本在 .uid 里
func _resource_uid(res_path: String) -> String:
	var imp := res_path + ".import"
	if FileAccess.file_exists(imp):
		return _grep_uid(imp, '^uid="([^"]+)"')
	if res_path.ends_with(".tres") or res_path.ends_with(".tscn"):
		return _read_uid(res_path)
	var side := res_path + ".uid"
	if FileAccess.file_exists(side):
		var sf := FileAccess.open(side, FileAccess.READ)
		if sf:
			var s := sf.get_line().strip_edges()
			sf.close()
			return s
	return ""


func _read_uid(path: String) -> String:
	return _grep_uid(path, 'uid="([^"]+)"')


func _grep_uid(path: String, pattern: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var head := f.get_line()
	f.close()
	var re := RegEx.new()
	re.compile(pattern)
	var m := re.search(head)
	return m.get_string(1) if m else ""

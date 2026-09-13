extends SceneTree
## C1 —— 把 plaza / treehouse_district 各自内联的 TileSet 抽成一份共享外部 .tres。
##
## 为什么需要它：两个关卡场景各自内联了同一套 TileSet（6 个图集源共 ~2585 行），
## 唯一真实差异是 terrain_4 的名称与颜色（纯编辑器元数据，运行期代码只读整数
## terrain id）。内联导致同一份数据在仓库里存两份，且美工改地形时无从复用。
##
## 本工具只负责「导出 .tres」这一步——让 Godot 自己生成合法的 uid 与序列化格式，
## 而不是手写 2585 行资源数据。场景侧的引用改写另做（手工精修，保持 diff 最小）。
##
## 用法：
##   godot --headless --path . --script res://scripts/tools/extract_shared_tileset.gd

const SRC_SCENE := "res://scenes/levels/plaza.tscn"
const OUT_TRES := "res://assets/tilesets/forest_plaza.tres"

## terrain_4 在两区叫法不一致（草地装饰 / 草地点缀），统一取后者。
const TERRAIN_SET := 0
const TERRAIN_ID := 4
const TERRAIN_UNIFIED_NAME := "草地点缀"
const TERRAIN_UNIFIED_COLOR := Color(0.26903757, 0.36825904, 0.90448135, 1)


func _init() -> void:
	_run()
	quit()


func _run() -> void:
	var ps: PackedScene = load(SRC_SCENE)
	if ps == null:
		push_error("无法加载 %s" % SRC_SCENE)
		return

	var root := ps.instantiate()
	var ground: TileMapLayer = root.get_node_or_null("Ground")
	if ground == null:
		push_error("%s 顶层找不到 Ground 节点" % SRC_SCENE)
		return

	var ts: TileSet = ground.tile_set
	if ts == null:
		push_error("Ground 没有 tile_set")
		return

	print("源 TileSet：图集源 %d 个 · 地形集 %d 个" % [ts.get_source_count(), ts.get_terrain_sets_count()])
	for t in ts.get_terrains_count(TERRAIN_SET):
		print("  terrain_set%d/terrain%d = %s" % [TERRAIN_SET, t, ts.get_terrain_name(TERRAIN_SET, t)])

	# 统一 terrain_4 的名称与颜色，消掉两区之间的唯一语义分歧。
	var was := ts.get_terrain_name(TERRAIN_SET, TERRAIN_ID)
	ts.set_terrain_name(TERRAIN_SET, TERRAIN_ID, TERRAIN_UNIFIED_NAME)
	ts.set_terrain_color(TERRAIN_SET, TERRAIN_ID, TERRAIN_UNIFIED_COLOR)
	print("terrain_%d：%s → %s" % [TERRAIN_ID, was, TERRAIN_UNIFIED_NAME])

	# --script 模式不走编辑器的保存流程，不会自动分配 uid。
	# 项目惯例是 .tres 首行带 uid、场景按 uid 引用；缺 uid 则文件一旦移动就会断链。
	# 调用方须先删除旧文件，这里无条件分配新 uid。
	var new_uid := ResourceUID.create_id()
	ResourceUID.set_id(new_uid, OUT_TRES)
	print("分配 uid：%s" % ResourceUID.id_to_text(new_uid))

	var err := ResourceSaver.save(ts, OUT_TRES)
	if err != OK:
		push_error("保存失败，错误码 %d" % err)
		return

	print("已写出 %s" % OUT_TRES)
	root.free()

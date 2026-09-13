extends SceneTree

## 交付场景体检器 —— 校验外部引用 / 契约节点 / 脚本挂载 / TileMap 层
##
## 用途：美术同学交付的 .tscn 在别的环境里画好，脚本与 uid 常常丢失或对不上。
## 本工具在「落盘后、合并前」跑一次，把断链和契约破损全部列出来。
##
## 用法（无头）：
##   Godot_v4.7.1-stable_win64_console.exe --headless --path . \
##       --script res://scripts/tools/check_scene_refs.gd -- [选项] [场景路径...]
##
## 选项：
##   --baseline <仓库相对路径>   与 git HEAD 里的该文件对比（模式 A：丢了什么）
##   --baseline-file <绝对路径>  与指定文件对比（模式 A 的离线替代）
## 不传场景路径时，默认扫描 res://scenes/levels/ 下全部 .tscn。
##
## 退出码：0 = 通过；1 = 存在错误。

const SKIP_DIRS := [".godot", ".git", "addons"]

var uid2path: Dictionary = {}   # "uid://x" -> "res://..."
var path2uid: Dictionary = {}   # "res://..." -> "uid://x"
var n_err := 0
var n_warn := 0
var _queue: Array = []            # 待校验队列（含自动发现实例化的子场景）
var _checked: Dictionary = {}     # 已校验，防环
var _baseline_map: Dictionary = {}  # 场景 -> 它的基线文件（只对显式传入的生效）


# ────────────────────────────── 入口 ──────────────────────────────

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var targets: Array = []
	var baseline_file := ""
	var i := 0
	while i < args.size():
		var a: String = args[i]
		if a == "--baseline" and i + 1 < args.size():
			baseline_file = _baseline_from_git(args[i + 1])
			i += 2
		elif a == "--baseline-file" and i + 1 < args.size():
			baseline_file = args[i + 1]
			i += 2
		else:
			targets.append(a)
			i += 1

	print("扫描工程 uid 真值表 ...")
	_scan("res://")
	print("  已收录 %d 条 uid 映射\n" % uid2path.size())

	if targets.is_empty():
		targets = _list_scenes("res://scenes/levels")

	if targets.is_empty():
		print("没有可校验的场景。")
		quit(0)
		return

	for t in targets:
		_baseline_map[str(t)] = baseline_file
		_queue.append(str(t))

	# 队列会在校验过程中增长：遇到实例化的子场景自动入队
	var idx := 0
	while idx < _queue.size():
		var s: String = _queue[idx]
		idx += 1
		if _checked.has(s):
			continue
		_checked[s] = true
		_check_scene(s, _baseline_map.get(s, ""))

	print("\n" + "=".repeat(64))
	print("合计：%d 处错误 · %d 处告警" % [n_err, n_warn])
	quit(1 if n_err > 0 else 0)


# ──────────────────────── uid 真值表扫描 ────────────────────────

func _scan(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if d.current_is_dir():
			if not name.begins_with(".") and not SKIP_DIRS.has(name):
				_scan(dir.path_join(name))
		else:
			var full := dir.path_join(name)
			if name.ends_with(".import"):
				_record_import(full)
			elif name.ends_with(".uid"):
				_record_sidecar(full)
			elif name.ends_with(".tscn") or name.ends_with(".tres"):
				_record_header_uid(full)
		name = d.get_next()
	d.list_dir_end()


## 图片等导入资源：uid 记在 .import 里
func _record_import(full: String) -> void:
	var txt := _read_text(full)
	var u := _attr(txt, "uid")
	var src := _attr(txt, "source_file")
	if u != "" and src != "":
		uid2path[u] = src
		path2uid[src] = u


## 脚本：uid 记在同名 .uid 边车文件里
func _record_sidecar(full: String) -> void:
	var u := _read_text(full).strip_edges()
	if u.begins_with("uid://"):
		var target := full.trim_suffix(".uid")
		uid2path[u] = target
		path2uid[target] = u


## 场景/资源：uid 写在首行 [gd_scene ...] / [gd_resource ...] 里
func _record_header_uid(full: String) -> void:
	var f := FileAccess.open(full, FileAccess.READ)
	if f == null:
		return
	var head := f.get_line()
	f.close()
	var u := _attr(head, "uid")
	if u.begins_with("uid://"):
		uid2path[u] = full
		path2uid[full] = u


# ──────────────────────── 单个场景校验 ────────────────────────

func _check_scene(path: String, baseline_file: String) -> void:
	if not FileAccess.file_exists(path):
		print("\n=== %s ===" % path)
		_err("文件不存在，跳过")
		return

	var lines := _read_text(path).split("\n")
	var ext := {}      # id -> {type, uid, path, line}
	var nodes := []    # {name, type, parent, inst, line, props}
	_parse(lines, ext, nodes)

	print("\n=== %s ===" % path)
	print("  节点 %d · 外部引用 %d" % [nodes.size(), ext.size()])

	_check_ext_resources(ext)
	_check_dangling_refs(lines, ext)
	_check_scripts(nodes, ext)
	if _looks_like_level(nodes):
		_check_contract(nodes, ext, path)
	if baseline_file != "":
		_check_baseline(path, baseline_file, nodes)


## 模式 B-1：外部引用可解析性（path 在不在 / uid 对不对）
func _check_ext_resources(ext: Dictionary) -> void:
	for id in ext:
		var e: Dictionary = ext[id]
		var p: String = e["path"]
		var dec: String = e["uid"]

		if p == "":
			_warn("[引用] id=%s 没有 path" % id)
			continue

		if not FileAccess.file_exists(p):
			var msg := "[断链] id=%s (%s)\n         场景写: %s   ← 不存在" % [id, e["type"], p]
			var cand := _find_same_name(p)
			if cand != "":
				msg += "\n         实况候选: %s   %s" % [cand, path2uid.get(cand, "(无 uid)")]
			_err(msg)
			continue

		if e["type"] == "PackedScene":
			_enqueue(p)   # 实例化的子场景也要一起体检

		var real: String = path2uid.get(p, "")
		if real == "":
			_warn("[引用] id=%s %s 无法确定其 uid（非导入资源？）" % [id, p])
		elif dec == "":
			_warn("[uid 缺失] id=%s %s  真实 uid=%s" % [id, p, real])
		elif dec != real:
			_err("[uid 不符] id=%s\n         场景写: %s\n         实况:   %s\n         资源:   %s" % [id, dec, real, p])


## 模式 B-2：内部一致性 —— 正文引用的 ExtResource("id") / SubResource("id")
## 必须在文件里声明过。美工删掉一条 ext_resource 却留下节点属性引用时，就断在这里。
func _check_dangling_refs(lines: PackedStringArray, ext: Dictionary) -> void:
	var subs := {}
	var re_sub := RegEx.new()
	re_sub.compile("^\\[sub_resource\\b")
	var re_id := RegEx.new()
	re_id.compile("id=\"([^\"]+)\"")
	for ln in lines:
		if re_sub.search(ln) != null:
			var m := re_id.search(ln)
			if m:
				subs[m.get_string(1)] = true

	var re_use := RegEx.new()
	re_use.compile('(Ext|Sub)Resource\\("([^"]+)"\\)')
	var seen := {}
	for i in lines.size():
		var ln := lines[i]
		if ln.begins_with("[ext_resource") or ln.begins_with("[sub_resource"):
			continue
		for m in re_use.search_all(ln):
			var kind := m.get_string(1)
			var id := m.get_string(2)
			var k := kind + ":" + id
			if seen.has(k):
				continue
			seen[k] = true
			if kind == "Ext" and not ext.has(id):
				_err("[悬空引用] 第 %d 行 ExtResource(\"%s\") 没有对应声明" % [i + 1, id])
			elif kind == "Sub" and not subs.has(id):
				_err("[悬空引用] 第 %d 行 SubResource(\"%s\") 没有对应声明" % [i + 1, id])


## 模式 B-3：脚本挂载（置空覆盖 / 该挂没挂）
func _check_scripts(nodes: Array, ext: Dictionary) -> void:
	for n in nodes:
		var props: Dictionary = n["props"]
		var nm: String = n["name"]
		var ty: String = n["type"]

		# script = null 会把实例自带脚本覆盖成空
		if props.get("script", "") == "null":
			_err("[脚本置空] %s  写死 script = null，会覆盖实例自带脚本" % nm)

		# 门 / 告示板：Area2D 且名字有约定，必须挂脚本
		if ty == "Area2D" and (nm.begins_with("Door") or nm.begins_with("NoticeBoard")):
			var s: String = props.get("script", "")
			if s == "" or s == "null":
				_err("[脚本缺失] %s (Area2D)  未挂脚本" % nm)
			else:
				var sid := _ext_id(s)
				if sid != "" and ext.has(sid):
					var sp: String = ext[sid]["path"]
					if not FileAccess.file_exists(sp):
						_err("[脚本断链] %s -> %s 不存在" % [nm, sp])


## 模式 B-4：契约节点（§2.1 骨架）
func _check_contract(nodes: Array, ext: Dictionary, path: String) -> void:
	var by_name := {}
	for n in nodes:
		if n["parent"] == "":
			by_name[n["name"]] = n

	var root: Dictionary = {}
	for n in nodes:
		if n["parent"] == "":
			root = n
			break

	if root.is_empty():
		_err("[契约] 找不到根节点")
		return
	if root["type"] != "Node2D" and not root["type"].is_empty():
		_warn("[契约] 根节点类型是 %s，契约要求 Node2D" % root["type"])
	if root["props"].get("y_sort_enabled", "") != "true":
		_warn("[契约] 根节点未开 y_sort_enabled")

	if not by_name.has("Ground"):
		_err("[契约] 缺 Ground 节点")
	else:
		var g: Dictionary = by_name["Ground"]
		if g["type"] != "TileMapLayer":
			_warn("[契约] Ground 类型是 %s，契约要求 TileMapLayer" % g["type"])
		var ts: String = g["props"].get("tile_set", "")
		if ts == "":
			_warn("[契约] Ground 没有 tile_set")
		else:
			var sid := _ext_id(ts)
			if sid != "" and ext.has(sid) and not FileAccess.file_exists(ext[sid]["path"]):
				_err("[契约] Ground.tile_set -> %s 不存在" % ext[sid]["path"])

	if not by_name.has("Props"):
		_warn("[契约] 缺 Props 节点")

	var spawns := 0
	var doors: Array = []
	var unnamed := []
	for n in nodes:
		var nm: String = n["name"]
		if n["parent"] == "" and nm.begins_with("Spawn"):
			spawns += 1
		if n["parent"] == "" and nm.begins_with("Door"):
			doors.append(n)
		if n["type"] == "TileMapLayer" and _is_default_layer_name(nm):
			unnamed.append(nm)

	if spawns == 0:
		_warn("[契约] 没有任何 Spawn* 出生点")
	for d in doors:
		if not d["props"].has("target_area") or not d["props"].has("target_spawn"):
			_err("[契约] %s 缺 target_area / target_spawn 导出值" % d["name"])
	if unnamed.size() > 0:
		_warn("[契约] 无名默认图层：%s（契约⑦要求具名，如 Overlay）" % ", ".join(unnamed))


## 模式 A：与基线对比，列出「丢了什么」
func _check_baseline(path: String, baseline_file: String, nodes: Array) -> void:
	if not FileAccess.file_exists(baseline_file):
		_warn("[基线] 读不到基线文件 %s" % baseline_file)
		return

	var bl_ext := {}
	var bl_nodes := []
	_parse(_read_text(baseline_file).split("\n"), bl_ext, bl_nodes)

	var now := {}
	for n in nodes:
		now[_key(n)] = n

	print("  ── 对比基线（%d 节点）──" % bl_nodes.size())

	var lost_script := 0
	var lost_prop := 0
	for b in bl_nodes:
		var k := _key(b)
		if not now.has(k):
			_err("[节点丢失] %s" % k)
			continue
		var c: Dictionary = now[k]

		var bs: String = b["props"].get("script", "")
		var cs: String = c["props"].get("script", "")
		if bs.begins_with("ExtResource") and (cs == "" or cs == "null"):
			var sp := _ext_path(bl_ext, bs)
			_err("[脚本丢失] %s  基线挂 %s，交付版没有" % [k, sp if sp != "" else bs])
			lost_script += 1
		elif bs.begins_with("ExtResource") and cs.begins_with("ExtResource") and bs != cs:
			_warn("[脚本变更] %s  基线 %s → 交付 %s" % [k, _ext_path(bl_ext, bs), _ext_path(bl_ext, cs)])

		# 基线有的属性，交付版没有 = 丢了。重点盯「指向资源的属性」（shape/texture/tile_set…）
		# 被整条删掉的情况——它既不是悬空引用，也不在契约里，最易漏。
		for key in b["props"]:
			if c["props"].has(key):
				continue
			if key == "script":
				continue   # 已由上面的「脚本丢失」专门报，别再报一遍
			var bv: String = b["props"][key]
			if bv.begins_with("ExtResource") or bv.begins_with("SubResource"):
				_err("[属性丢失] %s  %s（基线 = %s）" % [k, key, bv])
				lost_prop += 1
			elif key in ["target_area", "target_spawn"]:
				_err("[导出值丢失] %s  %s（基线 = %s）" % [k, key, bv])
				lost_prop += 1

	if lost_script == 0 and lost_prop == 0:
		print("  ✓ 基线对比无脚本/导出值丢失")


# ──────────────────────── 解析 ────────────────────────

func _parse(lines: PackedStringArray, ext: Dictionary, nodes: Array) -> void:
	var cur := {}
	for i in lines.size():
		var ln := lines[i]
		if ln.begins_with("[ext_resource"):
			ext[_attr(ln, "id")] = {
				"type": _attr(ln, "type"),
				"uid": _attr(ln, "uid"),
				"path": _attr(ln, "path"),
				"line": i + 1,
			}
		elif ln.begins_with("[node "):
			if not cur.is_empty():
				nodes.append(cur)
			var par := _attr(ln, "parent")
			if par == ".":
				par = ""   # 顶层节点的 parent 写作 "."，归一成空串，下游才好判
			cur = {
				"name": _attr(ln, "name"),
				"type": _attr(ln, "type"),
				"parent": par,
				"inst": _ext_id(ln),
				"line": i + 1,
				"props": {},
			}
		elif ln.begins_with("["):
			if not cur.is_empty():
				nodes.append(cur)
				cur = {}
		elif not cur.is_empty() and ln.contains(" = "):
			var eq := ln.find(" = ")
			var k := ln.substr(0, eq).strip_edges()
			if not cur["props"].has(k):
				cur["props"][k] = ln.substr(eq + 3).strip_edges()
	if not cur.is_empty():
		nodes.append(cur)


# ──────────────────────── 小工具 ────────────────────────

## 取 name="..." / uid="..." 这类属性的值
func _attr(line: String, key: String) -> String:
	var re := RegEx.new()
	re.compile("\\b%s=\"([^\"]*)\"" % key)
	var m := re.search(line)
	return m.get_string(1) if m else ""


## 取 ExtResource("xxx") 里的 xxx
func _ext_id(s: String) -> String:
	var re := RegEx.new()
	re.compile('ExtResource\\("([^"]+)"\\)')
	var m := re.search(s)
	return m.get_string(1) if m else ""


func _ext_path(ext: Dictionary, ref: String) -> String:
	var id := _ext_id(ref)
	return ext[id]["path"] if ext.has(id) else ""


func _key(n: Dictionary) -> String:
	var p: String = n["parent"]
	return (p + "/" + n["name"]) if p != "" else n["name"]


## TileMapLayer / TileMapLayer2 / TileMapLayer3 ... = Godot 自动生成的默认名，未按契约⑦具名
func _is_default_layer_name(nm: String) -> bool:
	var re := RegEx.new()
	re.compile("^TileMapLayer[0-9]*$")
	return re.search(nm) != null


## 顶层有 Ground 就当作「关卡场景」，跑契约校验。
## 不能用路径判断：交付件可能落在 scenes/ 而非 scenes/levels/（就地校验正是本工具用途）。
func _looks_like_level(nodes: Array) -> bool:
	for n in nodes:
		if n["parent"] == "" and n["name"] == "Ground":
			return true
	return false


func _find_same_name(p: String) -> String:
	var base := p.get_file()
	for k in path2uid:
		if k.get_file() == base:
			return k
	return ""


func _enqueue(path: String) -> void:
	if not _checked.has(path) and not _queue.has(path):
		_queue.append(path)
		_baseline_map[path] = ""


func _list_scenes(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if not d.current_is_dir() and name.ends_with(".tscn"):
			out.append(dir.path_join(name))
		name = d.get_next()
	d.list_dir_end()
	out.sort()
	return out


func _read_text(p: String) -> String:
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return ""
	var t := f.get_as_text()
	f.close()
	return t


## 模式下 A 的 git 取基线：把 HEAD 里的版本落到 user:// 再比对
func _baseline_from_git(repo_rel: String) -> String:
	var proj := ProjectSettings.globalize_path("res://").replace("\\", "/")
	var root := _git(proj, ["rev-parse", "--show-toplevel"]).strip_edges().replace("\\", "/")
	if root == "":
		_warn("[基线] 不在 git 仓库里，跳过模式 A")
		return ""
	var sub := proj.trim_prefix(root).trim_prefix("/")
	var txt := _git(root, ["show", "HEAD:" + sub + repo_rel])
	if txt == "":
		_warn("[基线] git 取不到 HEAD:%s%s" % [sub, repo_rel])
		return ""
	var out := "user://__baseline.tscn"
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(txt)
	f.close()
	return out


func _git(cwd: String, args: Array) -> String:
	var out: Array = []
	var code := OS.execute("git", ["-C", cwd] + args, out, true)
	if code != 0:
		return ""
	var s := ""
	for o in out:
		s += str(o)
	return s


func _err(msg: String) -> void:
	n_err += 1
	print("  [✗] " + msg)


func _warn(msg: String) -> void:
	n_warn += 1
	print("  [!] " + msg)

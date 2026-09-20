extends Node

## F12 调试截图。
##
## 为什么挂在 autoload：autoload 在任何场景下都会加载，所以无论跑主场景还是
## 编辑器里 F6 单跑某个关卡场景，F12 都生效。（旧实现挂在 game.gd 上，单跑场景就没有。）
##
## 尺寸保证 1920×1080：本项目 stretch 模式是 canvas_items，窗口尺寸即抓帧尺寸，
## 而 visible_rect 恒为基准分辨率 1152×648。所以 F12 时把窗口临时拉到 1920×1080，
## 抓到的就是 1920×1080，且构图与平时完全一致（不改变基准分辨率，不影响任何布局、
## 相机边界和 16px 网格），抓完立刻还原窗口。

## 目标出图尺寸。改这一处即可换输出分辨率。
const TARGET_SIZE := Vector2i(1920, 1080)
const SHOT_DIR := "res://debug_shots/"
## 抓帧尺寸万一不是 TARGET_SIZE（小屏被系统夹住窗口），是否缩放兜底。关掉则只告警。
const ENFORCE_SIZE := true

var _capturing := false


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F12:
		_capture()


## 抓一帧存到 SHOT_DIR。用 _capturing 挡住连按导致的并发。
func _capture() -> void:
	if _capturing:
		return
	_capturing = true

	var vp := get_viewport()
	if vp == null:
		print("[shot] 取不到根 viewport")
		_capturing = false
		return

	var prev_size := DisplayServer.window_get_size()
	var prev_pos := DisplayServer.window_get_position()
	var resized := prev_size != TARGET_SIZE
	if resized:
		DisplayServer.window_set_size(TARGET_SIZE)
		# 只等一帧时渲染缓冲还是旧尺寸，实测要两帧才稳定
		await get_tree().process_frame
		await get_tree().process_frame

	await RenderingServer.frame_post_draw  # 等本帧画完再抓，像素才完整
	var img := vp.get_texture().get_image()

	if resized:
		DisplayServer.window_set_size(prev_size)
		DisplayServer.window_set_position(prev_pos)

	if img == null:
		print("[shot] 抓帧失败（--headless 或 dummy 渲染器下取不到纹理）")
		_capturing = false
		return

	if img.get_size() != TARGET_SIZE:
		if ENFORCE_SIZE:
			print("[shot] 抓帧 %s ≠ %s，已缩放兜底（窗口多半被系统夹住了）" % [img.get_size(), TARGET_SIZE])
			img.resize(TARGET_SIZE.x, TARGET_SIZE.y, Image.INTERPOLATE_NEAREST)
		else:
			print("[shot] 警告：抓帧 %s ≠ %s" % [img.get_size(), TARGET_SIZE])

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	var path := SHOT_DIR + _file_name()
	var err := img.save_png(path)
	if err == OK:
		print("[shot] 已存 %s  %s" % [path, img.get_size()])
	else:
		print("[shot] 保存失败 err=%d -> %s" % [err, path])
	_capturing = false


## 文件名：shot_<场景或区域>_<时间戳>.png
## 单跑场景时 GameManager.current_area 不可信（它可能还停在默认值），所以默认用
## 当前场景名；只有确实在跑 main 时，才换成 GameManager 管的区域名。
func _file_name() -> String:
	var label := "unknown"
	var cs := get_tree().current_scene
	if cs != null and not cs.name.is_empty():
		label = str(cs.name)

	if label == "main":
		var gm := get_node_or_null("/root/GameManager")
		if gm != null:
			var area: Variant = gm.get("current_area")
			if area is String and not (area as String).is_empty():
				label = area

	var t := Time.get_datetime_string_from_system().replace(":", "").replace(" ", "_")
	return "shot_%s_%s.png" % [label, t]

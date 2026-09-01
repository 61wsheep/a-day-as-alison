extends CanvasLayer

## 按键帮助面板 — 右上角常驻提示 + K 键开关。
## 面板列出全部功能键（彩色图标 + 动作 + 按键），点击条目可查看按键说明；可隐藏。
## 打开期间锁定玩家移动；对话/其他界面打开时自动关闭。

const KEY_ROWS := [
	{"color": Color(0.45, 0.75, 0.45), "action": "移动", "key": "WASD / 方向键",
	 "detail": "WASD 或方向键控制艾莉森在森林中移动。"},
	{"color": Color(0.9, 0.6, 0.3), "action": "交互（对话 / 采集）", "key": "E",
	 "detail": "靠近 NPC 按 E 对话；靠近采集物按 E 采集。"},
	{"color": Color(0.45, 0.6, 0.9), "action": "状态面板", "key": "Tab",
	 "detail": "打开/关闭状态面板（天数、金币、线索、好感度）。"},
	{"color": Color(0.9, 0.8, 0.4), "action": "背包", "key": "I",
	 "detail": "打开/关闭背包（查看已采集的物品）。"},
	{"color": Color(0.7, 0.5, 0.85), "action": "推进时间", "key": "T",
	 "detail": "跳过当前时段，加速推进一天。"},
	{"color": Color(0.55, 0.65, 0.7), "action": "按键帮助", "key": "K",
	 "detail": "打开/关闭本按键帮助面板。"},
	{"color": Color(0.75, 0.4, 0.4), "action": "关闭 / 退出", "key": "Esc",
	 "detail": "关闭当前面板，或退出对话。"},
]

var _chip: Button
var _dim: ColorRect
var _panel: PanelContainer
var _rows: VBoxContainer
var _open := false
var _dlg_active := false


func _ready() -> void:
	layer = 12
	_build_chip()
	_build_panel()
	var bus = get_node("/root/EventBus")
	bus.dialogue_started.connect(func():
		_dlg_active = true
		_close())
	bus.dialogue_ended.connect(func(): _dlg_active = false)


func _build_chip() -> void:
	_chip = Button.new()
	_chip.text = "按键   [Tab] 状态 · [I] 背包 · [K] 帮助"
	_chip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_chip.offset_left = -320
	_chip.offset_top = 8
	_chip.offset_right = -8
	_chip.offset_bottom = 32
	_chip.focus_mode = Control.FOCUS_NONE
	_chip.add_theme_font_size_override("font_size", 13)
	_chip.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	_chip.pressed.connect(_toggle)
	add_child(_chip)


func _build_panel() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.5)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)
	_dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			_close())

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(430, 0)
	_panel.offset_left = -215
	_panel.offset_top = -180
	_panel.offset_right = 215
	_panel.offset_bottom = 180
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_panel.add_child(vbox)

	var title := Label.new()
	title.text = "—— 按键一览 ——"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
	vbox.add_child(title)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 5)
	vbox.add_child(_rows)
	for row in KEY_ROWS:
		_rows.add_child(_make_row(row))

	var hint := Label.new()
	hint.text = "[K] 或点击右上角关闭 · 点击条目查看说明"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	vbox.add_child(hint)

	_dim.hide()
	_panel.hide()


func _make_row(row: Dictionary) -> Button:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.icon = _make_icon(row.get("color", Color.WHITE))
	btn.expand_icon = true
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_size_override("font_size", 15)
	btn.text = "%s    [%s]" % [row.get("action", ""), row.get("key", "")]
	btn.pressed.connect(func() -> void:
		get_node("/root/EventBus").toast.emit("[%s] %s" % [row.get("key", ""), row.get("detail", "")]))
	return btn


func _make_icon(color: Color) -> Texture2D:
	var img := Image.create(22, 22, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if _is_text_focus_owner():
		return
	if event.keycode == KEY_K:
		_toggle()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and _open:
		_close()
		get_viewport().set_input_as_handled()


func _is_text_focus_owner() -> bool:
	var c := get_viewport().gui_get_focus_owner()
	return c is LineEdit


func _toggle() -> void:
	if _open:
		_close()
	else:
		_dim.show()
		_panel.show()
		_open = true
		_set_player_locked(true)


func _close() -> void:
	if not _open:
		return
	_dim.hide()
	_panel.hide()
	_open = false
	_set_player_locked(false)


func is_open() -> bool:
	return _open


func _set_player_locked(locked: bool) -> void:
	var p := get_tree().get_first_node_in_group("player")
	if p and "_movement_locked" in p:
		p._movement_locked = locked

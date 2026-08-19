extends CanvasLayer

## 对话 UI — 左右大立绘 + 底部对话面板（ui_dialogue_box 素材）+ 三选项（固定/不回答/自由输入）+ 提示气泡。
## 全部节点由代码构建，监听 EventBus 信号驱动。

const PORTRAIT_DIR := {
	"player": "res://assets/portraits/alison/",
	"soraya": "res://assets/portraits/soraya/",
	"padwin": "res://assets/portraits/padwin/",
	"cactus": "res://assets/portraits/cactus/",
}

const PORTRAIT_FILE := {
	"player": {
		"angry_smile": "chr_alison_angry_smile.png", "angry_talk": "chr_alison_angry_talk.png",
		"cry": "chr_alison_cry.png", "furious_talk": "chr_alison_furious_talk.png",
		"laugh_talk_01": "chr_alison_laugh_talk_01.png", "laugh_talk_02": "chr_alison_laugh_talk_02.png",
		"laugh_talk_03": "chr_alison_laugh_talk_03.png", "laugh_talk_04": "chr_alison_laugh_talk_04.png",
		"smile_01": "chr_alison_smile_01.png", "smile_02": "chr_alison_smile_02.png",
		"smile_03": "chr_alison_smile_03.png", "smile_04": "chr_alison_smile_04.png",
		"smile_05": "chr_alison_smile_05.png", "talk_01": "chr_alison_talk_01.png",
		"talk_02": "chr_alison_talk_02.png",
	},
	"soraya": {
		"intro": "npc_soraya_intro.png",
		"laugh_talk_01": "npc_soraya_laugh_talk_01.png", "laugh_talk_02": "npc_soraya_laugh_talk_02.png",
		"laugh_talk_03": "npc_soraya_laugh_talk_03.png", "smile_01": "npc_soraya_smile_01.png",
		"smile_02": "npc_soraya_smile_02.png", "smile_03": "npc_soraya_smile_03.png",
	},
	"padwin": {
		"angry": "npc_padwin_angry.png", "awkward": "npc_padwin_awkward.png",
		"happy": "npc_padwin_happy.png", "helpless": "npc_padwin_helpless.png",
		"idle": "npc_padwin_idle.png", "shy": "npc_padwin_shy.png",
		"talk": "npc_padwin_talk.png", "think": "npc_padwin_think.png",
	},
	"cactus": {
		"angry": "npc_cactus_angry.png", "happy": "npc_cactus_happy.png",
		"helpless": "npc_cactus_helpless.png", "idle": "npc_cactus_idle.png",
		"sad": "npc_cactus_sad.png", "shy": "npc_cactus_shy.png",
		"talk": "npc_cactus_talk.png", "think": "npc_cactus_think.png",
	},
}

const PORTRAIT_DEFAULT := {
	"player": "talk_01", "soraya": "smile_01", "padwin": "idle", "cactus": "idle",
}

## 立绘目录别名（npc_id → 立绘目录键）
const PORTRAIT_ALIAS := {
	"cactus_bishop": "cactus",
}

const PANEL_TEXTURE := "res://assets/ui/ui_dialogue_box.png"
const PORTRAIT_W := 480.0   # 立绘宽（1.36:1 → 高约 353）
const PORTRAIT_H := 353.0

var _panel: PanelContainer
var _npc_portrait: TextureRect
var _player_portrait: TextureRect
var _name_label: Label
var _text_label: Label
var _hint_label: Label
var _ai_badge: Label
var _choice_panel: PanelContainer
var _choice_box: VBoxContainer
var _interact_hint: Label
var _toast_label: Label
var _toast_timer: Timer
var _portrait_cache: Dictionary = {}
var _thinking_label: Label
var _free_input: LineEdit

# -- AI 对话状态 --
var _ai_mode := false
var _ai_free_input_enabled := false
var _thinking_npc := ""


func _ready() -> void:
	layer = 10
	_build_ui()
	var bus = get_node("/root/EventBus")
	bus.interaction_hint_show.connect(func(): _interact_hint.show())
	bus.interaction_hint_hide.connect(func(): _interact_hint.hide())
	bus.dialogue_line.connect(_on_dialogue_line)
	bus.dialogue_choices.connect(_on_choices)
	bus.dialogue_ended.connect(_on_dialogue_ended)
	bus.toast.connect(_show_toast)
	bus.dialogue_ai_meta.connect(_on_dialogue_ai_meta)
	bus.ai_thinking.connect(_on_ai_thinking)


func _build_ui() -> void:
	# -- 交互提示（右下角） --
	_interact_hint = Label.new()
	_interact_hint.text = "[E] 对话"
	_interact_hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_interact_hint.offset_left = -140
	_interact_hint.offset_top = -48
	_interact_hint.offset_right = -16
	_interact_hint.offset_bottom = -16
	_interact_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_interact_hint.add_theme_font_size_override("font_size", 18)
	_interact_hint.hide()
	add_child(_interact_hint)

	# -- 左右大立绘（NPC 左 / 玩家右），先加 → 面板盖其上 --
	_npc_portrait = _make_portrait(Control.PRESET_BOTTOM_LEFT, 0, -PORTRAIT_H, PORTRAIT_W, 0)
	add_child(_npc_portrait)

	_player_portrait = _make_portrait(Control.PRESET_BOTTOM_RIGHT, -PORTRAIT_W, -PORTRAIT_H, 0, 0)
	add_child(_player_portrait)

	# -- 底部对话面板（ui_dialogue_box 素材九宫格） --
	var sb := StyleBoxTexture.new()
	sb.texture = load(PANEL_TEXTURE)
	sb.texture_margin_left = 80
	sb.texture_margin_top = 40
	sb.texture_margin_right = 80
	sb.texture_margin_bottom = 40
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_left = 166
	_panel.offset_right = -166
	_panel.offset_top = -192
	_panel.offset_bottom = -12
	_panel.hide()
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(vbox)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	vbox.add_child(name_row)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 20)
	_name_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
	name_row.add_child(_name_label)

	# AI 对话标记（绿字小标，有 AI 能力时显示）
	_ai_badge = Label.new()
	_ai_badge.text = "AI 对话中"
	_ai_badge.add_theme_font_size_override("font_size", 13)
	_ai_badge.add_theme_color_override("font_color", Color(0.45, 0.9, 0.55))
	_ai_badge.hide()
	name_row.add_child(_ai_badge)

	_text_label = Label.new()
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.add_theme_font_size_override("font_size", 17)
	_text_label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.95))
	vbox.add_child(_text_label)

	_hint_label = Label.new()
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint_label.add_theme_font_size_override("font_size", 12)
	_hint_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	vbox.add_child(_hint_label)

	# -- 选项面板（对话面板上方，从底部基准线向上生长，内容多不裁剪） --
	_choice_panel = PanelContainer.new()
	_choice_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_choice_panel.offset_left = 216
	_choice_panel.offset_right = -216
	_choice_panel.offset_top = -204
	_choice_panel.offset_bottom = -204
	_choice_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_choice_panel.hide()
	add_child(_choice_panel)

	_choice_box = VBoxContainer.new()
	_choice_box.add_theme_constant_override("separation", 5)
	_choice_panel.add_child(_choice_box)

	# -- 提示气泡（顶部中央） --
	_toast_label = Label.new()
	_toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast_label.offset_left = -300
	_toast_label.offset_right = 300
	_toast_label.offset_top = 12
	_toast_label.offset_bottom = 44
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.add_theme_font_size_override("font_size", 16)
	_toast_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
	_toast_label.hide()
	add_child(_toast_label)

	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.timeout.connect(func(): _toast_label.hide())
	add_child(_toast_timer)

	# -- AI 思考加载态（对话框中央） --
	_thinking_label = Label.new()
	_thinking_label.set_anchors_preset(Control.PRESET_CENTER)
	_thinking_label.offset_left = -260
	_thinking_label.offset_right = 260
	_thinking_label.offset_top = -24
	_thinking_label.offset_bottom = 24
	_thinking_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_thinking_label.add_theme_font_size_override("font_size", 18)
	_thinking_label.hide()
	add_child(_thinking_label)


func _make_portrait(preset: int, left: float, top: float, right: float, bottom: float) -> TextureRect:
	var p := TextureRect.new()
	p.set_anchors_preset(preset)
	p.offset_left = left
	p.offset_top = top
	p.offset_right = right
	p.offset_bottom = bottom
	p.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	p.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	p.hide()
	return p


func _on_dialogue_line(speaker_id: String, display_name: String, text: String, emotion: String) -> void:
	_choice_panel.hide()
	_name_label.text = display_name
	_text_label.text = text
	_hint_label.text = "[E] 继续"
	_update_portrait(speaker_id, emotion)
	_panel.show()


func _update_portrait(speaker_id: String, emotion: String) -> void:
	if speaker_id == "player":
		_set_portrait(_player_portrait, "player", emotion)
		_npc_portrait.hide()
	elif speaker_id == "narrator":
		_npc_portrait.hide()
		_player_portrait.hide()
	else:
		_set_portrait(_npc_portrait, speaker_id, emotion)
		_player_portrait.hide()


func _set_portrait(target: TextureRect, key: String, emotion: String) -> void:
	var dir_key: String = PORTRAIT_ALIAS.get(key, key)
	if dir_key == "narrator" or not PORTRAIT_FILE.has(dir_key):
		target.texture = null
		target.hide()
		return
	target.show()
	var emo := emotion
	if emo == "" or not PORTRAIT_FILE[dir_key].has(emo):
		emo = PORTRAIT_DEFAULT.get(dir_key, "")
	var path: String = PORTRAIT_DIR[dir_key] + PORTRAIT_FILE[dir_key].get(emo, "")
	if path == "":
		target.texture = null
		return
	if not _portrait_cache.has(path):
		if ResourceLoader.exists(path):
			_portrait_cache[path] = load(path)
		else:
			_portrait_cache[path] = null
	target.texture = _portrait_cache[path]


func _on_choices(choices: Array) -> void:
	_hint_label.text = ""
	for child in _choice_box.get_children():
		child.queue_free()

	# 三类恒定选项：固定回答 / 不回答 / 自由输入（≤100字）
	for i in choices.size():
		var btn := Button.new()
		btn.text = str(choices[i])
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 15)
		btn.pressed.connect(_on_choice_pressed.bind(i))
		_choice_box.add_child(btn)

	_choice_box.add_child(_make_choice_sep())

	# 不回答 —— 一种真实的「选择沉默」回应，NPC 会对此作出反应
	var silent := Button.new()
	silent.text = "不回答"
	silent.alignment = HORIZONTAL_ALIGNMENT_LEFT
	silent.add_theme_font_size_override("font_size", 14)
	silent.pressed.connect(_on_silence)
	_choice_box.add_child(silent)

	# 自由输入（100字内）—— 始终可见的输入框，回车/发送提交
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_choice_box.add_child(row)

	_free_input = LineEdit.new()
	_free_input.placeholder_text = "自由输入（100字内）…"
	_free_input.max_length = 100
	_free_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_free_input.add_theme_font_size_override("font_size", 14)
	_free_input.text_submitted.connect(func(_t): _on_free_input_submit())
	row.add_child(_free_input)

	var send := Button.new()
	send.text = "发送"
	send.add_theme_font_size_override("font_size", 13)
	send.pressed.connect(_on_free_input_submit)
	row.add_child(send)

	_choice_panel.show()
	if _choice_box.get_child_count() > 0:
		(_choice_box.get_child(0) as Button).grab_focus()


func _make_choice_sep() -> Control:
	var sep := HSeparator.new()
	sep.modulate = Color(1, 1, 1, 0.25)
	return sep


func _on_choice_pressed(index: int) -> void:
	_choice_panel.hide()
	get_node("/root/EventBus").dialogue_choice_made.emit(index)


## 不回答 → 以「（沉默不语）」作为玩家输入，交给 NPC（AI 会话 / S2 旁路）回应。
func _on_silence() -> void:
	_choice_panel.hide()
	if not _ai_can_respond():
		_show_toast("（对方没有回应……）")
		_choice_panel.show()
		return
	get_node("/root/EventBus").dialogue_free_input.emit("（沉默不语）")


func _on_dialogue_ended() -> void:
	_panel.hide()
	_choice_panel.hide()
	_npc_portrait.hide()
	_player_portrait.hide()
	_ai_badge.hide()


func _show_toast(message: String) -> void:
	_toast_label.text = message
	_toast_label.show()
	_toast_timer.wait_time = 3.0
	_toast_timer.start()


# ---------------------------------------------------------------------------
# AI 对话相关
# ---------------------------------------------------------------------------
func _on_dialogue_ai_meta(npc_id: String, ai_mode: bool, free_input_enabled: bool) -> void:
	_ai_mode = ai_mode
	_ai_free_input_enabled = free_input_enabled
	_thinking_npc = npc_id
	if ai_mode or free_input_enabled:
		_ai_badge.show()
	else:
		_ai_badge.hide()


func _on_ai_thinking(active: bool) -> void:
	_choice_panel.hide()
	if active:
		_thinking_label.text = "（%s 在想着什么……）" % _display_name_or_id(_thinking_npc)
		_thinking_label.show()
	else:
		_thinking_label.hide()


func _display_name_or_id(npc_id: String) -> String:
	return {"padwin": "帕德温", "soraya": "索拉雅", "cactus_bishop": "卡克特斯主教"}.get(npc_id, npc_id)


func _on_free_input_submit() -> void:
	if _free_input == null:
		return
	var text := _free_input.text.strip_edges()
	if text.is_empty():
		return
	_choice_panel.hide()
	if not _ai_can_respond():
		_show_toast("（对方没有回应……）")
		_choice_panel.show()
		return
	get_node("/root/EventBus").dialogue_free_input.emit(text)


## AI 是否能对自由输入/沉默作出回应（key 有效 且 有角色卡）。
func _ai_can_respond() -> bool:
	var bridge = get_node_or_null("/root/AIBridge")
	if bridge == null:
		return false
	return bridge.is_available() and bridge.has_role_card(_thinking_npc)

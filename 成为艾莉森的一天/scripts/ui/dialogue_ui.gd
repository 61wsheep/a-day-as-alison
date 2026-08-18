extends CanvasLayer

## 对话 UI — 立绘 + 对话面板 + 动态选项按钮 + 提示气泡。
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

var _panel: PanelContainer
var _portrait: TextureRect
var _name_label: Label
var _text_label: Label
var _hint_label: Label
var _choice_panel: PanelContainer
var _choice_box: VBoxContainer
var _interact_hint: Label
var _toast_label: Label
var _toast_timer: Timer
var _portrait_cache: Dictionary = {}


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

	# -- 对话面板（底部） --
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_left = 24
	_panel.offset_right = -24
	_panel.offset_top = -150
	_panel.offset_bottom = -12
	_panel.hide()
	add_child(_panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	_panel.add_child(hbox)

	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(120, 120)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hbox.add_child(_portrait)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(vbox)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_name_label)

	_text_label = Label.new()
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(_text_label)

	_hint_label = Label.new()
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_hint_label)

	# -- 选项面板（对话面板上方） --
	_choice_panel = PanelContainer.new()
	_choice_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_choice_panel.offset_left = 60
	_choice_panel.offset_right = -60
	_choice_panel.offset_top = -290
	_choice_panel.offset_bottom = -160
	_choice_panel.hide()
	add_child(_choice_panel)

	_choice_box = VBoxContainer.new()
	_choice_box.add_theme_constant_override("separation", 6)
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


func _on_dialogue_line(speaker_id: String, display_name: String, text: String, emotion: String) -> void:
	_choice_panel.hide()
	_name_label.text = display_name
	_text_label.text = text
	_hint_label.text = "[E] 继续"
	_update_portrait(speaker_id, emotion)
	_panel.show()


func _update_portrait(speaker_id: String, emotion: String) -> void:
	var key: String = PORTRAIT_ALIAS.get(speaker_id, speaker_id)
	if key == "narrator" or not PORTRAIT_FILE.has(key):
		_portrait.texture = null
		_portrait.hide()
		return
	_portrait.show()
	var emo := emotion
	if emo == "" or not PORTRAIT_FILE[key].has(emo):
		emo = PORTRAIT_DEFAULT.get(key, "")
	var path: String = PORTRAIT_DIR[key] + PORTRAIT_FILE[key].get(emo, "")
	if path == "":
		_portrait.texture = null
		return
	if not _portrait_cache.has(path):
		if ResourceLoader.exists(path):
			_portrait_cache[path] = load(path)
		else:
			_portrait_cache[path] = null
	_portrait.texture = _portrait_cache[path]


func _on_choices(choices: Array) -> void:
	_hint_label.text = ""
	for child in _choice_box.get_children():
		child.queue_free()
	for i in choices.size():
		var btn := Button.new()
		btn.text = str(choices[i])
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 15)
		btn.pressed.connect(_on_choice_pressed.bind(i))
		_choice_box.add_child(btn)
	_choice_panel.show()
	if _choice_box.get_child_count() > 0:
		(_choice_box.get_child(0) as Button).grab_focus()


func _on_choice_pressed(index: int) -> void:
	_choice_panel.hide()
	get_node("/root/EventBus").dialogue_choice_made.emit(index)


func _on_dialogue_ended() -> void:
	_panel.hide()
	_choice_panel.hide()


func _show_toast(message: String) -> void:
	_toast_label.text = message
	_toast_label.show()
	_toast_timer.wait_time = 3.0
	_toast_timer.start()

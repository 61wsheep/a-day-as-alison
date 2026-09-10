extends CanvasLayer

## 状态面板 —— Tab 键开合：天数/时段/金币/塔罗/住所 + 已获得线索 + NPC 好感度。
## 全部节点代码构建；打开时取 GameManager 快照刷新，不实时监听。
## 对话进行中不可打开；打开期间锁定玩家移动。

const NPC_NAMES := {
	"soraya": "索拉雅",
	"padwin": "帕德温",
	"cactus_bishop": "卡克特斯主教",
}
const TIER_NAMES := {
	"hostile": "敌视", "cold": "冷淡", "neutral": "平淡",
	"friendly": "友善", "intimate": "亲密",
}
const TIME_NAMES := {
	"morning": "清晨", "afternoon": "午后", "evening": "傍晚",
	"night": "夜晚", "midnight": "午夜",
}
const HOUSE_NAMES := {"oak": "橡树屋", "cedar": "杉树屋", "willow": "柳树屋"}

## 线索/UI 文案外部数据（文案同学交付，owner 统一录入）——见 resources/data/clues.json、ui_text.json
const CLUES_FILE := "res://resources/data/clues.json"
const UI_TEXT_FILE := "res://resources/data/ui_text.json"

var _dim: ColorRect
var _panel: PanelContainer
var _content: VBoxContainer
var _open := false
var _dlg_active := false
var _clue_desc: Dictionary = {}
var _ui_text: Dictionary = {}


func _ready() -> void:
	layer = 12
	_load_text_data()
	_build_ui()
	var bus = get_node("/root/EventBus")
	bus.dialogue_started.connect(func():
		_dlg_active = true
		_close())
	bus.dialogue_ended.connect(func(): _dlg_active = false)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_TAB and not _dlg_active:
		_toggle()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and _open:
		_close()
		get_viewport().set_input_as_handled()


func is_open() -> bool:
	return _open


# ---------------------------------------------------------------------------
# UI 构建与刷新
# ---------------------------------------------------------------------------
func _build_ui() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.55)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(440, 0)
	_panel.offset_left = -220
	_panel.offset_top = -200
	_panel.offset_right = 220
	_panel.offset_bottom = 200
	add_child(_panel)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420, 380)
	_panel.add_child(scroll)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 6)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)

	_dim.hide()
	_panel.hide()


func _toggle() -> void:
	if _open:
		_close()
	else:
		_refresh()
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


## 载入线索描述与集中 UI 文案。文件缺失时两者为空，_refresh 各自回落硬编码串。
func _load_text_data() -> void:
	_clue_desc = _load_json_section(CLUES_FILE, "clues")
	_ui_text = _load_json(UI_TEXT_FILE)


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}


func _load_json_section(path: String, section: String) -> Dictionary:
	var d := _load_json(path)
	var s = d.get(section, {})
	return s if s is Dictionary else {}


func _empty_text(key: String, fallback: String) -> String:
	var empty: Dictionary = _ui_text.get("empty", {})
	return str(empty.get(key, fallback))


func _set_player_locked(locked: bool) -> void:
	var p := get_tree().get_first_node_in_group("player")
	if p and "_movement_locked" in p:
		p._movement_locked = locked


func _refresh() -> void:
	for child in _content.get_children():
		child.queue_free()
	var gm = get_node("/root/GameManager")

	_add_title("—— 艾莉森的状态 ——")

	var time_name: String = TIME_NAMES.get(str(gm.current_time), str(gm.current_time))
	_add_line("第 %d 天 · %s · 金币 %d G" % [int(gm.current_day), time_name, int(gm.gold)])
	var tarot := str(gm.daily_tarot_card) if str(gm.daily_tarot_card) != "" else "（今日未抽牌）"
	_add_line("今日塔罗：%s" % tarot)
	if gm.treehouse_rented:
		_add_line("住所：%s（已租）" % HOUSE_NAMES.get(str(gm.treehouse), str(gm.treehouse)))
	else:
		_add_line("住所：尚未租房（没有住处将无法入睡）")

	_add_sep()
	var total_clues: int = gm.CLUE_NAMES.size()
	_add_title("线索（%d/%d）" % [gm.clues_found.size(), total_clues], 16)
	if gm.clues_found.is_empty():
		_add_line(_empty_text("clues", "（尚未获得线索）"))
	else:
		for cid in gm.clues_found:
			_add_line("· %s" % gm.CLUE_NAMES.get(cid, cid))
			var d: String = str(_clue_desc.get(cid, {}).get("desc", ""))
			if d != "":
				_add_line("    %s" % d, 12, Color(0.72, 0.72, 0.78))

	_add_sep()
	_add_title("好感度", 16)
	for npc_id in NPC_NAMES:
		var val := int(gm.npc_affection.get(npc_id, 0))
		var tier: String = TIER_NAMES.get(gm.get_affection_tier(npc_id), "")
		_add_line("%s：%d/100（%s）" % [NPC_NAMES[npc_id], val, tier])

	_add_sep()
	_add_line("[Tab] 关闭", 12, Color(0.7, 0.7, 0.75))


func _add_title(text: String, size: int = 20) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
	_content.add_child(l)


func _add_line(text: String, size: int = 15, color: Color = Color(0.92, 0.92, 0.95)) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	_content.add_child(l)


func _add_sep() -> void:
	var sep := HSeparator.new()
	sep.modulate = Color(1, 1, 1, 0.25)
	_content.add_child(sep)

extends Node

## AIBridge API key 接口测试（开始界面数据流）。
## 运行：godot --headless res://scripts/tests/test_api_key.tscn
##
## ⚠ 本测试会**动到** user://ai_api_key.txt —— 那是开发者/玩家真填过的密钥。
##    故开头整份备份、结尾原样恢复。早期版本是直接删掉且不还的：跑一次就把真人密钥
##    变成 sk-test-123，之后真机表现是"AI 突然全程 401、聊两句就不聊了"，
##    而且几乎不可能怀疑到测试头上（本机的 ai_net.log 里就留着一次 key_len=11 的证据）。
##
## 另注：「无 key 状态」必须靠 bridge.clear_api_key() 造，**不能靠删文件**：
##    AIBridge._ready() 早于本测试执行，key 那时已经进了内存，删磁盘上的文件删不掉它。

const KEY_PATH := "user://ai_api_key.txt"

var _failures := 0
var _passes := 0
var _backup := ""
var _had_backup := false


func _ready() -> void:
	_run.call_deferred()


func _check(name: String, cond: bool) -> void:
	if cond:
		_passes += 1
		print("[KEYTEST] PASS  ", name)
	else:
		_failures += 1
		printerr("[KEYTEST] FAIL  ", name)


func _run() -> void:
	var bridge = get_node("/root/AIBridge")
	_backup_key()

	# 1. 无 key 状态（内存 + 磁盘都清干净；否则在已配好 key 的开发机上永远测不到这一支）
	bridge.clear_api_key()
	_check("无 key 时不可用", not bridge.is_available())
	_check("状态文本=未配置", bridge.get_status_text() == "未配置密钥（AI 将回落 JSON 对话）")

	# 2. 空 key 提交
	_check("空 key 提交失败", bridge.set_api_key("   ") == false)

	# 3. 合法 key 提交
	_check("set_api_key 成功", bridge.set_api_key("sk-test-123") == true)
	_check("提交后可用", bridge.is_available() == true)
	_check("get_stored_key 回读", bridge.get_stored_key() == "sk-test-123")
	_check("状态文本=已启用", bridge.get_status_text() == "AI 已启用（已保存密钥）")

	# 4. 持久化文件已写入
	_check("user://ai_api_key.txt 已写入", FileAccess.file_exists(KEY_PATH))
	if FileAccess.file_exists(KEY_PATH):
		var f := FileAccess.open(KEY_PATH, FileAccess.READ)
		_check("文件内容正确", f.get_as_text().strip_edges() == "sk-test-123")
		f.close()

	# 5. 清除后回到未配置（内存 + 磁盘都该干净）
	bridge.clear_api_key()
	_check("clear 后不可用", not bridge.is_available())
	_check("clear 后文件已删除", not FileAccess.file_exists(KEY_PATH))

	_restore_key(bridge)
	print("[KEYTEST] 完成: %d 通过, %d 失败" % [_passes, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## 备份真人密钥（也可能本机就没有）。**必须在任何 clear/删除之前调用。**
func _backup_key() -> void:
	_had_backup = FileAccess.file_exists(KEY_PATH)
	if _had_backup:
		_backup = FileAccess.get_file_as_string(KEY_PATH)


## 原样还回去：文件内容 + 内存状态都复原，跑完测试不影响本机继续用 AI。
func _restore_key(bridge: Node) -> void:
	if not _had_backup:
		bridge.clear_api_key()
		print("[KEYTEST] 本机原本就没有密钥，已保持清空。")
		return
	# 先无条件把文件写回：这一步绝不能挂在 set_api_key 的成功上——
	# 它可能因 --ai-off / 空内容而返回 false，那样备份就白备了。
	var f := FileAccess.open(KEY_PATH, FileAccess.WRITE)
	if f:
		f.store_string(_backup)
		f.close()
	if bridge.set_api_key(_backup):
		print("[KEYTEST] 已恢复原密钥（长度 %d）" % bridge.get_stored_key().length())
	else:
		print("[KEYTEST] 密钥文件已还原，但 AI 当前不可用（--ai-off？）。")

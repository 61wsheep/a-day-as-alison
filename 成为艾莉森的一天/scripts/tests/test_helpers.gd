extends Node

## 测试公用工具。用 preload 引，不注册 class_name（免得污染全局类表）。


## 把开机自动播放的第一轮开场旁白（绳→苔→树→看→撞）翻完。
##
## 为什么每个要按键的测试都得先调这个：开场播放期间 game.gd 会锁住玩家
## （_set_player_locked(true)），而 collectible / npc_base / 委托板 的输入处理
## 都会先查 _player_locked() 再响应。不翻完开场，玩家就一直锁着，
## 测试里所有「按 E」的断言都会莫名其妙地失败。
static func dismiss_opening(scene: Node) -> void:
	var opening: Node = scene.get_node_or_null("OpeningUI")
	if opening == null:
		return
	var tree := Engine.get_main_loop() as SceneTree
	var guard := 0
	while opening.is_playing() and guard < 12:
		opening._advance()
		await tree.process_frame
		guard += 1


# ============================================================
# API key 保护（凡是要调 set_api_key / 往开始界面填 key 的测试都必须用）
# ============================================================

const API_KEY_PATH := "user://ai_api_key.txt"


## 备份开发者/玩家真填过的密钥，返回其内容（本机没有则返回空串）。
##
## 为什么必须有这个：set_api_key() 是**无条件落盘**的。测试里为了造前置随手塞一个
## sk-test-123，就把开发机上真能用的密钥冲掉了；而症状要等到下次真机跑 AI 才显现
## ——"AI 断线""聊两句就不聊了"，几乎不可能联想到是几天前某个测试干的。
## （本机 ai_net.log 里留着的 key_len=11 记录，就是这么来的。）
##
## 用法：`var bak := HelpersScript.backup_api_key()` 开头，收尾
## `HelpersScript.restore_api_key(bridge, bak)`。测试中途 quit 会让恢复失效，
## 所以别在两者之间提前退出。
static func backup_api_key() -> String:
	if not FileAccess.file_exists(API_KEY_PATH):
		return ""
	return FileAccess.get_file_as_string(API_KEY_PATH)


## 把备份原样还回去（文件 + 内存状态都复原）。
static func restore_api_key(bridge: Node, backup: String) -> void:
	if bridge == null:
		return
	if backup.strip_edges().is_empty():
		bridge.clear_api_key()   # 本机原本就没有 key，保持干净
		return
	# 先无条件写回文件：这一步绝不能挂在 set_api_key 的成功上——
	# 它可能因 --ai-off / 内容为空而返回 false，那样备份就白备了。
	var f := FileAccess.open(API_KEY_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(backup)
		f.close()
	bridge.set_api_key(backup)

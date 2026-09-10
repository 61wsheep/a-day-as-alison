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

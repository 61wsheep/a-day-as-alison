extends SceneTree

## 打包前把 API key 注入 res://ai/api_key.txt，让导出包**开箱自带密钥**。
##
## 为什么需要它：导出包里的 res:// 只读，玩家改不了；而文件又必须**导出前**就躺在磁盘上
## （Godot 的 EditorExportPlugin 不能在打包时凭空塞一个不存在的文件）。所以必须有个
## 明确的注入步骤。之前这一步靠人肉记忆，漏了就会打出"没有密钥"的包——朋友试玩时
## AI 全程 401，症状却是"聊两句就不聊了""AI 断线"，极难排查。
##
## 用法（在项目根目录）：
##   godot --headless --path . -s res://scripts/tools/inject_api_key.gd
##   ... -- --check     只检查不写入（CI / 打包前自检）
##   ... -- --clear     删除 res://ai/api_key.txt（准备发公开版时用）
##
## key 来源顺序（与 AIBridge._resolve_key 一致）：环境变量 → user://ai_api_key.txt。
## res://ai/api_key.txt 本身在 .gitignore 里，不会被提交。

const DEST := "res://ai/api_key.txt"
const USER_KEY := "user://ai_api_key.txt"
## 硅基流动的 key 形如 sk- + 48 位；留宽一点，只拦住明显残缺的输入。
const MIN_KEY_LEN := 20


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if "--clear" in args:
		_clear()
		return
	var check_only := "--check" in args
	var key := _resolve()
	if key.is_empty():
		_fail("没找到可用的 key。请先在游戏开始界面填入并保存，或设 SILICONFLOW_API_KEY 环境变量。")
		return
	var problem := _validate(key)
	if problem != "":
		_fail("key 格式可疑：%s（长度 %d）\n  key 不会被写入——残缺的 key 打进包里只会让玩家全程 401。" % [problem, key.length()])
		return
	if check_only:
		print("[INJECT] --check 通过：找到可用 key（长度 %d）" % key.length())
		quit(0)
		return
	var f := FileAccess.open(DEST, FileAccess.WRITE)
	if f == null:
		_fail("写入 %s 失败：%s" % [DEST, error_string(FileAccess.get_open_error())])
		return
	f.store_string(key)
	f.close()
	print("[INJECT] 已写入 %s（长度 %d）。该文件在 .gitignore 内，不会进版本库。" % [DEST, key.length()])
	print("[INJECT] 现在可以导出：导出包会自动带上密钥，玩家无需手填。")
	print("[INJECT] 发公开版前记得跑 --clear 清掉。")
	quit(0)


func _clear() -> void:
	if FileAccess.file_exists(DEST):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DEST))
		print("[INJECT] 已删除 %s —— 导出的包将不含密钥。" % DEST)
	else:
		print("[INJECT] %s 本来就不存在，无需清理。" % DEST)
	quit(0)


## key 来源：环境变量 → user://ai_api_key.txt（游戏里填过就有）。
func _resolve() -> String:
	var env_key := _clean(OS.get_environment("SILICONFLOW_API_KEY"))
	if not env_key.is_empty():
		return env_key
	if FileAccess.file_exists(USER_KEY):
		return _clean(FileAccess.get_file_as_string(USER_KEY))
	return ""


## 剔除 BOM / 空白 / 换行（从聊天软件复制粘贴最容易混进这些东西）。
func _clean(raw: String) -> String:
	var k := raw.strip_edges()
	if k.begins_with(char(0xFEFF)):
		k = k.substr(1).strip_edges()
	return k.replace("\n", "").replace("\r", "").strip_edges()


## 返回 "" 表示格式没问题；否则返回人话描述。只拦明显残缺的，不做严格校验。
func _validate(key: String) -> String:
	if key.length() < MIN_KEY_LEN:
		return "太短了，像是复制时被截断"
	if not key.begins_with("sk-"):
		return "不是 sk- 开头"
	for ch in key:
		var c := ch.unicode_at(0)
		if c < 0x21 or c > 0x7E:
			return "含非 ASCII 字符（可能是全角符号或空格混入）"
	return ""


func _fail(message: String) -> void:
	printerr("[INJECT] 失败：%s" % message)
	quit(1)

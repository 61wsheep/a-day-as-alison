extends SceneTree

## 流式延迟探针（真实网络，批量跑）。
##
## 用法：
##   godot --headless --path . -s res://scripts/tests/ai_stream_probe.gd -- --rounds 5
##   ... -- --rounds 5 --mode stream      # 只跑流式
##   ... -- --rounds 5 --mode nostream    # 只跑非流式（对照组）
##   ... -- --rounds 5 --npc soraya --max-tokens 512 --text "你今天怎么样？"
##
## 输出：每轮一行明细 + 分组统计（均值/中位/最小/最大），并追加 CSV 到
##       user://stream_probe.csv（可直接丢进表格看趋势）。
##
## 说明：prompt 由 res://ai/ 下的真实文件组装（tian_system + npc 角色卡 + schema），
## user 段仿照 AIDialogueSession 第 2 轮的格式，保证与线上几轮对话的体量可比。
## 非流式没有"首字"概念，first_ms 记 -1；两个模式在同一轮里背靠背跑，便于配对比较。

const AIJsonUtilsScript := preload("res://scripts/systems/ai_json_utils.gd")

var _rounds := 5
var _npc := "padwin"
var _mode := "both"
var _max_tokens := 512
var _text := "你今天看起来不太一样，发生什么了吗？"
var _hard_timeout := 30.0
var _warmup := 1            # 预热轮（不计入统计）：摊掉首次 TLS 握手/DNS 的开销
var _csv_path := "user://stream_probe.csv"

# 流式回调状态（闭包不按引用捕获局部变量，只能用成员）
var _first_delta_ms := -1
var _delta_count := 0
var _t_start := 0

var _rows: Array = []
var _failures := 0


func _init() -> void:
	_parse_args()
	_run.call_deferred()


func _parse_args() -> void:
	_rounds = int(_arg("rounds", str(_rounds)))
	_npc = _arg("npc", _npc)
	_mode = _arg("mode", _mode)
	_max_tokens = int(_arg("max-tokens", str(_max_tokens)))
	_text = _arg("text", _text)
	_hard_timeout = float(_arg("timeout", str(_hard_timeout)))
	_warmup = int(_arg("warmup", str(_warmup)))


func _arg(name: String, default: String) -> String:
	var a := OS.get_cmdline_user_args()
	var key := "--" + name
	for i in a.size():
		if a[i] == key and i + 1 < a.size():
			return a[i + 1]
		if a[i].begins_with(key + "="):
			return a[i].substr(key.length() + 1)
	return default


func _run() -> void:
	await process_frame
	var bridge = root.get_node_or_null("AIBridge")
	if bridge == null:
		printerr("[PROBE] FAIL 无 AIBridge autoload")
		quit(1)
		return
	if not bridge.is_available():
		printerr("[PROBE] FAIL AI 不可用：%s" % bridge.get_status_text())
		quit(1)
		return

	var payload := _build_payload()
	var sys_len := str(payload.get("system", "")).length()
	var usr_len := str(payload.get("user", "")).length()
	print("[PROBE] npc=%s rounds=%d mode=%s max_tokens=%d system=%d字 user=%d字"
			% [_npc, _rounds, _mode, _max_tokens, sys_len, usr_len])
	print("[PROBE] CSV → %s" % ProjectSettings.globalize_path(_csv_path))
	print("[PROBE] " + "-".repeat(92))

	# 预热：走一遍真实连接（结果丢弃），让后面的测量不含首次握手成本
	for w in range(_warmup):
		var t := Time.get_ticks_msec()
		var warm: String = await bridge.request_llm_stream_with_guard(
			payload, _hard_timeout, Callable())
		print("[PROBE] 预热 %d/%d：%dms（不计入统计）" % [
			w + 1, _warmup, Time.get_ticks_msec() - t])
		if warm.begins_with("[API_ERROR]"):
			printerr("[PROBE] FAIL 预热失败：%s" % warm.left(140))
			quit(1)
			return

	for i in range(1, _rounds + 1):
		if _mode == "both":
			# 交替先后，避免"总是流式先跑"带来的顺序偏差（缓存/限流）
			if i % 2 == 1:
				await _run_stream(bridge, payload, i)
				await _run_nostream(bridge, payload, i)
			else:
				await _run_nostream(bridge, payload, i)
				await _run_stream(bridge, payload, i)
		elif _mode == "stream":
			await _run_stream(bridge, payload, i)
		else:
			await _run_nostream(bridge, payload, i)

	_report()
	quit(1 if _failures > 0 else 0)


func _run_stream(bridge: Node, payload: Dictionary, round_i: int) -> void:
	_first_delta_ms = -1
	_delta_count = 0
	_t_start = Time.get_ticks_msec()
	var raw: String = await bridge.request_llm_stream_with_guard(
		payload, _hard_timeout, _on_delta)
	var total := Time.get_ticks_msec() - _t_start
	_record("stream", round_i, _first_delta_ms, total, _delta_count, raw)


func _run_nostream(bridge: Node, payload: Dictionary, round_i: int) -> void:
	_first_delta_ms = -1
	_delta_count = 0
	_t_start = Time.get_ticks_msec()
	var raw: String = await bridge.request_llm_with_guard(payload, _hard_timeout)
	var total := Time.get_ticks_msec() - _t_start
	_record("nostream", round_i, -1, total, 0, raw)


func _on_delta(_visible: String) -> void:
	_delta_count += 1
	if _first_delta_ms < 0:
		_first_delta_ms = Time.get_ticks_msec() - _t_start


func _record(mode: String, round_i: int, first_ms: int, total_ms: int,
		deltas: int, raw: String) -> void:
	var failed: bool = raw.begins_with("[API_ERROR]") or raw.begins_with("[BUSY]") \
		or raw.begins_with("[DISABLED]") or raw.strip_edges().is_empty()
	var parsed := AIJsonUtilsScript.parse_response(raw, ["response_text"], true)
	var ok: bool = parsed.get("success", false)
	var method := str(parsed.get("method", "-"))
	var text := str(parsed.get("data", {}).get("response_text", "")) if ok else ""
	var truncated := method == "repaired"
	if failed:
		_failures += 1

	var first_col := "%6d" % first_ms if first_ms >= 0 else "     -"
	print("[PROBE] #%-2d %-8s 首字%sms 总%6dms delta=%-3d %s %s %s"
			% [round_i, mode, first_col, total_ms, deltas,
			"FAIL" if failed else ("OK  " if ok else "解析败"),
			"截断修复" if truncated else "完整    ",
			text.left(28)])
	if failed:
		print("[PROBE]        └ %s" % raw.left(140))

	_rows.append({
		"round": round_i, "mode": mode, "first_ms": first_ms, "total_ms": total_ms,
		"deltas": deltas, "ok": ok, "failed": failed, "truncated": truncated,
		"chars": text.length(), "text": text,
	})
	_append_csv(_rows[-1])


## 分组统计：首字/总时长/字符数 的 均值、中位、最小、最大。
func _report() -> void:
	print("[PROBE] " + "=".repeat(92))
	for mode in ["stream", "nostream"]:
		var rows: Array = []
		for r in _rows:
			if r["mode"] == mode and not r["failed"]:
				rows.append(r)
		if rows.is_empty():
			continue
		var totals: Array = rows.map(func(r): return float(r["total_ms"]))
		var chars: Array = rows.map(func(r): return float(r["chars"]))
		var line := "[PROBE] %-8s n=%d  总时长 均%.0fms 中位%.0f 最小%.0f 最大%.0f | 字符 均%.0f" % [
			mode, rows.size(), _mean(totals), _median(totals), totals.min(), totals.max(),
			_mean(chars)]
		if mode == "stream":
			var firsts: Array = []
			for r in rows:
				if int(r["first_ms"]) >= 0:
					firsts.append(float(r["first_ms"]))
			if not firsts.is_empty():
				line += " | 首字 均%.0fms 中位%.0f 最小%.0f 最大%.0f" % [
					_mean(firsts), _median(firsts), firsts.min(), firsts.max()]
		print(line)
	# 流式 vs 非流式：配对提升（仅取同一轮两边都成功的）
	var pairs: Array = []
	for i in range(1, _rounds + 1):
		var s: Variant = _find(i, "stream")
		var n: Variant = _find(i, "nostream")
		if s != null and n != null and not s["failed"] and not n["failed"]:
			pairs.append([int(s["total_ms"]), int(n["total_ms"]), int(s["first_ms"])])
	if not pairs.is_empty():
		var st := 0; var nt := 0; var ft := 0
		for p in pairs:
			st += p[0]; nt += p[1]; ft += p[2]
		var n := pairs.size()
		var mean_st := float(st) / n
		var mean_nt := float(nt) / n
		var mean_ft := float(ft) / n
		print("[PROBE] 配对 n=%d：非流式整段等完 %.0fms → 流式首字 %.0fms（提前 %.1fs 看到字），流式整段耗时 %+.0fms"
				% [n, mean_nt, mean_ft, (mean_nt - mean_ft) / 1000.0, mean_st - mean_nt])
	if _failures > 0:
		print("[PROBE] 失败 %d 次（已在上方标 FAIL）" % _failures)


func _find(round_i: int, mode: String) -> Variant:
	for r in _rows:
		if int(r["round"]) == round_i and r["mode"] == mode:
			return r
	return null


func _mean(v: Array) -> float:
	if v.is_empty():
		return 0.0
	var s := 0.0
	for x in v:
		s += x
	return s / v.size()


func _median(v: Array) -> float:
	if v.is_empty():
		return 0.0
	var a := v.duplicate()
	a.sort()
	var n := a.size()
	return float(a[n / 2]) if n % 2 == 1 else (float(a[n / 2 - 1]) + float(a[n / 2])) / 2.0


func _append_csv(row: Dictionary) -> void:
	var need_header := not FileAccess.file_exists(_csv_path)
	var f := FileAccess.open(_csv_path, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(_csv_path, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	if need_header:
		f.store_line("time,round,mode,first_ms,total_ms,deltas,ok,failed,truncated,chars,text")
	f.store_line("%s,%d,%s,%d,%d,%d,%s,%s,%s,%d,%s" % [
		Time.get_datetime_string_from_system(), int(row["round"]), str(row["mode"]),
		int(row["first_ms"]), int(row["total_ms"]), int(row["deltas"]),
		str(row["ok"]), str(row["failed"]), str(row["truncated"]), int(row["chars"]),
		_csv_escape(str(row["text"]))])
	f.close()


func _csv_escape(s: String) -> String:
	return "\"%s\"" % s.replace("\"", "\"\"")   # 引号包裹 + 内部引号转义，换行由引号保护


## 用真实 prompt 资产组装一轮对话请求（体量与线上一致；不含天的注视等动态注入）。
func _build_payload() -> Dictionary:
	var system_text := _read("res://ai/tian_system.txt")
	var card_text := _read("res://ai/npc_%s.txt" % _npc)
	var schema_text := _read("res://ai/dialogue_schema.json")

	var user := ""
	user += "第 3 天 傍晚。%s 对玩家的好感度: 52/100。\n\n" % _npc
	user += "跨天记忆:\n- 上次见面时你提过森林里的雾。\n\n"
	user += "本轮对话历史:\n玩家: 今天集市上很热闹。\n%s: 是啊，收成不错。\n\n" % _npc
	user += "玩家刚才说: [%s]\n\n" % _text
	user += "以 %s 的身份回应（JSON）。记住:\n" % _npc
	user += "- 你是 %s —— 用你的性格、经历、语气说话，你不是 AI 助手\n" % _npc
	user += "- 回复要精炼：response_text 一般 1-2 句、别超 3 句；topic_suggestions 每条 6-12 个字即可\n"
	user += "- 请同时以玩家艾莉森的第一人称口吻给出 3 条她下一步可能说的话（topic_suggestions——玩家视角的回复选项，让对话能继续下去）\n"
	user += "\n\n【重要：你必须严格按照以下 JSON Schema 返回合法 JSON，不要输出任何 JSON 之外的文字】\n"
	user += "```json\n%s\n```\n" % schema_text
	user += "请直接返回 JSON，不要用 markdown 代码块包裹，不要加任何解释。"

	return {
		"system": "%s\n\n%s" % [system_text, card_text],
		"user": user,
		"max_tokens": _max_tokens,
	}


func _read(path: String) -> String:
	if FileAccess.file_exists(path):
		return FileAccess.get_file_as_string(path).strip_edges()
	return ""

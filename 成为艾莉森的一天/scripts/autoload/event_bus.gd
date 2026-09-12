extends Node

## 全局信号总线
## 所有游戏事件通过此单例发出信号，各系统监听对应的信号响应。

# -- 时间相关 --
signal time_changed(time_of_day: String)
signal day_started(day_number: int)
signal midnight_reached()

# -- 玩家状态相关 --
signal gold_changed(new_amount: int)

# -- 对话相关 --
signal interaction_hint_show()
signal interaction_hint_hide()
signal dialogue_started()
signal dialogue_line(speaker_id: String, display_name: String, text: String, emotion: String)
## 流式增量：AI 台词边生成边显示（text 为「当前累计」全文，UI 直接覆盖，非追加）。
## 独立于 dialogue_line —— 后者会写 DialogueLog 并触发立绘/提示，增量绝不能复用。
signal dialogue_line_delta(speaker_id: String, display_name: String, text: String, emotion: String)
signal dialogue_choices(choices: Array)
signal dialogue_choice_made(choice_index: int)
signal dialogue_ended()

# -- 采集交互提示（右下角：按 E 采集 XX）--
signal collect_hint_show(item_name: String)
signal collect_hint_hide()

# -- 委托板交互提示（右下角：按 E 查看委托板；dialogue_ui 渲染）--
signal board_hint_show()
signal board_hint_hide()

# -- 魔法桌交互提示（右下角：按 E 抽今天的牌；dialogue_ui 渲染）--
signal tarot_hint_show()
signal tarot_hint_hide()

# -- AI 对话相关 --
signal dialogue_ai_meta(npc_id: String, ai_mode: bool, free_input_enabled: bool)
signal dialogue_free_input(text: String)
signal dialogue_exit_requested()
signal ai_thinking(active: bool)

# -- 探索相关 --
signal clue_found(clue_id: String)
signal area_changed(area_id: String)
signal door_entered(target_area: String, target_spawn: String)

# -- 历史对话（贴近 NPC 按 H 打开） --
signal history_requested(npc_id: String)

# -- 游戏动作（由剧情 effects 触发，game.gd 统一路由） --
signal game_action(action_id: String)

# -- 塔罗 / 结局 --
signal tarot_drawn(card: Dictionary)
signal ending_reached(ending_id: String)

# -- 循环 --
## from_ending: 本次重置是否由结局「回到清晨」触发（false = 午夜入睡进入下一天）。
## 只有结局那条链路会播循环开场那行旁白 —— 入睡是常规推进，不该再演一遍醒来。
signal loop_reset(from_ending: bool)

# -- 背包 / 售卖 --
signal inventory_opened()
signal inventory_closed()
signal item_sold(item_id: String, count: int, price_total: int)
signal sell_requested()   # 对话内玩家主动提出卖东西（dialogue_ui → game.gd 路由）

# -- 提示 --
signal toast(message: String)

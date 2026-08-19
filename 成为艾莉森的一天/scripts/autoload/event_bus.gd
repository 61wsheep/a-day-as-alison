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
signal dialogue_choices(choices: Array)
signal dialogue_choice_made(choice_index: int)
signal dialogue_ended()

# -- AI 对话相关 --
signal dialogue_ai_meta(npc_id: String, ai_mode: bool, free_input_enabled: bool)
signal dialogue_free_input(text: String)
signal dialogue_exit_requested()
signal ai_thinking(active: bool)

# -- 探索相关 --
signal clue_found(clue_id: String)
signal area_changed(area_id: String)
signal door_entered(target_area: String, target_spawn: String)

# -- 游戏动作（由剧情 effects 触发，game.gd 统一路由） --
signal game_action(action_id: String)

# -- 塔罗 / 结局 --
signal tarot_drawn(card: Dictionary)
signal ending_reached(ending_id: String)

# -- 循环 --
signal loop_reset()

# -- 提示 --
signal toast(message: String)

extends Node

## 全局信号总线
## 所有游戏事件通过此单例发出信号，各系统监听对应的信号响应。

# -- 时间相关 --
signal time_changed(time_of_day: String)
signal day_started(day_number: int)

# -- 玩家状态相关 --
signal gold_changed(new_amount: int)

# -- 对话相关 --
signal dialogue_started(npc_id: String)
signal dialogue_ended(npc_id: String)

# -- 探索相关 --
signal clue_found(clue_id: String)
signal area_entered(area_id: String)

# -- 结局相关 --
signal ending_triggered(ending_id: String)
signal loop_reset()

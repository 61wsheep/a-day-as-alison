extends Node

## ������������������
## ���������������������������������������������������������������������������������������

# -- ������������ --
signal time_changed(time_of_day: String)
signal day_started(day_number: int)

# -- ������������������ --
signal gold_changed(new_amount: int)

# -- ������������ --
signal dialogue_started(npc_id: String)
signal dialogue_ended(npc_id: String)

# -- ������������ --
signal clue_found(clue_id: String)
signal area_entered(area_id: String)

# -- ������������ --
signal ending_triggered(ending_id: String)
signal loop_reset()

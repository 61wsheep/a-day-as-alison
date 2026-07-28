extends Node

## ���������������������
## ���������������������������������������������������������������������������
## ���������������������������������������������������������

# ========== ��������������������� ==========

## ������������������������������������������������������������������
var gold: int = 100

## ������������������������ [ending_id: String, ...]
var endings_unlocked: Array[String] = []

## ������������������������ [clue_id: String, ...]
var clues_found: Array[String] = []

## NPC ��������������� {npc_id: int, ...}
var npc_affection: Dictionary = {
	"soraya": 55,
	"padwin": 50,
	"cactus_bishop": 25,
}

## ������������������������ 1 ���������
var current_day: int = 1

## ���������������
var current_time: String = "morning"

## ������������������������
var current_area: String = "plaza"

## ���������������������������
var tarot_drawn_today: bool = false

## ������������������������ ID
var daily_tarot_card: String = ""

## ������������������
var treehouse_rented: bool = false

## ��������������������������������� ID ��� ���������
var inventory: Dictionary = {}


# ========== ������������ ==========

## ������������
func add_gold(amount: int) -> void:
	gold += amount
	gold = max(gold, 0)  # ������������������
	EventBus.gold_changed.emit(gold)


## ���������������������������������
func spend_gold(amount: int) -> bool:
	if gold >= amount:
		gold -= amount
		EventBus.gold_changed.emit(gold)
		return true
	return false


## ������������
func unlock_ending(ending_id: String) -> void:
	if ending_id not in endings_unlocked:
		endings_unlocked.append(ending_id)


## ������������
func discover_clue(clue_id: String) -> void:
	if clue_id not in clues_found:
		clues_found.append(clue_id)
		EventBus.clue_found.emit(clue_id)


## ������ NPC ���������
func change_affection(npc_id: String, delta: int) -> void:
	if npc_affection.has(npc_id):
		npc_affection[npc_id] = clamp(npc_affection[npc_id] + delta, 0, 100)


## ������ NPC ���������������
func get_affection_tier(npc_id: String) -> String:
	var val = npc_affection.get(npc_id, 0)
	if val < 20: return "hostile"
	elif val < 40: return "cold"
	elif val < 60: return "neutral"
	elif val < 80: return "friendly"
	else: return "intimate"


## ���������������������������������
func reset_loop() -> void:
	current_day += 1
	current_time = "morning"
	tarot_drawn_today = false
	daily_tarot_card = ""
	# ������/���������/������/������/������ ���������������
	EventBus.loop_reset.emit()
	EventBus.day_started.emit(current_day)


## ���������������
func set_time(time_id: String) -> void:
	current_time = time_id
	EventBus.time_changed.emit(time_id)

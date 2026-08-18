extends NPCBase

## Padwin NPC — 帕德温，前贵族战士，现树屋区看守。
## 对话数据见 res://resources/dialogues/padwin.json

func _ready() -> void:
	npc_id = "padwin"
	dialogue_file = "res://resources/dialogues/padwin.json"
	super._ready()

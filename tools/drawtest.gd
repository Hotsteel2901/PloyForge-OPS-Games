extends Node

func _ready() -> void:
	var hud := HUD.new()
	add_child(hud)
	await get_tree().create_timer(0.8).timeout
	var info: Dictionary = hud.get_crosshair_info()
	print("[TEST] hud.can_process=", hud.can_process(), " paused=", get_tree().paused, " frames=", Engine.get_frames_drawn(), " hud_layer=", hud.layer)
	print("[TEST] crosshair=", info)
	get_tree().quit()

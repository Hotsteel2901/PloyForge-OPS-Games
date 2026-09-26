extends Node

func _ready() -> void:
	var sc: Dictionary = {"CT": 0, "T": 1}
	print("a: " + String(sc.get("CT", 0)))
	var v: Variant = sc.get("CT", 0)
	print("b: " + String(v))
	print("c: " + str(sc.get("CT", 0)))
	print("d: " + "%s" % sc.get("CT", 0))
	get_tree().quit()

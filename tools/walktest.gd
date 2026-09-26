extends Node

func _ready() -> void:
	var room := Room.new({"id": "t", "mode": "defusal", "mapId": "cinder", "botCount": 2, "maxPlayers": 12})
	var p := room.add_local_player("Tester", "ct")
	room.start()
	room.spawn_joiner(p)
	for _i in range(500):
		room.tick()
	var t: Dictionary = {}
	for q in room.state.players.values():
		if int(q.team) == Constants.TEAM_T and q.isBot:
			t = q
			break
	if t.is_empty():
		print("[BOMB] no T bot")
		get_tree().quit()
		return
	t.bombCarrier = true
	t.pos = Vector3(room.state.map.sites[0].pos.x, 0, room.state.map.sites[0].pos.z)
	t.input.u = true
	var planted: bool = false
	for i in range(150):
		room.tick()
		if room.state.bomb.planted:
			planted = true
			print("[BOMB] planted at tick ", i, " timeLeft=", room.state.bomb.timeLeft)
			break
	if planted:
		for i in range(30):
			room.tick()
		print("[BOMB] after 1s more timeLeft=", room.state.bomb.timeLeft, " (should be ~39)")
	get_tree().quit()

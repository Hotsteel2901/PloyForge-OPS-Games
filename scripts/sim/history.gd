# PositionHistory: ring buffer of recent positions (used by hit verification).
class_name PositionHistory
extends RefCounted

var _points: Array = []
var _max: int = 64


func push(time: float, entry: Dictionary) -> void:
	_points.append({"t": time, "e": entry})
	if _points.size() > _max:
		_points.pop_front()


func prune(time: float) -> void:
	while _points.size() > 1 and float(_points[0].t) < time - 1.0:
		_points.pop_front()


func latest() -> Dictionary:
	if _points.is_empty():
		return {}
	return _points[_points.size() - 1].e


func get_at(t: float) -> Variant:
	# best snapshot at or before time t
	var best: Variant = null
	for p in _points:
		if float(p.t) <= t + 0.1:
			best = p.e
		else:
			break
	return best


func count() -> int:
	return _points.size()

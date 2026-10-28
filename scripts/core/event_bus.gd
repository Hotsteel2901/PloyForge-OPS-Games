# 全局事件总线。用于解耦「模拟层 → 表现层 / 成就 / 统计 / Mod」。
# 约定：模拟层只 emit，不关心谁在听；监听者必须自行做失败隔离。
extends Node

signal app_paused(paused: bool)
signal settings_applied()
signal quality_changed(tier: int)

signal match_started(info: Dictionary)
signal match_ended(info: Dictionary)
signal round_started(info: Dictionary)
signal round_ended(info: Dictionary)

signal player_spawned(player_id: String, info: Dictionary)
signal player_died(victim_id: String, killer_id: String, info: Dictionary)
signal player_damaged(victim_id: String, attacker_id: String, amount: int, info: Dictionary)
signal player_scored(player_id: String, amount: int, reason: String)
signal weapon_fired(player_id: String, weapon_id: String, info: Dictionary)
signal weapon_reloaded(player_id: String, weapon_id: String)
signal grenade_thrown(player_id: String)
signal explosion_happened(pos: Vector3, radius: float, owner_id: String)

signal bot_spawned(bot_id: String)
signal bot_killed(bot_id: String, killer_id: String)

signal net_status_changed(status: int, detail: String)
signal net_player_joined(player_id: String, name: String)
signal net_player_left(player_id: String, reason: String)
signal net_latency_updated(ms: int)
signal net_disconnected(reason: String)

signal mod_loaded(mod_id: String, info: Dictionary)
signal mod_failed(mod_id: String, reason: String)
signal mods_changed()

signal ui_notify(text: String, duration: float)
signal ui_toast(text: String, icon: String)

## 只用于调试：记录最近 N 条事件，便于崩溃时回溯
const HISTORY_MAX: int = 64
var history: Array = []
var trace_enabled: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func trace(kind: String, payload: Dictionary = {}) -> void:
	if not trace_enabled:
		return
	history.append({"t": Time.get_ticks_msec(), "k": kind, "p": payload})
	if history.size() > HISTORY_MAX:
		history.remove_at(0)

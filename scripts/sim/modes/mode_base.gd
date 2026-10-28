# 游戏模式基类（v2）。
# Room 只负责「通用模拟」（物理/武器/伤害/投掷物/补给箱），模式负责「规则与胜负」。
# 这样新增模式 = 新建一个子类 + 注册，不用动 Room。
class_name ModeBase
extends RefCounted

var id: String = "base"
var label: String = "基础模式"
var short: String = "BASE"
var desc: String = ""

# --- 规则开关（Room 会读这些字段决定通用流程） ---
var team_based: bool = true          # 是否有阵营
var team_count: int = 2              # 阵营数（2 = CT/T 或 HUMAN/ZOMBIE，0 = 无队）
var friendly_fire: bool = false
var respawn: bool = true             # 死后是否复活
var respawn_delay: float = 3.0
var round_time: float = 300.0        # 单回合时长（秒）
var round_limit: int = 1             # 回合数（0 = 无限）
var score_limit: int = 0             # 达到即结束（0 = 时间制）
var uses_money: bool = false         # 是否启用经济
var uses_buy_phase: bool = false     # 是否有购买阶段
var buy_time: float = 10.0
var needs_sites: bool = true         # 地图是否需要 A/B 点
var warmup: float = 0.0
var allow_spectate: bool = true
var infinite_ammo: bool = false
var zombie_infection: bool = false
var join_in_progress: bool = true    # 中途加入是否立即生效
var hud_objective: String = ""       # HUD 顶部提示文本

# --- 记分板列 ---
var columns: Array = ["kills", "deaths", "score"]


func setup(_room) -> void:
	pass


## 回合开始：分配阵营、给装备、重置状态（由 Room 在 spawn 前调用）
func start_round(_room) -> void:
	pass


## 每 tick（在通用模拟之后）
func on_tick(_room, _dt: float) -> void:
	pass


## 玩家阵亡。返回 true 表示模式已处理复活/转换逻辑，Room 不再走默认分支。
func on_kill(_room, _victim: Dictionary, _killer: Variant, _info: Dictionary) -> bool:
	return false


## 玩家出生（给默认装备等）
func on_player_spawn(_room, _p: Dictionary) -> void:
	pass


## 长按 E 交互（安放/拆除/拾取/补给）。返回 true 表示模式已接管，Room 跳过通用逻辑。
func process_use(_room, _p: Dictionary, _dt: float) -> bool:
	return false


## 该玩家此刻能否使用购买菜单
func can_buy(_room, _p: Dictionary) -> bool:
	return uses_money and _room.state.phase == "buy"


## 回合核心事件（round_start / round_end / bomb_planted ...）
func on_round_event(_room, _e: Dictionary) -> void:
	pass


## 返回 {end: bool, winner: String, reason: String, draw: bool}
func check_round_end(_room) -> Dictionary:
	return {"end": false}


## 结算：回合结束后给分
func award_round(_room, _winner: String, _reason: String) -> void:
	pass


## 记分板附加列（键名 -> 显示名）
func extra_columns() -> Dictionary:
	return {}


## 快照附加信息（HUD 用）
func snapshot_extra(_room) -> Dictionary:
	return {}


## 玩家退出时清理模式内引用
func on_player_leave(_room, _p: Dictionary) -> void:
	pass


# ---- 工具 ----

func alive_count(room, team: int = -1) -> int:
	var n: int = 0
	for p in room.state.players.values():
		if not p.alive:
			continue
		if team >= 0 and int(p.team) != team:
			continue
		n += 1
	return n


func players_of(room, team: int) -> Array:
	var out: Array = []
	for p in room.state.players.values():
		if int(p.team) == team:
			out.append(p)
	return out


func hostiles(room, a: Dictionary) -> Array:
	var out: Array = []
	for p in room.state.players.values():
		if p == a or not p.alive:
			continue
		if room.is_hostile(a, p):
			out.append(p)
	return out


func nearest(room, pos: Vector3, filter_team: int = -1) -> Variant:
	var best: Variant = null
	var best_d: float = INF
	for p in room.state.players.values():
		if not p.alive:
			continue
		if filter_team >= 0 and int(p.team) != filter_team:
			continue
		var d: float = pos.distance_squared_to(p.pos)
		if d < best_d:
			best_d = d
			best = p
	return best

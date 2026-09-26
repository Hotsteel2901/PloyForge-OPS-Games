# 全局共享常量：协议、队伍、模式、玩家物理、消息类型。
# 移植自 shared/constants.js
extends Node

const TICK_RATE: int = 30
const TICK_MS: float = 1000.0 / TICK_RATE
const MAX_PLAYERS: int = 12
const MAX_BOTS: int = 10

# 队伍
const TEAM_NONE: int = 0
const TEAM_CT: int = 1       # 拆弹模式 CT / 生化模式人类
const TEAM_T: int = 2        # 拆弹模式 T / 生化模式僵尸
const TEAM_HUMAN: int = 1
const TEAM_ZOMBIE: int = 2

# 模式
const MODE_DEFUSAL: String = "defusal"
const MODE_ZOMBIE: String = "zombie"

const MODE_LABEL: Dictionary = {
	"defusal": "拆弹模式",
	"zombie": "生化模式",
}

# 玩家物理常量（单位：米/秒，米）
const PHYS: Dictionary = {
	"HALF": 0.35,           # 玩家碰撞半宽
	"STAND_H": 1.8,         # 站立高度
	"CROUCH_H": 1.2,        # 蹲下高度
	"EYE_STAND": 1.62,
	"EYE_CROUCH": 1.05,
	"SPEED": 5.5,           # 人类基础速度（CS2 风格）
	"SPRINT_MULT": 1.3,     # CS2 无跑步加速，保留接口
	"CROUCH_MULT": 0.55,
	"ZOMBIE_SPEED": 5.4,
	"ZOMBIE_JUMP": 6.9,
	"ZOMBIE_HP": 600,
	"ZOMBIE_REGEN": 4,
	"ZOMBIE_SLOW_TICKS": 24,
	"ZOMBIE_SLOW_MULT": 0.4,
	"JUMP": 5.8,            # CS2 跳跃速度
	"GRAVITY": -14.0,       # CS2 重力
	"TERMINAL": -22.0,
	"ACCEL_GROUND": 11.0,   # 地面加速度（原硬编码 11.0）
	"ACCEL_AIR": 3.5,       # 空中加速度（CS 风格空中控制，远低于地面）
	"ACCEL_FRICTION": 12.0, # 地面减速摩擦力
	"MAX_SPEED_BHOP": 1.2,  # 连跳速度保留系数（>1.0 允许加速）
	"COUNTERSTRAFE": 0.7,   # 急停效率（按下反方向时速度衰减比例）
	"BOB_FREQ": 12.0,       # 视图晃动频率
	"BOB_AMP": 0.015,       # 视图晃动幅度
	"BOB_ADS_AMP": 0.003,   # ADS 时晃动幅度
}

const WEAPON_SLOT_KNIFE: int = 0
const WEAPON_SLOT_PISTOL: int = 1
const WEAPON_SLOT_PRIMARY: int = 2
const WEAPON_SLOT_GRENADE: int = 3

# 生化模式"琉璃决战"末段
const FINALE: Dictionary = {
	"DURATION": 60,
	"HUNTER_HP": 500,
	"HUNTER_ARMOR": 100,
	"HUNTER_DAMAGE": 3.0,
	"KING_HP": 1200,
	"KING_ARMOR": 80,
	"KING_DAMAGE": 2.6,
	"SERVANT_HP": 800,
	"SERVANT_ARMOR": 40,
	"SERVANT_DAMAGE": 1.6,
	"ZOMBIE_HP_MULT": 1.3,
}

# 生化模式丧尸加速技能（F 键）
const ZOMBIE_BOOST_SPEED: float = 8.0
const ZOMBIE_BOOST_DURATION: float = 3.0
const ZOMBIE_BOOST_COOLDOWN: float = 20.0

# 生化模式人类加速技能（F 键）：与丧尸同样的加速机制，5 秒加速、45 秒冷却
const HUMAN_BOOST_SPEED: float = 8.0
const HUMAN_BOOST_DURATION: float = 5.0
const HUMAN_BOOST_COOLDOWN: float = 45.0

# 回血箱每次回复量
const HEALTH_BOX_HEAL: float = 100.0

const INPUT_MAX_HISTORY: int = 64
const SNAPSHOT_INTERVAL_MS: float = 1000.0 / 20.0

# 默认 Bot 数量与配置
const BOT_COUNT: int = 8
const MODS_ENABLED: bool = false # 本地移植版禁用 Mod 系统

# 经济系统纯数据与价格表。移植自 shared/economy.js
extends Node

const PRICES: Dictionary = {
	"k9": 400,
	"vx9": 1300,
	"arc17": 2700,
	"warden": 1800,
	"longshot": 4600,
	"bruiser": 4200,
	"pc": 400,
	"pf": 700,
	"ra": 2700,
	"rb": 3200,
	"sc": 1300,
	"sf": 2350,
	"sa": 2000,
	"sp": 1050,
	"sm": 4750,
	"sr": 1700,
	"armor": 650,
	"grenade": 300,
}

const START_MONEY: int = 800
const MONEY_CAP: int = 16000
const KILL_REWARD: int = 300
const WIN_REWARD: int = 3000
const LOSS_REWARD: int = 1500
const PLANT_REWARD: int = 300
const DEFUSE_REWARD: int = 300

# CS2 式连败补偿：输掉第 1 局后 1400，之后每连败 +500，上限 3400
const LOSS_STREAK_TIERS: Array = [1400, 1900, 2400, 2900, 3400]


static func loss_reward(streak: int) -> int:
	var idx: int = clampi(streak - 1, 0, LOSS_STREAK_TIERS.size() - 1)
	return LOSS_STREAK_TIERS[idx]

# 生化模式经济
const ZOMBIE_START_MONEY: int = 1000
const ZOMBIE_KILL_REWARD: int = 200


# 任意主武器的价格：优先武器自身的 cost，否则查内置价格表
static func weapon_price(def: Dictionary) -> int:
	if not def.is_empty() and def.has("cost") and typeof(def.cost) == TYPE_INT:
		return def.cost
	var id: String = def.get("id", "")
	return PRICES.get(id, 800)


# armor 已满时价格为 0
static func cost_of(item: String, armor: int) -> int:
	if item == "armor":
		return 0 if armor >= 100 else PRICES.armor
	return PRICES.get(item, -1)

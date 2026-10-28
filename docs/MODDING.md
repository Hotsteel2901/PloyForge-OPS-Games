# PolyForge: Ops — 模组开发指南

> 目标：**从零到可玩模组 ≤ 5 分钟**。不需要编译引擎，不需要 C++，不需要安装任何 SDK。
> 一个文件夹 + 几个 JSON + 可选的一段 GDScript。

---

## 0. 30 秒上手

```bash
# 1) 生成骨架（自动带一把武器、一张地图、一个事件钩子）
python3 tools/modc/modc.py new my_mod

# 2) 打包
python3 tools/modc/modc.py build my_mod
# → my_mod-1.0.0.pfmod

# 3) 安装到游戏
python3 tools/modc/modc.py install my_mod-1.0.0.pfmod

# 4) 启动游戏 → 主菜单就多了一把枪 / 一张图
```

`modc` 是零依赖单文件 Python 脚本，Windows / macOS / Linux 通用。

---

## 1. 模组是什么

一个模组 = 一个目录：

```
my_mod/
├── mod.json            # 必需：清单
├── main.gd             # 可选：入口脚本（extends ModBase）
├── weapons/*.json      # 可选：武器（自动注册，无需写代码）
├── maps/*.json         # 可选：地图（极简描述，自动生成碰撞与导航）
├── modes/*.gd          # 可选：自定义模式（在 main.gd 里注册）
├── assets/             # 可选：贴图 / 音频 / 模型
└── README.md
```

打包后的 `.pfmod` 就是标准 ZIP。玩家把文件丢进
`user://mods/`（Windows：`%APPDATA%\Godot\app_userdata\PolyForge- Ops\mods`）
即可，游戏启动时自动解包加载。

---

## 2. mod.json

```json
{
  "id": "my_mod",
  "name": "我的模组",
  "version": "1.0.0",
  "author": "you",
  "desc": "一句话介绍",
  "api": 2,
  "entry": "main.gd",
  "dependencies": []
}
```

| 字段 | 必填 | 说明 |
|---|---|---|
| `id` | ✅ | 小写字母/数字/下划线，2–32 字符，全局唯一（冲突时后加载者覆盖） |
| `name` | ✅ | 显示名 |
| `version` | ✅ | 语义化版本 `x.y.z` |
| `api` | ✅ | 当前为 `2`；高于引擎支持会拒绝加载 |
| `entry` | | 入口脚本，默认 `main.gd`；纯数据模组可留空 |
| `dependencies` | | 依赖的其它 mod id 数组，按顺序加载 |

---

## 3. 只用 JSON：加武器

`weapons/anything.json`：

```json
{
  "weapons": [
    {
      "id": "my_mod_railpistol",
      "name": "磁轨手枪",
      "slot": 1,
      "auto": false,
      "damage": 55,
      "fireRate": 180,
      "headshotMult": 2.2,
      "magSize": 6,
      "reserve": 30,
      "reloadTime": 2.0,
      "spread": 0.02,
      "adsSpread": 0.004,
      "recoil": 0.06,
      "penetration": 0.9,
      "armorPen": 0.9,
      "cost": 2100,
      "category": "pistol",
      "desc": "一枪打穿两个人。"
    }
  ]
}
```

### 武器字段表

| 字段 | 默认 | 说明 |
|---|---|---|
| `id` / `name` | — | 唯一 id / 显示名 |
| `slot` | 2 | 0 近战 / 1 副武器 / 2 主武器 / 3 投掷物 |
| `auto` | false | 按住连发 |
| `melee` | false | 近战（用 `range` 判定） |
| `damage` | 10 | 单发伤害（霰弹为单颗弹丸） |
| `fireRate` | 600 | 每分钟发数 |
| `pellets` | 1 | 弹丸数（霰弹枪 7–12） |
| `magSize` / `reserve` | 30 / 90 | 弹匣 / 备弹；近战填 `1e9` 表示无限 |
| `reloadTime` | 2.0 | 换弹秒数 |
| `spread` / `adsSpread` | 0.03 / 0.01 | 腰射 / 开镜散布（弧度） |
| `recoil` | 0.02 | 后坐力 |
| `moveMult` | 1.0 | 持枪移速倍率 |
| `falloffNear/Far/Min` | 15/60/0.45 | 距离衰减曲线 |
| `headshotMult` | 1.8 | 爆头倍率 |
| `penetration` | 0.2 | 穿墙能力 0–1（>0.55 可穿一层墙） |
| `armorPen` | 0.5 | 护甲穿透 0–1 |
| `loudness` | 1.0 | 声音传播（影响 Bot 听觉） |
| `projectile` | "" | `grenade` / `flash` / `smoke` / `fire` / `decoy` / `bolt` |
| `radius` | 8 | 投掷物作用半径 |
| `charge` | 0 | 蓄力秒数（磁轨炮） |
| `spinUp` | 0 | 转管预热秒数 |
| `stun` | 0 | 命中定身秒数（电击枪） |
| `adsFov` | 50 | 开镜 FOV |
| `cost` | 2000 | 购买价格 |
| `category` | rifle | `rifle/smg/shotgun/sniper/lmg/pistol/melee/special/grenade` |
| `model` | "" | 使用 `assets/` 里的 GLB 作为第一人称模型 |
| `attach` | [] | 允许的配件 id 列表（留空 = 全部可用） |

> 数值建议：步枪 26–36 伤害 / 600–900 RPM；冲锋枪 18–24 / 850–1000；
> 狙击 90–130 / 40–60；霰弹 12–20 × 7–10 颗。

---

## 4. 只用 JSON：加地图

`maps/yard.json`：

```json
{
  "id": "yard",
  "name": "训练场",
  "size": [48, 48],
  "boxes": [
    { "x": 0,  "z": 0,   "sx": 8, "sz": 8,  "h": 3.0 },
    { "x": -14, "z": -10, "sx": 4, "sz": 10, "h": 2.2 },
    { "x": 16, "z": 12,  "sx": 6, "sz": 6,  "h": 3.4, "type": "wall" }
  ],
  "spawns": {
    "CT": [{ "x": 0, "z": 18, "yaw": 0 }],
    "T":  [{ "x": 0, "z": -18, "yaw": 3.14159 }]
  },
  "sites": [
    { "id": "A", "x": -10, "z": 0, "radius": 4 },
    { "id": "B", "x": 10,  "z": 0, "radius": 4 }
  ]
}
```

引擎会自动做三件事：**生成碰撞体**、**生成 A\* 导航图**、**生成装饰**。
所以你不需要写任何网格代码。地图会自动出现在主菜单的地图列表里。

- `size` 决定地面与外圈墙；
- `boxes` 是长方体障碍，`type` 为 `crate`（木箱质感）或 `wall`（墙体）；
- `y` 可选，用于抬高平台；台阶用多个小 box 叠即可；
- `sites` 只有拆弹模式用，其它模式忽略。

---

## 5. 写代码：入口脚本

```gdscript
extends ModBase

func setup(ctx: ModContext) -> void:
    ctx.log("hello")

    # 加武器（省略大量默认值）
    ctx.add_weapon(ctx.quick_weapon("spark", "Spark 电浆枪", 34.0, 700, {
        "magSize": 24, "reserve": 96, "cost": 3100,
    }))

    # 事件钩子
    ctx.on("player_kill", func(p: Dictionary) -> void:
        var info: Dictionary = p.get("info", {})
        if bool(info.get("headshot", false)):
            ctx.log("headshot by " + str(p.get("killer", "")))
    )
```

`setup()` 在加载时调用一次；`teardown()` 在卸载/热重载时调用。

---

## 6. ModContext API 全表

### 内容注册

| 方法 | 说明 |
|---|---|
| `add_weapon(def) -> bool` | 注册武器（字段同 JSON） |
| `quick_weapon(id, name, damage, rpm, opts) -> Dictionary` | 生成武器字典，交给 `add_weapon` |
| `add_map(id, spec) -> bool` | 注册地图（spec 同 JSON） |
| `quick_map(id, name, size, sites) -> bool` | 一键生成对称竞技图 |
| `add_mode(meta, factory) -> bool` | 注册模式，`factory` 返回 `ModeBase` 实例 |
| `add_sound(name, path) -> bool` | 注册音效，之后 `Sfx.play_custom(name)` |

### 事件

| 事件 | payload |
|---|---|
| `player_spawn` | `{id, info}` |
| `player_kill` | `{victim, killer, info}` |
| `player_damage` | `{victim, attacker, amount, info}` |
| `weapon_fire` | `{id, weapon, info}` |
| `round_start` / `round_end` | `{...}` |
| `match_start` / `match_end` | `{...}` |
| `explosion` | `{pos, radius, owner}` |

自定义事件：`ctx.emit("我的事件", {...})` → 别人 `ctx.on("mod:我的事件", cb)`。

### 工具

| 方法 | 说明 |
|---|---|
| `ctx.log(msg)` / `ctx.warn(msg)` | 带 `[Mod:id]` 前缀的输出 |
| `ctx.asset("assets/a.png")` | 解析成 `res://` 或 `user://` 绝对路径 |
| `ctx.store_get(k, def)` / `store_set(k, v)` | 每个模组独立的持久化存储 |
| `ctx.mod_id` / `ctx.manifest` | 自身信息 |

---

## 7. 自定义游戏模式

```gdscript
extends ModBase

func setup(ctx: ModContext) -> void:
    ctx.add_mode({
        "id": "hardcore", "label": "硬核死斗", "short": "HC",
        "desc": "一滴血", "min": 2, "max": 12, "tag": "MOD",
    }, func() -> ModeBase: return Hardcore.new())


class Hardcore extends ModeBase:
    func _init() -> void:
        id = "hardcore"
        label = "硬核死斗"
        team_based = false      # 关闭阵营
        respawn = true
        respawn_delay = 1.5
        round_time = 300.0
        score_limit = 15

    func setup(room) -> void:
        room.state.core = Room.RoundCore.new(round_time, 0.0)

    func start_round(room) -> void:
        for p in room.state.players.values():
            p.team = Constants.TEAM_NONE
            p.kills = 0
        room.spawn_all()
        room.state.core.begin(round_time)

    func on_player_spawn(room, p: Dictionary) -> void:
        p.hp = 1.0
        p.maxHp = 1.0
        p.armor = 0

    func on_kill(room, victim, killer, info) -> bool:
        victim.respawnAt = room.state.time + respawn_delay
        if killer != null and int(killer.kills) >= score_limit:
            room.state.core.end_round(str(killer.team), "score_limit")
        return true   # true = 我处理了复活逻辑，Room 不再插手

    func on_tick(room, dt: float) -> void:
        room.state.core.time_left -= dt
        if room.state.core.time_left <= 0.0:
            room.state.core.end_round("DRAW", "timeout")

    func award_round(room, winner, reason) -> void:
        room.finish_round(winner, reason, true, 6.0)
```

### ModeBase 可覆写钩子

| 钩子 | 何时调用 | 返回 |
|---|---|---|
| `setup(room)` | Room 初始化后一次 | — |
| `start_round(room)` | 每回合开始（此时应分队 + 生成） | — |
| `on_tick(room, dt)` | 每 tick（30Hz） | — |
| `on_kill(room, victim, killer, info)` | 玩家死亡 | `true` 表示已接管复活/转换 |
| `on_player_spawn(room, p)` | 出生后（给装备） | — |
| `process_use(room, p, dt)` | 长按 E | `true` 表示已接管 |
| `check_round_end(room)` | 需要时查询 | `{end, winner, reason}` |
| `award_round(room, winner, reason)` | 结算 | 应调用 `room.finish_round(...)` |

### 常用 `room` 能力

```gdscript
room.state                    # 全部状态（players / bomb / matchScore / core ...）
room.spawn_all()              # 全员按阵营出生
room.broadcast_msg({...})     # 给所有客户端推事件（HUD 可直接消费）
room.infect(p)                # 把玩家变成丧尸
room.finish_round(w, r, final, delay)
room.mode                     # 自己
room.is_hostile(a, b)         # 阵营判定（含 FFA / 感染）
```

---

## 8. 打包与分发

```bash
modc check  my_mod        # 校验（CI 友好，出错退出码 1）
modc build  my_mod        # → my_mod-1.0.0.pfmod
modc build  my_mod --minify   # 去注释、压缩 JSON
modc watch  my_mod        # 保存即打包
modc install my_mod-1.0.0.pfmod
modc list
```

`.pfmod` 可以直接上传到任意网盘 / GitHub Release / 自建 CDN。
玩家也可以直接把**解压后的目录**放进 `user://mods/`（开发时推荐）。

### 版本与依赖

- 玩家端会按 `api` 字段做兼容检查；
- `dependencies` 里的 id 必须已加载，否则该模组标记为 `failed` 并在 UI 显示原因；
- 同一个 id 后加载者覆盖先加载者（方便本地调试覆盖线上版本）。

---

## 9. 调试

| 现象 | 排查 |
|---|---|
| 模组没出现在列表 | `mod.json` 的 `id` 是否合法？`api` 是否 > 2？ |
| 武器不在购买菜单 | `slot` 是否为 2？`cost` 是否超过钱包上限？ |
| 地图加载黑屏 | `size` 是否过小（< 20）？`spawns` 是否为空？ |
| 模式按钮点了没反应 | `factory` 是否返回了 `ModeBase` 实例（不是脚本）？ |
| 脚本报错 | 控制台搜 `[Mod:你的id]`；`modc check` 也能提前发现字段问题 |

热重载：改完脚本后调用 `Mods.reload_all()`（可在调试控制台执行），
或直接重启游戏 —— 加载耗时 < 100 ms。

---

## 10. 最佳实践

1. **id 前缀化**：所有武器/地图 id 加 `你的modid_` 前缀，避免撞车。
2. **数值克制**：新武器不要全面超越原版，否则没人玩原版武器。
3. **别改原版**：需要"削弱"就用事件钩子做模式级修正，而不是覆盖内置定义。
4. **资源体积**：贴图 ≤ 1024²，音频用 OGG，单包建议 < 64 MB。
5. **兼容性**：只依赖 `ModContext` 暴露的 API，不直接 `preload` 引擎内部脚本。
6. **声明依赖**：用到别的模组的武器 id 时写进 `dependencies`。

---

## 11. 示例模组

| 目录 | 演示 |
|---|---|
| `mods_examples/neon_arsenal` | 纯 JSON：2 把武器 + 1 张地图 + 一行钩子 |
| `mods_examples/hardcore` | 完整自定义模式（一滴血 / 随机武器） |

```bash
python3 tools/modc/modc.py build mods_examples/hardcore
python3 tools/modc/modc.py install mods_examples/hardcore-1.0.0.pfmod
```

---

## 12. 引擎侧实现索引（想改引擎的人看这里）

| 文件 | 职责 |
|---|---|
| `scripts/mod/mod_loader.gd` | 扫描 / 校验 / 加载 / 事件分发 |
| `scripts/mod/mod_context.gd` | 暴露给模组的 API 表面 |
| `scripts/mod/mod_map_builder.gd` | 极简地图描述 → 引擎地图字典 |
| `scripts/data/weapon_db.gd` | 武器注册表（内置 + JSON + 模组） |
| `scripts/sim/modes/mode_base.gd` | 模式基类 |
| `tools/modc/modc.py` | 编译器 / 脚手架 / 校验器 |

# PolyForge: Ops · v2「Reloaded」

> 一个用 **Godot 4.7.2** 写的战术 FPS：单人 AI、局域网/公网联机、八种模式、完整的模组生态。
> 一次编写，Windows / Linux / macOS / Web / **Android** 全端运行。

[![Godot](https://img.shields.io/badge/Godot-4.7.2-478cbf)](https://godotengine.org)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue)](LICENSE)

---

## 这一版做了什么

v1 是一个能跑的单机原型。v2 把「能跑」推到「能玩、能联机、能扩展」：

| 方向 | v1 | v2 |
|---|---|---|
| 模式 | 2（拆弹 / 生化） | **8**（+团队死斗、混战、军备竞赛、占点、夺旗、生存） |
| 武器 | 18 | **32**（含 5 种投掷物、穿透/护甲穿透、蓄力与转管） |
| 联机 | 无 | **局域网直连 + 公网中继 + 专用服务器** |
| 平台 | 桌面 + Web | **+ Android**（虚拟摇杆 / 陀螺仪 / 刘海安全区） |
| AI | 单层状态机 | **感知-记忆-效用决策 + A\* + 人类化瞄准**，5 档难度 |
| 模组 | 关闭 | **JSON 即可加枪加图；GDScript 加模式；自带编译器 `modc`** |
| 设置 | 3 项 | **45+ 项**，分画质/音频/操作/玩法/网络/无障碍 |
| 性能 | 固定档位 | **自动画质档位 + 自适应 3D 分辨率 + 帧时间监控** |

---

## 核心特性

### 战斗手感
- 固定 30 Hz 确定性模拟 + 渲染插值；服务器回溯命中判定（lag compensation）
- 逐发弹道：距离衰减、护甲穿透、墙体穿透、爆头倍率、散布随移动/连发膨胀
- 视图模型：独立弹夹动画、换弹四阶段音效、落地冲击、冲刺 FOV、ADS 平滑
- 后坐力、命中反馈、伤害数字、屏幕震动、闪光弹致盲

### 模式（8 种，全部可被模组替换/扩展）
`defusal` 拆弹 · `tdm` 团队死斗 · `ffa` 自由混战 · `gungame` 军备竞赛 ·
`koth` 占点 · `ctf` 夺旗 · `zombie` 生化 · `survival` 生存波次

### AI
- **感知**：视锥 + 视线遮挡 + 烟雾阻断 + 枪声听觉 + 记忆衰减
- **决策**：效用打分选目标，角色分工，目标驱动（安包/拆包/夺旗/占点）
- **移动**：二叉堆 A\*（带路径缓存）、贴墙滑行、跳障、分离力、掩体搜索
- **枪法**：反应延迟、过冲、抖动、压枪、点射节奏、开镜距离判断
- **难度**：easy / normal / hard / elite / insane

### 联机
- 房主权威 + 客户端预测 + 远端插值 + 输入限速 + 超时接管
- **局域网**零配置（UDP 广播发现）；**公网中继**单文件 Node.js，零依赖
- 浏览器端可直接通过 `wss://` 加入
- 详见 [`docs/NETWORKING.md`](docs/NETWORKING.md)

### 移动端
- 左摇杆 + 右侧拖拽视角 + 11 个功能键，位置/大小/透明度/左右手全部可调
- 陀螺仪辅助、辅助瞄准强度、刘海与手势条安全区适配
- 画质按设备自动分档（土豆/低/中/高/极致），帧率不足自动降 3D 分辨率
- Android 返回键 → 关闭菜单 → 暂停，失焦自动暂停

### 模组
- 一个 JSON 加一把枪、加一张图（碰撞体和导航自动生成）
- 一段 GDScript 加一个完整游戏模式
- `modc`：脚手架 / 校验 / 打包 / 监听 / 安装，零依赖
- 详见 [`docs/MODDING.md`](docs/MODDING.md)，示例见 `mods_examples/`

---

## 操作

| 桌面 | 按键 | 移动端 |
|---|---|---|
| 移动 | `WASD` | 左摇杆 |
| 跳跃 / 蹲 | `Space` / `Ctrl` | 跳 / 蹲 |
| 冲刺 | `Shift` | 推满摇杆 |
| 射击 / 开镜 | 左键 / 右键 | 开火 / 瞄准 |
| 换弹 / 使用 / 技能 | `R` / `E` / `F` | 对应按钮 |
| 切枪 | `1` `2` `3` `4` | 底部槽位 |
| 购买 / 计分板 / 暂停 | `B` / `Tab` / `Esc` | — / TAB / II |
| 全屏 / 性能面板 | `F11` / `F3` | — |

---

## 运行

1. 安装 [Godot 4.7.2](https://godotengine.org/download)（标准版）。
2. 打开本目录的 `project.godot`。
3. `F5`。

命令行直启（便于自动化测试）：

```bash
godot --path . -- --autostart=cinder --mode=tdm --bots=8
godot --headless --path . -- --autostart=cinder --mode=defusal --bots=6 --seconds=20
```

---

## 构建与导出

```bash
./export_all.sh                 # Windows / Linux / Web / Android 全量导出
./export_all.sh --only android  # 只导 Android
```

Android 需要：Android SDK（platform 35 + build-tools 35）、JDK 17+、NDK（Godot 自动下载）。
产物在 `build/`。详细步骤见 [`docs/BUILDING.md`](docs/BUILDING.md)。

---

## 启动公网中继

```bash
node server/relay.js --port 8080
# 游戏内：联机对战 → 公网中继 → ws://你的IP:8080
```

单文件、零依赖、1 核 512MB 可跑 200+ 房间。

---

## 项目结构

```
scripts/
  core/      平台探测 / 设置中心 / 事件总线 / 性能监控
  data/      常量、武器、经济、地图、武器注册表
  sim/       玩家、物理、命中、房间、Bot AI、模式（modes/）
  net/       协议、传输（中继 / 内置 WS 服务端）、服务端、客户端、管理器
  mod/       加载器、上下文 API、地图编译器
  render/    世界渲染、地图构建、材质、特效、视图模型、角色
  ui/        HUD、菜单、购买、计分板、联机面板、触屏手柄
  audio/     程序化音效、动态 BGM
docs/        MODDING / NETWORKING / BUILDING / CHANGELOG
server/      中继服务器（Node.js）
tools/modc/  模组编译器（Python，零依赖）
mods_examples/  两个可直接跑的示例模组
```

---

## 许可

Apache-2.0。第三方素材许可见 `NOTICE` 与 `License.txt`。

# PolyForge: Ops

> **棱镜行动** — 基于 Godot 引擎的网页第一人称射击游戏（本地 AI 对战原型）。
> A Godot-made browser FPS prototype with local AI bots.

[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Godot](https://img.shields.io/badge/Godot-4.7.1-478cbf.svg)](https://godotengine.org/)

---

## 简介 / Overview

《PolyForge: Ops》是 **PolyForge Arena** 的单机（本地 AI 对战）原型版本，使用
**Godot 4.7.1 (Forward+)** 制作，可导出为 Web (WebAssembly)、Windows 与 Linux。
浏览器打开即可游玩，无需安装任何依赖。

> 本作仅包含单机玩法，不含联机功能。

## 核心特性 / Features

- **第一人称射击**：匕首 / 手枪 / 冲锋枪 / 步枪 / 霰弹枪 / 狙击枪等多款武器，支持爆头判定与射击手感反馈。
- **多种模式**：拆弹模式（Defusal）与生化模式（Zombie）。
- **多张地图**：Cinder 沙漠小镇、Containment 丧尸实验室、Obsidian 暮色塔楼等。
- **完整 HUD 与操作**：计分板、准星、冲刺、蹲伏、换弹动画、落地冲击、视角摆动（headbob）。
- **购买系统**：局内购买菜单可更换与升级武器。
- **渲染管线**：SDFGI 体素全局光照、SSR、SSAO、体积雾、ACES 色调映射、TAA、HDRI 天空。
- **确定性模拟**：30Hz 固定步长模拟 + 渲染插值，兼顾模拟确定性与高帧率画面。
- **Web 自适应**：低配设备自动降低 3D 分辨率以保帧率，UI 始终原生清晰。

## 操作说明 / Controls

| 操作 | 按键 |
| --- | --- |
| 移动 | `W` `A` `S` `D` |
| 跳跃 | `Space` |
| 冲刺 | `Shift` |
| 蹲伏 | `Ctrl` |
| 射击 / 瞄准 | 鼠标左键 / 右键 |
| 换弹 | `R` |
| 使用 / 交互 | `E` |
| 技能 | `F` |
| 切换武器 | `1` `2` `3` `4` |
| 购买菜单 | `B` |
| 计分板 | `Tab` |
| 暂停 | `Esc` |
| 切换 BGM | `M` |

## 技术栈 / Tech Stack

- Godot 4.7.1，Forward+ 渲染器（Web 端自动使用 GL Compatibility），Jolt Physics
- 外部 CC0 素材（ambientCG PBR 贴图 / Poly Haven HDRI / Quaternius GLB 枪械与角色）+ 程序化资源兜底
- 单线程 WebAssembly 构建

## 运行 / Running

1. 安装 [Godot 4.7.1](https://godotengine.org/download)（标准版即可）。
2. 用 Godot 打开本目录下的 `project.godot`。
3. 按 `F5` 运行（主场景 `scenes/main.tscn`）。

## 导出 / Export

项目根目录提供一键导出脚本，需先安装对应的 Godot 导出模板
（编辑器 → 管理导出模板）：

```powershell
# Windows
.\export_all.ps1
.\export_all.ps1 -Godot "C:\Path\To\godot.exe"
```

```bash
# Linux / macOS
./export_all.sh
```

导出产物写入 `build/`（该目录已被 `.gitignore` 忽略）。

## 项目结构 / Project Structure

```
scripts/
  data/      # 常量、武器、经济、地图数据
  sim/       # 玩家、机器人、命中、物理、房间与回放
  render/    # 世界渲染、地图构建、材质、特效、视图模型
  ui/        # HUD、购买菜单、计分板、主菜单、准星
  audio/     # BGM 与音效
scenes/      # 主场景与各测试场景
assets/      # 贴图、HDRI、音效、字体、枪械模型、着色器
addons/      # Godot AI 插件（MIT）
docs/        # 文档（含与 CS2 的盲测对比）
Godot/ Unity/ "Unreal Engine"/   # 各引擎用动画库资源
```

## 许可证 / License

本项目以 **Apache License 2.0** 授权，详见 [LICENSE](LICENSE)。
第三方组件与素材（各自保留其原始许可）详见 [NOTICE](NOTICE) 与 [License.txt](License.txt)。

# 构建与导出

## 依赖

| 目标 | 需要 |
|---|---|
| 桌面（Win/Linux/macOS） | Godot 4.7.2 + 导出模板 |
| Web | 同上 |
| Android | Godot 4.7.2 + 导出模板 + Android SDK(35) + build-tools 35 + JDK 17+ + NDK 27 |

导出模板安装：编辑器 → 编辑器 → 管理导出模板 → 下载并安装；
或手动解压到 `~/.local/share/godot/export_templates/4.7.2.stable/`。

## 一键导出

```bash
./export_all.sh                    # 全部
./export_all.sh --only android     # 只导 Android
./export_all.sh --only web,linux   # 多选
GODOT=/path/to/godot ./export_all.sh
```

产物：

```
build/
├── windows/PolyForgeOps.exe
├── linux/PolyForgeOps.x86_64
├── web/index.html
└── android/PolyForgeOps.apk
```

## Android 细节

1. 环境变量（编辑器 → 编辑器设置 → 导出 → Android）：
   - `Android SDK Path` → 你的 SDK 根目录
   - `Java SDK Path` → JDK 17 或 21
2. 若使用 Gradle 构建（本仓库默认 `use_gradle_build=true`），首次导出会自动下载
   Gradle 与依赖，需要网络。
3. 签名：默认使用调试密钥；发布请在
   `项目 → 导出 → Android → 密钥库` 里配置自己的 keystore。
4. 包名 `com.polyforge.ops`，minSdk 24，targetSdk 35，仅 arm64-v8a（体积最小）。

### 移动端输入与显示

- 触控 UI 层级：世界 → HUD(10) → 触控(20) → 暂停/购买(30) → 计分(32) → 主菜单(34) → 联机(36) → 设置(40)。
- `project.godot` 已启用 `stretch/mode=canvas_items` + `aspect=expand`，配合
  `Platform.apply_ui_scale()` 在手机上自动放大 UI（可于设置 → 画面调整）。
- 触屏设备关闭鼠标模拟（`emulate_mouse_from_touch=false`），键盘与触屏输入分层合并互不覆盖；
  开镜/冲刺支持"切换"模式，陀螺仪与辅助瞄准可在设置 → 操作中开关。
- 设置中心由 `Settings.SCHEMA` 驱动自动生成（6 类 56 项），改动即时生效，支持导入/导出配置。

## 专用服务器

```bash
godot --headless --export-release "Linux" build/linux/PolyForgeOps.x86_64
./build/linux/PolyForgeOps.x86_64 --headless -- --net-host=1 --room=RANKED --seconds=0
```

推荐用 systemd 守护，或 Docker（基础镜像 `ubuntu:22.04` + 解压后的可执行文件）。

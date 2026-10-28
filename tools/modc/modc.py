#!/usr/bin/env python3
"""
modc — PolyForge: Ops 模组编译器（零依赖，单文件）
====================================================
一条命令完成：脚手架 → 校验 → 打包 → 安装。

用法:
  python3 modc.py new  my_mod              # 生成可直接运行的模组骨架
  python3 modc.py check my_mod             # 只校验（CI 用，退出码非 0 表示失败）
  python3 modc.py build my_mod             # 打包成 my_mod.pfmod
  python3 modc.py build my_mod --minify    # 顺手压缩 JSON / 去掉注释
  python3 modc.py watch my_mod             # 文件变动自动重新打包
  python3 modc.py install my_mod.pfmod     # 安装到游戏 user://mods
  python3 modc.py list                     # 列出已安装模组
  python3 modc.py docs                     # 速查表

.pfmod 就是标准 ZIP，游戏端 ZIPReader 直接读取，无需任何运行时依赖。
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import sys
import time
import zipfile
from pathlib import Path

API_VERSION = 2
GAME_NAME = "PolyForge- Ops"
VALID_SLOTS = {0, 1, 2, 3}
VALID_KINDS = {"bool", "int", "float", "string", "color", "vector3", "array", "dict"}
RESERVED_IDS = {"weapon", "name", "id"}

# ---------------------------------------------------------------- 配色输出
_TTY = sys.stdout.isatty()


def C(s: str, code: str) -> str:
    return f"\033[{code}m{s}\033[0m" if _TTY else s


def ok(s: str) -> str:
    return C("✔ " + s, "32")


def warn(s: str) -> str:
    return C("▲ " + s, "33")


def err(s: str) -> str:
    return C("✖ " + s, "31")


def dim(s: str) -> str:
    return C(s, "2")


# ---------------------------------------------------------------- 校验
WEAPON_DEFAULTS = {
    "slot": 2, "auto": True, "melee": False, "pellets": 1, "magSize": 30,
    "reserve": 90, "reloadTime": 2.0, "spread": 0.03, "adsSpread": 0.01,
    "recoil": 0.02, "moveMult": 1.0, "falloffNear": 15.0, "falloffFar": 60.0,
    "falloffMin": 0.45, "headshotMult": 1.8, "sound": "rifle", "penetration": 0.2,
    "armorPen": 0.5, "loudness": 1.0, "category": "rifle", "cost": 2000,
    "desc": "", "projectile": "", "adsFov": 50.0,
}


class Issue:
    def __init__(self, level: str, where: str, msg: str):
        self.level, self.where, self.msg = level, where, msg

    def __str__(self) -> str:
        tag = err("ERROR") if self.level == "error" else warn("WARN ")
        return f"  {tag}  {dim(self.where):<28} {self.msg}"


def validate_mod(root: Path) -> list[Issue]:
    issues: list[Issue] = []
    man_path = root / "mod.json"
    if not man_path.exists():
        issues.append(Issue("error", "mod.json", "文件不存在"))
        return issues
    try:
        man = json.loads(man_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        issues.append(Issue("error", "mod.json", f"JSON 语法错误：{e}"))
        return issues

    for key in ("id", "name", "version"):
        if key not in man:
            issues.append(Issue("error", "mod.json", f"缺少必填字段 `{key}`"))
    if "id" in man and not re.fullmatch(r"[a-z0-9_]{2,32}", str(man["id"])):
        issues.append(Issue("error", "mod.json", "id 只能是小写字母/数字/下划线，2~32 字符"))
    if int(man.get("api", 1)) > API_VERSION:
        issues.append(Issue("error", "mod.json", f"api={man.get('api')} 高于引擎支持的 {API_VERSION}"))
    if "version" in man and not re.fullmatch(r"\d+\.\d+\.\d+", str(man["version"])):
        issues.append(Issue("warn", "mod.json", "version 建议使用语义化版本，例如 1.0.0"))

    entry = str(man.get("entry", "main.gd"))
    if entry and not (root / entry).exists():
        issues.append(Issue("warn", entry, "入口脚本不存在（纯数据模组可忽略）"))

    # 武器
    wdir = root / "weapons"
    if wdir.is_dir():
        for f in sorted(wdir.glob("*.json")):
            issues += validate_weapon_file(f)

    # 地图（可选清单）
    mdir = root / "maps"
    if mdir.is_dir():
        for f in sorted(mdir.glob("*.json")):
            issues += validate_map_file(f)

    # 资源大小
    total = sum(p.stat().st_size for p in root.rglob("*") if p.is_file())
    if total > 64 * 1024 * 1024:
        issues.append(Issue("warn", "package", f"包体 {total/1048576:.1f} MB，建议 < 64 MB"))
    return issues


def validate_weapon_file(f: Path) -> list[Issue]:
    out: list[Issue] = []
    rel = f.name
    try:
        data = json.loads(f.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        return [Issue("error", rel, f"JSON 语法错误：{e}")]
    items = data.get("weapons", []) if isinstance(data, dict) else data
    if isinstance(items, dict):
        items = [items]
    if not isinstance(items, list):
        return [Issue("error", rel, "应为武器对象、数组或 {weapons:[...]}")]
    seen = set()
    for i, w in enumerate(items):
        where = f"{rel}[{i}]"
        if not isinstance(w, dict):
            out.append(Issue("error", where, "武器必须是对象"))
            continue
        wid = w.get("id")
        if not wid:
            out.append(Issue("error", where, "缺少 id"))
        elif not re.fullmatch(r"[a-z0-9_]{2,32}", str(wid)):
            out.append(Issue("error", where, "id 只能小写字母/数字/下划线"))
        elif wid in seen:
            out.append(Issue("error", where, f"id 重复：{wid}"))
        else:
            seen.add(wid)
        for req in ("name", "damage", "fireRate"):
            if req not in w:
                out.append(Issue("error", where, f"缺少 {req}"))
        if "slot" in w and int(w["slot"]) not in VALID_SLOTS:
            out.append(Issue("error", where, "slot 必须 0..3"))
        if float(w.get("damage", 1)) < 0:
            out.append(Issue("error", where, "damage 不能为负"))
        if int(w.get("fireRate", 1)) <= 0:
            out.append(Issue("error", where, "fireRate 必须 > 0"))
        if int(w.get("pellets", 1)) > 32:
            out.append(Issue("error", where, "pellets 上限 32"))
        if float(w.get("magSize", 1)) <= 0:
            out.append(Issue("error", where, "magSize 必须 > 0"))
        if float(w.get("damage", 0)) > 400:
            out.append(Issue("warn", where, f"damage={w['damage']} 过高，可能破坏平衡"))
        if w.get("model") and not (f.parent.parent / "assets").exists():
            out.append(Issue("warn", where, "引用了 model 但没有 assets/ 目录"))
    return out


def validate_map_file(f: Path) -> list[Issue]:
    out: list[Issue] = []
    try:
        data = json.loads(f.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        return [Issue("error", f.name, f"JSON 语法错误：{e}")]
    maps = data.get("maps", [data]) if isinstance(data, dict) else data
    for i, m in enumerate(maps):
        where = f"{f.name}[{i}]"
        if not isinstance(m, dict):
            out.append(Issue("error", where, "地图必须是对象"))
            continue
        for req in ("id", "name"):
            if req not in m:
                out.append(Issue("error", where, f"缺少 {req}"))
        size = m.get("size", [60, 60])
        if not isinstance(size, list) or len(size) != 2:
            out.append(Issue("error", where, "size 必须是 [宽, 长]"))
        for b in m.get("boxes", []):
            if "x" not in b or "z" not in b:
                out.append(Issue("error", where, "box 缺少 x/z"))
    return out


# ---------------------------------------------------------------- 打包
SKIP_DIRS = {".git", "__pycache__", ".idea", ".vscode", "node_modules", ".modc"}
SKIP_FILES = {".DS_Store", "Thumbs.db"}


def collect(root: Path) -> list[Path]:
    files = []
    for p in root.rglob("*"):
        if p.is_dir():
            continue
        rel = p.relative_to(root)
        if any(part in SKIP_DIRS for part in rel.parts):
            continue
        if p.name in SKIP_FILES or p.name.endswith((".pfmod", ".tmp")):
            continue
        files.append(p)
    return sorted(files)


def minify_json(text: str) -> str:
    try:
        return json.dumps(json.loads(text), ensure_ascii=False, separators=(",", ":"))
    except Exception:
        return text


def strip_gdscript(text: str) -> str:
    """保守地去掉整行注释与行尾空白（不碰字符串内的 #）。"""
    out = []
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("#"):
            continue
        # 行尾注释：只在 # 前不是引号的情况下裁剪
        if "#" in line:
            in_str = False
            quote = ""
            cut = -1
            for i, ch in enumerate(line):
                if ch in "\"'":
                    if not in_str:
                        in_str, quote = True, ch
                    elif ch == quote:
                        in_str = False
                elif ch == "#" and not in_str:
                    cut = i
                    break
            if cut >= 0:
                line = line[:cut].rstrip()
        out.append(line)
    return "\n".join(out) + "\n"


def build(root: Path, out_path: Path | None = None, minify: bool = False) -> int:
    issues = validate_mod(root)
    for it in issues:
        print(it)
    errors = [i for i in issues if i.level == "error"]
    if errors:
        print(err("构建失败：%d 个错误" % len(errors)))
        return 1
    man = json.loads((root / "mod.json").read_text(encoding="utf-8"))
    out = out_path or (root.parent / f"{man['id']}-{man.get('version','0.0.0')}.pfmod")
    files = collect(root)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for p in files:
            rel = p.relative_to(root).as_posix()
            data = p.read_bytes()
            if minify and p.suffix == ".json":
                data = minify_json(data.decode("utf-8")).encode("utf-8")
            elif minify and p.suffix == ".gd":
                data = strip_gdscript(data.decode("utf-8")).encode("utf-8")
            z.writestr(rel, data)
    size = out.stat().st_size
    print(ok(f"打包完成 {out.name}  ({len(files)} 文件, {size/1024:.1f} KB)"))
    return 0


# ---------------------------------------------------------------- 安装
def user_mod_dir() -> Path:
    if sys.platform.startswith("win"):
        base = Path(os.environ.get("APPDATA", "~")).expanduser()
    elif sys.platform == "darwin":
        base = Path("~/Library/Application Support").expanduser()
    else:
        base = Path("~/.local/share/godot/app_userdata").expanduser()
    return base / GAME_NAME / "mods"


def install(src: Path, dest: Path | None = None) -> int:
    target = (dest or user_mod_dir()).expanduser()
    target.mkdir(parents=True, exist_ok=True)
    if src.is_dir():
        man = json.loads((src / "mod.json").read_text(encoding="utf-8"))
        root = target / man["id"]
        if root.exists():
            shutil.rmtree(root)
        shutil.copytree(src, root)
        print(ok(f"已安装目录模组 {man['id']} → {root}"))
    else:
        shutil.copy2(src, target / src.name)
        print(ok(f"已复制 {src.name} → {target}"))
    return 0


def list_installed() -> int:
    base = user_mod_dir()
    if not base.exists():
        print(warn("没有安装任何模组"))
        return 0
    rows = []
    for d in sorted(base.iterdir()):
        if d.is_dir() and (d / "mod.json").exists():
            m = json.loads((d / "mod.json").read_text(encoding="utf-8"))
            rows.append((m.get("id", d.name), m.get("version", "?"), m.get("name", "")))
        elif d.suffix == ".pfmod":
            rows.append((d.stem, "pfmod", ""))
    if not rows:
        print(warn("没有安装任何模组"))
        return 0
    print(C("已安装模组", "1"))
    for r in rows:
        print(f"  {r[0]:<20} {r[1]:<10} {r[2]}")
    return 0


# ---------------------------------------------------------------- 脚手架
MAIN_GD = '''# __SLUG__ 主入口。
# 这里只演示 API 的 5%：完整参考见 docs/MODDING.md。
extends ModBase


func setup(ctx: ModContext) -> void:
	ctx.log("hello from __SLUG__")

	# 1) 注册一把武器（字段可只写必要项，其余走默认值）
	ctx.add_weapon(ctx.quick_weapon("spark", "Spark 电浆枪", 34.0, 700, {
		"magSize": 24, "reserve": 96, "spread": 0.022, "adsSpread": 0.006,
		"recoil": 0.018, "cost": 3100, "category": "rifle",
		"desc": "模组示例武器：稳定的三连发。",
	}))

	# 2) 事件钩子：每次有人出生，回满护甲
	ctx.on("player_spawn", func(payload: Dictionary) -> void:
		var id: String = str(payload.get("id", ""))
		print("[__SLUG__] spawn ", id)
	)

	# 3) 每回合开始做点事
	ctx.on("round_start", func(_info: Dictionary) -> void:
		ctx.log("round start")
	)


func teardown() -> void:
	pass
'''

WEAPON_JSON = '''{
  "weapons": [
    {
      "id": "{id}_pulse",
      "name": "Pulse 脉冲手枪",
      "slot": 1,
      "auto": false,
      "damage": 40,
      "fireRate": 320,
      "headshotMult": 2.0,
      "magSize": 14,
      "reserve": 42,
      "reloadTime": 1.5,
      "spread": 0.026,
      "adsSpread": 0.008,
      "recoil": 0.024,
      "cost": 900,
      "category": "pistol",
      "desc": "模组示例：一把更稳的副武器。"
    }
  ]
}
'''

MAP_JSON = '''{
  "id": "yard",
  "name": "模组示例 · 训练场",
  "size": [48, 48],
  "boxes": [
    {"x": 0, "z": 0, "sx": 8, "sz": 8, "h": 3},
    {"x": -14, "z": -10, "sx": 4, "sz": 10, "h": 2.2},
    {"x": 14, "z": 10, "sx": 4, "sz": 10, "h": 2.2},
    {"x": -16, "z": 12, "sx": 6, "sz": 6, "h": 3.4},
    {"x": 16, "z": -12, "sx": 6, "sz": 6, "h": 3.4}
  ],
  "spawns": {
    "CT": [{"x": 0, "z": 18, "yaw": 0}],
    "T":  [{"x": 0, "z": -18, "yaw": 3.14159}]
  },
  "sites": [
    {"id": "A", "x": -10, "z": 0, "radius": 4},
    {"id": "B", "x": 10, "z": 0, "radius": 4}
  ]
}
'''


def scaffold(name: str, root: Path | None = None) -> int:
    slug = re.sub(r"[^a-z0-9_]", "_", name.lower())
    root = root or Path(slug)
    if root.exists():
        print(err(f"目录已存在：{root}"))
        return 1
    (root / "weapons").mkdir(parents=True)
    (root / "maps").mkdir(parents=True)
    man = {
        "id": slug,
        "name": name,
        "version": "1.0.0",
        "author": os.environ.get("USER", "anonymous"),
        "desc": "一个 PolyForge: Ops 模组",
        "api": API_VERSION,
        "entry": "main.gd",
        "dependencies": [],
    }
    (root / "mod.json").write_text(json.dumps(man, ensure_ascii=False, indent=2), encoding="utf-8")
    (root / "main.gd").write_text(MAIN_GD.replace("__SLUG__", slug), encoding="utf-8")
    (root / "weapons" / "example.json").write_text(WEAPON_JSON.replace("{id}", slug), encoding="utf-8")
    (root / "maps" / "yard.json").write_text(MAP_JSON, encoding="utf-8")
    (root / "README.md").write_text(
        f"# {name}\n\n由 `modc new` 生成。\n\n"
        "```bash\npython3 tools/modc/modc.py build .\n```\n\n"
        "把生成的 `.pfmod` 放进游戏的 `user://mods/` 即可。\n",
        encoding="utf-8",
    )
    print(ok(f"已生成模组骨架：{root}"))
    print(dim("  ├─ mod.json        清单"))
    print(dim("  ├─ main.gd         入口（注册武器 / 绑定事件）"))
    print(dim("  ├─ weapons/        纯 JSON 武器，自动注册"))
    print(dim("  ├─ maps/yard.json  一张可玩的训练场"))
    print(dim("  └─ README.md"))
    print()
    print("下一步： " + C(f"python3 tools/modc/modc.py build {root}", "36"))
    return 0


# ---------------------------------------------------------------- watch
def watch(root: Path, minify: bool) -> int:
    print(C(f"监视 {root} …（Ctrl+C 退出）", "36"))
    last = 0.0
    while True:
        newest = max((p.stat().st_mtime for p in collect(root)), default=0.0)
        if newest > last:
            last = newest
            print(dim(time.strftime("[%H:%M:%S] 变更，重新打包…")))
            build(root, minify=minify)
        time.sleep(0.6)


DOCS = """
PolyForge: Ops — 模组速查
=========================
目录结构
  my_mod/
    mod.json             必需，清单
    main.gd              可选，extends ModBase，实现 setup(ctx)
    weapons/*.json       可选，自动注册武器
    maps/*.json          可选，自动注册地图（极简描述即可）
    assets/…             贴图/音效/模型
    modes/*.gd           可选，自定义模式（在 main.gd 里 add_mode）

mod.json
  id          小写字母/数字/下划线，2..32 字符，全局唯一
  name        显示名
  version     语义化版本
  api         2
  entry       入口脚本，默认 main.gd
  dependencies  ["other_mod_id"]

武器 JSON 必填：id, name, damage, fireRate
常用可选：slot(0..3) auto melee pellets magSize reserve reloadTime
          spread adsSpread recoil moveMult headshotMult cost category desc
          penetration armorPen loudness projectile sound adsFov attach

地图 JSON
  { "name": "...", "size": [宽, 长],
    "boxes": [{"x","z","sx","sz","h","type":"crate|wall"}],
    "spawns": {"CT":[{x,z,yaw}], "T":[...]},
    "sites": [{"id":"A","x","z","radius"}] }
  碰撞体与导航图由引擎自动生成。

事件（ctx.on）
  player_spawn / player_kill / player_damage / weapon_fire
  round_start / round_end / match_start / match_end / explosion
  自定义：ctx.emit("我的事件", {...})，别人 ctx.on("mod:我的事件", cb)

常用 API
  ctx.add_weapon(def) / ctx.quick_weapon(...)
  ctx.add_map(id, spec) / ctx.quick_map(...)
  ctx.add_mode(meta, func(): return MyMode.new())
  ctx.add_sound("名字", "assets/hit.wav")
  ctx.store_get / ctx.store_set        持久化
  ctx.log / ctx.warn

命令
  modc new <名称>     生成骨架
  modc check <目录>   校验
  modc build <目录>   打包 .pfmod
  modc install <包>   安装到游戏
"""


# ---------------------------------------------------------------- main
def main() -> int:
    ap = argparse.ArgumentParser(prog="modc", description="PolyForge: Ops 模组编译器")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_new = sub.add_parser("new", help="生成模组骨架")
    p_new.add_argument("name")

    p_check = sub.add_parser("check", help="校验模组")
    p_check.add_argument("path", nargs="?", default=".")

    p_build = sub.add_parser("build", help="打包 .pfmod")
    p_build.add_argument("path", nargs="?", default=".")
    p_build.add_argument("-o", "--out", default=None)
    p_build.add_argument("--minify", action="store_true")

    p_watch = sub.add_parser("watch", help="监视并自动打包")
    p_watch.add_argument("path", nargs="?", default=".")
    p_watch.add_argument("--minify", action="store_true")

    p_inst = sub.add_parser("install", help="安装模组")
    p_inst.add_argument("path")
    p_inst.add_argument("--to", default=None)

    sub.add_parser("list", help="列出已安装模组")
    sub.add_parser("docs", help="打印速查表")

    args = ap.parse_args()

    if args.cmd == "new":
        return scaffold(args.name)
    if args.cmd == "check":
        issues = validate_mod(Path(args.path).resolve())
        for it in issues:
            print(it)
        e = sum(1 for i in issues if i.level == "error")
        w = len(issues) - e
        if e:
            print(err(f"校验失败：{e} 错误 / {w} 警告"))
            return 1
        print(ok(f"校验通过（{w} 警告）"))
        return 0
    if args.cmd == "build":
        out = Path(args.out) if args.out else None
        return build(Path(args.path).resolve(), out, args.minify)
    if args.cmd == "watch":
        return watch(Path(args.path).resolve(), args.minify)
    if args.cmd == "install":
        return install(Path(args.path), Path(args.to) if args.to else None)
    if args.cmd == "list":
        return list_installed()
    if args.cmd == "docs":
        print(DOCS)
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())

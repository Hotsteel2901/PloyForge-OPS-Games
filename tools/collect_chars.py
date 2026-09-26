# 提取项目所有 GDScript 字符串字面量中的字符，生成字体子集字符集文件。
# 用法: python tools/collect_chars.py
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT_DIRS = ["scripts"]
SKIP_EXTS = {".import", ".uid"}

chars = set()
# 基础必需字符：ASCII 可见 + 常用符号（数字、标点、货币）
chars.update(chr(c) for c in range(0x20, 0x7F))
chars.update("！？：；、。，！%—–·…“”‘’（）【】《》¥$#&*+-×÷≤≥∞→↑↓←→⇒★☆①②③④⑤⑥⑦⑧⑨⑩")
chars.update("〇一二三四五六七八九十百千万亿")

pat = re.compile(r'"(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\'')

for d in SCRIPT_DIRS:
    base = os.path.join(ROOT, d)
    for root, _, files in os.walk(base):
        for fn in files:
            if not fn.endswith(".gd"):
                continue
            p = os.path.join(root, fn)
            try:
                with open(p, encoding="utf-8") as f:
                    text = f.read()
            except Exception:
                continue
            for m in pat.finditer(text):
                s = m.group()
                if s[0] == "'":
                    continue
                for ch in s[1:-1]:
                    if ord(ch) >= 0x20 and ord(ch) != 0x7F:
                        chars.add(ch)

# 双引号字符串里被 \" 转义的引号已在上层循环排除，直接补上引号与反斜杠
chars.add('"')
chars.add("\\")

out = "".join(sorted(chars, key=ord))
out_path = os.path.join(ROOT, "tools", "charset.txt")
with open(out_path, "w", encoding="utf-8") as f:
    f.write(out)
print("chars:", len(chars), "->", out_path)

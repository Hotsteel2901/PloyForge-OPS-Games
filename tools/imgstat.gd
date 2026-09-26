# ImgStat: headless image quality metrics tool for the visual review loop.
# Usage: Godot --headless --path . res://tools/imgstat.tscn -- --dir=shots --files=a.png,b.png
# Outputs JSON-ish metrics per image: luma stats, contrast, saturation, edge energy, clipping.
extends Node

const OUT: String = "luma_mean,luma_std,luma_p5,luma_p95,luma_median,clip_black,clip_white,edge_energy,contrast_rms,sat_mean,colorfulness,shadow_pct,mid_pct,hi_pct,r_mean,g_mean,b_mean"

func _ready() -> void:
	var dir: String = "shots"
	var files: Array = []
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--dir="):
			dir = a.get_slice("=", 1)
		elif a.begins_with("--files="):
			files = a.get_slice("=", 1).split(",")
	if files.is_empty():
		var d := DirAccess.open("res://" + dir)
		if d == null:
			printerr("IMGSTAT: cannot open dir res://" + dir)
			get_tree().quit(1)
			return
		d.list_dir_begin()
		var f: String = d.get_next()
		while f != "":
			if f.ends_with(".png"):
				files.append(f)
			f = d.get_next()
	files.sort()
	print("IMGSTAT dir=" + dir + " files=" + str(files.size()))
	for f in files:
		var img := Image.new()
		var err := img.load("res://" + dir + "/" + f)
		if err != OK:
			print("IMGSTAT ERR " + f)
			continue
		print("IMGSTAT " + f + " " + analyze(img))
	get_tree().quit(0)


func analyze(img: Image) -> String:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var down: int = 4
	var n: int = 0
	var luma: PackedFloat32Array = PackedFloat32Array()
	var r_sum: float = 0.0
	var g_sum: float = 0.0
	var b_sum: float = 0.0
	var sat_sum: float = 0.0
	var clip_b: int = 0
	var clip_w: int = 0
	var rg_vals: PackedFloat32Array = PackedFloat32Array()
	var yb_vals: PackedFloat32Array = PackedFloat32Array()
	var x0: int = w / 2 - w / 4
	var x1: int = w / 2 + w / 4
	var y0: int = h / 2 - h / 4
	var y1: int = h / 2 + h / 4
	for y in range(0, h, down):
		for x in range(0, w, down):
			var c: Color = img.get_pixel(x, y)
			var l: float = c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
			r_sum += c.r
			g_sum += c.g
			b_sum += c.b
			var mx: float = max(c.r, max(c.g, c.b))
			var mn: float = min(c.r, min(c.g, c.b))
			sat_sum += 0.0 if mx <= 0.0001 else (mx - mn) / max(mx, 0.0001)
			var rg: float = c.r - c.g
			var yb: float = 0.5 * (c.r + c.g) - c.b
			rg_vals.append(rg)
			yb_vals.append(yb)
			if l < 0.02:
				clip_b += 1
			elif l > 0.98:
				clip_w += 1
			luma.append(l)
			n += 1
	luma.sort()
	var rms: float = 0.0
	var l_mean: float = 0.0
	for l in luma:
		l_mean += l
	l_mean /= n
	for l in luma:
		var d: float = l - l_mean
		rms += d * d
	rms = sqrt(rms / n)
	# edge energy on center crop (detail proxy)
	var edge: float = 0.0
	var e_n: int = 0
	for y in range(y0, y1, 2):
		for x in range(x0, x1, 2):
			var l00: float = img.get_pixel(x, y).r
			var l10: float = img.get_pixel(min(x + 2, w - 1), y).r
			var l01: float = img.get_pixel(x, min(y + 2, h - 1)).r
			edge += abs(l10 - l00) + abs(l01 - l00)
			e_n += 1
	edge = edge / e_n
	var rg_m: float = 0.0
	var yb_m: float = 0.0
	for i in rg_vals.size():
		rg_m += rg_vals[i]
		yb_m += yb_vals[i]
	rg_m /= rg_vals.size()
	yb_m /= yb_vals.size()
	var rg_s: float = 0.0
	var yb_s: float = 0.0
	for i in rg_vals.size():
		rg_s += (rg_vals[i] - rg_m) * (rg_vals[i] - rg_m)
		yb_s += (yb_vals[i] - yb_m) * (yb_vals[i] - yb_m)
	rg_s = sqrt(rg_s / rg_vals.size())
	yb_s = sqrt(yb_s / yb_vals.size())
	var colorfulness: float = sqrt(rg_s * rg_s + yb_s * yb_s) + 0.3 * sqrt(rg_m * rg_m + yb_m * yb_m)
	var p5: float = luma[int(n * 0.05)]
	var p95: float = luma[int(n * 0.95)]
	var med: float = luma[int(n * 0.5)]
	var sh: float = 0.0
	var md: float = 0.0
	var hi: float = 0.0
	for l in luma:
		if l < 0.25:
			sh += 1.0
		elif l < 0.75:
			md += 1.0
		else:
			hi += 1.0
	sh /= n
	md /= n
	hi /= n
	return "%0.3f,%0.3f,%0.3f,%0.3f,%0.3f,%d,%d,%0.4f,%0.3f,%0.3f,%0.3f,%0.3f,%0.3f,%0.3f,%0.3f,%0.3f,%0.3f" % [
		l_mean, rms, p5, p95, med, clip_b, clip_w, edge, rms, sat_sum / n, colorfulness,
		sh, md, hi, r_sum / n, g_sum / n, b_sum / n,
	]

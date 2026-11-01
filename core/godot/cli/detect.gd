## xGEO Core's detection probabilities, for checking them from outside Godot.
##   godot --headless --path godot --script res://cli/detect.gd -- --cases=in.json --out=out.json
## in.json: {"radar": [{snr, pfa, n, swerling}, ...],
##           "optical": [{mag, D, qe, throughput, sky_mag, pixel_arcsec, w_px, rate_px_s, t, dark, read, frac}, ...]}
## out.json: {"radar": [{pd, T}, ...], "optical": [{rate, sky, n, snr}, ...]}
extends SceneTree


func _init() -> void:
	var o := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		o[kv[0]] = kv[1] if kv.size() > 1 else ""
	var cases = JSON.parse_string(FileAccess.get_file_as_string(String(o.get("cases", ""))))
	if not cases is Dictionary:
		printerr("cannot read --cases")
		quit(1)
		return
	var out := {"radar": [], "optical": []}
	for c in cases.get("radar", []):
		out.radar.append({"pd": RF.radar_pd(float(c.snr), float(c.pfa), int(c.n), int(c.swerling)), "T": RF.radar_threshold(float(c.pfa), int(c.n))})
	for c in cases.get("optical", []):
		var rate := Sensing.photon_rate(float(c.mag), float(c.D), float(c.qe), float(c.throughput))
		var sky := Sensing.photon_rate(float(c.sky_mag), float(c.D), float(c.qe), float(c.throughput)) * pow(float(c.pixel_arcsec), 2.0)
		var n := Sensing.streak_pixels(float(c.w_px), float(c.rate_px_s), float(c.t))
		out.optical.append({"rate": rate, "sky": sky, "n": n, "snr": Sensing.ccd_snr(rate * float(c.frac), float(c.t), n, sky, float(c.dark), float(c.read))})
	var f := FileAccess.open(String(o.get("out", "")), FileAccess.WRITE)
	if f == null:
		printerr("cannot write --out")
		quit(1)
		return
	f.store_string(JSON.stringify(out, "", false, true))
	f.close()
	quit(0)

class_name ScreenshotMode
extends Node
## Verification helper. With user args after "--":
##   --screenshot=/abs/path.png   render [member wait_frames] frames, save PNG, quit
##   --cam=x,z,distance,yaw_deg   place the RTS camera (with --focus: only distance and yaw are used)
##   --focus=<node name>          follow a body (planet, moon, HomeStation, gate, Star)
##   --time=<seconds>             advance sim time before the shot
##   --frames=<n>                 frames to render before the shot (default [member wait_frames])
##   --novsync                    disable vsync so the printed frame times are uncapped
## Prints FPS, CPU process time and GPU frame time averaged over the last frames.

@export var wait_frames: int = 90
@export var measure_frames: int = 60

var _path := ""
var _frames := 0
var _sum_delta := 0.0
var _sum_process := 0.0
var _sum_gpu := 0.0
var _sum_cpu_render := 0.0
var _measured := 0
var _last_usec := 0


func _ready() -> void:
	var cam_spec := ""
	var focus_name := ""
	var advance := 0.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			_path = arg.trim_prefix("--screenshot=")
		elif arg.begins_with("--cam="):
			cam_spec = arg.trim_prefix("--cam=")
		elif arg.begins_with("--focus="):
			focus_name = arg.trim_prefix("--focus=")
		elif arg.begins_with("--time="):
			advance = arg.trim_prefix("--time=").to_float()
		elif arg.begins_with("--frames="):
			wait_frames = maxi(arg.trim_prefix("--frames=").to_int(), 10)
			measure_frames = mini(measure_frames, wait_frames / 2)
		elif arg == "--novsync":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if _path.is_empty():
		set_process(false)
		return
	var clock := get_node_or_null(^"/root/SimClock")
	if clock and advance != 0.0:
		clock.call("advance", advance)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	var cam := RTSCamera.of(get_tree())
	if cam:
		cam.set("edge_pan_enabled", false)
	_apply_view.call_deferred(cam_spec, focus_name)


func _apply_view(cam_spec: String, focus_name: String) -> void:
	# Let the system builder configure the camera first (it defers too).
	await get_tree().process_frame
	var cam := RTSCamera.of(get_tree())
	if cam == null:
		return
	var parts := cam_spec.split(",") if not cam_spec.is_empty() else PackedStringArray()
	if not cam_spec.is_empty() and parts.size() < 4:
		push_warning("ScreenshotMode: --cam needs x,z,distance,yaw_deg, got '%s'" % cam_spec)
		parts = PackedStringArray()
	if not focus_name.is_empty():
		var target := get_tree().current_scene.find_child(focus_name, true, false) as Node3D
		if target == null:
			push_warning("ScreenshotMode: --focus node '%s' not found" % focus_name)
		elif cam.has_method("focus_on"):
			if parts.size() >= 4:
				cam.call("set_yaw", parts[3].to_float(), true)
				cam.call("focus_on", target, parts[2].to_float(), true)
			else:
				cam.call("focus_on", target, -1.0, true)
			return
	if parts.size() >= 4 and cam.has_method("set_view"):
		cam.call("set_view", parts[0].to_float(), parts[1].to_float(), parts[2].to_float(), parts[3].to_float())


func _process(delta: float) -> void:
	_frames += 1
	if _frames > wait_frames - measure_frames:
		var vp := get_viewport().get_viewport_rid()
		var now := Time.get_ticks_usec()
		_sum_delta += float(now - _last_usec) / 1000000.0 if _last_usec > 0 else delta
		_sum_process += Performance.get_monitor(Performance.TIME_PROCESS)
		_sum_gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		_sum_cpu_render += RenderingServer.viewport_get_measured_render_time_cpu(vp)
		_measured += 1
	_last_usec = Time.get_ticks_usec()
	if _frames < wait_frames:
		return
	set_process(false)
	var n := maxf(float(_measured), 1.0)
	print("ScreenshotMode: FPS %.1f (monitor %.0f) | frame %.2f ms | TIME_PROCESS monitor avg %.4f | render cpu %.2f ms | gpu %.2f ms | draw calls %d | primitives %d" % [
		n / maxf(_sum_delta, 1e-6), Engine.get_frames_per_second(),
		_sum_delta / n * 1000.0, _sum_process / n, _sum_cpu_render / n, _sum_gpu / n,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	DirAccess.make_dir_recursive_absolute(_path.get_base_dir())
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(_path)
	print("ScreenshotMode: saved %s (%dx%d) err=%d" % [_path, img.get_width(), img.get_height(), err])
	get_tree().quit()

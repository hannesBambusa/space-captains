extends Node
## Autoload "Sfx". Sound effects: pooled 3D one-shots inside the system
## they happen in, 3D loops that follow a node, and flat UI cues.
##
## Hook points call one line:
##   Sfx.play_at(&"hull_hit", pos, self)   # 3D one-shot, self = a node in that system
##   Sfx.play_on(&"dock", self)            # 3D one-shot at a node
##   Sfx.loop(self, &"mining_laser", on)  # 3D loop on a node while on
##   Sfx.ui(&"ui_click")                  # flat cue (UI bus or SFX bus, see SOUNDS)
## Signals wired here, no hooks: Research.tech_completed (research_done),
## every BaseButton's pressed (ui_click).
## Files: recorded Kenney CC0 packs, levelled to one loudness (loudest
## 100 ms at -14 dBFS); the mix lives in the "db" column below
## (assets/audio/sfx/CREDITS.md).
##
## Only the viewed system is heard ([ViewManager]): a sound in any other
## World3D is dropped before it takes a player. Each live system gets its
## own pool node ("SfxPool", a child of its [SystemWorld]) of at most
## [constant VOICES] players; each sound has a voice limit (the oldest of
## that sound is restarted when full) and a minimum real-time gap that
## grows with the sim speed. Above [constant MAX_SIM_SPEED] the world is
## silent (loops pause). Distance: inverse attenuation with unit size and
## cutoff scaled by the camera's zoom distance (80 m to 120 km), so what is
## on screen is heard at every zoom and what is far off screen is not;
## small sounds (hits, guns) are dropped past their max zoom.
## Off in headless runs (smoke tests) unless --sfx-headless is given.

## id -> path (file stem in SFX_DIR; "variants": N = stem_1..stem_N, one
## picked at random), bus, db, limit (voices), gap (real s between starts),
## jitter (pitch +-), zoom (max camera distance, m; 3D only), unit (unit
## size per metre of camera distance; 3D only).
const SOUNDS := {
	&"autocannon": {"path": "autocannon", "variants": 3, "db": -10.0, "limit": 4, "gap": 0.08, "jitter": 0.08, "zoom": 9000.0, "unit": 0.5},
	&"missile_launch": {"path": "missile_launch", "db": -7.0, "limit": 3, "gap": 0.2, "jitter": 0.06, "zoom": 15000.0, "unit": 0.6},
	&"hull_hit": {"path": "hull_hit", "variants": 3, "db": -9.0, "limit": 4, "gap": 0.07, "jitter": 0.12, "zoom": 6000.0, "unit": 0.45},
	&"shield_hit": {"path": "shield_hit", "db": -12.0, "limit": 3, "gap": 0.08, "jitter": 0.1, "zoom": 6000.0, "unit": 0.45},
	&"explosion_small": {"path": "explosion_small", "variants": 3, "db": -4.0, "limit": 3, "gap": 0.15, "jitter": 0.12, "zoom": 30000.0, "unit": 0.7},
	&"explosion_big": {"path": "explosion_big", "db": 0.0, "limit": 2, "gap": 0.6, "jitter": 0.06, "zoom": 130000.0, "unit": 1.0},
	&"warp_spool": {"path": "warp_spool", "db": -9.0, "limit": 3, "gap": 0.3, "jitter": 0.05, "zoom": 8000.0, "unit": 0.5},
	&"warp_jump": {"path": "warp_jump", "db": -7.0, "limit": 3, "gap": 0.2, "jitter": 0.08, "zoom": 12000.0, "unit": 0.55},
	&"gate_transit": {"path": "gate_transit", "db": -5.0, "limit": 2, "gap": 0.8, "jitter": 0.04, "zoom": 20000.0, "unit": 0.7},
	&"dock": {"path": "dock", "db": -6.0, "limit": 2, "gap": 0.4, "jitter": 0.07, "zoom": 3000.0, "unit": 0.5},
	&"undock": {"path": "undock", "db": -6.0, "limit": 2, "gap": 0.4, "jitter": 0.07, "zoom": 3000.0, "unit": 0.5},
	&"mining_laser": {"path": "mining_laser", "db": -15.0, "limit": 3, "gap": 0.0, "jitter": 0.04, "zoom": 4000.0, "unit": 0.4, "loop": true},
	&"ui_click": {"path": "ui_click", "bus": &"UI", "db": -10.0, "limit": 2, "gap": 0.03, "jitter": 0.03},
	&"ui_hover": {"path": "ui_hover", "bus": &"UI", "db": -18.0, "limit": 1, "gap": 0.06, "jitter": 0.0},
	&"build_placed": {"path": "build_placed", "bus": &"SFX", "db": -6.0, "limit": 2, "gap": 0.15, "jitter": 0.05},
	&"research_done": {"path": "research_done", "bus": &"UI", "db": -7.0, "limit": 1, "gap": 1.0, "jitter": 0.0},
	&"alert": {"path": "alert", "bus": &"UI", "db": -5.0, "limit": 1, "gap": 3.0, "jitter": 0.0},
	&"contract_posted": {"path": "contract_posted", "bus": &"UI", "db": -8.0, "limit": 1, "gap": 0.5, "jitter": 0.02},
}
const SFX_DIR := "res://assets/audio/sfx/"
## Players per system pool.
const VOICES := 16
## Flat (UI) players.
const UI_VOICES := 6
## World sounds are silent above this sim speed.
const MAX_SIM_SPEED := 8.0
## 3D sounds farther from the camera than this many camera distances are
## dropped (and cut off by max_distance).
const CULL := 3.0
## Seconds between loop refreshes (which loops sound, their pause state).
const LOOP_TICK := 0.25
const POOL_NAME := &"SfxPool"

var enabled := true

var _streams: Dictionary = {}
## Real time (s) before which a sound may not start again, by id.
var _next_ok: Dictionary = {}
var _ui: Array[AudioStreamPlayer] = []
## Pool node per SystemWorld instance id.
var _pools: Dictionary = {}
## Loop requests: owner instance id -> sound id.
var _loop_req: Dictionary = {}
## Live loop players: owner instance id -> AudioStreamPlayer3D (child of the owner).
var _loop_players: Dictionary = {}
var _loop_left := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	AudioSettings.apply_saved()
	var args := OS.get_cmdline_user_args() + OS.get_cmdline_args()
	enabled = DisplayServer.get_name() != "headless" or args.has("--sfx-headless")
	if not enabled:
		return
	_rng.randomize()
	for id: StringName in SOUNDS:
		var d: Dictionary = SOUNDS[id]
		var takes: Array[AudioStreamWAV] = []
		for path in _paths(d):
			var s := load(path) as AudioStreamWAV if ResourceLoader.exists(path) else null
			if s and d.get("loop", false):
				s = s.duplicate() as AudioStreamWAV
				s.loop_mode = AudioStreamWAV.LOOP_FORWARD
				s.loop_begin = 0
				s.loop_end = int(s.get_length() * s.mix_rate)
			if s:
				takes.append(s)
		if not takes.is_empty():
			_streams[id] = takes
	for i in UI_VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = &"UI"
		add_child(p)
		_ui.append(p)
	get_tree().node_added.connect(_on_node_added)
	Research.tech_completed.connect(func(_t: TechDef) -> void: ui(&"research_done"))


## A 3D one-shot at [param at] (world) in the system [param ctx] is in.
func play_at(id: StringName, at: Vector3, ctx: Node) -> void:
	if not enabled or SimClock.paused or SimClock.speed > MAX_SIM_SPEED:
		return
	var now := Time.get_ticks_msec() * 0.001
	if now < float(_next_ok.get(id, 0.0)) or not _streams.has(id):
		return
	if ctx == null or not ctx.is_inside_tree():
		return
	var w := SystemWorld.of(ctx)
	if w == null or w != _viewed():
		return
	var rig := w.camera
	var cam := rig.get_camera() if rig else null
	if cam == null:
		return
	var d: Dictionary = SOUNDS[id]
	var cam_d := maxf(rig.get_distance(), 1.0)
	if cam_d > float(d.get("zoom", INF)):
		return
	if cam.global_position.distance_to(at) > cam_d * CULL:
		return
	var p := _take(w, id, int(d.get("limit", 4)))
	if p == null:
		return
	_next_ok[id] = now + float(d.get("gap", 0.0)) * maxf(SimClock.speed, 1.0)
	p.stream = _pick(id)
	p.set_meta(&"sfx", id)
	p.set_meta(&"t", now)
	_fit(p, d, cam_d)
	p.global_position = at
	p.play()


## [method play_at] at [param n]'s position (safe while [param n] is
## outside the tree: then nothing plays).
func play_on(id: StringName, n: Node3D) -> void:
	if enabled and is_instance_valid(n) and n.is_inside_tree():
		play_at(id, n.global_position, n)


## A round landing on [param target]: a shield zap while its shields still
## hold (they soak first, [Durability]), else metal.
func hit(at: Vector3, target: Node, ctx: Node) -> void:
	if not enabled:
		return
	var dur := target.get(&"durability") as Durability if is_instance_valid(target) else null
	play_at(&"shield_hit" if dur and dur.shields > 0.0 else &"hull_hit", at, ctx)


## Starts ([param on]) or stops a looping 3D sound on [param owner]. The
## nearest few of each sound in the viewed system play; the rest wait.
func loop(owner: Node3D, id: StringName, on: bool) -> void:
	if not enabled or owner == null:
		return
	var key := owner.get_instance_id()
	if on:
		_loop_req[key] = id
		_loop_left = 0.0
	else:
		_loop_req.erase(key)
		_drop_loop(key)


## A flat cue (UI bus unless the sound says otherwise).
func ui(id: StringName) -> void:
	if not enabled or not _streams.has(id):
		return
	var now := Time.get_ticks_msec() * 0.001
	if now < float(_next_ok.get(id, 0.0)):
		return
	var d: Dictionary = SOUNDS[id]
	_next_ok[id] = now + float(d.get("gap", 0.0))
	var p: AudioStreamPlayer = null
	for q in _ui:
		if not q.playing:
			p = q
			break
	if p == null:
		return
	p.stream = _pick(id)
	p.bus = d.get("bus", &"UI")
	p.volume_db = float(d.get("db", 0.0))
	p.pitch_scale = 1.0 + _rng.randf_range(-1.0, 1.0) * float(d.get("jitter", 0.0))
	p.play()


func _process(delta: float) -> void:
	if not enabled:
		return
	_loop_left -= delta
	if _loop_left > 0.0:
		return
	_loop_left = LOOP_TICK
	_refresh_loops()


## Drops the streams on exit, so the engine does not report them as leaked.
func _exit_tree() -> void:
	var players: Array = []
	players.append_array(_ui)
	for pool: Variant in _pools.values():
		if is_instance_valid(pool):
			players.append_array((pool as Node).get_children())
	for p: Variant in _loop_players.values():
		if is_instance_valid(p):
			players.append(p)
	for p: Variant in players:
		(p as Node).call(&"stop")
		(p as Node).set(&"stream", null)
	_streams.clear()


## The files of a sound: name_1..name_N for variants, else name.wav.
func _paths(d: Dictionary) -> PackedStringArray:
	var base := SFX_DIR + String(d.get("path", ""))
	var n := int(d.get("variants", 0))
	if n == 0:
		return PackedStringArray([base + ".wav"])
	var out := PackedStringArray()
	for i in n:
		out.append("%s_%d.wav" % [base, i + 1])
	return out


func _pick(id: StringName) -> AudioStreamWAV:
	var takes: Array = _streams[id]
	return takes[_rng.randi() % takes.size()]


func _viewed() -> SystemWorld:
	var vm := ViewManager.of(get_tree())
	return vm.viewed if vm else null


## A free player of [param w]'s pool, or the oldest of [param id] when that
## sound has [param limit] voices going; null when the pool is busy.
func _take(w: SystemWorld, id: StringName, limit: int) -> AudioStreamPlayer3D:
	var pool := _pool(w)
	var free: AudioStreamPlayer3D = null
	var oldest: AudioStreamPlayer3D = null
	var same := 0
	for c in pool.get_children():
		var p := c as AudioStreamPlayer3D
		if not p.playing:
			if free == null:
				free = p
			continue
		if p.get_meta(&"sfx", &"") == id:
			same += 1
			if oldest == null or float(p.get_meta(&"t", 0.0)) < float(oldest.get_meta(&"t", 0.0)):
				oldest = p
	if same >= limit:
		return oldest
	if free:
		return free
	if pool.get_child_count() < VOICES:
		var p := _make_3d()
		pool.add_child(p)
		return p
	return null


func _pool(w: SystemWorld) -> Node3D:
	var key := w.get_instance_id()
	var pool := _pools.get(key) as Node3D
	if is_instance_valid(pool):
		return pool
	for k: int in _pools.keys():
		if not is_instance_valid(_pools[k]):
			_pools.erase(k)
	pool = Node3D.new()
	pool.name = POOL_NAME
	w.add_child(pool)
	_pools[key] = pool
	return pool


func _make_3d() -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = &"SFX"
	p.top_level = true
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	p.panning_strength = 0.7
	p.max_db = 3.0
	p.attenuation_filter_cutoff_hz = 9000.0
	p.attenuation_filter_db = -12.0
	return p


## Volume, pitch and distance of [param p] for the camera at [param cam_d] m.
## Zoomed far out the whole world is a little quieter.
func _fit(p: AudioStreamPlayer3D, d: Dictionary, cam_d: float) -> void:
	var far := clampf(inverse_lerp(log(300.0), log(120000.0), log(cam_d)), 0.0, 1.0)
	p.volume_db = float(d.get("db", 0.0)) - 8.0 * far
	p.unit_size = cam_d * float(d.get("unit", 0.5))
	p.max_distance = cam_d * CULL
	p.pitch_scale = 1.0 + _rng.randf_range(-1.0, 1.0) * float(d.get("jitter", 0.0))


## Which loops sound: per sound, the [code]limit[/code] nearest requests in
## the viewed system; paused while the sim is paused or too fast.
func _refresh_loops() -> void:
	if _loop_req.is_empty() and _loop_players.is_empty():
		return
	var w := _viewed()
	var rig := w.camera if w else null
	var cam := rig.get_camera() if rig else null
	var quiet := SimClock.paused or SimClock.speed > MAX_SIM_SPEED
	var by_id: Dictionary = {}
	for key: int in _loop_req.keys():
		var n := instance_from_id(key) as Node3D
		if not is_instance_valid(n) or not n.is_inside_tree():
			_loop_req.erase(key)
			continue
		if cam == null or SystemWorld.of(n) != w:
			continue
		var id: StringName = _loop_req[key]
		var d: Dictionary = SOUNDS[id]
		var dist := cam.global_position.distance_to(n.global_position)
		if rig.get_distance() > float(d.get("zoom", INF)) or dist > rig.get_distance() * CULL:
			continue
		if not by_id.has(id):
			by_id[id] = []
		(by_id[id] as Array).append([dist, key])
	var keep: Dictionary = {}
	for id: StringName in by_id:
		var list: Array = by_id[id]
		list.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		for i in mini(list.size(), int(SOUNDS[id].get("limit", 2))):
			keep[list[i][1]] = id
	for key: int in _loop_players.keys():
		if not keep.has(key):
			_drop_loop(key)
	for key: int in keep:
		var id: StringName = keep[key]
		var p := _loop_players.get(key) as AudioStreamPlayer3D
		if not is_instance_valid(p):
			if not _streams.has(id):
				continue
			p = _make_3d()
			p.top_level = false
			p.stream = _pick(id)
			(instance_from_id(key) as Node3D).add_child(p)
			_loop_players[key] = p
			_fit(p, SOUNDS[id], rig.get_distance())
			p.play(_rng.randf() * p.stream.get_length())
		else:
			_fit_keep_pitch(p, SOUNDS[id], rig.get_distance())
		p.stream_paused = quiet


func _fit_keep_pitch(p: AudioStreamPlayer3D, d: Dictionary, cam_d: float) -> void:
	var pitch := p.pitch_scale
	_fit(p, d, cam_d)
	p.pitch_scale = pitch


func _drop_loop(key: int) -> void:
	var p := _loop_players.get(key) as AudioStreamPlayer3D
	_loop_players.erase(key)
	if is_instance_valid(p):
		p.queue_free()


func _on_node_added(n: Node) -> void:
	var b := n as BaseButton
	if b and not b.pressed.is_connected(_on_button_pressed):
		b.pressed.connect(_on_button_pressed)


func _on_button_pressed() -> void:
	ui(&"ui_click")

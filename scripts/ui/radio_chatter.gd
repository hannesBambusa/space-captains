class_name RadioChatter
extends PanelContainer
## Captain radio chatter: short voiced lines from the player's captains in
## the viewed system ("Taking fire!", "Hold's full. Coming home."), on the
## Radio bus (filtered like a radio; its own volume slider), with a
## subtitle at the bottom centre. Lines and voices: data/radio/radio_lines.json
## (two voices per personality; [method Captain.voice_slot] picks one), files
## assets/audio/voice/radio/<personality>_<slot>/<event>_<n>.mp3
## (tools/gen_radio_lines.py). A missing file shows the subtitle only.
## Events come from the ships' brains (state changes, refusals), hits
## (under fire after a quiet spell, shields gone), kills, gate jumps
## ([method say] from GateTransit), a raid warning and a warlord's arrival.
## Rate limits: one line at a time, [constant GLOBAL_GAP] s between lines,
## [constant CAPTAIN_GAP] s per captain, [constant EVENT_GAP] s per captain
## and event; urgent lines ([constant PRIORITY] 3) skip the first two and
## may cut a calmer line off.
## Comms feel: the Radio bus band-limits (450 Hz to 2.7 kHz), overdrives,
## squashes and sits 18 dB down (background, not a focus) (default_bus_layout.tres); each line opens
## with a short burst of static and a click and closes with a static tail
## ([method _make_static], generated, no files).

const H := preload("res://scripts/ui/theme/hud_style.gd")
const GROUP := "radio_chatter"
const TABLE := "res://data/radio/radio_lines.json"
const DIR := "res://assets/audio/voice/radio/"
const BUS := &"Radio"
const KEYS: PackedStringArray = ["bold", "cautious", "greedy", "lazy"]

const GLOBAL_GAP := 12.0
const CAPTAIN_GAP := 45.0
const EVENT_GAP := 60.0
## A hit after this many sim seconds without one is "under fire" again.
const QUIET_HIT := 15.0
const SHOW_TIME := 3.5
const SCAN_EVERY := 1.0
## Chance a refusal is said out loud (most are silent).
const REFUSAL_CHANCE := 0.15
## Static bursts: length (s) and level of the open and close.
const SQUELCH_OPEN := 0.11
const SQUELCH_CLOSE := 0.16
const SQUELCH_LEVEL := 0.22
const SQUELCH_RATE := 22050
const PRIORITY := {&"under_fire": 3, &"shields_down": 3, &"fleeing": 3, &"warlord": 3, &"kill": 2, &"raid_alert": 2,
		&"hunting": 2, &"jump": 1, &"loaded": 1, &"delivered": 1, &"on_site": 1, &"launch_mining": 1, &"launch_bounty": 1,
		&"repairs": 1, &"refusal": 0}

static var _table: Dictionary = {}

var hud: HUD
var _player: AudioStreamPlayer
var _squelch: AudioStreamPlayer
var _open_static: AudioStreamWAV
var _close_static: AudioStreamWAV
var _label: Label
var _show_left := 0.0
var _scan := 0.0
var _current_pri := -1
var _last_any := -INF
var _last_cap: Dictionary = {}
var _last_ev: Dictionary = {}
var _rng := RandomNumberGenerator.new()
## Raid warning and warlord phase already announced.
var _raid_seen := -1.0
var _warlord_phase := -1


static func of(tree: SceneTree) -> RadioChatter:
	return tree.get_first_node_in_group(GROUP) as RadioChatter if tree else null


## Line [param ev] from [param c] (its ship by default). Quietly dropped
## when the ship is not in the viewed system or a limit holds it back.
static func say(c: Captain, ev: StringName, ship: Ship = null) -> void:
	if c == null or not c.alive:
		return
	var s := ship if ship else c.ship
	if not is_instance_valid(s) or not s.is_inside_tree():
		return
	var rc := of(s.get_tree())
	if rc:
		rc._say(c, ev, s)


static func line_text(personality: int, ev: StringName, n: int) -> String:
	_load_table()
	var lines: Dictionary = (_table.get("lines", {}) as Dictionary).get(KEYS[clampi(personality, 0, 3)], {})
	var list: Array = lines.get(String(ev), [])
	return String(list[n]) if n >= 0 and n < list.size() else ""


static func line_path(personality: int, slot: int, ev: StringName, n: int) -> String:
	return DIR + "%s_%d/%s_%d.mp3" % [KEYS[clampi(personality, 0, 3)], slot, ev, n]


static func _load_table() -> void:
	if not _table.is_empty():
		return
	var f := FileAccess.open(TABLE, FileAccess.READ)
	if f:
		var d: Variant = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			_table = d


func _ready() -> void:
	add_to_group(GROUP)
	_rng.randomize()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player = AudioStreamPlayer.new()
	_player.name = "RadioVoice"
	_player.bus = BUS
	add_child(_player)
	_squelch = AudioStreamPlayer.new()
	_squelch.name = "RadioSquelch"
	_squelch.bus = BUS
	add_child(_squelch)
	_open_static = _make_static(SQUELCH_OPEN, true)
	_close_static = _make_static(SQUELCH_CLOSE, false)
	_player.finished.connect(func() -> void: _play_static(_close_static))
	_label = UIUtil.label("", &"")
	_label.add_theme_color_override("font_color", H.HOLO_SOFT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size.x = 420.0
	add_child(_label)


func setup(owner_hud: HUD) -> void:
	hud = owner_hud


func _process(delta: float) -> void:
	if _show_left > 0.0:
		_show_left -= delta
		if _show_left <= 0.0 and not _player.playing:
			visible = false
	_scan -= delta
	if _scan <= 0.0:
		_scan = SCAN_EVERY
		_hook_viewed()
		_watch_threats()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _viewed() -> SystemWorld:
	return hud.view_manager.viewed if hud and hud.view_manager else null


func _say(c: Captain, ev: StringName, s: Ship) -> void:
	if hud == null or not hud.visible or SystemWorld.of(s) != _viewed():
		return
	var pri := int(PRIORITY.get(ev, 1))
	var now := _now()
	var id := SaveIds.of(c)
	var key := "%d|%s" % [id, ev]
	if now - float(_last_ev.get(key, -INF)) < EVENT_GAP:
		return
	if _player.playing and pri <= _current_pri:
		return
	if pri < 3 and (now - _last_any < GLOBAL_GAP or now - float(_last_cap.get(id, -INF)) < CAPTAIN_GAP):
		return
	var n := _rng.randi() % 2
	var text := line_text(c.personality, ev, n)
	if text.is_empty():
		return
	_last_any = now
	_last_cap[id] = now
	_last_ev[key] = now
	_current_pri = pri
	_player.stop()
	var path := line_path(c.personality, c.voice_slot(), ev, n)
	if ResourceLoader.exists(path):
		_player.stream = load(path) as AudioStream
		_player.play()
		_play_static(_open_static)
	_label.text = "%s: %s" % [c.captain_name, text]
	_show_left = SHOW_TIME
	visible = true
	_place.call_deferred()



func _play_static(s: AudioStreamWAV) -> void:
	if _squelch == null or s == null:
		return
	_squelch.stream = s
	_squelch.play()


## A burst of radio static, 16-bit mono: white noise under an envelope
## (open: a click, then a fast fade; close: a short swell and fade out).
static func _make_static(seconds: float, opening: bool) -> AudioStreamWAV:
	var n := int(seconds * SQUELCH_RATE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711 if opening else 4712
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / float(maxi(n - 1, 1))
		var env := (1.0 - t) * (1.0 - t) if opening else sin(t * PI) * (1.0 - t * 0.5)
		var v := rng.randf_range(-1.0, 1.0) * SQUELCH_LEVEL * env
		if opening and i < 40:
			v += 0.55 * (1.0 - float(i) / 40.0)
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = SQUELCH_RATE
	w.stereo = false
	w.data = data
	return w


func _place() -> void:
	reset_size()
	var vp := get_viewport_rect().size
	position = Vector2((vp.x - size.x) * 0.5, vp.y - size.y - 150.0)


# --- Hooks ---------------------------------------------------------------------

## Connects the viewed system's player ships (once each) and its combat.
func _hook_viewed() -> void:
	var w := _viewed()
	if w == null:
		return
	if w.combat and not w.combat.combatant_destroyed.is_connected(_on_destroyed):
		w.combat.combatant_destroyed.connect(_on_destroyed)
	for n in SystemWorld.nodes_in(w, Ship.GROUP):
		var s := n as Ship
		if s == null or s.dead or s.captain == null or s.brain == null or s.faction != Combat.Faction.PLAYER:
			continue
		if s.has_meta(&"radio_hooked"):
			continue
		s.set_meta(&"radio_hooked", true)
		s.brain.state_changed.connect(_on_state)
		s.brain.decided.connect(_on_decided)
		s.damaged.connect(_on_damaged)


func _on_state(brain: CaptainBrain) -> void:
	var s := brain.ship
	if not is_instance_valid(s) or s.captain == null:
		return
	var prev := int(s.get_meta(&"radio_state", -1))
	s.set_meta(&"radio_state", int(brain.state))
	var c := s.captain
	var trip := brain.trip
	match brain.state:
		CaptainBrain.State.UNDOCKING:
			if trip and trip.contract is MiningContract:
				say(c, &"launch_mining", s)
			elif trip and trip.contract is BountyContract:
				say(c, &"launch_bounty", s)
		CaptainBrain.State.MINING:
			if prev != CaptainBrain.State.MINING:
				say(c, &"on_site", s)
		CaptainBrain.State.RETURNING:
			if trip and trip.loaded and prev == CaptainBrain.State.MINING:
				say(c, &"loaded", s)
			elif brain is MercenaryBrain and (brain as MercenaryBrain).retreating:
				say(c, &"repairs", s)
		CaptainBrain.State.UNLOADING:
			say(c, &"delivered", s)
		CaptainBrain.State.FLEEING:
			say(c, &"fleeing", s)
		CaptainBrain.State.HUNTING:
			if prev != CaptainBrain.State.HUNTING and trip and trip.contract is BountyContract:
				say(c, &"hunting", s)


func _on_decided(brain: CaptainBrain, accepted: bool, _text: String) -> void:
	if not accepted and is_instance_valid(brain.ship) and _rng.randf() < REFUSAL_CHANCE:
		say(brain.ship.captain, &"refusal", brain.ship)


func _on_damaged(s: Ship, _amount: float, _attacker: Node3D) -> void:
	if s.captain == null or s.dead:
		return
	var last := float(s.get_meta(&"radio_hit", -INF))
	s.set_meta(&"radio_hit", SimClock.time)
	if SimClock.time - last > QUIET_HIT:
		s.set_meta(&"radio_shields", false)
		say(s.captain, &"under_fire", s)
	elif s.durability.max_shields > 0.0 and s.durability.shields <= 0.0 and not bool(s.get_meta(&"radio_shields", false)):
		s.set_meta(&"radio_shields", true)
		say(s.captain, &"shields_down", s)


func _on_destroyed(n: Node3D, killer: Node3D) -> void:
	var k := killer as Ship
	if k and k.captain and k.faction == Combat.Faction.PLAYER and n is ScavengerShip:
		say(k.captain, &"kill", k)


## A raid warning and a warlord's arrival at home: a captain there says so.
func _watch_threats() -> void:
	var w := _viewed()
	if w == null or not w.is_home or w.combat == null:
		return
	var raids := w.combat.raids
	if raids and raids.pending_size > 0 and raids.pending_at != _raid_seen:
		_raid_seen = raids.pending_at
		_someone_says(w, &"raid_alert")
	var wl := w.combat.warlords
	if wl and int(wl.phase) != _warlord_phase:
		_warlord_phase = int(wl.phase)
		if wl.phase == WarlordDirector.Phase.PRESENT:
			_someone_says(w, &"warlord")


## A mercenary if there is one in [param w] (else any captain) says [param ev].
func _someone_says(w: SystemWorld, ev: StringName) -> void:
	var pick: Ship = null
	for n in SystemWorld.nodes_in(w, Ship.GROUP):
		var s := n as Ship
		if s == null or s.dead or s.captain == null or s.faction != Combat.Faction.PLAYER:
			continue
		if pick == null or (s is MercenaryShip and not pick is MercenaryShip):
			pick = s
	if pick:
		say(pick.captain, ev, pick)

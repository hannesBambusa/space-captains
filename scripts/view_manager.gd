class_name ViewManager
extends Node
## Root of scenes/game.tscn. Knows the live systems ([SystemWorld], each in
## its own SubViewport under a [SystemView] container), the home system and
## the one on screen. UI and controllers outside every system act on the
## viewed one ([method SystemWorld.of]).
##
## Home is always live (the SystemView node in game.tscn). A remote system
## is live while it is viewed and for [constant GRACE_TIME] real seconds
## after the view left it ([SystemHost]: materialise from its
## RemoteSystemState, dematerialise back into it); otherwise the
## [RemoteSim] child steps it as data. Switching ([method view]): a quick
## fade (black while it builds), or the LoadingScreen when building that
## system took longer than [constant COVER_MS] last time. Only the
## viewed container draws, renders, has the 3D audio listener and gets
## input; hidden cameras do not pan. [signal view_changed] tells the HUD
## and the controllers to rebind.
##
## Viewable ([method viewable_ids]): home, systems marked known, systems
## with one of the player's ships inside (live or as data) and live ones;
## [member debug_view_all] (or the --view-all command line argument)
## allows every system.
##
## Pinned systems ([method pin], forward stations: [ForwardStations]) stay
## live for good: never released, not dropped by [method dematerialise]
## (unpin first); hidden like home while not viewed, simulating at the
## same rate.

signal view_changed(world: SystemWorld)

const GROUP := "view_manager"
## Real seconds a remote system stays live after the view left it.
const GRACE_TIME := 20.0
## Builds slower than this (ms, measured on the last build of the same
## system) get the LoadingScreen instead of the quick fade.
const COVER_MS := 150
const FADE_TIME := 0.12

## The player's home system (registered with the "home" id).
var home: SystemWorld
## The system on screen.
var viewed: SystemWorld
## Live systems by id.
var worlds: Dictionary = {}
## Debug: every system of the network may be viewed.
var debug_view_all := false
var remote_sim: RemoteSim
var forward: ForwardStations

## Remote hosts by id, and the real time each is dropped at (INF while viewed).
var _hosts: Dictionary = {}
var _release_at: Dictionary = {}
## Last build time per system id, ms.
var _build_ms: Dictionary = {}
## Pinned system ids (value true).
var _pinned: Dictionary = {}
var _busy := false
var _real := 0.0
var _fade: ColorRect


static func of(tree: SceneTree) -> ViewManager:
	return tree.get_first_node_in_group(GROUP) as ViewManager if tree else null


## True while home is on screen (or there is no view switch at all).
static func viewing_home(n: Node) -> bool:
	var vm := of(n.get_tree()) if n and n.is_inside_tree() else null
	return vm == null or vm.viewed == null or vm.viewed == vm.home


func _enter_tree() -> void:
	# Before the systems below enter, so they can register.
	add_to_group(GROUP)
	remote_sim = RemoteSim.new()
	remote_sim.name = "RemoteSim"
	add_child(remote_sim)
	forward = ForwardStations.new()
	forward.name = "ForwardStations"
	add_child(forward)


func _ready() -> void:
	debug_view_all = debug_view_all or OS.get_cmdline_user_args().has("--view-all")


## Called by every [SystemWorld] entering the tree.
func register(world: SystemWorld) -> void:
	if world.system_id.is_empty():
		return
	worlds[world.system_id] = world
	if home == null and world.is_home:
		home = world
	if viewed == null and world.is_home:
		viewed = world
		_apply_shown()
		view_changed.emit(world)


func unregister(world: SystemWorld) -> void:
	if world.system_id.is_empty():
		return
	if worlds.get(world.system_id) == world:
		worlds.erase(world.system_id)
	if home == world:
		home = null
	if viewed == world:
		viewed = home
		_apply_shown()
		view_changed.emit(viewed)


## The live system with [param id], or null.
func world(id: StringName) -> SystemWorld:
	var w: Variant = worlds.get(id)
	return w as SystemWorld if is_instance_valid(w) else null


func is_live(id: StringName) -> bool:
	return world(id) != null


func viewed_id() -> StringName:
	return viewed.system_id if is_instance_valid(viewed) else ClusterNetwork.HOME_ID


# --- Viewable systems -----------------------------------------------------------

## Ids the player may switch the view to, home first, then network order.
func viewable_ids() -> Array[StringName]:
	var out: Array[StringName] = [ClusterNetwork.HOME_ID]
	if Sector.network == null:
		return out
	for id in Sector.network.remote_ids():
		if can_view(id):
			out.append(id)
	return out


func can_view(id: StringName) -> bool:
	if id == ClusterNetwork.HOME_ID or debug_view_all or is_live(id):
		return true
	var st := Sector.state(id)
	if st == null:
		return false
	return st.known or RemoteSim.has_player_ship(st) or remote_sim.player_ship_bound_for(id)


func system_name(id: StringName) -> String:
	var def := Sector.system_def(id)
	return def.system_name if def else String(id)


# --- Switching --------------------------------------------------------------------

## Switches the view to [param id] with a fade (or the loading cover when
## the build is slow). Returns once the new view is up.
func view(id: StringName) -> void:
	if _busy or id == viewed_id():
		return
	if not can_view(id):
		return
	_busy = true
	# Unknown build time (first visit): the fade; it holds black while it builds.
	var slow := not is_live(id) and int(_build_ms.get(id, 0)) > COVER_MS
	var cover: LoadingScreen = null
	if slow:
		cover = await LoadingScreen.cover(get_tree(), "Viewing %s" % system_name(id))
	else:
		await _fade_to(1.0)
	view_now(id)
	_busy = false
	if cover:
		cover.reveal()
	else:
		await get_tree().process_frame
		await _fade_to(0.0)


## The view goes home (H, the top bar).
func view_home() -> void:
	await view(ClusterNetwork.HOME_ID)


## Switches at once (materialises when needed). Returns the viewed system.
func view_now(id: StringName) -> SystemWorld:
	var w := world(id)
	if w == null:
		if id == ClusterNetwork.HOME_ID or Sector.system_def(id) == null:
			return viewed
		w = materialise(id)
		if w == null:
			return viewed
	if w == viewed:
		return w
	var old := viewed
	viewed = w
	if is_instance_valid(old) and not old.is_home:
		_release_at[old.system_id] = INF if is_pinned(old.system_id) else _real + GRACE_TIME
	if not w.is_home:
		_release_at[id] = INF
	_apply_shown()
	view_changed.emit(w)
	return w


## Builds remote system [param id] live (no view change). Its host stays
## until it has been out of view for the grace time.
func materialise(id: StringName) -> SystemWorld:
	var have := world(id)
	if have:
		return have
	var host := SystemHost.new()
	host.name = "View_%s" % id
	add_child(host)
	# Right after the other system containers: they hear input last.
	move_child(host, _first_non_view_index())
	host.set_shown(false)
	var t0 := Time.get_ticks_msec()
	var w := host.materialise(id)
	_build_ms[id] = Time.get_ticks_msec() - t0
	if w == null:
		host.queue_free()
		return null
	_hosts[id] = host
	_release_at[id] = INF if is_pinned(id) else _real + GRACE_TIME
	if w.camera:
		w.camera.input_enabled = false
	return w


## Drops live remote system [param id] back into data (not a pinned one).
func dematerialise(id: StringName) -> void:
	var host := _hosts.get(id) as SystemHost
	if host == null or is_pinned(id):
		return
	if viewed == host.world:
		view_now(ClusterNetwork.HOME_ID)
	_hosts.erase(id)
	_release_at.erase(id)
	var old := host.world
	host.dematerialise()
	host.queue_free()
	# Not live from now on (the world leaves the tree at the frame's end; a
	# materialise right after, ForwardStations.found, builds a new one).
	if worlds.get(id) == old:
		worlds.erase(id)


## Keeps remote system [param id] live for good (materialised now when it
## is not). Returns the live world, or null.
func pin(id: StringName) -> SystemWorld:
	if id == ClusterNetwork.HOME_ID or Sector.system_def(id) == null:
		return null
	_pinned[id] = true
	var w := materialise(id)
	if w:
		_release_at[id] = INF
	return w


## Back to the normal rule: released after the grace time out of view.
func unpin(id: StringName) -> void:
	if not _pinned.erase(id):
		return
	if _hosts.has(id) and viewed_id() != id:
		_release_at[id] = _real + GRACE_TIME


func is_pinned(id: StringName) -> bool:
	return _pinned.has(id)


## Every live remote system writes its state into Sector (before a save).
func sync_states() -> void:
	for id: StringName in _hosts:
		(_hosts[id] as SystemHost).capture_into_state()


## Build time of the last materialise of [param id], ms (-1 = never).
func build_ms(id: StringName) -> int:
	return int(_build_ms.get(id, -1))


func _process(delta: float) -> void:
	_real += delta
	for id: StringName in _release_at.keys():
		if _real >= float(_release_at[id]) and (viewed == null or viewed.system_id != id):
			dematerialise(id)


func _first_non_view_index() -> int:
	var i := 0
	for c in get_children():
		if c is SystemView:
			i = c.get_index() + 1
	return i


## Only the viewed system's container draws, renders and listens.
func _apply_shown() -> void:
	for c in get_children():
		var sv := c as SystemView
		if sv == null:
			continue
		var on := false
		for vc in sv.get_children():
			if vc is SubViewport and is_instance_valid(viewed) and viewed.get_viewport() == vc:
				on = true
		sv.set_shown(on)
	for id: StringName in worlds:
		var w := world(id)
		if w and w.camera:
			w.camera.input_enabled = w == viewed


func _fade_to(alpha: float) -> void:
	if _fade == null:
		var layer := CanvasLayer.new()
		layer.name = "ViewFade"
		layer.layer = LoadingScreen.LAYER - 1
		add_child(layer)
		_fade = ColorRect.new()
		_fade.color = Color(0.0, 0.0, 0.0, 0.0)
		_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
		layer.add_child(_fade)
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", alpha, FADE_TIME)
	await tw.finished

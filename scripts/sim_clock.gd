extends Node
## Autoload "SimClock". Simulation time for orbits, spins and cluster drift.
## Space toggles pause, 1 to 6 set speed 1x/2x/4x/8x/16x/24x, +/- (and the
## keypad +/-) step it up/down. Cosmetic shader motion (asteroid tumble, star
## granulation) keeps using real time on purpose.
##
## Big frames are split: each frame's sim seconds ([member frame_dt]) come as
## [member substeps] steps of [member substep_dt] (at most [constant MAX_STEP],
## at most [constant MAX_SUBSTEPS] of them; past that the steps get longer).
## Ships substep on their own (Ship.MAX_STEP); turrets and den guns run
## [method substep] so their fire rate holds at 24x. Timer-only nodes take the
## whole frame in one step. SimStepper steps everything itself.

signal paused_changed(paused: bool)
signal speed_changed(speed: float)

const SPEEDS: Array[float] = [1.0, 2.0, 4.0, 8.0, 16.0, 24.0]
## Longest sim step a substepped node takes (24x at 60 fps = 4 steps).
const MAX_STEP := 0.1
## Cap per frame; a slower frame gets longer steps instead.
const MAX_SUBSTEPS := 40

## Sim seconds since start.
var time: float = 0.0
var speed: float = 1.0
var paused: bool = false
## Sim seconds this frame (0 while paused), set before any other node's _process.
var frame_dt: float = 0.0
## This frame's split of [member frame_dt] (0 steps while paused).
var substeps: int = 0
var substep_dt: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -100


func _process(delta: float) -> void:
	frame_dt = 0.0 if paused else delta * speed
	substeps = 0 if frame_dt <= 0.0 else mini(ceili(frame_dt / MAX_STEP), MAX_SUBSTEPS)
	substep_dt = frame_dt / float(substeps) if substeps > 0 else 0.0
	time += frame_dt


## Calls [param step] (a sim_step(dt)) for this frame's substeps.
func substep(step: Callable) -> void:
	for i in substeps:
		step.call(substep_dt)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed("sim_pause"):
		set_paused(not paused)
	elif event.is_action_pressed("sim_speed_1"):
		set_speed(SPEEDS[0])
	elif event.is_action_pressed("sim_speed_2"):
		set_speed(SPEEDS[1])
	elif event.is_action_pressed("sim_speed_3"):
		set_speed(SPEEDS[2])
	elif event.is_action_pressed("sim_speed_4"):
		set_speed(SPEEDS[3])
	elif event.is_action_pressed("sim_speed_5"):
		set_speed(SPEEDS[4])
	elif event.is_action_pressed("sim_speed_6"):
		set_speed(SPEEDS[5])
	elif event.is_action_pressed("sim_speed_up"):
		step_speed(1)
	elif event.is_action_pressed("sim_speed_down"):
		step_speed(-1)
	else:
		return
	get_viewport().set_input_as_handled()


func set_paused(value: bool) -> void:
	if paused == value:
		return
	paused = value
	paused_changed.emit(paused)


func set_speed(value: float) -> void:
	if is_equal_approx(speed, value):
		return
	speed = value
	speed_changed.emit(speed)


## Next (+1) or previous (-1) entry of [constant SPEEDS], clamped; with
## [param wrap] past the fastest goes back to 1x (top bar click).
func step_speed(dir: int, wrap: bool = false) -> void:
	var i := SPEEDS.find(speed)
	if i < 0:
		i = 0
	i += dir
	set_speed(SPEEDS[posmod(i, SPEEDS.size()) if wrap else clampi(i, 0, SPEEDS.size() - 1)])


## Jumps the clock forward (used by screenshot mode's --time).
func advance(seconds: float) -> void:
	time += seconds


# --- Save ---------------------------------------------------------------------

## A new game: time 0, 1x, running.
func reset() -> void:
	time = 0.0
	set_speed(SPEEDS[0])
	set_paused(false)


## [param paused_override] >= 0 saves that pause state instead (the pause
## menu pauses the clock while it is open).
func save_state(paused_override: int = -1) -> Dictionary:
	return {"time": time, "speed": speed, "paused": paused if paused_override < 0 else paused_override == 1}


func load_state(d: Dictionary) -> void:
	time = float(d.get("time", 0.0))
	set_speed(float(d.get("speed", 1.0)))
	set_paused(bool(d.get("paused", false)))

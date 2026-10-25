extends Node
## Autoload "SimClock". Simulation time for orbits, spins and cluster drift.
## Space toggles pause, 1/2/3 set speed 1x/2x/4x. Cosmetic shader motion
## (asteroid tumble, star granulation) keeps using real time on purpose.

signal paused_changed(paused: bool)
signal speed_changed(speed: float)

const SPEEDS: Array[float] = [1.0, 2.0, 4.0]

## Sim seconds since start.
var time: float = 0.0
var speed: float = 1.0
var paused: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -100


func _process(delta: float) -> void:
	if not paused:
		time += delta * speed


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

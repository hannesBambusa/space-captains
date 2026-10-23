class_name CruiseLeg
extends RefCounted
## Cruise altitude of one open-space leg (see Ship._update_altitude).
##
## A leg starts where the ship was when it got its goal. Its "line" runs
## straight from the start height to the goal's height; the ship flies an
## arc off that line: it climbs (or dives) out over [member ramp] metres,
## holds [member amplitude] off the line, and eases back onto it before
## [member end_pad] metres short of the goal, so it arrives at the goal's
## height. Both ramps are smoothsteps, sized so the designed slope stays
## under [constant RAMP_ANGLE_DEG]; the mover's climb limits smooth the rest.
## Progress is measured by the flat distance still to go, so routes around
## bodies and slowly moving goals (orbits) need no bookkeeping.
##
## The amplitude comes from the ship ([method Ship.cruise_band]: personality
## band, leg length) and the highway rule ([method highway_sign]): legs
## away from the Home Station fly above the line, legs toward it below, so
## opposing traffic on the same route passes at different heights.

## Steepest designed slope of the climb out and the descent, degrees.
const RAMP_ANGLE_DEG := 10.0
## Shortest ramp, metres.
const MIN_RAMP := 40.0
## Even short hops keep this far off the line (the highway rule), metres;
## scaled in over [constant HIGHWAY_LEG] of leg length.
const HIGHWAY_MIN := 20.0
const HIGHWAY_LEG := Vector2(80.0, 320.0)
## A goal that jumps farther than this in one step (beyond its own motion)
## starts a new leg, metres.
const NEW_LEG_JUMP := 250.0

var active: bool = false
## Height the leg started at (world).
var start_y: float = 0.0
## Flat leg length, metres (grows when the goal drifts away).
var length: float = 0.0
## Signed height off the line on the plateau, metres.
var amplitude: float = 0.0
var ramp: float = MIN_RAMP
## The ship is back on the line this far (flat) from the goal, metres.
var end_pad: float = 40.0
## Where the leg started (world), and the goal it was planned for.
var start := Vector3.ZERO
var goal := Vector3.INF
## Last line height and offset (for tools and the route's height span).
var last_line_y: float = 0.0
var last_offset: float = 0.0


## Plans a leg from [param from] to [param to] with [param offset] metres
## off the line on the plateau.
func begin(from: Vector3, to: Vector3, offset: float) -> void:
	active = true
	start = from
	start_y = from.y
	goal = to
	length = maxf(Vector2(to.x - from.x, to.z - from.z).length(), 1.0)
	amplitude = offset
	end_pad = clampf(length * 0.06, 40.0, 400.0)
	var span := maxf(length - end_pad, 0.0)
	ramp = clampf(absf(offset) / tan(deg_to_rad(RAMP_ANGLE_DEG)), MIN_RAMP, maxf(span * 0.45, MIN_RAMP))
	last_line_y = start_y
	last_offset = 0.0


func clear() -> void:
	active = false
	goal = Vector3.INF
	last_offset = 0.0


## True when [param to] is not the goal this leg is flying to any more
## ([param goal_vel]: its own motion over [param dt]).
func goal_jumped(to: Vector3, goal_vel: Vector3, dt: float) -> bool:
	if not active or goal == Vector3.INF:
		return true
	return to.distance_to(goal + goal_vel * dt) > NEW_LEG_JUMP


## Cruise height with [param remaining] flat metres to go to a goal at
## [param end_y]. Also tracks the goal ([param to]).
func height(remaining: float, end_y: float, to: Vector3) -> float:
	goal = to
	length = maxf(length, remaining)
	var t := clampf(1.0 - remaining / length, 0.0, 1.0)
	last_line_y = lerpf(start_y, end_y, t)
	last_offset = offset_at(remaining)
	return last_line_y + last_offset


## Height off the line with [param remaining] flat metres to go.
func offset_at(remaining: float) -> float:
	var travelled := length - remaining
	var up := smoothstep(0.0, ramp, travelled)
	var down := smoothstep(end_pad, end_pad + ramp, remaining)
	return amplitude * up * down


## Highest point of the leg above (or lowest below) both ends, for the
## route's height span.
func peak(end_y: float) -> float:
	return maxf(start_y, end_y) + amplitude if amplitude > 0.0 else minf(start_y, end_y) + amplitude


## Highway rule: +1 for legs leading away from [param station] (outbound),
## -1 toward it (inbound). Without a station: by the leg's heading.
static func highway_sign(from: Vector3, to: Vector3, station: Vector3) -> float:
	if station != Vector3.INF:
		var d_from := Vector2(from.x - station.x, from.z - station.z).length()
		var d_to := Vector2(to.x - station.x, to.z - station.z).length()
		return 1.0 if d_to >= d_from else -1.0
	return 1.0 if (to.x - from.x) >= 0.0 else -1.0


## Signed plateau offset for a leg of [param leg_length] metres:
## [param band] x..y is the ship's offset range (picked by [param roll]
## 0..1), reached in full at legs of [param band].z metres and scaled down
## below; never under the highway minimum on all but the shortest hops.
static func plan_offset(leg_length: float, band: Vector3, roll: float, sign_: float) -> float:
	if band.y <= 0.0:
		return 0.0
	var mag := lerpf(band.x, band.y, clampf(roll, 0.0, 1.0))
	var k := smoothstep(band.z * 0.05, band.z, leg_length)
	var floor_ := minf(band.x, HIGHWAY_MIN) * smoothstep(HIGHWAY_LEG.x, HIGHWAY_LEG.y, leg_length)
	return sign_ * maxf(mag * k, floor_)

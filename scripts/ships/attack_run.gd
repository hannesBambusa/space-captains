class_name AttackRun
extends RefCounted
## One ship's 3D attack pattern around its target (see Ship.fight_step).
## Every step it gives a world goal (position, vertical speed to feed
## forward, whether to face the target) for the mover to chase:
## - ORBIT: circling at about half cannon range on a tilted plane (the
##   circle's height rises and falls with the bearing, [member tilt]) around
##   a centre [member lift_m] above or below the target;
## - CLIMB: swinging wide while climbing (or diving) [member Style.pass_height]
##   above (or below) the target, guns still on it;
## - PASS: the dive (or climb) through: aimed past the target with a lateral
##   miss distance, firing while it is ahead;
## - BREAK: pulling out on the far side, leaving vertically while the nose
##   swings back onto the target, then back to the orbit.
## Targets wider than [constant PASS_MAX_TARGET_RADIUS] (dens, the shield
## bubble) are only circled. The circle stays inside cannon range.
## Fleets ([member slot] of [member slots]) spread the wingmen around the
## target: each its own orbit plane, height and pass side, passes staggered.

enum Phase { ORBIT, CLIMB, PASS, BREAK }


## How a pilot flies its runs (Ship.attack_style: personality, raiders).
class Style:
	## Orbit plane tilt range, degrees.
	var tilt_deg := Vector2(25.0, 40.0)
	## Orbit centre above (+) the target, share of the orbit radius.
	var lift := 0.0
	## Orbit radius, share of the default (half cannon range).
	var radius := 1.0
	## Height off the target at the start of a pass, metres.
	var pass_height := 200.0
	## Miss distance of a pass, share of the orbit radius.
	var pass_close := 0.45
	## Seconds of orbit between passes (min, max).
	var orbit_time := Vector2(9.0, 15.0)
	## Chance that an orbit ends in a pass (else another orbit).
	var pass_chance := 0.45
	## +1 = passes only from above, 0 = alternate above and below.
	var pass_from := 0.0
	## Seconds of the pull-out (min, max).
	var break_time := Vector2(1.4, 2.0)


const PASS_MAX_TARGET_RADIUS := 30.0
## Longest climb, pass, seconds (then the next phase starts anyway).
const CLIMB_TIMEOUT := 7.0
const PASS_TIMEOUT := 7.0
## The goal stays this share of cannon range (3D) from the target.
const RANGE_SHARE := 0.85

var phase: Phase = Phase.ORBIT
var target_id: int = 0
## Orbit plane tilt (radians) and the bearing of its highest point.
var tilt: float = 0.5
var node: float = 0.0
## Orbit centre height off the target, metres.
var lift_m: float = 0.0
## +1 = the pass dives from above, -1 = climbs from below.
var pass_sign: float = 1.0
var slot: int = 0
var slots: int = 1

## Outputs of [method step].
var goal := Vector3.ZERO
var goal_vy: float = 0.0
var face: bool = true
var radius: float = 18.0
## Inside the fight (not still closing in from afar).
var close: bool = false

var _style: Style
var _until: float = 0.0
var _break_len: float = 1.0
var _pass_dir := Vector3.FORWARD
var _pass_lat := Vector3.ZERO
var _rng := RandomNumberGenerator.new()


## New target: rolls this pilot's plane, height and timers ([param roll_seed]
## keeps them stable per ship), spread by fleet [param fleet_slot] of
## [param fleet_size].
func begin(target: Node3D, style: Style, roll_seed: int, fleet_slot: int, fleet_size: int, now: float) -> void:
	target_id = target.get_instance_id()
	_style = style
	slot = fleet_slot
	slots = maxi(fleet_size, 1)
	_rng.seed = roll_seed ^ target_id
	tilt = deg_to_rad(_rng.randf_range(style.tilt_deg.x, style.tilt_deg.y))
	lift_m = 0.0
	if slots > 1:
		# Wingmen: planes evenly around the target, centres stepped in height.
		var base := float(target_id % 6283) * 0.001
		node = base + TAU * float(slot) / float(slots)
		var steps: PackedFloat32Array = [0.0, 1.0, -1.0, 2.0, -2.0]
		lift_m = steps[slot % steps.size()] * 0.22
		pass_sign = 1.0 if slot % 2 == 0 else -1.0
	else:
		node = _rng.randf() * TAU
		pass_sign = 1.0 if _rng.randf() < 0.5 else -1.0
	if style.pass_from > 0.0:
		pass_sign = 1.0
	phase = Phase.ORBIT
	_until = now + _rng.randf_range(style.orbit_time.x, style.orbit_time.y) * 0.6 + 2.5 * float(slot)


## Advances the pattern and sets [member goal], [member goal_vy],
## [member face], [member radius]. [param my] / [param vel]: the ship's
## world position and velocity; [param tp] / [param tv]: the target's;
## [param r]: cannon range, [param hr]: target hit radius, [param side]:
## circling direction (+1 / -1).
func step(my: Vector3, vel: Vector3, tp: Vector3, tv: Vector3, r: float, hr: float, side: float, now: float) -> void:
	var to := Vector3(tp.x - my.x, 0.0, tp.z - my.z)
	var dist := to.length()
	var dir := to / maxf(dist, 0.1)
	var keep := r * 0.5 * _style.radius + hr
	var reach := r * RANGE_SHARE + hr
	var far := dist > maxf(r * 0.9 + hr, keep * 1.3)
	var tangent := dir.cross(Vector3.UP) * side
	var height := minf(_style.pass_height, _dy_max(reach, keep * 1.25))
	close = not far or phase == Phase.PASS or phase == Phase.BREAK
	match phase:
		Phase.ORBIT:
			if not far and now >= _until:
				if hr <= PASS_MAX_TARGET_RADIUS and _rng.randf() < _style.pass_chance:
					phase = Phase.CLIMB
					_until = now + CLIMB_TIMEOUT
				else:
					_until = now + _rng.randf_range(_style.orbit_time.x, _style.orbit_time.y)
		Phase.CLIMB:
			var dy := my.y - tp.y
			if now >= _until or (dist > keep * 1.1 and absf(dy - pass_sign * height) < 40.0):
				phase = Phase.PASS
				_until = now + PASS_TIMEOUT
				_pass_dir = dir
				_pass_lat = dir.cross(Vector3.UP) * side * maxf(_style.pass_close * keep, hr + 25.0) * 2.0
		Phase.PASS:
			var past := (Vector3(my.x - tp.x, 0.0, my.z - tp.z)).dot(_pass_dir)
			if past > keep * 0.3 or now >= _until:
				phase = Phase.BREAK
				_break_len = _rng.randf_range(_style.break_time.x, _style.break_time.y)
				_until = now + _break_len
		Phase.BREAK:
			if now >= _until:
				phase = Phase.ORBIT
				_until = now + _rng.randf_range(_style.orbit_time.x, _style.orbit_time.y)
				if _style.pass_from <= 0.0 and slots <= 1:
					pass_sign = -pass_sign
	radius = 18.0
	face = true
	match phase:
		Phase.CLIMB:
			goal = tp - dir * keep * 1.25 + tangent * keep * 0.9
			goal.y = tp.y + pass_sign * height
			goal_vy = tv.y
			return
		Phase.PASS:
			goal = tp + _pass_dir * keep * 1.2 + _pass_lat
			goal.y = tp.y - pass_sign * height * 0.35
			goal_vy = tv.y
			radius = 40.0
			face = to.dot(_pass_dir) > 0.0
			return
		Phase.BREAK:
			goal = tp + _pass_dir * keep * 2.2 + _pass_lat * 1.5
			goal.y = tp.y - pass_sign * height
			goal_vy = tv.y
			radius = 40.0
			# Pulling out vertically, then swinging the nose back onto the target.
			face = _until - now < _break_len * 0.55
			return
	# Orbit (or closing in): the flat circle as before, its height from the tilted plane.
	if far:
		goal = tp - dir * keep
		face = dist < r * 1.6 + hr
	else:
		goal = tp - dir * keep + tangent * keep * 0.7
	var rel := Vector3(goal.x - tp.x, 0.0, goal.z - tp.z)
	var bearing := atan2(rel.z, rel.x)
	var amp := keep * sin(tilt)
	var lim := _dy_max(reach, rel.length())
	var dy_goal := clampf(lift_m * keep + _style.lift * keep + amp * sin(bearing - node), -lim, lim)
	goal.y = tp.y + dy_goal
	# Feed the plane's rise and fall forward (bearing rate of the ship).
	var mr := Vector3(my.x - tp.x, 0.0, my.z - tp.z)
	var mv := vel - tv
	var rate := (mr.x * mv.z - mr.z * mv.x) / maxf(mr.length_squared(), 100.0)
	goal_vy = tv.y + amp * cos(bearing - node) * rate if absf(dy_goal) < lim else tv.y


## Largest height off the target that keeps a point at flat distance
## [param flat] within [param reach] (3D).
static func _dy_max(reach: float, flat: float) -> float:
	return sqrt(maxf(reach * reach - flat * flat, 0.0))

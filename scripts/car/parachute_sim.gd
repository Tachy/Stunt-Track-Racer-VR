class_name ParachuteSim
extends RefCounted
## The parachute's physics (no autoloads: tested headless). The canopy is a
## point mass with air drag (1/2 rho Cd A v^2) on an elastic nylon line
## from the hook over the car: the line pulls only when stretched (a spring
## and damper). The canopy opens over the first OPEN_DIST metres it travels
## through the air after it was fired - before, only the small pilot chute
## catches air. Fully open, a 900 kg car sinks at about 6.4 m/s, below the
## landing damage speed. Once cut, the canopy drifts down on its own.

const AIR_DENSITY := 1.2         # kg/m3
const CD := 0.8                  # round canopy
const DIAMETER := 24.0           # fully open (m)
const PILOT_AREA := 1.0          # m2, the pilot chute that pulls it out
const OPEN_DIST := 50.0          # m through the air till fully open
const LINE_LEN := 22.0           # hook to canopy (m)
const CANOPY_MASS := 25.0        # kg with the lines
const LINE_STIFF := 30000.0      # N/m: nylon, about 5 % stretch at 30 kN
const LINE_DAMP := 900.0         # N per m/s

var pos := Vector3.ZERO          # canopy
var vel := Vector3.ZERO
var dist := 0.0                  # travelled through the air since fired (m)
var cut := false
## Force of the line on the car (last step).
var tension := Vector3.ZERO


## Fired at the hook (world position and velocity): the packet leaves it
## upwards and backwards.
func _init(hook_pos: Vector3, hook_vel: Vector3) -> void:
	pos = hook_pos
	vel = hook_vel + Vector3.UP * 4.0 - hook_vel.normalized() * 2.0


## 0 (packed) .. 1 (fully open), by the distance travelled.
func opening() -> float:
	return smoothstep(0.0, 1.0, dist / OPEN_DIST)


## Area catching the air now (m2).
func area() -> float:
	return lerpf(PILOT_AREA, PI * DIAMETER * DIAMETER * 0.25, opening())


## One physics step with the hook at hook_pos moving at hook_vel; returns
## the force of the line on the car (zero while slack or cut).
func step(dt: float, hook_pos: Vector3, hook_vel: Vector3) -> Vector3:
	var t := Vector3.ZERO           # on the canopy
	if not cut:
		var d := pos - hook_pos
		var l := d.length()
		if l > LINE_LEN:
			var n := d / l
			var pull := LINE_STIFF * (l - LINE_LEN) + LINE_DAMP * (vel - hook_vel).dot(n)
			t = -n * maxf(pull, 0.0)
	# air drag implicitly (stable however large the canopy), with the speed at
	# the start of the step: in balance exactly k v^2 = the other forces
	var k := 0.5 * AIR_DENSITY * CD * area() / CANOPY_MASS
	var speed := vel.length()
	vel = (vel + (t / CANOPY_MASS + Vector3.DOWN * 9.81) * dt) / (1.0 + k * speed * dt)
	pos += vel * dt
	dist += vel.length() * dt
	tension = -t
	return tension


## Sinking speed of a load of mass m under the open canopy (m/s).
static func terminal_speed(m: float) -> float:
	return sqrt(2.0 * (m + CANOPY_MASS) * 9.81 / (AIR_DENSITY * CD * PI * DIAMETER * DIAMETER * 0.25))

class_name CarTuning
extends Resource
## All handling parameters in one place.

@export var mass := 900.0
@export var engine_force := 7600.0
@export var top_speed := 64.0           # m/s (~230 km/h)
@export var boost_factor := 2.0
@export var boost_top_speed := 74.0
@export var brake_force := 11000.0
@export var reverse_force := 3500.0
@export var reverse_top_speed := 9.0
@export var drag := 0.35

@export var suspension_rest := 0.5
@export var spring := 17000.0
@export var damping := 1700.0           # compression (bump), N per m/s
## Rebound is damped harder than compression, as on real dampers, so a hard
## landing does not throw the car back up.
@export var damping_rebound := 4000.0
@export var bump_stop := 120000.0
## Share of the bump stop force while extending again: the rubber stop eats
## most of the energy instead of acting like a trampoline.
@export var bump_stop_return := 0.25
@export var anti_roll := 7000.0

@export var grip := 1.35                 # friction coefficient
## Lateral tyre force per rad of slip angle (real tyres: ~60-90 kN/rad). The
## wide rear tyres are stiffer, which keeps the car stable (understeer).
@export var cornering_stiffness_front := 60000.0
@export var cornering_stiffness_rear := 90000.0
## Below this speed the slip angle is taken against this speed instead, so a
## (nearly) standing car still gets a finite, stable lateral force.
@export var slip_min_speed := 6.4
## Traction control + ABS: within the friction circle the tyre's side force
## comes first; drive and brake only get what is left, so the rear does not
## break away under full throttle and the car still steers while braking.
@export var traction_control := true
@export var max_steer_deg := 32.0
@export var high_speed_steer_deg := 7.0
@export var steer_falloff_speed := 50.0

@export var landing_damage_speed := 9.5  # m/s into the road at touchdown
@export var landing_damage_factor := 0.025
@export var impact_threshold := 4.5      # m/s unexplained velocity change
@export var impact_damage_factor := 0.022
## A single crash cracks a lot and punches a hole, but never wrecks outright.
@export var max_hit_damage := 0.3
@export var hole_threshold := 0.12       # single hit that punches a hole

@export var boost_unit_time := 0.4       # seconds of boost per unit

## In the air the car aligns with its flight path (velocity vector).
@export var air_align_rate := 4.0        # 1/s turn rate per rad of error
@export var air_align_blend := 10.0      # how firmly the alignment takes over
@export var air_align_delay := 0.08      # s airborne before aligning
@export var air_align_min_speed := 6.0   # m/s; slower -> only level
@export var air_align_max_pitch := 60.0  # deg


static func standard() -> CarTuning:
	return CarTuning.new()


static func super_league() -> CarTuning:
	var t := CarTuning.new()
	t.engine_force = 10000.0
	t.top_speed = 72.0
	t.boost_top_speed = 82.0
	t.brake_force = 15000.0
	return t

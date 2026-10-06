class_name InputMath
## Normalisation of raw joypad axes using calibration values.


## Pedal: 0 at rest value, 1 at full value (works for inverted and combined axes).
static func pedal_norm(v: float, rest: float, full: float) -> float:
	if absf(full - rest) < 0.05:
		return 0.0
	return clampf((v - rest) / (full - rest), 0.0, 1.0)


## Steering: -1 at vmin (full left), +1 at vmax (full right).
static func axis_norm(v: float, vmin: float, vmax: float) -> float:
	var half := (vmax - vmin) * 0.5
	if absf(half) < 0.05:
		return 0.0
	return clampf((v - (vmin + vmax) * 0.5) / half, -1.0, 1.0)

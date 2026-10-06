# Stunt Track Racer VR

**English** · [Deutsch](README.de.md)

VR stunt racing on elevated tracks without guard rails, built with **Godot 4.7.2** (GDScript, OpenXR, Forward+).
Inspired by *Stunt Car Racer* (Geoff Crammond, MicroStyle, 1989). An independent fan project that contains no data, graphics or code from the original and is not affiliated with its rights holders.
Played with a Thrustmaster steering wheel and pedals (detected as "Thrustmaster T80 (USB)" during development); the keyboard works as a fallback.

## Starting

The game starts **either** in VR **or** on the desktop. There is no switching while it runs.

| Mode | Double-click | Command |
|---|---|---|
| **VR** | `Start-VR.cmd` | `"<Godot.exe>" --path "<project folder>"` |
| **Desktop** | `Start-Desktop.cmd` | `"<Godot.exe>" --xr-mode off --path "<project folder>" -- --no-xr` |

The `.cmd` files expect Godot 4.7.2 in `D:\Eigene_Programme\Godot 4\`. If yours lives elsewhere, set the environment variable `GODOT` to the Godot executable or edit the line in the files.

- **VR:** The headset must be on and its OpenXR runtime (e.g. Pimax, SteamVR) running. If it isn't, the game shows a message and quits. It never falls back to desktop silently.
- **Desktop:** OpenXR is not started at all. Hold the right mouse button and drag to look around; F12 resets the view.

You can also open the project in the Godot editor and press F5, which starts in VR. For desktop, enter `--xr-mode off -- --no-xr` under *Project → Project Settings → Editor → Run → Main Run Args*.

**Language:** English by default. Switch to German under *Settings → Language*; the choice is saved.

**On first start:** Menu → *Calibrate wheel*. Then:

| Action | Wheel | Keyboard |
|---|---|---|
| Steer / select in menu | turn the wheel | arrow left/right or up/down |
| Throttle / menu OK | gas pedal | arrow up, Enter |
| Brake, reverse (when stopped) / menu back | brake pedal | arrow down, Esc |
| Boost | assigned button | Space |
| Pause | assigned back button | Esc |
| Crane: drop the car | gas | arrow up / Enter |
| **Recenter VR** | optional assigned button | **F12** |
| Screenshot | | F9 |
| FPS display (in front of your eyes) | | F10 |

Notes: F12 only arrives while the Godot window has focus. Without force feedback the Thrustmaster has no centering force, so enable *Auto-Center: by the wheel* in the Thrustmaster control panel. Enter the rotation range set there under *Settings → Wheel range* (default 900°). Steering is **linear 1:1**: wheel at its stop (±450° at 900°) means road wheels at their stop (*Max. steering angle*, default 32°, a ratio of about 14:1 as in a real car). With a wheel, steering is not reduced at high speed; that only applies to the keyboard.

## View in VR

The base view direction follows the car's heading (yaw) fully. Pitch and roll are followed only by an adjustable share (*View tilt*, default **50 %**), using a **folding rule**:
- Up to ±90° the view follows by that share.
- Beyond that the share decreases again; upside down (loop apex, rollover) the view is level.

At 50 % the view therefore always stays within ±45° of straight ahead, in pitch and roll, without jumps. The headset adds full 6DOF on top. **F12** makes the current head position the eye point in the seat; only yaw and position are taken over, so the horizon never tilts. The value is saved. See `scripts/car/cockpit_math.gd` and `scripts/autoload/xr_manager.gd`.

## Car, physics, lighting

- **Layout like the original:** the cabin sits far back, ahead of it a long nose with an open V engine (supercharger, headers). The big front wheels stand free, with visible double-wishbone suspension and coil springs that compress and extend with the physics. When airborne, the wheels drop lazily.
- **Physics:** Jolt at 120 Hz with interpolation. Raycast suspension per wheel (0.5 m travel), anti-roll bars, slip tyre model. Gravity 9.81 m/s². Everything runs in real time. In the air the car aligns with its flight parabola: the nose points along the velocity vector, the car does not roll, and pitch is limited to ±60° (`air_align_*` in `car_tuning.gd`).
- **Dimensions:** wheelbase 2.9 m, track 1.96 m, wheel diameter 0.84 m front and 0.96 m rear, 900 kg, eye point about 1.75 m above the road. Tracks: 10 m wide, 5–30 m high, curve radii 50–60 m, jumps over 10–30 m, lap lengths 870–1900 m.
- **Lighting:** the sun is a directional light with parallel rays from infinity and casts shadows (can be switched off in the settings). Diffuse sky light keeps shadows bright enough. Flat shading, no specular highlights.
- **Performance** (measured with `--vr-bench`: two eyes at Pimax resolution 5692×4220 and 5194×4220, MSAA 4x, shadows on): about 3.3 ms GPU time per frame for both eyes on an RTX 4090, i.e. a GPU limit of about 300 FPS. 90 Hz needs less than 11.1 ms.

## Content

- **8 tracks**, freely rebuilt (no original data). Div 4: First Flight, Camel Back · Div 3: Mega Ramp, Stone Hopper · Div 2: Big Dipper, The Tower · Div 1: Bridge Run (with drawbridge), Ski Flyer
- **Loop and Jump** (practice only): a figure eight with an **underpass** at the crossing (the upper branch runs on a bridge deck with thickness, the lower one passes beneath), plus **two loops**, a jump and banked curves. Loops have walls down to the ground up to the vertical tangent; the overhead part is a curved road slab.
- **Elevated tracks without guard rails.** If you fall off, the **crane** puts you back. The race also starts from the crane ("DROP START").
- **Damage:** a crack runs along the roll bar, heavy hits punch holes. Holes stay for the whole season and amplify further damage. When the crack is full, the car is wrecked.
- **Boost**, limited per race. 3 laps, 1 against 1. Opponent AI with 11 drivers and their habits (pushing, blocking, edge riding, wheelies).
- **League** with 4 divisions of 3 drivers, promotion and relegation. Winning division 1 unlocks the Super League.
- Procedural engine sound, effects, retro pixel font, UI in English and German. No external assets needed.

## Development / tests

```
set G="<path>\Godot_v4.7.2-stable_win64_console.exe"
%G% --headless --xr-mode off --path . --import
%G% --headless --xr-mode off --path . --script res://tests/run_tests.gd
%G% --headless --xr-mode off --fixed-fps 120 --path . -- --track=ski_flyer --opponent=5 --autopilot --debug --quit-after=200
```

Command line options go after `--`, see `scripts/main.gd`: `--track=<id>`, `--opponent=<0..10>`, `--super`, `--autopilot`, `--no-xr`, `--menu=<screen>`, `--joydump`, `--debug`, `--chase` (camera behind the car), `--fps`, `--vr-bench`, `--render-scale=<x>`, `--screenshot=<s>`, `--quit-after=<s>`, `--lang=<en|de>`.

Handling is tuned centrally in `scripts/car/car_tuning.gd`, tracks live in `scripts/track/track_library.gd`. UI texts are English keys in the code (`Lang.t("...")`); the German table is in `scripts/core/lang.gd`, and a test checks that every key has a translation.

User data is stored in `%APPDATA%\Godot\app_userdata\Stunt Track Racer VR\`: `settings.cfg`, `input.cfg`, `save.json`, `logs\`, `screenshots\`.

## License and origin

- Code, tracks, 3D models (procedurally generated), sounds (synthesized) and pixel font: own work, **MIT license** (see `LICENSE`).
- `icon.svg` is the default Godot icon (Godot Engine, CC BY 4.0) and can be replaced.
- `openxr_action_map.tres` is Godot's default OpenXR action map.
- The game idea and mechanics are inspired by *Stunt Car Racer* (1989). No data, graphics, sounds or code of the original are used.

## How it was made

The game was developed in dialogue with an AI assistant (Claude Code): research on the original, architecture, all GDScript code, track designs (with a small Python solver for closed circuits) and tests. Verification used automated tests (`tests/run_tests.gd`), simulated headless races (autopilot against AI) and screenshots. The actual driving feel in VR and with the wheel was judged by the human.

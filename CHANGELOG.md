# Changelog

## [0.2.0](https://github.com/Tachy/Stunt-Track-Racer-VR/compare/v0.1.0...v0.2.0) (2026-10-09)


### Features

* admin mode tunes the official tracks in the track editor ([ad531a1](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/ad531a14b57416155b391fb3783e53b5d8b66233))
* arrow left/right move a height point 1 m along the lap ([52ec5d8](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/52ec5d8b5e83dd340e06d6f1dd4a5c1d7fd03849))
* arrows for the driving direction on the 3D height line ([b2327bb](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/b2327bbcaadc7c772e78d46fd9fbb7d6153d6636))
* crane drop allowed from the first swing over the road, trolley sets off early ([5366867](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/5366867b232398f31abc47d435af38100285b3f5))
* crane lifts the car from beside the road and swings it over the track ([f58855b](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/f58855b06cd70b7feb4221c4bd65796def2046ea))
* crane sets the car down where it left the road, lowers it into cuts ([3c22366](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/3c22366deb98736132457c0799b22840c4b5ae49))
* crane stands at a fixed height and winches the chain in ([d6ea4ce](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/d6ea4ce69b1d4e1a60c5253fe1dec77c0d74247b))
* crane trolley runs back off the road after the drop ([fd449ba](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/fd449ba3e46fb447529209cacbcd76f658555aa3))
* crane trolley sets off briskly (half-sine ramps, constant speed between) ([245f815](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/245f815bd733f49edd62db364ecbf3bc9aa74651))
* crane winch moves without jerk, carries the car over a banked road's upper edge ([faef2d5](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/faef2d56be5858bf544897590bf15cd7db42c32e))
* crane winch takes 5 s, trolley sets off with 3 m of chain left ([3404741](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/340474103c77ae5691dff0ef6ef139b68d94c689))
* editor deletes marked pieces in the middle of a closed lap ([11c9271](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/11c9271ff043954359e79f66b21c88c273bd62c3))
* editor sees into tunnels through a see-through ground ([fef5498](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/fef5498b528836d0ea2e4cf55d6af5cb6927f5f2))
* first start drops automatically at the first chance ([4396d9a](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/4396d9add7fe646a198f34f26ad5d890f4cc282b))
* height editor in 3D with a plan navigation window ([0280863](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/02808638621c49ef5e187b13144b7aee18fc5f66))
* height surface for the 3D height editor ([f18487e](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/f18487e43ef52f398642fb96a3d25c117adde76a))
* official track Camel Back retuned in the editor ([6c64cec](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/6c64cec18fdd1127f8251824dcb64d719acc2b31))
* official tracks as height splines, tunable in the height editor ([d204a52](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/d204a5248c52e2b84fafeae0122039bf0c6e591d))
* official tracks First Flight, Mega Ramp and Stone Hopper retuned in the height editor ([75fd465](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/75fd46561e1e4e5f15b3a2148c4b00a63db84aec))
* official tracks live in files (server/official) ([c72d680](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/c72d680f0d0a50966a854e9f48aaf583c02b5df0))
* pitch assist off also drops the rotational damping and spin limit ([05352e2](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/05352e244ed36876b3f73ca7445e4214c79eddd9))
* setting "pitch assist" on/off, online the one who offers decides ([d62a633](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/d62a633d7df0c1c0d8ec34143223672d11884888))
* track editor in VR on a screen panel with a mouse pointer ([1174a4d](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/1174a4dd959a0d7f65d0748741a35786a13cb31a))
* Windows release build with installer, /build publishes it ([4032c0a](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/4032c0a66eff8243d94fad35e8d62c47bcdb76a9))


### Bug Fixes

* a car wrecked while falling is not lifted back onto the road ([80c6dfb](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/80c6dfbb9787f1bec4b0e11635e37235bc7c37c7))
* a click selects and drags a height point, a double click moves the camera ([ab8b685](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/ab8b6850112ba762118d5af0bbac1f9688ad2508))
* a piece picked in the navigation window moves the camera again ([19f076b](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/19f076b913e4a615f4d1a922aa510a2237fba249))
* a point added by double click is not selected right away ([ff34a53](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/ff34a53e933296bcae6e9eebb51b552a103e0597))
* a wall down to the ground or into a cut is built upright ([b356673](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/b356673cf32e005987584e55cec6e7d7a04100b2))
* clicks at crossings act on the road clicked, not the one below ([a2e7c54](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/a2e7c5403e3e26f48dd1d17171a46d599c50b1fd))
* crane drop from the first swing through the rest position, trolley 2 m early ([f5eb85d](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/f5eb85d120a74a91445a0acb65381ba5f3bf101f))
* dragging height points stays smooth enough for VR ([765fc11](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/765fc115a1adf7493bc7762ec7040e406fe1ab7f))
* every wall (yellow foot point) is built upright, wherever it is ([eaa22c8](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/eaa22c847505fd6798dfa5a97518f1d5cdf9830a))
* no more "press gas and brake" - unmoved pedals read as released ([16815d6](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/16815d6ae67bd5f42f03e75ed863f002c6ede793))
* no pitch assist after a crane drop; crane height from the road it crosses ([216388f](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/216388f59ac87f45a3f5904459a4fe0faf2e27bc))
* no title music in the track editor ([f2a33e5](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/f2a33e5e3b3d2b614038389b73a4b85cc1f361a8))
* only a click on a height point moves the camera's pivot ([62e7a45](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/62e7a4506214dfdc7aa1abed0925c6b3aa6246b5))
* the foot points of walls (yellow) can be picked again ([39605f0](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/39605f0ebf4d1ae7b8b6fda0e179c3c0967a5c4e))
* VR editor pointer moves freely on a sphere around the eye ([b02c2e6](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/b02c2e67e4e80e4e570c4f872522c2fb488e48f3))
* VR height editor turns around the pivot, steady screen, 6DOF kept ([28b9105](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/28b91052ae87e0837ef2f4780b46142d51474cd1))
* VR pointer drawn at the depth of what it points at ([f50d456](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/f50d4568eebd4a3a6f77be629ddbcead8df2bc41))
* VR pointer stays put for the viewer and always sits in 3D ([4bdea1e](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/4bdea1e82cc597521e8899c459077ee33a3bd263))
* walls on a whole metre are built upright again ([0018426](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/0018426962cd50606f31c41d5ce24c6799aff84e))
* walls stand exactly at their points, the road meets both ([64e0ccd](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/64e0ccd1ede80d62ee0a8a40608f277f9b801051))

## 0.1.0 (2026-10-08)


### Features

* bilingual UI (English, German), 8-bit title music, Doppler and tunnel echo ([c5429b6](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/c5429b6e2fabfe4b0e951ed10d50664075dea280))
* league with divisions, AI opponents with the same physics, practice mode ([c5429b6](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/c5429b6e2fabfe4b0e951ed10d50664075dea280))
* online 1 vs 1 over a Go server: list of open races, editor tracks go along ([c5429b6](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/c5429b6e2fabfe4b0e951ed10d50664075dea280))
* releases with release-please, the Linux server binary attached ([c5429b6](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/c5429b6e2fabfe4b0e951ed10d50664075dea280))
* track editor (plan view, height profile, loops, pits, ski jumps, tunnels) ([c5429b6](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/c5429b6e2fabfe4b0e951ed10d50664075dea280))
* VR stunt racing on elevated tracks with real car physics (9.81 m/s², slip-angle tyres, suspension, damage, crane) ([c5429b6](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/c5429b6e2fabfe4b0e951ed10d50664075dea280))


### Bug Fixes

* in the air only the pitch follows the flight path, roll and yaw stay free ([c5429b6](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/c5429b6e2fabfe4b0e951ed10d50664075dea280))
* smooth road where it twists out of banked curves (no more bumps) ([c5429b6](https://github.com/Tachy/Stunt-Track-Racer-VR/commit/c5429b6e2fabfe4b0e951ed10d50664075dea280))

class_name NetCodec
extends RefCounted
## Binary encoding of the online protocol (docs/net-protocol.md). Mirrors
## server/protocol.go; both are checked against server/testdata/*.hex.
## No autoload references, so the headless tests can use it.

const MAGIC := 0xB1
const VERSION := 3
## Race rules byte (set by whoever offers the race): super league, flight
## pitch assist switched off.
const RULE_SUPER := 1
const RULE_NO_PITCH_ASSIST := 2
const HEADER_SIZE := 10
const STATE_SIZE := 36
const MAX_STR := 32
const DEFAULT_PORT := 27015
## A shared track goes in TRACK events of at most TRACK_PART bytes, at most
## TRACK_PARTS of them.
const TRACK_PART := 1000
const TRACK_PARTS := 16

# packet types
const HELLO := 1
const WELCOME := 2
const PING := 3
const PONG := 4
const STATE := 5
const EVENT := 6
const ACK := 7
const BYE := 8

# reliable events
const EV_JOIN := 1
const EV_ROOM := 2
const EV_MATCH := 3
const EV_READY := 4
const EV_START := 5
const EV_LAP := 6
const EV_FINISH := 7
const EV_WRECKED := 8
const EV_LEAVE := 9
const EV_OPP := 10
const EV_RESULT := 11
const EV_ERROR := 12
const EV_WATCH := 13
const EV_LOBBY := 14
const EV_OFFER := 15
const EV_TAKE := 16
const EV_TRACK := 17

const JOIN_QUICK := 0
const JOIN_CREATE := 1
const JOIN_CODE := 2

# ERROR codes
const ERR_ROOM_NOT_FOUND := 1
const ERR_ROOM_FULL := 2
const ERR_VERSION := 3
const ERR_OFFER_GONE := 4
## Not on the wire: the shared track of a MATCH did not arrive or is broken.
const ERR_NO_TRACK := 100

const RESULT_NONE := 255
## Race states in STATE packets (index = wire value).
const RACE_STATES := ["hold", "racing", "falling", "craned", "finished", "wrecked"]
const SQRT1_2 := 0.70710678118654752


## "host", "host:port", "1.2.3.4:27015" -> [host, port]; the port defaults
## to DEFAULT_PORT. Host "" if nothing usable was entered.
static func parse_address(address: String) -> Array:
	var a := address.strip_edges()
	for prefix in ["udp://", "http://", "https://"]:
		if a.begins_with(prefix):
			a = a.substr(prefix.length())
	a = a.trim_suffix("/")
	var port := DEFAULT_PORT
	if a.count(":") == 1:
		var parts := a.split(":")
		a = parts[0]
		if parts[1].is_valid_int() and int(parts[1]) > 0 and int(parts[1]) < 65536:
			port = int(parts[1])
	return [a, port]


# --- header ------------------------------------------------------------------------

static func packet(type: int, seq: int, ack: int, token: int, payload := PackedByteArray()) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u8(MAGIC)
	b.put_u8(type)
	b.put_u16(seq & 0xFFFF)
	b.put_u16(ack & 0xFFFF)
	b.put_u32(token & 0xFFFFFFFF)
	b.put_data(payload)
	return b.data_array


## {type, seq, ack, token, body: StreamPeerBuffer at the payload} or {} if
## the packet is not ours.
static func parse(data: PackedByteArray) -> Dictionary:
	if data.size() < HEADER_SIZE or data[0] != MAGIC:
		return {}
	var b := StreamPeerBuffer.new()
	b.data_array = data
	b.seek(1)
	var h := {"type": b.get_u8(), "seq": b.get_u16(), "ack": b.get_u16(), "token": b.get_u32()}
	h["body"] = b
	return h


## true when sequence number a is newer than b (with 16-bit wrap-around).
static func seq_newer(a: int, b: int) -> bool:
	var d := (a - b) & 0xFFFF
	return d != 0 and d < 0x8000


# --- primitives --------------------------------------------------------------------

static func put_str(b: StreamPeerBuffer, s: String) -> void:
	var bytes := s.to_utf8_buffer()
	while bytes.size() > MAX_STR:
		s = s.left(s.length() - 1)
		bytes = s.to_utf8_buffer()
	b.put_u8(bytes.size())
	b.put_data(bytes)


static func get_str(b: StreamPeerBuffer) -> String:
	var n := b.get_u8()
	if n == 0 or b.get_available_bytes() < n:
		return ""
	var r: Array = b.get_data(n)
	return (r[1] as PackedByteArray).get_string_from_utf8()


static func put_i24(b: StreamPeerBuffer, v: int) -> void:
	v = clampi(v, -0x800000, 0x7FFFFF) & 0xFFFFFF
	b.put_u8(v & 0xFF)
	b.put_u8((v >> 8) & 0xFF)
	b.put_u8((v >> 16) & 0xFF)


static func get_i24(b: StreamPeerBuffer) -> int:
	var v := b.get_u8() | (b.get_u8() << 8) | (b.get_u8() << 16)
	return v - 0x1000000 if v & 0x800000 else v


static func put_color(b: StreamPeerBuffer, c: Color) -> void:
	b.put_u8(c.r8)
	b.put_u8(c.g8)
	b.put_u8(c.b8)


static func get_color(b: StreamPeerBuffer) -> Color:
	return Color8(b.get_u8(), b.get_u8(), b.get_u8())


static func put_code(b: StreamPeerBuffer, code: String) -> void:
	var c := (code.to_upper() + "    ").left(4).to_ascii_buffer()
	b.put_data(c)


static func get_code(b: StreamPeerBuffer) -> String:
	var r: Array = b.get_data(4)
	return (r[1] as PackedByteArray).get_string_from_ascii().strip_edges()


## Rotation as "smallest three": index of the largest component (dropped,
## made positive) in bits 30-31, the other three in 10 bits each.
static func pack_quat(q: Quaternion) -> int:
	q = q.normalized()
	var c := [q.x, q.y, q.z, q.w]
	var big := 0
	for i in range(1, 4):
		if absf(c[i]) > absf(c[big]):
			big = i
	var sgn := -1.0 if c[big] < 0.0 else 1.0
	var bits := big << 30
	var shift := 20
	for i in 4:
		if i == big:
			continue
		var v := clampi(roundi((float(c[i]) * sgn / SQRT1_2 + 1.0) * 0.5 * 1023.0), 0, 1023)
		bits |= v << shift
		shift -= 10
	return bits


static func unpack_quat(bits: int) -> Quaternion:
	var big := (bits >> 30) & 3
	var c := [0.0, 0.0, 0.0, 0.0]
	var shift := 20
	var sum := 0.0
	for i in 4:
		if i == big:
			continue
		var v := float((bits >> shift) & 1023) / 1023.0 * 2.0 - 1.0
		c[i] = v * SQRT1_2
		sum += c[i] * c[i]
		shift -= 10
	c[big] = sqrt(maxf(0.0, 1.0 - sum))
	return Quaternion(c[0], c[1], c[2], c[3]).normalized()


# --- car state ---------------------------------------------------------------------

## s: {t (s), pos, rot (Quaternion), vel, angvel, steer (-1..1), throttle,
## brake, boosting, reverse, held, airborne (optional), state (RACE_STATES),
## boost, crack, holes}
static func encode_state(s: Dictionary) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u32(clampi(roundi(float(s["t"]) * 1000.0), 0, 0xFFFFFFFF))
	var p: Vector3 = s["pos"]
	for k in 3:
		put_i24(b, roundi(p[k] * 1000.0))
	b.put_u32(pack_quat(s["rot"]))
	var v: Vector3 = s["vel"]
	for k in 3:
		b.put_16(clampi(roundi(v[k] * 100.0), -32768, 32767))
	var w: Vector3 = s["angvel"]
	for k in 3:
		b.put_16(clampi(roundi(w[k] * 1000.0), -32768, 32767))
	b.put_8(clampi(roundi(float(s["steer"]) * 127.0), -127, 127))
	b.put_u8(clampi(roundi(float(s["throttle"]) * 255.0), 0, 255))
	b.put_u8(clampi(roundi(float(s["brake"]) * 255.0), 0, 255))
	var flags := (1 if s["boosting"] else 0) | (2 if s["reverse"] else 0) | (4 if s["held"] else 0)
	flags |= 8 if s.get("airborne", false) else 0
	flags |= maxi(RACE_STATES.find(s["state"]), 0) << 4
	b.put_u8(flags)
	b.put_u8(clampi(int(s["boost"]), 0, 255))
	b.put_u8(clampi(roundi(float(s["crack"]) * 255.0), 0, 255))
	b.put_u8(clampi(int(s["holes"]), 0, 255))
	return b.data_array


## The STATE payload at the buffer position, or {} if too short.
static func decode_state(b: StreamPeerBuffer) -> Dictionary:
	if b.get_available_bytes() < STATE_SIZE:
		return {}
	var s := {}
	s["t"] = b.get_u32() / 1000.0
	s["pos"] = Vector3(get_i24(b), get_i24(b), get_i24(b)) / 1000.0
	s["rot"] = unpack_quat(b.get_u32())
	s["vel"] = Vector3(b.get_16(), b.get_16(), b.get_16()) / 100.0
	s["angvel"] = Vector3(b.get_16(), b.get_16(), b.get_16()) / 1000.0
	s["steer"] = b.get_8() / 127.0
	s["throttle"] = b.get_u8() / 255.0
	s["brake"] = b.get_u8() / 255.0
	var flags := b.get_u8()
	s["boosting"] = flags & 1 != 0
	s["reverse"] = flags & 2 != 0
	s["held"] = flags & 4 != 0
	s["airborne"] = flags & 8 != 0
	s["state"] = RACE_STATES[mini((flags >> 4) & 7, RACE_STATES.size() - 1)]
	s["boost"] = b.get_u8()
	s["crack"] = b.get_u8() / 255.0
	s["holes"] = b.get_u8()
	return s


# --- client -> server payloads -----------------------------------------------------

static func encode_hello(player_name: String, color: Color) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u8(VERSION)
	put_color(b, color)
	put_str(b, player_name)
	return b.data_array


static func encode_ping(client_ms: int) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u32(client_ms & 0xFFFFFFFF)
	return b.data_array


## Event payload: u16 id, u8 kind, data.
static func encode_event(id: int, kind: int, data := PackedByteArray()) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u16(id & 0xFFFF)
	b.put_u8(kind)
	b.put_data(data)
	return b.data_array


static func ev_join(mode: int, code: String, track: String, super_league: bool, pitch_assist := true) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u8(mode)
	put_code(b, code)
	put_str(b, track)
	b.put_u8(rules(super_league, pitch_assist))
	return b.data_array


static func rules(super_league: bool, pitch_assist: bool) -> int:
	return (RULE_SUPER if super_league else 0) | (0 if pitch_assist else RULE_NO_PITCH_ASSIST)


## Adds super / pitch_assist to a dictionary decoded with a rules byte.
static func _put_rules(d: Dictionary, r: int) -> Dictionary:
	d["super"] = r & RULE_SUPER != 0
	d["pitch_assist"] = r & RULE_NO_PITCH_ASSIST == 0
	return d


static func ev_watch(on: bool) -> PackedByteArray:
	return PackedByteArray([1 if on else 0])


static func ev_offer(track: String, super_league: bool, pitch_assist := true) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	put_str(b, track)
	b.put_u8(rules(super_league, pitch_assist))
	return b.data_array


static func ev_take(offer_id: int) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u16(offer_id & 0xFFFF)
	return b.data_array


## Part of a shared track (TrackLibrary.share_data).
static func ev_track(part: int, parts: int, data: PackedByteArray) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u8(part)
	b.put_u8(parts)
	b.put_u16(data.size())
	b.put_data(data)
	return b.data_array


static func ev_lap(laps: int, race_s: float) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u8(laps)
	b.put_u32(maxi(roundi(race_s * 1000.0), 0))
	return b.data_array


static func ev_finish(race_s: float, best_s: float) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u32(maxi(roundi(race_s * 1000.0), 0))
	b.put_u32(maxi(roundi(best_s * 1000.0), 0))
	return b.data_array


# --- server -> client payloads -----------------------------------------------------

## WELCOME / PONG / EVENT bodies as dictionaries ({} if malformed).
static func decode_welcome(b: StreamPeerBuffer) -> Dictionary:
	if b.get_available_bytes() < 8:
		return {}
	return {"token": b.get_u32(), "server_ms": b.get_u32()}


static func decode_pong(b: StreamPeerBuffer) -> Dictionary:
	if b.get_available_bytes() < 8:
		return {}
	return {"client_ms": b.get_u32(), "server_ms": b.get_u32()}


static func decode_event(b: StreamPeerBuffer) -> Dictionary:
	if b.get_available_bytes() < 3:
		return {}
	var e := {"id": b.get_u16(), "kind": b.get_u8()}
	match e["kind"]:
		EV_ROOM:
			e["code"] = get_code(b)
		EV_MATCH:
			e["slot"] = b.get_u8()
			e["track"] = get_str(b)
			_put_rules(e, b.get_u8())
			e["opp_name"] = get_str(b)
			e["opp_color"] = get_color(b)
		EV_START:
			e["drop_ms"] = b.get_u32()
		EV_OPP:
			e["what"] = b.get_u8()
			e["laps"] = b.get_u8()
			e["ms"] = b.get_u32()
		EV_RESULT:
			e["winner"] = b.get_u8()
			e["reason"] = b.get_u8()
		EV_ERROR:
			e["code"] = b.get_u8()
		EV_LOBBY:
			# open races: [{id, name, color, track, super, pitch_assist}], oldest first
			e["online"] = b.get_u16()
			var offers := []
			for i in b.get_u8():
				if b.get_available_bytes() < 2:
					break
				var o := {"id": b.get_u16(), "name": get_str(b), "color": get_color(b), "track": get_str(b)}
				offers.append(_put_rules(o, b.get_u8()))
			e["offers"] = offers
		EV_TRACK:
			e["part"] = b.get_u8()
			e["parts"] = b.get_u8()
			var n := b.get_u16()
			var r: Array = b.get_data(mini(n, b.get_available_bytes()))
			e["data"] = r[1] if r[1].size() == n else PackedByteArray()
	return e

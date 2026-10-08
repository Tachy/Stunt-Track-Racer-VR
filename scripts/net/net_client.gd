extends Node
## Online connection (autoload "Net"): UDP session with the race server,
## clock sync, reliable events and the car state stream. Idle until
## connect_to(). Protocol: docs/net-protocol.md, encoding: NetCodec.

signal welcomed
signal room_created(code: String)
signal lobby_changed                      # players_online / offers
signal matched(info: Dictionary)          # {slot, track, super, opp_name, opp_color}
                                          # (a shared track: track = TrackLibrary.SHARED_ID)
signal start_at(server_s: float)          # drop time on the server clock
signal opponent_event(what: int, laps: int, race_s: float)
signal result_received(winner: int, reason: int)
signal failed(code: int)                  # NetCodec ERROR codes
signal disconnected(reason: String)

const RESEND := 0.1
const HELLO_RESEND := 0.5
const PING_INTERVAL := 0.5
const TIMEOUT := 5.0
const CLOCK_SAMPLES := 8

## offline, connecting, online
var status := "offline"
var token := 0
var slot := -1
var match_info := {}
## Round trip time (s), from the PING/PONG with the shortest time.
var rtt := 0.0
## Latest opponent car state (NetCodec.decode_state) and when it came.
var opp_state := {}
var opp_state_ms := 0
## Server clock (s) when the latest opponent state arrived.
var opp_state_server_s := 0.0
var opp_states_received := 0
## LOBBY (while watching): players on the server and the open races
## [{id, name, color, track, super}], oldest first.
var players_online := 0
var offers: Array = []

var _udp: PacketPeerUDP
var _seq := 0
var _in_ack := 0          # last reliable event handled in order
var _out_id := 0
var _out: Array = []      # [{id, payload, sent}]
var _opp_seq := -1
var _player_name := ""
var _color := Color.WHITE
var _hello_t := 0.0
var _ping_t := 0.0
var _last_rx := 0
var _clock: Array = []    # [{rtt, offset}] newest last
var _offset_ms := 0.0     # server_ms - local ms
var _watching := false
var _track_in: Array = [] # TRACK parts received for the next MATCH


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _exit_tree() -> void:
	disconnect_from()   # game closed: BYE, so the opponent hears it at once


func is_online() -> bool:
	return status == "online"


func local_ms() -> int:
	return Time.get_ticks_msec()


## Server clock in seconds (same on both clients up to the clock sync error).
func server_time() -> float:
	return (local_ms() + _offset_ms) / 1000.0


## address: "host" or "host:port" (NetCodec.parse_address).
func connect_to(address: String, player_name: String, color: Color) -> bool:
	disconnect_from()
	var hp := NetCodec.parse_address(address)
	var host: String = hp[0]
	var port: int = hp[1]
	if host == "":
		return false
	var ip := host if host.is_valid_ip_address() else IP.resolve_hostname(host, IP.TYPE_IPV4)
	if ip == "":
		push_warning("[Net] cannot resolve %s" % host)
		return false
	_udp = PacketPeerUDP.new()
	if _udp.connect_to_host(ip, port) != OK:
		_udp = null
		return false
	_player_name = player_name
	_color = color
	status = "connecting"
	_hello_t = HELLO_RESEND
	_last_rx = local_ms()
	if _watching:
		_event(NetCodec.EV_WATCH, NetCodec.ev_watch(true))
	print("[Net] connecting to %s:%d as %s" % [ip, port, player_name])
	return true


func disconnect_from() -> void:
	if _udp:
		if token != 0:
			_send(NetCodec.BYE)
		_udp.close()
	_udp = null
	status = "offline"
	token = 0
	slot = -1
	match_info = {}
	_seq = 0
	_in_ack = 0
	_out_id = 0
	_out.clear()
	_clock.clear()
	players_online = 0
	offers = []
	_reset_race()


func _reset_race() -> void:
	_track_in = []
	opp_state = {}
	opp_states_received = 0
	_opp_seq = -1


# --- requests ------------------------------------------------------------------------

func join(mode: int, code: String, track: String, super_league: bool) -> void:
	slot = -1
	match_info = {}
	_reset_race()
	if mode != NetCodec.JOIN_CODE:
		_send_track(track)
	_event(NetCodec.EV_JOIN, NetCodec.ev_join(mode, code, track, super_league))


## Receive the LOBBY list (kept across reconnects until switched off).
func watch(on: bool) -> void:
	_watching = on
	if not on:
		players_online = 0
		offers = []
	_event(NetCodec.EV_WATCH, NetCodec.ev_watch(on))


## Puts an open race on the track into the LOBBY list (replaces one of our own).
## A track from the editor goes along: the one who takes the race gets it.
func offer(track: String, super_league: bool) -> void:
	slot = -1
	match_info = {}
	_reset_race()
	_send_track(track)
	_event(NetCodec.EV_OFFER, NetCodec.ev_offer(track, super_league))


## Accepts the open race offer_id of another player: MATCH follows (or ERROR).
func take(offer_id: int) -> void:
	slot = -1
	match_info = {}
	_reset_race()
	_event(NetCodec.EV_TAKE, NetCodec.ev_take(offer_id))


func send_ready() -> void:
	_event(NetCodec.EV_READY)


func send_lap(laps: int, race_s: float) -> void:
	_event(NetCodec.EV_LAP, NetCodec.ev_lap(laps, race_s))


func send_finish(race_s: float, best_s: float) -> void:
	_event(NetCodec.EV_FINISH, NetCodec.ev_finish(race_s, best_s))


func send_wrecked() -> void:
	_event(NetCodec.EV_WRECKED)


## Leaves the current room (retire / back to the menu); stays connected.
func leave() -> void:
	if is_online():
		_event(NetCodec.EV_LEAVE)
	slot = -1
	match_info = {}
	_reset_race()


func send_state(s: Dictionary) -> void:
	if is_online():
		_send(NetCodec.STATE, NetCodec.encode_state(s))


## A track from the editor goes to the server in TRACK parts before the
## OFFER / JOIN that names it (the reliable events arrive in order).
func _send_track(track: String) -> void:
	if not TrackLibrary.is_custom(track):
		return
	var data := TrackLibrary.share_data(track)
	var parts := ceili(data.size() / float(NetCodec.TRACK_PART))
	if parts == 0 or parts > NetCodec.TRACK_PARTS:
		push_warning("[Net] track %s cannot be shared (%d bytes)" % [track, data.size()])
		return
	for i in parts:
		_event(NetCodec.EV_TRACK, NetCodec.ev_track(i, parts, data.slice(i * NetCodec.TRACK_PART, (i + 1) * NetCodec.TRACK_PART)))


## The shared track of a MATCH, kept for this race: TrackLibrary.SHARED_ID,
## or "" if it did not arrive whole or is broken.
func _install_track() -> String:
	var data := PackedByteArray()
	for p in _track_in:
		data.append_array(p["data"])
	if _track_in.is_empty() or _track_in.size() != int(_track_in[0]["parts"]):
		return ""
	return TrackLibrary.install_shared(data)


# --- transport -----------------------------------------------------------------------

func _send(type: int, payload := PackedByteArray()) -> void:
	_seq = (_seq + 1) & 0xFFFF
	_udp.put_packet(NetCodec.packet(type, _seq, _in_ack, token, payload))


func _event(kind: int, data := PackedByteArray()) -> void:
	if _udp == null:
		return
	_out_id = (_out_id + 1) & 0xFFFF
	var payload := NetCodec.encode_event(_out_id, kind, data)
	_out.append({"id": _out_id, "payload": payload, "sent": local_ms()})
	if is_online():
		_send(NetCodec.EVENT, payload)


func _process(delta: float) -> void:
	if _udp == null:
		return
	while _udp.get_available_packet_count() > 0:
		_receive(_udp.get_packet())
		if _udp == null:
			return
	if local_ms() - _last_rx > TIMEOUT * 1000.0:
		print("[Net] server timeout")
		disconnect_from()
		disconnected.emit("timeout")
		return
	if status == "connecting":
		_hello_t += delta
		if _hello_t >= HELLO_RESEND:
			_hello_t = 0.0
			_send(NetCodec.HELLO, NetCodec.encode_hello(_player_name, _color))
		return
	_ping_t += delta
	if _ping_t >= PING_INTERVAL:
		_ping_t = 0.0
		_send(NetCodec.PING, NetCodec.encode_ping(local_ms()))
	var now := local_ms()
	for o in _out:
		if now - int(o["sent"]) >= RESEND * 1000.0:
			o["sent"] = now
			_send(NetCodec.EVENT, o["payload"])


func _receive(data: PackedByteArray) -> void:
	var h := NetCodec.parse(data)
	if h.is_empty():
		return
	var b: StreamPeerBuffer = h["body"]
	if h["type"] == NetCodec.WELCOME:
		var w := NetCodec.decode_welcome(b)
		if w.is_empty() or status != "connecting":
			return
		token = w["token"]
		status = "online"
		_last_rx = local_ms()
		_offset_ms = float(w["server_ms"]) - local_ms()
		print("[Net] online (token %08x)" % token)
		_ping_t = PING_INTERVAL
		for o in _out:
			o["sent"] = 0
		welcomed.emit()
		return
	if h["token"] != token or token == 0:
		return
	_last_rx = local_ms()
	# cumulative ack of our events
	while not _out.is_empty():
		var id: int = _out[0]["id"]
		if id == h["ack"] or NetCodec.seq_newer(h["ack"], id):
			_out.pop_front()
		else:
			break
	match h["type"]:
		NetCodec.PONG:
			_clock_sample(NetCodec.decode_pong(b))
		NetCodec.STATE:
			if _opp_seq < 0 or NetCodec.seq_newer(h["seq"], _opp_seq):
				var s := NetCodec.decode_state(b)
				if not s.is_empty():
					_opp_seq = h["seq"]
					opp_state = s
					opp_state_ms = local_ms()
					opp_state_server_s = server_time()
					opp_states_received += 1
		NetCodec.EVENT:
			var e := NetCodec.decode_event(b)
			if not e.is_empty() and e["id"] == ((_in_ack + 1) & 0xFFFF):
				_in_ack = e["id"]
				_handle_event(e)
			if _udp:
				_send(NetCodec.ACK)


func _clock_sample(p: Dictionary) -> void:
	if p.is_empty():
		return
	var now := local_ms()
	var r := now - int(p["client_ms"])
	if r < 0 or r > 5000:
		return
	_clock.append({"rtt": r, "offset": float(p["server_ms"]) + r * 0.5 - now})
	if _clock.size() > CLOCK_SAMPLES:
		_clock.pop_front()
	var best: Dictionary = _clock[0]
	for c in _clock:
		if c["rtt"] < best["rtt"]:
			best = c
	rtt = best["rtt"] / 1000.0
	# never jump the clock by much at once (race_time follows it)
	var target: float = best["offset"]
	_offset_ms = target if absf(target - _offset_ms) > 500.0 else lerpf(_offset_ms, target, 0.3)


func _handle_event(e: Dictionary) -> void:
	match e["kind"]:
		NetCodec.EV_ROOM:
			print("[Net] room %s, waiting for an opponent" % e["code"])
			room_created.emit(e["code"])
		NetCodec.EV_TRACK:
			if e["part"] == 0:
				_track_in = []
			if e["part"] == _track_in.size():
				_track_in.append(e)
		NetCodec.EV_MATCH:
			if e["slot"] == 1 and TrackLibrary.is_custom(e["track"]):
				var id := _install_track()
				_track_in = []
				if id == "":
					push_warning("[Net] the shared track %s did not arrive" % e["track"])
					_event(NetCodec.EV_LEAVE)
					failed.emit(NetCodec.ERR_NO_TRACK)
					return
				print("[Net] shared track %s received (%s)" % [e["track"], TrackLibrary.display_name(id)])
				e["track"] = id
			slot = e["slot"]
			match_info = e
			print("[Net] match: slot %d vs %s on %s" % [slot, e["opp_name"], e["track"]])
			matched.emit(e)
		NetCodec.EV_LOBBY:
			players_online = e["online"]
			offers = e["offers"]
			lobby_changed.emit()
		NetCodec.EV_START:
			start_at.emit(e["drop_ms"] / 1000.0)
		NetCodec.EV_OPP:
			opponent_event.emit(e["what"], e["laps"], e["ms"] / 1000.0)
		NetCodec.EV_RESULT:
			result_received.emit(e["winner"], e["reason"])
		NetCodec.EV_ERROR:
			print("[Net] error %d" % e["code"])
			failed.emit(e["code"])

package main

// Server core: sessions, rooms, the reliable event layer and the referee.
// No sockets here: Handle() takes a received packet, Tick() runs resends and
// timeouts, and every outgoing packet goes through the send callback. One
// goroutine owns all of it (see main.go), so nothing is locked.

import (
	"log"
	"math/rand"
	"sort"
	"time"
)

const (
	SessionTimeout = 5 * time.Second
	ResendInterval = 100 * time.Millisecond
	DropDelayMs    = 3000
	MaxSessions    = 256
	MaxPerIP       = 4
	MaxQueue       = 64
	RatePerSecond  = 120 // packets per session and second
	MaxSpeed       = 150 // m/s, STATE above this is dropped
	MinLapMs       = 5000
	// LobbyInterval: the LOBBY list goes out at most this often.
	LobbyInterval = 500 * time.Millisecond
	// FinishSlackMs: a finisher wins once the other car's race clock is this
	// far past the finish time without a FINISH of its own.
	FinishSlackMs = 500
)

type outEvent struct {
	ev       Event
	lastSent time.Time
}

type Session struct {
	Token    uint32
	Addr     string
	IP       string
	Name     string
	Color    [3]byte
	lastSeen time.Time

	sendSeq   uint16
	nextOutID uint16
	out       []outEvent
	inAck     uint16 // last reliable event id handled in order

	watching bool // gets the LOBBY list

	// upload: the TRACK parts received so far, of uploadParts; the next
	// OFFER / JOIN (create) takes them along
	upload      [][]byte
	uploadParts int

	room     *Room
	slot     int
	ready    bool
	finished bool
	finishMs uint32
	wrecked  bool
	left     bool
	laps     int
	raceMs   uint32 // race clock of the latest STATE
	stateSeq uint16
	hasState bool

	rateWindow time.Time
	rateCount  int
}

func (s *Session) isOut() bool { return s.wrecked || s.left }

type Room struct {
	Code       string
	Quick      bool
	OfferID    uint16 // != 0: listed in the LOBBY while waiting
	Track      string
	Rules      byte
	TrackData  [][]byte // shared track of the first player (TRACK parts)
	Players    [2]*Session
	Started    bool // MATCH sent
	Racing     bool // START sent
	ResultSent bool
}

func (r *Room) full() bool { return r.Players[0] != nil && r.Players[1] != nil }

func (r *Room) other(s *Session) *Session {
	if r.Players[0] == s {
		return r.Players[1]
	}
	return r.Players[0]
}

type Server struct {
	start    time.Time
	sessions map[uint32]*Session
	byAddr   map[string]*Session
	rooms    map[string]*Room
	quick    *Room
	rng      *rand.Rand

	nextOffer  uint16
	lobbyDirty bool
	lobbySent  time.Time
	send       func(addr string, data []byte)
	Verbose    bool
}

func NewServer(start time.Time, seed int64, send func(addr string, data []byte)) *Server {
	return &Server{
		start:    start,
		sessions: map[uint32]*Session{},
		byAddr:   map[string]*Session{},
		rooms:    map[string]*Room{},
		rng:      rand.New(rand.NewSource(seed)),
		send:     send,
	}
}

func (sv *Server) logf(format string, args ...any) {
	if sv.Verbose {
		log.Printf(format, args...)
	}
}

func (sv *Server) ms(now time.Time) uint32 { return uint32(now.Sub(sv.start).Milliseconds()) }

// --- sending -----------------------------------------------------------------------

func (sv *Server) sendPkt(s *Session, typ byte, payload []byte) {
	s.sendSeq++
	sv.send(s.Addr, Packet(Header{Type: typ, Seq: s.sendSeq, Ack: s.inAck, Token: s.Token}, payload))
}

// queue sends a reliable event now and keeps it until acknowledged.
func (sv *Server) queue(s *Session, e Event, now time.Time) {
	s.nextOutID++
	e.ID = s.nextOutID
	s.out = append(s.out, outEvent{ev: e, lastSent: now})
	sv.sendPkt(s, PktEvent, EncodeEvent(e))
}

// --- receiving ---------------------------------------------------------------------

func ipOf(addr string) string {
	for i := len(addr) - 1; i >= 0; i-- {
		if addr[i] == ':' {
			return addr[:i]
		}
	}
	return addr
}

func (sv *Server) Handle(data []byte, addr string, now time.Time) {
	h, body, err := ParseHeader(data)
	if err != nil {
		return
	}
	if h.Type == PktHello {
		sv.hello(body, addr, now)
		return
	}
	s := sv.sessions[h.Token]
	if s == nil || h.Token == 0 {
		return
	}
	if s.Addr != addr {
		// NAT rebinding: the token proves the session, follow the new port
		delete(sv.byAddr, s.Addr)
		s.Addr = addr
		sv.byAddr[addr] = s
	}
	if now.Sub(s.rateWindow) >= time.Second {
		s.rateWindow = now
		s.rateCount = 0
	}
	s.rateCount++
	if s.rateCount > RatePerSecond {
		return
	}
	s.lastSeen = now
	// cumulative ack of our reliable events
	n := 0
	for _, o := range s.out {
		if o.ev.ID == h.Ack || SeqNewer(h.Ack, o.ev.ID) {
			n++
		} else {
			break
		}
	}
	s.out = s.out[n:]

	switch h.Type {
	case PktPing:
		r := Reader{B: body}
		cms := r.U32()
		if r.Err == nil {
			w := Writer{}
			w.U32(cms)
			w.U32(sv.ms(now))
			sv.sendPkt(s, PktPong, w.B)
		}
	case PktState:
		sv.state(s, h, body, now)
	case PktEvent:
		e, err := DecodeEvent(body)
		if err == nil && e.ID == s.inAck+1 {
			s.inAck = e.ID
			sv.event(s, e, now)
		}
		if sv.sessions[s.Token] != nil {
			sv.sendPkt(s, PktAck, nil)
		}
	case PktBye:
		sv.drop(s, now, "bye")
	}
}

func (sv *Server) hello(body []byte, addr string, now time.Time) {
	hl, err := DecodeHello(body)
	if err != nil {
		return
	}
	s := sv.byAddr[addr]
	if s == nil {
		ip := ipOf(addr)
		perIP := 0
		for _, o := range sv.sessions {
			if o.IP == ip {
				perIP++
			}
		}
		if len(sv.sessions) >= MaxSessions || perIP >= MaxPerIP {
			return
		}
		s = &Session{Addr: addr, IP: ip, slot: -1}
		for s.Token == 0 || sv.sessions[s.Token] != nil {
			s.Token = sv.rng.Uint32()
		}
		sv.sessions[s.Token] = s
		sv.byAddr[addr] = s
		sv.lobbyDirty = true
		sv.logf("hello %q from %s (token %08x)", hl.Name, addr, s.Token)
	}
	s.Name = hl.Name
	s.Color = hl.Color
	s.lastSeen = now
	w := Writer{}
	w.U32(s.Token)
	w.U32(sv.ms(now))
	sv.sendPkt(s, PktWelcome, w.B)
	if hl.Version != Version {
		sv.queue(s, Event{Kind: EvError, ErrNo: ErrVersion}, now)
	}
}

// state forwards a car state to the opponent (newest only, sane values only).
func (sv *Server) state(s *Session, h Header, body []byte, now time.Time) {
	st, err := DecodeState(body)
	if err != nil || s.room == nil || !s.room.Started {
		return
	}
	if s.hasState && !SeqNewer(h.Seq, s.stateSeq) {
		return
	}
	if st.Speed() > MaxSpeed {
		return
	}
	s.hasState = true
	s.stateSeq = h.Seq
	s.raceMs = uint32(st.T * 1000)
	if o := s.room.other(s); o != nil && !o.left {
		sv.sendPkt(o, PktState, body[:StateSize])
	}
	sv.checkResult(s.room, now)
}

func (sv *Server) event(s *Session, e Event, now time.Time) {
	r := s.room
	switch e.Kind {
	case EvJoin:
		if r == nil {
			sv.join(s, e, now)
		}
	case EvReady:
		if r != nil && r.Started && !s.ready {
			s.ready = true
			o := r.other(s)
			if o.ready && !r.Racing {
				r.Racing = true
				drop := sv.ms(now) + DropDelayMs
				for _, p := range r.Players {
					sv.queue(p, Event{Kind: EvStart, DropMs: drop}, now)
				}
				sv.logf("room %s: start, drop at %d", r.Code, drop)
			}
		}
	case EvLap:
		if r != nil && r.Racing && int(e.Laps) == s.laps+1 && e.Ms >= uint32(e.Laps)*MinLapMs {
			s.laps = int(e.Laps)
			sv.relay(s, EvLap, e.Laps, e.Ms, now)
		}
	case EvFinish:
		if r != nil && r.Racing && !s.finished && !s.isOut() && s.laps > 0 {
			s.finished = true
			s.finishMs = e.Ms
			sv.relay(s, EvFinish, byte(s.laps), e.Ms, now)
			sv.checkResult(r, now)
		}
	case EvWrecked:
		if r != nil && r.Racing && !s.finished && !s.isOut() {
			s.wrecked = true
			sv.relay(s, EvWrecked, byte(s.laps), s.raceMs, now)
			sv.checkResult(r, now)
		}
	case EvLeave:
		sv.leave(s, now)
	case EvWatch:
		s.watching = e.On
		if e.On {
			sv.sendLobby(s, now)
		}
	case EvOffer:
		if r != nil && r.Started {
			return
		}
		sv.leave(s, now) // an offer of its own before: replaced
		sv.offer(s, e, now)
	case EvTake:
		sv.take(s, e.OfferID, now)
	case EvTrack:
		sv.receiveTrack(s, e)
	}
}

func (sv *Server) relay(s *Session, what byte, laps byte, ms uint32, now time.Time) {
	if o := s.room.other(s); o != nil && !o.left {
		sv.queue(o, Event{Kind: EvOpp, What: what, Laps: laps, Ms: ms}, now)
	}
}

// --- rooms -------------------------------------------------------------------------

const codeLetters = "ABCDEFGHJKLMNPQRSTUVWXYZ" // no I/O: easy to tell from 1/0

func (sv *Server) newCode() string {
	for {
		b := make([]byte, 4)
		for i := range b {
			b[i] = codeLetters[sv.rng.Intn(len(codeLetters))]
		}
		if sv.rooms[string(b)] == nil {
			return string(b)
		}
	}
}

func (sv *Server) join(s *Session, e Event, now time.Time) {
	var r *Room
	switch e.Mode {
	case JoinQuick:
		if sv.quick != nil && sv.quick.Players[0] != nil {
			r = sv.quick
			sv.quick = nil
		}
	case JoinCode:
		r = sv.rooms[e.Code]
		if r == nil {
			sv.queue(s, Event{Kind: EvError, ErrNo: ErrRoomNotFound}, now)
			return
		}
		if r.full() {
			sv.queue(s, Event{Kind: EvError, ErrNo: ErrRoomFull}, now)
			return
		}
	}
	if r == nil {
		// create (also: first quick-match player waits in a fresh room)
		r = &Room{Code: sv.newCode(), Quick: e.Mode == JoinQuick, Track: e.Track, Rules: e.Rules, TrackData: s.takeUpload()}
		r.Players[0] = s
		sv.rooms[r.Code] = r
		if r.Quick {
			sv.quick = r
		}
		sv.attach(s, r, 0)
		sv.queue(s, Event{Kind: EvRoom, Code: r.Code}, now)
		sv.logf("room %s created by %q (track %s)", r.Code, s.Name, r.Track)
		return
	}
	sv.match(s, r, now)
}

// match makes s the second player of r and sends MATCH to both.
func (sv *Server) match(s *Session, r *Room, now time.Time) {
	r.Players[1] = s
	sv.attach(s, r, 1)
	r.Started = true
	if r.OfferID != 0 {
		sv.lobbyDirty = true
	}
	// the shared track first: the reliable events arrive in order
	for i, d := range r.TrackData {
		sv.queue(s, Event{Kind: EvTrack, Part: byte(i), Parts: byte(len(r.TrackData)), Data: d}, now)
	}
	for i, p := range r.Players {
		o := r.Players[1-i]
		sv.queue(p, Event{Kind: EvMatch, Slot: byte(i), Track: r.Track, Rules: r.Rules, OppName: o.Name, OppColor: o.Color}, now)
	}
	sv.logf("room %s: %q vs %q on %s", r.Code, r.Players[0].Name, r.Players[1].Name, r.Track)
}

// offer opens a room listed in the LOBBY; the first one to TAKE it races.
func (sv *Server) offer(s *Session, e Event, now time.Time) {
	sv.nextOffer++
	if sv.nextOffer == 0 {
		sv.nextOffer = 1
	}
	r := &Room{Code: sv.newCode(), Track: e.Track, Rules: e.Rules, OfferID: sv.nextOffer, TrackData: s.takeUpload()}
	r.Players[0] = s
	sv.rooms[r.Code] = r
	sv.attach(s, r, 0)
	sv.lobbyDirty = true
	sv.queue(s, Event{Kind: EvRoom, Code: r.Code}, now)
	sv.logf("offer %d by %q (track %s)", r.OfferID, s.Name, r.Track)
}

// receiveTrack collects the TRACK parts of a session (part 0 starts anew,
// anything out of line or too big drops the upload).
func (sv *Server) receiveTrack(s *Session, e Event) {
	if e.Part == 0 {
		s.upload, s.uploadParts = nil, int(e.Parts)
	}
	if int(e.Part) != len(s.upload) || int(e.Parts) != s.uploadParts || s.uploadParts > MaxTrackParts || len(e.Data) > MaxTrackPart {
		s.upload, s.uploadParts = nil, 0
		return
	}
	s.upload = append(s.upload, e.Data)
}

// takeUpload hands over a complete upload (nil if none) and clears it.
func (s *Session) takeUpload() [][]byte {
	d := s.upload
	if len(d) == 0 || len(d) != s.uploadParts {
		d = nil
	}
	s.upload, s.uploadParts = nil, 0
	return d
}

func (sv *Server) findOffer(id uint16) *Room {
	for _, r := range sv.rooms {
		if r.OfferID == id && !r.Started && r.Players[0] != nil && r.Players[0].room == r {
			return r
		}
	}
	return nil
}

// take accepts an open offer (an offer of its own is withdrawn first).
func (sv *Server) take(s *Session, id uint16, now time.Time) {
	if s.room != nil && s.room.Started {
		return
	}
	r := sv.findOffer(id)
	if r == nil || r.Players[0] == s {
		sv.queue(s, Event{Kind: EvError, ErrNo: ErrOfferGone}, now)
		return
	}
	sv.leave(s, now)
	sv.match(s, r, now)
}

// openOffers lists the waiting offers of the others, oldest first.
func (sv *Server) openOffers(except *Session) []Offer {
	var list []Offer
	for _, r := range sv.rooms {
		if r.OfferID != 0 && !r.Started && r.Players[0] != nil && r.Players[0].room == r && r.Players[0] != except {
			p := r.Players[0]
			list = append(list, Offer{ID: r.OfferID, Name: p.Name, Color: p.Color, Track: r.Track, Rules: r.Rules})
		}
	}
	sort.Slice(list, func(i, j int) bool { return SeqNewer(list[j].ID, list[i].ID) })
	return list
}

func (sv *Server) sendLobby(s *Session, now time.Time) {
	sv.queue(s, Event{Kind: EvLobby, Online: uint16(len(sv.sessions)), Offers: sv.openOffers(s)}, now)
}

func (sv *Server) attach(s *Session, r *Room, slot int) {
	s.room = r
	s.slot = slot
	s.ready, s.finished, s.wrecked, s.left, s.hasState = false, false, false, false, false
	s.laps, s.finishMs, s.raceMs = 0, 0, 0
}

// leave takes a player out of its room; the other one keeps racing.
func (sv *Server) leave(s *Session, now time.Time) {
	r := s.room
	if r == nil {
		return
	}
	if !s.left && r.Racing && !s.finished && !s.wrecked {
		s.left = true
		sv.relay(s, EvLeave, byte(s.laps), s.raceMs, now)
	}
	s.left = true
	s.room = nil
	if r.Racing {
		sv.checkResult(r, now)
	} else if o := r.other(s); o != nil && r.Started {
		// left before the start: the other one is told and the room closes
		sv.queue(o, Event{Kind: EvOpp, What: EvLeave}, now)
		o.room = nil
	}
	gone := true
	for _, p := range r.Players {
		if p != nil && p.room == r {
			gone = false
		}
	}
	if gone {
		delete(sv.rooms, r.Code)
		if r.OfferID != 0 && !r.Started {
			sv.lobbyDirty = true
		}
		if sv.quick == r {
			sv.quick = nil
		}
		sv.logf("room %s closed", r.Code)
	}
}

// checkResult sends RESULT once the order is clear: the lower FINISH time
// wins, a wrecked or departed car never wins.
func (sv *Server) checkResult(r *Room, now time.Time) {
	if r == nil || !r.Racing || r.ResultSent || !r.full() {
		return
	}
	a, b := r.Players[0], r.Players[1]
	winner, reason, done := NoWinner, ReasonFinished, false
	switch {
	case a.finished && b.finished:
		winner, done = 0, true
		if b.finishMs < a.finishMs {
			winner = 1
		}
	case a.finished || b.finished:
		f, o, fi := a, b, 0
		if b.finished {
			f, o, fi = b, a, 1
		}
		if o.isOut() || (o.hasState && o.raceMs > f.finishMs+FinishSlackMs) {
			winner, done = fi, true
			if o.wrecked {
				reason = ReasonOppWrecked
			} else if o.left {
				reason = ReasonOppLeft
			}
		}
	case a.isOut() && b.isOut():
		winner, reason, done = NoWinner, ReasonBothOut, true
	}
	if !done {
		return
	}
	r.ResultSent = true
	for _, p := range r.Players {
		if p.room == r && !p.left {
			sv.queue(p, Event{Kind: EvResult, Winner: byte(winner), Reason: byte(reason)}, now)
		}
	}
	sv.logf("room %s: result winner=%d reason=%d", r.Code, winner, reason)
}

// --- timers ------------------------------------------------------------------------

func (sv *Server) drop(s *Session, now time.Time, why string) {
	sv.leave(s, now)
	delete(sv.sessions, s.Token)
	delete(sv.byAddr, s.Addr)
	sv.lobbyDirty = true
	sv.logf("session %q dropped (%s)", s.Name, why)
}

// Tick resends unacknowledged events, drops silent sessions and sends the
// LOBBY list to its watchers when it changed.
func (sv *Server) Tick(now time.Time) {
	for _, s := range sv.sessions {
		if now.Sub(s.lastSeen) > SessionTimeout || len(s.out) > MaxQueue {
			sv.drop(s, now, "timeout")
			continue
		}
		for i := range s.out {
			if now.Sub(s.out[i].lastSent) >= ResendInterval {
				s.out[i].lastSent = now
				sv.sendPkt(s, PktEvent, EncodeEvent(s.out[i].ev))
			}
		}
	}
	if sv.lobbyDirty && now.Sub(sv.lobbySent) >= LobbyInterval {
		sv.lobbyDirty = false
		sv.lobbySent = now
		for _, s := range sv.sessions {
			if s.watching {
				sv.sendLobby(s, now)
			}
		}
	}
}

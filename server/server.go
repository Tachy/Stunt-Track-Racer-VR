package main

// Server core: sessions, rooms, the reliable event layer and the referee.
// No sockets here: Handle() takes a received packet, Tick() runs resends and
// timeouts, and every outgoing packet goes through the send callback. One
// goroutine owns all of it (see main.go), so nothing is locked.

import (
	"log"
	"math/rand"
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
	Track      string
	Super      bool
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
	send     func(addr string, data []byte)
	Verbose  bool
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
		r = &Room{Code: sv.newCode(), Quick: e.Mode == JoinQuick, Track: e.Track, Super: e.Super}
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
	r.Players[1] = s
	sv.attach(s, r, 1)
	r.Started = true
	for i, p := range r.Players {
		o := r.Players[1-i]
		sv.queue(p, Event{Kind: EvMatch, Slot: byte(i), Track: r.Track, Super: r.Super, OppName: o.Name, OppColor: o.Color}, now)
	}
	sv.logf("room %s: %q vs %q on %s", r.Code, r.Players[0].Name, r.Players[1].Name, r.Track)
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
	sv.logf("session %q dropped (%s)", s.Name, why)
}

// Tick resends unacknowledged events and drops silent sessions.
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
}

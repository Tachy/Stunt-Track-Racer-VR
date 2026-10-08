package main

import (
	"testing"
	"time"
)

// fakeClient plays one game client against the server core.
type fakeClient struct {
	addr   string
	token  uint32
	seq    uint16
	outID  uint16
	inAck  uint16
	events []Event
	states int
}

type harness struct {
	sv      *Server
	now     time.Time
	clients map[string]*fakeClient
}

func newHarness(t *testing.T) *harness {
	h := &harness{now: time.Unix(1000, 0), clients: map[string]*fakeClient{}}
	h.sv = NewServer(h.now, 1, func(addr string, data []byte) {
		c := h.clients[addr]
		hd, body, err := ParseHeader(data)
		if c == nil || err != nil {
			t.Fatalf("bad packet to %s", addr)
		}
		switch hd.Type {
		case PktWelcome:
			r := Reader{B: body}
			c.token = r.U32()
		case PktEvent:
			e, err := DecodeEvent(body)
			if err != nil {
				t.Fatal(err)
			}
			if e.ID == c.inAck+1 {
				c.inAck = e.ID
				c.events = append(c.events, e)
			}
		case PktState:
			c.states++
		}
	})
	return h
}

func (h *harness) client(addr, name string) *fakeClient {
	c := &fakeClient{addr: addr}
	h.clients[addr] = c
	h.send(c, PktHello, EncodeHello(Hello{Version: Version, Name: name}))
	if c.token == 0 {
		panic("no welcome")
	}
	return c
}

func (h *harness) send(c *fakeClient, typ byte, payload []byte) {
	c.seq++
	h.sv.Handle(Packet(Header{Type: typ, Seq: c.seq, Ack: c.inAck, Token: c.token}, payload), c.addr, h.now)
}

func (h *harness) event(c *fakeClient, e Event) {
	c.outID++
	e.ID = c.outID
	h.send(c, PktEvent, EncodeEvent(e))
}

func (h *harness) state(c *fakeClient, raceS float64) {
	s := goldenState()
	s.T = raceS
	h.send(c, PktState, EncodeState(s))
}

func (c *fakeClient) last(kind byte) *Event {
	for i := len(c.events) - 1; i >= 0; i-- {
		if c.events[i].Kind == kind {
			return &c.events[i]
		}
	}
	return nil
}

func startRace(t *testing.T, h *harness) (*fakeClient, *fakeClient) {
	a := h.client("1.1.1.1:5000", "Ann")
	b := h.client("2.2.2.2:6000", "Bob")
	h.event(a, Event{Kind: EvJoin, Mode: JoinCreate, Track: "camel_back"})
	room := a.last(EvRoom)
	if room == nil || len(room.Code) != 4 {
		t.Fatalf("no room: %+v", a.events)
	}
	h.event(b, Event{Kind: EvJoin, Mode: JoinCode, Code: room.Code, Track: "ignored"})
	ma, mb := a.last(EvMatch), b.last(EvMatch)
	if ma == nil || mb == nil || ma.Slot != 0 || mb.Slot != 1 || mb.Track != "camel_back" || ma.OppName != "Bob" || mb.OppName != "Ann" {
		t.Fatalf("match: %+v / %+v", ma, mb)
	}
	h.event(a, Event{Kind: EvReady})
	if a.last(EvStart) != nil {
		t.Fatal("start before both ready")
	}
	h.event(b, Event{Kind: EvReady})
	sa, sb := a.last(EvStart), b.last(EvStart)
	if sa == nil || sb == nil || sa.DropMs != DropDelayMs || sb.DropMs != sa.DropMs {
		t.Fatalf("start: %+v %+v", sa, sb)
	}
	return a, b
}

func TestRaceFinishOrder(t *testing.T) {
	h := newHarness(t)
	a, b := startRace(t, h)
	h.state(a, 1.0)
	if b.states != 1 {
		t.Fatalf("state not relayed")
	}
	h.state(a, 0.5)
	// an older sequence number is dropped
	a.seq -= 2
	h.state(a, 0.4)
	if b.states != 2 {
		t.Fatalf("stale state relayed: %d", b.states)
	}
	a.seq += 2
	for lap := byte(1); lap <= 3; lap++ {
		h.event(a, Event{Kind: EvLap, Laps: lap, Ms: uint32(lap) * 30000})
		h.event(b, Event{Kind: EvLap, Laps: lap, Ms: uint32(lap) * 31000})
	}
	if o := b.last(EvOpp); o == nil || o.What != EvLap || o.Laps != 3 {
		t.Fatalf("lap relay: %+v", o)
	}
	h.event(b, Event{Kind: EvFinish, Ms: 93000, BestMs: 31000})
	if a.last(EvResult) != nil {
		t.Fatal("result before the order is clear")
	}
	h.event(a, Event{Kind: EvFinish, Ms: 90000, BestMs: 30000})
	ra, rb := a.last(EvResult), b.last(EvResult)
	if ra == nil || rb == nil || ra.Winner != 0 || rb.Winner != 0 || ra.Reason != ReasonFinished {
		t.Fatalf("result: %+v %+v", ra, rb)
	}
}

func TestFinisherWinsWhenOtherClockPasses(t *testing.T) {
	h := newHarness(t)
	a, b := startRace(t, h)
	h.event(a, Event{Kind: EvLap, Laps: 1, Ms: 30000})
	h.event(a, Event{Kind: EvFinish, Ms: 90000})
	h.state(b, 90.2)
	if a.last(EvResult) != nil {
		t.Fatal("decided inside the slack")
	}
	h.state(b, 90.6)
	if r := a.last(EvResult); r == nil || r.Winner != 0 {
		t.Fatalf("result: %+v", r)
	}
}

func TestWreckAndTimeout(t *testing.T) {
	h := newHarness(t)
	a, b := startRace(t, h)
	h.event(a, Event{Kind: EvWrecked})
	if o := b.last(EvOpp); o == nil || o.What != EvWrecked {
		t.Fatalf("wreck relay: %+v", o)
	}
	if b.last(EvResult) != nil {
		t.Fatal("a wrecked car alone decides nothing: the other must finish")
	}
	// b goes silent: both out -> no winner (a still gets it)
	for i := 0; i < 3; i++ {
		h.now = h.now.Add(2 * time.Second)
		h.send(a, PktAck, nil)
		h.sv.Tick(h.now)
	}
	if r := a.last(EvResult); r == nil || r.Winner != NoWinner || r.Reason != ReasonBothOut {
		t.Fatalf("result: %+v", r)
	}
	if len(h.sv.sessions) != 1 {
		t.Fatalf("silent session kept: %d", len(h.sv.sessions))
	}
}

func TestResendUntilAcked(t *testing.T) {
	h := newHarness(t)
	a := h.client("1.1.1.1:5000", "Ann")
	h.event(a, Event{Kind: EvJoin, Mode: JoinQuick, Track: "first_flight"})
	if len(h.sv.byAddr[a.addr].out) != 1 {
		t.Fatal("ROOM not queued")
	}
	h.now = h.now.Add(150 * time.Millisecond)
	h.sv.Tick(h.now)
	h.send(a, PktAck, nil) // a.inAck = 1 now
	if n := len(h.sv.byAddr[a.addr].out); n != 0 {
		t.Fatalf("acked event still queued: %d", n)
	}
	// quick match pairs the next player
	b := h.client("2.2.2.2:6000", "Bob")
	h.event(b, Event{Kind: EvJoin, Mode: JoinQuick, Track: "other"})
	if m := b.last(EvMatch); m == nil || m.Track != "first_flight" {
		t.Fatalf("quick match: %+v", m)
	}
}

func TestJoinErrors(t *testing.T) {
	h := newHarness(t)
	startRace(t, h)
	c := h.client("3.3.3.3:7000", "Cat")
	h.event(c, Event{Kind: EvJoin, Mode: JoinCode, Code: "ZZZZ"})
	if e := c.last(EvError); e == nil || e.ErrNo != ErrRoomNotFound {
		t.Fatalf("not found: %+v", e)
	}
	var code string
	for k := range h.sv.rooms {
		code = k
	}
	h.event(c, Event{Kind: EvJoin, Mode: JoinCode, Code: code})
	if e := c.last(EvError); e == nil || e.ErrNo != ErrRoomFull {
		t.Fatalf("full: %+v", c.events)
	}
}

func lobbyTick(h *harness) {
	h.now = h.now.Add(LobbyInterval)
	h.sv.Tick(h.now)
}

func TestLobbyOfferTake(t *testing.T) {
	h := newHarness(t)
	a := h.client("1.1.1.1:5000", "Ann")
	b := h.client("2.2.2.2:6000", "Bob")
	h.event(b, Event{Kind: EvWatch, On: true})
	if l := b.last(EvLobby); l == nil || l.Online != 2 || len(l.Offers) != 0 {
		t.Fatalf("first lobby: %+v", l)
	}
	h.event(a, Event{Kind: EvOffer, Track: "camel_back", Super: true})
	lobbyTick(h)
	l := b.last(EvLobby)
	if l == nil || len(l.Offers) != 1 || l.Offers[0].Name != "Ann" || l.Offers[0].Track != "camel_back" || !l.Offers[0].Super {
		t.Fatalf("offer not listed: %+v", l)
	}
	if a.last(EvLobby) != nil {
		t.Fatal("lobby sent to a non-watcher")
	}
	h.event(a, Event{Kind: EvWatch, On: true})
	if l := a.last(EvLobby); l == nil || len(l.Offers) != 0 {
		t.Fatalf("own offer listed: %+v", l)
	}
	// own offer: not to be taken
	h.event(a, Event{Kind: EvTake, OfferID: l.Offers[0].ID})
	if e := a.last(EvError); e == nil || e.ErrNo != ErrOfferGone {
		t.Fatalf("own offer taken: %+v", a.events)
	}
	h.event(b, Event{Kind: EvTake, OfferID: l.Offers[0].ID})
	ma, mb := a.last(EvMatch), b.last(EvMatch)
	if ma == nil || mb == nil || ma.Slot != 0 || mb.Slot != 1 || mb.Track != "camel_back" || !mb.Super || mb.OppName != "Ann" {
		t.Fatalf("match: %+v / %+v", ma, mb)
	}
	lobbyTick(h)
	if l := b.last(EvLobby); len(l.Offers) != 0 {
		t.Fatalf("taken offer still listed: %+v", l)
	}
	// a third one comes too late
	c := h.client("3.3.3.3:7000", "Cat")
	h.event(c, Event{Kind: EvTake, OfferID: l.Offers[0].ID})
	if e := c.last(EvError); e == nil || e.ErrNo != ErrOfferGone {
		t.Fatalf("late take: %+v", c.events)
	}
}

func TestLobbyOfferGone(t *testing.T) {
	h := newHarness(t)
	a := h.client("1.1.1.1:5000", "Ann")
	b := h.client("2.2.2.2:6000", "Bob")
	h.event(b, Event{Kind: EvWatch, On: true})
	h.event(a, Event{Kind: EvOffer, Track: "camel_back"})
	h.event(a, Event{Kind: EvOffer, Track: "big_dipper"}) // replaces the first
	lobbyTick(h)
	if l := b.last(EvLobby); len(l.Offers) != 1 || l.Offers[0].Track != "big_dipper" {
		t.Fatalf("replaced offer: %+v", l)
	}
	h.event(a, Event{Kind: EvLeave})
	lobbyTick(h)
	if l := b.last(EvLobby); len(l.Offers) != 0 {
		t.Fatalf("withdrawn offer listed: %+v", l)
	}
	// an offer of a player gone silent disappears too
	h.event(a, Event{Kind: EvOffer, Track: "camel_back"})
	for i := 0; i < 3; i++ {
		h.now = h.now.Add(2 * time.Second)
		h.send(b, PktAck, nil)
		h.sv.Tick(h.now)
	}
	if l := b.last(EvLobby); len(l.Offers) != 0 || l.Online != 1 {
		t.Fatalf("offer of a silent player: %+v", l)
	}
	// b offers while watching, then takes a newer offer of c instead
	h.event(b, Event{Kind: EvOffer, Track: "little_ramp"})
	c := h.client("3.3.3.3:7000", "Cat")
	h.event(c, Event{Kind: EvOffer, Track: "big_dipper"})
	lobbyTick(h)
	l := b.last(EvLobby)
	if len(l.Offers) != 1 || l.Offers[0].Name != "Cat" {
		t.Fatalf("own offer listed: %+v", l)
	}
	d := h.client("4.4.4.4:8000", "Dan")
	h.event(d, Event{Kind: EvWatch, On: true})
	if l := d.last(EvLobby); len(l.Offers) != 2 || l.Offers[0].Name != "Bob" || l.Offers[1].Name != "Cat" {
		t.Fatalf("order: %+v", l)
	}
	h.event(b, Event{Kind: EvTake, OfferID: l.Offers[0].ID})
	if m := b.last(EvMatch); m == nil || m.Track != "big_dipper" {
		t.Fatalf("take while offering: %+v", m)
	}
	lobbyTick(h)
	if l := b.last(EvLobby); len(l.Offers) != 0 {
		t.Fatalf("both offers should be gone: %+v", l)
	}
}

// A shared track goes with the offer to the one who takes it, before MATCH.
func TestSharedTrack(t *testing.T) {
	h := newHarness(t)
	a := h.client("1.1.1.1:5000", "Ann")
	b := h.client("2.2.2.2:6000", "Bob")
	parts := [][]byte{[]byte("first part"), []byte("second")}
	for i, p := range parts {
		h.event(a, Event{Kind: EvTrack, Part: byte(i), Parts: 2, Data: p})
	}
	h.event(a, Event{Kind: EvOffer, Track: "custom/my_track"})
	h.event(b, Event{Kind: EvWatch, On: true})
	l := b.last(EvLobby)
	if l == nil || len(l.Offers) != 1 || l.Offers[0].Track != "custom/my_track" {
		t.Fatalf("offer: %+v", l)
	}
	h.event(b, Event{Kind: EvTake, OfferID: l.Offers[0].ID})
	var got [][]byte
	matched := false
	for _, e := range b.events {
		switch e.Kind {
		case EvTrack:
			if matched || int(e.Part) != len(got) || e.Parts != 2 {
				t.Fatalf("track part out of order: %+v", e)
			}
			got = append(got, e.Data)
		case EvMatch:
			matched = true
		}
	}
	if !matched || len(got) != 2 || string(got[0]) != "first part" || string(got[1]) != "second" {
		t.Fatalf("shared track: %q matched=%v", got, matched)
	}
	for _, e := range a.events {
		if e.Kind == EvTrack {
			t.Fatal("track sent back to its owner")
		}
	}
	// the upload went with that offer: a new offer without TRACK has none
	c := h.client("3.3.3.3:7000", "Cat")
	h.event(a, Event{Kind: EvLeave})
	h.event(a, Event{Kind: EvOffer, Track: "camel_back"})
	lobbyTick(h)
	h.event(c, Event{Kind: EvWatch, On: true})
	h.event(c, Event{Kind: EvTake, OfferID: c.last(EvLobby).Offers[0].ID})
	if c.last(EvTrack) != nil || c.last(EvMatch) == nil {
		t.Fatalf("built-in track: %+v", c.events)
	}
}

// Incomplete or oversized uploads are dropped.
func TestSharedTrackRejected(t *testing.T) {
	h := newHarness(t)
	a := h.client("1.1.1.1:5000", "Ann")
	b := h.client("2.2.2.2:6000", "Bob")
	h.event(a, Event{Kind: EvTrack, Part: 0, Parts: 2, Data: []byte("only one")})
	h.event(a, Event{Kind: EvOffer, Track: "custom/x"})
	h.event(b, Event{Kind: EvWatch, On: true})
	h.event(b, Event{Kind: EvTake, OfferID: b.last(EvLobby).Offers[0].ID})
	if b.last(EvTrack) != nil || b.last(EvMatch) == nil {
		t.Fatalf("incomplete upload sent: %+v", b.events)
	}
	s := h.sv.sessions[a.token]
	h.event(a, Event{Kind: EvTrack, Part: 0, Parts: 1, Data: make([]byte, MaxTrackPart+1)})
	if s.upload != nil {
		t.Fatal("oversized part kept")
	}
	h.event(a, Event{Kind: EvTrack, Part: 0, Parts: MaxTrackParts + 1, Data: []byte("x")})
	if s.upload != nil {
		t.Fatal("too many parts kept")
	}
}

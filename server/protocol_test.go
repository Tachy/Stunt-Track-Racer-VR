package main

import (
	"encoding/hex"
	"flag"
	"math"
	"os"
	"reflect"
	"strings"
	"testing"
)

var update = flag.Bool("update", false, "rewrite testdata/*.hex")

// The golden messages; tests/run_tests.gd builds the same ones in GDScript.
func goldenState() CarState {
	return CarState{
		T: 12.345, Pos: [3]float64{123.456, -7.89, 1000.001},
		Rot: [4]float64{0.1, -0.9, 0.3, 0.3},
		Vel: [3]float64{12.344, -3.21, 45.678}, AngVel: [3]float64{0.1234, -2.3456, 11.0},
		Steer: -0.3, Throttle: 0.8, Brake: 0.12,
		Boosting: true, Held: true, State: 1, Boost: 7, Crack: 0.4, Holes: 2,
	}
}

func goldenOffers() []Offer {
	return []Offer{
		{ID: 513, Name: "Max", Color: [3]byte{34, 102, 221}, Track: "camel_back"},
		{ID: 7, Name: "Jöhn", Color: [3]byte{255, 128, 0}, Track: "big_dipper", Super: true},
	}
}

func goldenPackets() map[string][]byte {
	return map[string][]byte{
		"state": Packet(Header{Type: PktState, Seq: 65535, Ack: 2, Token: 0xDEADBEEF}, EncodeState(goldenState())),
		"hello": Packet(Header{Type: PktHello, Seq: 1}, EncodeHello(Hello{Version: Version, Color: [3]byte{255, 128, 0}, Name: "Jöhn"})),
		"join": Packet(Header{Type: PktEvent, Seq: 7, Ack: 0, Token: 42},
			EncodeEvent(Event{ID: 1, Kind: EvJoin, Mode: JoinCreate, Code: "abcd", Track: "camel_back", Super: true})),
		"match": Packet(Header{Type: PktEvent, Seq: 9, Ack: 4, Token: 42},
			EncodeEvent(Event{ID: 3, Kind: EvMatch, Slot: 1, Track: "camel_back", OppName: "Max", OppColor: [3]byte{34, 102, 221}})),
		"lobby": Packet(Header{Type: PktEvent, Seq: 11, Ack: 2, Token: 42},
			EncodeEvent(Event{ID: 5, Kind: EvLobby, Online: 300, Offers: goldenOffers()})),
		"offer": Packet(Header{Type: PktEvent, Seq: 12, Ack: 5, Token: 42},
			EncodeEvent(Event{ID: 2, Kind: EvOffer, Track: "big_dipper", Super: true})),
		"take": Packet(Header{Type: PktEvent, Seq: 13, Ack: 5, Token: 42},
			EncodeEvent(Event{ID: 3, Kind: EvTake, OfferID: 513})),
		"track": Packet(Header{Type: PktEvent, Seq: 14, Ack: 5, Token: 42},
			EncodeEvent(Event{ID: 4, Kind: EvTrack, Part: 1, Parts: 3, Data: []byte{0x78, 0x9c, 0x01, 0xff}})),
	}
}

func TestGolden(t *testing.T) {
	for name, pkt := range goldenPackets() {
		file := "testdata/" + name + ".hex"
		if *update {
			os.MkdirAll("testdata", 0o755)
			if err := os.WriteFile(file, []byte(hex.EncodeToString(pkt)+"\n"), 0o644); err != nil {
				t.Fatal(err)
			}
			continue
		}
		want, err := os.ReadFile(file)
		if err != nil {
			t.Fatal(err)
		}
		if got := hex.EncodeToString(pkt); got != strings.TrimSpace(string(want)) {
			t.Errorf("%s:\n got %s\nwant %s", name, got, strings.TrimSpace(string(want)))
		}
	}
}

func TestStateRoundTrip(t *testing.T) {
	s := goldenState()
	enc := EncodeState(s)
	if len(enc) != StateSize {
		t.Fatalf("state size %d", len(enc))
	}
	d, err := DecodeState(enc)
	if err != nil {
		t.Fatal(err)
	}
	for k := 0; k < 3; k++ {
		if math.Abs(d.Pos[k]-s.Pos[k]) > 0.0006 || math.Abs(d.Vel[k]-s.Vel[k]) > 0.006 || math.Abs(d.AngVel[k]-s.AngVel[k]) > 0.0006 {
			t.Errorf("axis %d: %+v", k, d)
		}
	}
	// q and -q are the same rotation
	dot := 0.0
	for i := range s.Rot {
		dot += s.Rot[i] * d.Rot[i]
	}
	if math.Abs(dot) < 0.99999 {
		t.Errorf("rotation %v vs %v (dot %f)", d.Rot, s.Rot, dot)
	}
	if !d.Boosting || d.Reverse || !d.Held || d.State != 1 || d.Boost != 7 || d.Holes != 2 {
		t.Errorf("flags %+v", d)
	}
}

func TestQuatPrecision(t *testing.T) {
	worst := 0.0
	for i := 0; i < 2000; i++ {
		a := float64(i) * 0.37
		qt := [4]float64{math.Sin(a) * 0.3, math.Cos(a*1.3) * 0.6, math.Sin(a*0.7) * 0.5, math.Cos(a) * 0.4}
		n := math.Sqrt(qt[0]*qt[0] + qt[1]*qt[1] + qt[2]*qt[2] + qt[3]*qt[3])
		for k := range qt {
			qt[k] /= n
		}
		d := UnpackQuat(PackQuat(qt))
		dot := 0.0
		for k := range qt {
			dot += qt[k] * d[k]
		}
		ang := 2 * math.Acos(math.Min(1, math.Abs(dot))) * 180 / math.Pi
		worst = math.Max(worst, ang)
	}
	if worst > 0.25 {
		t.Errorf("worst rotation error %.3f deg", worst)
	}
}

func TestEventRoundTrip(t *testing.T) {
	for _, e := range []Event{
		{ID: 1, Kind: EvJoin, Mode: JoinCode, Code: "XKCD", Track: "big_dipper"},
		{ID: 2, Kind: EvStart, DropMs: 123456},
		{ID: 3, Kind: EvFinish, Ms: 99000, BestMs: 31000},
		{ID: 4, Kind: EvOpp, What: EvLap, Laps: 2, Ms: 64000},
		{ID: 5, Kind: EvResult, Winner: 1, Reason: ReasonOppWrecked},
		{ID: 6, Kind: EvWatch, On: true},
		{ID: 7, Kind: EvLobby, Online: 3, Offers: goldenOffers()},
		{ID: 8, Kind: EvOffer, Track: "little_ramp", Super: true},
		{ID: 9, Kind: EvTake, OfferID: 65535},
		{ID: 10, Kind: EvTrack, Part: 2, Parts: 5, Data: []byte("hello")},
		{ID: 11, Kind: EvTrack, Part: 0, Parts: 1, Data: []byte{}},
	} {
		d, err := DecodeEvent(EncodeEvent(e))
		if err != nil || !reflect.DeepEqual(d, e) {
			t.Errorf("%+v -> %+v (%v)", e, d, err)
		}
	}
	if _, err := DecodeEvent([]byte{1}); err == nil {
		t.Error("short event accepted")
	}
}

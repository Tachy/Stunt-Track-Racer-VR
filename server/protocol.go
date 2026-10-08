package main

// Binary encoding of the online protocol (docs/net-protocol.md). Mirrors
// scripts/net/net_codec.gd; both are checked against testdata/*.hex.

import (
	"encoding/binary"
	"errors"
	"math"
	"strings"
)

const (
	Magic      = 0xB1
	Version    = 2
	MaxOffers  = 20 // entries in one LOBBY
	HeaderSize = 10
	StateSize  = 36
	MaxStr     = 32
	// A shared track goes in TRACK events of at most MaxTrackPart bytes,
	// at most MaxTrackParts of them.
	MaxTrackPart  = 1000
	MaxTrackParts = 16
)

// packet types
const (
	PktHello   = 1
	PktWelcome = 2
	PktPing    = 3
	PktPong    = 4
	PktState   = 5
	PktEvent   = 6
	PktAck     = 7
	PktBye     = 8
)

// reliable events
const (
	EvJoin    = 1
	EvRoom    = 2
	EvMatch   = 3
	EvReady   = 4
	EvStart   = 5
	EvLap     = 6
	EvFinish  = 7
	EvWrecked = 8
	EvLeave   = 9
	EvOpp     = 10
	EvResult  = 11
	EvError   = 12
	EvWatch   = 13
	EvLobby   = 14
	EvOffer   = 15
	EvTake    = 16
	EvTrack   = 17
)

const (
	JoinQuick  = 0
	JoinCreate = 1
	JoinCode   = 2
)

const (
	ErrRoomNotFound = 1
	ErrRoomFull     = 2
	ErrVersion      = 3
	ErrOfferGone    = 4
)

const (
	ReasonFinished   = 0
	ReasonOppWrecked = 1
	ReasonOppLeft    = 2
	ReasonBothOut    = 3
	NoWinner         = 255
)

var errShort = errors.New("short packet")

type Header struct {
	Type  byte
	Seq   uint16
	Ack   uint16
	Token uint32
}

// Writer appends little-endian values to a byte slice.
type Writer struct{ B []byte }

func (w *Writer) U8(v byte)    { w.B = append(w.B, v) }
func (w *Writer) U16(v uint16) { w.B = binary.LittleEndian.AppendUint16(w.B, v) }
func (w *Writer) U32(v uint32) { w.B = binary.LittleEndian.AppendUint32(w.B, v) }
func (w *Writer) I8(v int8)    { w.U8(byte(v)) }
func (w *Writer) I16(v int16)  { w.U16(uint16(v)) }
func (w *Writer) I24(v int32) {
	if v < -0x800000 {
		v = -0x800000
	} else if v > 0x7FFFFF {
		v = 0x7FFFFF
	}
	u := uint32(v) & 0xFFFFFF
	w.B = append(w.B, byte(u), byte(u>>8), byte(u>>16))
}
func (w *Writer) Str(s string) {
	for len(s) > MaxStr {
		r := []rune(s)
		s = string(r[:len(r)-1])
	}
	w.U8(byte(len(s)))
	w.B = append(w.B, s...)
}
func (w *Writer) Code(code string) {
	c := strings.ToUpper(code) + "    "
	w.B = append(w.B, c[:4]...)
}
func (w *Writer) Color(c [3]byte) { w.B = append(w.B, c[0], c[1], c[2]) }

// Reader reads little-endian values; Err is set once data runs out.
type Reader struct {
	B   []byte
	Err error
}

func (r *Reader) take(n int) []byte {
	if r.Err != nil || len(r.B) < n {
		r.Err = errShort
		return make([]byte, n)
	}
	v := r.B[:n]
	r.B = r.B[n:]
	return v
}
func (r *Reader) U8() byte    { return r.take(1)[0] }
func (r *Reader) U16() uint16 { return binary.LittleEndian.Uint16(r.take(2)) }
func (r *Reader) U32() uint32 { return binary.LittleEndian.Uint32(r.take(4)) }
func (r *Reader) I8() int8    { return int8(r.U8()) }
func (r *Reader) I16() int16  { return int16(r.U16()) }
func (r *Reader) I24() int32 {
	b := r.take(3)
	v := int32(b[0]) | int32(b[1])<<8 | int32(b[2])<<16
	if v&0x800000 != 0 {
		v -= 0x1000000
	}
	return v
}
func (r *Reader) Str() string {
	n := int(r.U8())
	return string(r.take(n))
}
func (r *Reader) Code() string   { return strings.TrimSpace(string(r.take(4))) }
func (r *Reader) Color() [3]byte { b := r.take(3); return [3]byte{b[0], b[1], b[2]} }

func Packet(h Header, payload []byte) []byte {
	w := Writer{B: make([]byte, 0, HeaderSize+len(payload))}
	w.U8(Magic)
	w.U8(h.Type)
	w.U16(h.Seq)
	w.U16(h.Ack)
	w.U32(h.Token)
	w.B = append(w.B, payload...)
	return w.B
}

func ParseHeader(data []byte) (Header, []byte, error) {
	if len(data) < HeaderSize || data[0] != Magic {
		return Header{}, nil, errShort
	}
	r := Reader{B: data[1:]}
	h := Header{Type: r.U8(), Seq: r.U16(), Ack: r.U16(), Token: r.U32()}
	return h, r.B, nil
}

// SeqNewer reports whether a is newer than b with 16-bit wrap-around.
func SeqNewer(a, b uint16) bool {
	d := a - b
	return d != 0 && d < 0x8000
}

// --- car state -----------------------------------------------------------------------

type CarState struct {
	T        float64 // race time, s
	Pos      [3]float64
	Rot      [4]float64 // x, y, z, w
	Vel      [3]float64
	AngVel   [3]float64
	Steer    float64
	Throttle float64
	Brake    float64
	Boosting bool
	Reverse  bool
	Held     bool
	Airborne bool
	State    byte // 0 hold .. 5 wrecked
	Boost    byte
	Crack    float64
	Holes    byte
}

func clampI(v, lo, hi int64) int64 {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}

func q(v, scale float64, lo, hi int64) int64 { return clampI(int64(math.Round(v*scale)), lo, hi) }

// PackQuat stores a rotation as "smallest three".
func PackQuat(qt [4]float64) uint32 {
	n := math.Sqrt(qt[0]*qt[0] + qt[1]*qt[1] + qt[2]*qt[2] + qt[3]*qt[3])
	if n > 0 {
		for i := range qt {
			qt[i] /= n
		}
	}
	big := 0
	for i := 1; i < 4; i++ {
		if math.Abs(qt[i]) > math.Abs(qt[big]) {
			big = i
		}
	}
	sgn := 1.0
	if qt[big] < 0 {
		sgn = -1
	}
	bits := uint32(big) << 30
	shift := 20
	for i := 0; i < 4; i++ {
		if i == big {
			continue
		}
		v := clampI(int64(math.Round((qt[i]*sgn*math.Sqrt2+1)*0.5*1023)), 0, 1023)
		bits |= uint32(v) << shift
		shift -= 10
	}
	return bits
}

func UnpackQuat(bits uint32) [4]float64 {
	big := int(bits>>30) & 3
	var c [4]float64
	shift := 20
	sum := 0.0
	for i := 0; i < 4; i++ {
		if i == big {
			continue
		}
		v := float64((bits>>shift)&1023)/1023*2 - 1
		c[i] = v / math.Sqrt2
		sum += c[i] * c[i]
		shift -= 10
	}
	c[big] = math.Sqrt(math.Max(0, 1-sum))
	return c
}

func EncodeState(s CarState) []byte {
	w := Writer{B: make([]byte, 0, StateSize)}
	w.U32(uint32(q(s.T, 1000, 0, math.MaxUint32)))
	for k := 0; k < 3; k++ {
		w.I24(int32(q(s.Pos[k], 1000, -0x800000, 0x7FFFFF)))
	}
	w.U32(PackQuat(s.Rot))
	for k := 0; k < 3; k++ {
		w.I16(int16(q(s.Vel[k], 100, -32768, 32767)))
	}
	for k := 0; k < 3; k++ {
		w.I16(int16(q(s.AngVel[k], 1000, -32768, 32767)))
	}
	w.I8(int8(q(s.Steer, 127, -127, 127)))
	w.U8(byte(q(s.Throttle, 255, 0, 255)))
	w.U8(byte(q(s.Brake, 255, 0, 255)))
	var flags byte
	if s.Boosting {
		flags |= 1
	}
	if s.Reverse {
		flags |= 2
	}
	if s.Held {
		flags |= 4
	}
	if s.Airborne {
		flags |= 8
	}
	flags |= (s.State & 7) << 4
	w.U8(flags)
	w.U8(s.Boost)
	w.U8(byte(q(s.Crack, 255, 0, 255)))
	w.U8(s.Holes)
	return w.B
}

func DecodeState(p []byte) (CarState, error) {
	if len(p) < StateSize {
		return CarState{}, errShort
	}
	r := Reader{B: p}
	var s CarState
	s.T = float64(r.U32()) / 1000
	for k := 0; k < 3; k++ {
		s.Pos[k] = float64(r.I24()) / 1000
	}
	s.Rot = UnpackQuat(r.U32())
	for k := 0; k < 3; k++ {
		s.Vel[k] = float64(r.I16()) / 100
	}
	for k := 0; k < 3; k++ {
		s.AngVel[k] = float64(r.I16()) / 1000
	}
	s.Steer = float64(r.I8()) / 127
	s.Throttle = float64(r.U8()) / 255
	s.Brake = float64(r.U8()) / 255
	flags := r.U8()
	s.Boosting = flags&1 != 0
	s.Reverse = flags&2 != 0
	s.Held = flags&4 != 0
	s.Airborne = flags&8 != 0
	s.State = (flags >> 4) & 7
	s.Boost = r.U8()
	s.Crack = float64(r.U8()) / 255
	s.Holes = r.U8()
	return s, r.Err
}

func (s CarState) Speed() float64 {
	return math.Sqrt(s.Vel[0]*s.Vel[0] + s.Vel[1]*s.Vel[1] + s.Vel[2]*s.Vel[2])
}

// --- messages --------------------------------------------------------------------------

type Hello struct {
	Version byte
	Color   [3]byte
	Name    string
}

func EncodeHello(h Hello) []byte {
	w := Writer{}
	w.U8(h.Version)
	w.Color(h.Color)
	w.Str(h.Name)
	return w.B
}

func DecodeHello(p []byte) (Hello, error) {
	r := Reader{B: p}
	h := Hello{Version: r.U8(), Color: r.Color(), Name: r.Str()}
	return h, r.Err
}

// Offer is one open race in the LOBBY list.
type Offer struct {
	ID    uint16
	Name  string
	Color [3]byte
	Track string
	Super bool
}

// Event is one reliable message: id, kind and its fields (only those of the kind).
type Event struct {
	ID   uint16
	Kind byte
	// JOIN
	Mode  byte
	Code  string
	Track string
	Super bool
	// MATCH
	Slot     byte
	OppName  string
	OppColor [3]byte
	// START
	DropMs uint32
	// LAP / FINISH / OPP
	Laps   byte
	Ms     uint32
	BestMs uint32
	What   byte
	// RESULT / ERROR
	Winner byte
	Reason byte
	ErrNo  byte
	// WATCH / LOBBY / TAKE
	On      bool
	Online  uint16
	Offers  []Offer
	OfferID uint16
	// TRACK
	Part  byte
	Parts byte
	Data  []byte
}

func b2u(b bool) byte {
	if b {
		return 1
	}
	return 0
}

func EncodeEvent(e Event) []byte {
	w := Writer{}
	w.U16(e.ID)
	w.U8(e.Kind)
	switch e.Kind {
	case EvJoin:
		w.U8(e.Mode)
		w.Code(e.Code)
		w.Str(e.Track)
		w.U8(b2u(e.Super))
	case EvRoom:
		w.Code(e.Code)
	case EvMatch:
		w.U8(e.Slot)
		w.Str(e.Track)
		w.U8(b2u(e.Super))
		w.Str(e.OppName)
		w.Color(e.OppColor)
	case EvStart:
		w.U32(e.DropMs)
	case EvLap:
		w.U8(e.Laps)
		w.U32(e.Ms)
	case EvFinish:
		w.U32(e.Ms)
		w.U32(e.BestMs)
	case EvOpp:
		w.U8(e.What)
		w.U8(e.Laps)
		w.U32(e.Ms)
	case EvResult:
		w.U8(e.Winner)
		w.U8(e.Reason)
	case EvError:
		w.U8(e.ErrNo)
	case EvWatch:
		w.U8(b2u(e.On))
	case EvLobby:
		w.U16(e.Online)
		n := min(len(e.Offers), MaxOffers)
		w.U8(byte(n))
		for _, o := range e.Offers[:n] {
			w.U16(o.ID)
			w.Str(o.Name)
			w.Color(o.Color)
			w.Str(o.Track)
			w.U8(b2u(o.Super))
		}
	case EvOffer:
		w.Str(e.Track)
		w.U8(b2u(e.Super))
	case EvTake:
		w.U16(e.OfferID)
	case EvTrack:
		w.U8(e.Part)
		w.U8(e.Parts)
		w.U16(uint16(len(e.Data)))
		w.B = append(w.B, e.Data...)
	}
	return w.B
}

func DecodeEvent(p []byte) (Event, error) {
	r := Reader{B: p}
	e := Event{ID: r.U16(), Kind: r.U8()}
	switch e.Kind {
	case EvJoin:
		e.Mode = r.U8()
		e.Code = r.Code()
		e.Track = r.Str()
		e.Super = r.U8() != 0
	case EvRoom:
		e.Code = r.Code()
	case EvMatch:
		e.Slot = r.U8()
		e.Track = r.Str()
		e.Super = r.U8() != 0
		e.OppName = r.Str()
		e.OppColor = r.Color()
	case EvStart:
		e.DropMs = r.U32()
	case EvLap:
		e.Laps = r.U8()
		e.Ms = r.U32()
	case EvFinish:
		e.Ms = r.U32()
		e.BestMs = r.U32()
	case EvOpp:
		e.What = r.U8()
		e.Laps = r.U8()
		e.Ms = r.U32()
	case EvResult:
		e.Winner = r.U8()
		e.Reason = r.U8()
	case EvError:
		e.ErrNo = r.U8()
	case EvWatch:
		e.On = r.U8() != 0
	case EvLobby:
		e.Online = r.U16()
		n := int(r.U8())
		for i := 0; i < n && r.Err == nil; i++ {
			e.Offers = append(e.Offers, Offer{ID: r.U16(), Name: r.Str(), Color: r.Color(), Track: r.Str(), Super: r.U8() != 0})
		}
	case EvOffer:
		e.Track = r.Str()
		e.Super = r.U8() != 0
	case EvTake:
		e.OfferID = r.U16()
	case EvTrack:
		e.Part = r.U8()
		e.Parts = r.U8()
		e.Data = append([]byte{}, r.take(int(r.U16()))...)
	}
	return e, r.Err
}

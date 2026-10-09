# Network protocol (online 1 vs 1)

UDP, little endian. Server: `server/` (Go). Client codec: `scripts/net/net_codec.gd`.
Both sides are checked against the golden vectors in `server/testdata/`.

## Model
Every client simulates its own car and sends its state 30 times per second.
The server forwards it to the opponent and referees the race (rooms, start
time, laps, finish order, timeouts). It runs no physics.

## Packet header (10 bytes)

| offset | type | field |
|---|---|---|
| 0 | u8  | `magic` = 0xB1 (header format; the protocol version is in HELLO) |
| 1 | u8  | `type` |
| 2 | u16 | `seq`: packet counter of the sender (drops stale STATE packets) |
| 4 | u16 | `ack`: highest reliable event id received in order from the peer |
| 6 | u32 | `token`: session token (0 in HELLO) |

## Packet types

| type | name | dir | payload |
|---|---|---|---|
| 1 | HELLO | C→S | u8 version (3), u8 r, u8 g, u8 b, str name |
| 2 | WELCOME | S→C | u32 token, u32 server_ms |
| 3 | PING | C→S | u32 client_ms |
| 4 | PONG | S→C | u32 client_ms, u32 server_ms |
| 5 | STATE | both | car state (below); S→C is the opponent's |
| 6 | EVENT | both | u16 event_id, u8 event type, data (reliable) |
| 7 | ACK | both | empty: only the header `ack` |
| 8 | BYE | C→S | empty: leave the server |

`str` = u8 length + UTF-8 bytes (max 32). Times are milliseconds; the
server clock (`server_ms`) counts from server start.

### Reliable events
Event ids start at 1 per direction and session. The receiver handles only the
next expected id, acknowledges with the header `ack` (cumulative) and answers
every EVENT packet with an ACK. The sender resends all unacknowledged events
every 100 ms.

| event | name | dir | data |
|---|---|---|---|
| 1 | JOIN | C→S | u8 mode (0 quick, 1 create, 2 join), 4 bytes room code, str track, u8 rules |
| 2 | ROOM | S→C | 4 bytes room code (waiting for an opponent) |
| 3 | MATCH | S→C | u8 slot (0/1), str track, u8 rules, str opponent name, u8 r, g, b |
| 4 | READY | C→S | empty: track built, cars on the crane |
| 5 | START | S→C | u32 drop time in server ms |
| 6 | LAP | C→S | u8 laps done, u32 race ms |
| 7 | FINISH | C→S | u32 race ms, u32 best lap ms |
| 8 | WRECKED | C→S | empty |
| 9 | LEAVE | C→S | empty: retire / back to the menu |
| 10 | OPP | S→C | u8 kind (6 lap, 7 finish, 8 wrecked, 9 left), u8 laps, u32 ms |
| 11 | RESULT | S→C | u8 winner slot (255 = none), u8 reason |
| 12 | ERROR | S→C | u8 code (1 room not found, 2 room full, 3 version, 4 offer gone) |
| 13 | WATCH | C→S | u8 on: 1 = send me the LOBBY list, 0 = stop |
| 14 | LOBBY | S→C | u16 players online, u8 n (≤ 20), n × {u16 offer id, str name, u8 r, g, b, str track, u8 rules} |
| 15 | OFFER | C→S | str track, u8 rules: an open race in the list (replaces an own one) |
| 16 | TAKE | C→S | u16 offer id: race that open race |
| 17 | TRACK | both | u8 part, u8 parts (≤ 16), u16 n (≤ 1000), n bytes: part of a shared track |

`rules` (set by whoever offers or creates the race, passed on as it comes): bit 0 super league, bit 1 flight pitch assist off.

RESULT reasons: 0 finished first, 1 opponent wrecked, 2 opponent left /
timed out, 3 both out.

### Shared tracks
A track from the editor (id `custom/<name>`) goes along with the race: the
client sends its name and definition (compact JSON, deflated with zlib) as
TRACK parts right before the OFFER or JOIN (create / quick) that names it.
The server keeps the parts with that room without reading them and sends
them to the second player right before MATCH. That client keeps the track
in memory for this race only (never saved). Parts out of line, more than 16
parts or parts over 1000 bytes drop the upload; an offer without a complete
upload has no track along.

## STATE payload (36 bytes)

| offset | type | field | scale |
|---|---|---|---|
| 0 | u32 | race time | ms since the drop (0 before) |
| 4 | 3 × i24 | position x, y, z | 1 mm (±8.3 km) |
| 13 | u32 | rotation | smallest three, see below |
| 17 | 3 × i16 | linear velocity | 1 cm/s |
| 23 | 3 × i16 | angular velocity | 1 mrad/s |
| 29 | i8 | steering | road-wheel angle / 45° × 127 |
| 30 | u8 | throttle | × 255 |
| 31 | u8 | brake | × 255 |
| 32 | u8 | flags | bit0 boosting, bit1 reverse, bit2 held (crane), bit3 airborne, bits 4–6 race state |
| 33 | u8 | boost units | |
| 34 | u8 | crack | × 255 |
| 35 | u8 | holes | |

Race state: 0 hold, 1 racing, 2 falling, 3 craned, 4 finished, 5 wrecked.

Rotation, smallest three: the component with the largest magnitude is
dropped (its index in bits 30–31) and made positive by negating the whole
quaternion. The other three, in x-y-z-w order, lie in ±1/√2 and are stored as
10 bits each, `round((c / (1/√2) + 1) / 2 × 1023)`, in bits 20–29, 10–19, 0–9.

With the IP/UDP headers a STATE packet is 74 bytes: about 2.2 KB/s per
direction at 30 Hz.

## Room flow
1. HELLO → WELCOME (resent every 0.5 s until answered).
2. The menu sends WATCH and gets LOBBY: the open races of the others, oldest
   first, sent again when the list or the player count changes (at most
   twice a second). OFFER puts an own open race in the list (ROOM answers);
   TAKE races one of the list: both get MATCH with the track and league of
   the offer. A TAKE on an offer no longer there gets ERROR 4. An offer goes
   when it is taken, on LEAVE, or when its player leaves or times out.
   Without the list: JOIN. Quick match pairs two waiting quick-match
   players; create returns ROOM with a 4-letter code; join with that code.
3. Both build the race and send READY. The server sends START with a drop
   time 3 s ahead.
4. STATE flows both ways. LAP / FINISH / WRECKED / LEAVE go to the server,
   which relays them as OPP to the other player.
5. RESULT when the order is clear: the lower FINISH time wins; a wrecked or
   departed player loses. A player silent for 5 s counts as departed.

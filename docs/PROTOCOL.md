# Vader 5 Pro configuration protocol, as OpenVader uses it

This is a working summary for people extending OpenVader. It restates facts published by
flydigi-vader-pro-5-ctl, OpenFlydigi, SDL and others (see the README's credits) in the form the code uses
them. Offsets are decimal unless written in hex.

## Device

| | |
|---|---|
| USB | `37D7:2401` (receiver and cable alike) |
| Configuration interface | HID, usage page `0xFFA0`, usage 1, **no report IDs** |
| Marker interfaces | `0xFFEF` present when cabled, `0xFFEE` on the 2.4 GHz receiver |
| Device type (heartbeat byte 5) | 130 Vader 5 Pro, 144 and 145 special editions |

On macOS, `IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, frame, 32)` sends a frame exactly as
below. (The Windows SDK puts `0x06` in front, and Linux needs `0x00` there; macOS takes neither.)

## Frames

Request, padded to 32 bytes:

```
[0] 5A  [1] A5  [2] command  [3] length = 2 + payload.count  [4…] payload
[2 + length] checksum = sum(bytes[2 ..< 2 + length]) & 0xFF
```

Reply, 32 bytes:

```
[0] 5A  [1] A5  [2] command  [3] total packets  [4] packet index  [5…] payload  [31] sum(bytes[2..<31])
```

A frame with a bad checksum is ignored silently, so time out and retry; there is no NAK.

## Commands used

| Id | Name | Payload | Notes |
|---|---|---|---|
| `01` | heartbeat | — | type, connection, MAC, battery, chips, 7 firmware versions (BCD nibbles at 15, 17, 19, 21, 23, 25, 27) |
| `02` | nickname | — | |
| `03` | hardware status | — | 5/6 feature supported/enabled bits 1–8, 7/8 bits 9–10, 9 sleep minutes, 10 report rate, 11 stick precision, 12 stick sensitivity |
| `04` | UID | — | 13 bytes from 5 |
| `10` | data report status | — | 5 controller, 6 raw stream, 7 keyboard, 8 mouse, 9 third-party takeover, 10…29 holder name |
| `11` | set data report | 5 flags | `FF` keeps a flag unchanged |
| `12` | rumble | gripL gripR trigL trigR | no reply |
| `13` | feature toggle | sub, on | sub = feature number (1 quick swap … 7 rebound) |
| `17` | sleep time | minutes | 0 = never |
| `A1` | profile versions | — | 5 active (4–7 = Switch mode), 6… four u16 tags (`FFFF` = factory) |
| `A2` | activate | profile | read back with `A1`; it can ACK without switching |
| `A3`/`A7`/`AC` | read mapping / lighting / macros | profile, 20 | N replies, payload at 6; **selects the profile** |
| `A4`/`A8`/`AD` | write start | profile, 0, packets, 20 | |
| `A5`/`A9`/`AE` | write packet | index, 20 bytes | each ACKed |
| `A6` | save | tag lo, tag hi | commits **the running profile**; 10 s timeout |
| `AB` | save to Switch bank | irregular vendor frame | `5A A5 AB 04 tagLo tagHi (4+profile) sum(AB 04 tagLo tagHi)` |
| `EF` | live input | — | streamed at ~500 Hz while the raw stream is on |

Never sent: `1F` (bootloader), `AF` (resets all four profiles despite taking a slot), `FD` (factory reset),
`FE` (identity write). `HIDConnection.write` refuses them.

### Write sequence

1. Activate the target profile (`A2`, verify with `A1`).
2. Upload whatever changed (`A4`+`A5`, `AD`+`AE`, `A8`+`A9`).
3. `A6` with a fresh random tag if the mapping changed (also stamped into the blob at 225), otherwise with
   the profile's current tag.
4. Re-activate if macros changed (stored macros load when a profile is applied).
5. Read everything back and compare.

## Mapping blob (840 bytes, layout 3.2 = `02 03`)

| Offset | Size | Field |
|---|---|---|
| 0 | 2 | layout version, minor then major |
| 13 | 96 | key table: 32 × `[target, turbo mode, turbo rate]`, indexed by key id |
| 109 | 14 | stick curve source: 2 × `[type, dead zone, p1x, p1y, p2x, p2y, end]` (0…127 points) |
| 123 | 14 | trigger travel: 2 × `[type, start, s, s, e, e, end]` (0…255) |
| 137 | 8 | gyro: `[target, key, hold?, dead zone, sens, sens, mode, second key]` |
| 145 | 9 | grip rumble: master (0 on, FF off), 2 × `[on, min, max, gain]` |
| 154 | 29 | trigger rumble: master (0 on, 1 off), 2 × (2 × 7-byte gears) |
| 225 | 2 | revision tag |
| 770 | 20 | name, UTF-16LE, 10 units |
| 790 | 24 | stick table: 2 × `[type, 9 × output+50, circular, outer dead zone]` |

Key ids: 0 up, 1 right, 2 down, 3 left, 4 A, 5 B, 6 View, 7 X, 8 Y, 9 Menu, 10 LB, 11 RB, 12 LT, 13 RT,
14 L3, 15 R3, 16 C, 17 Z, 18–21 M1–M4, 22 LM, 23 RM, 24 Fn, 25 Turbo, 27 Home. Targets: `FF` default,
`20` macro, `FE` Windows keyboard/mouse binding.

**The controller plays the nine-point stick table at 790, not the curve fields at 109.** OpenVader writes
both and compiles the table from the curve (`StickCurveCompiler`, ported from OpenFlydigi): nodes at
`(deadZone, 0)`, the two points remapped into the remaining span, and `(100 − outer, 100)`; sampled at 0,
12.5 … 100 %, truncated, clamped to −50…100 and biased by 50. Linear gives `50 62 75 87 100 112 125 137 150`.

A factory Vader 5 Pro ships with a 5 % dead zone and the table `45 58 71 84 97 110 123 137 150`, which
Flydigi rounded slightly differently (two points differ by one), so OpenVader only recompiles a stick's
table when that stick's curve is edited.

## Lighting blob (320 bytes)

Header of 20 bytes: `[0, 3, clickFeedback, loopStart, loopEnd, frameTime, brightness, ledCount, effect,
rumbleSync, FF × 10]`, then frames × LEDs × RGB. The Vader 5 Pro reports 10 LEDs and 10 frames (the Apex 5 has 12); read
the geometry from the blob rather than assuming it.

The controller has no effect generator. It cycles frames `loopStart…loopEnd`, and the effect byte is only
a label. OpenVader generates the frames: steady = frame 0; breathing = colour, dark, colour, dark…;
colour cycle = one frame per colour; flow = a hue wheel shifted per frame. Keep `clickFeedback` at 0: it
latches the displayed frame.

## Macro store (1660 bytes)

```
[0..1] version  [2..3] count (≤ 10)  [4..23] 10 × u16 offsets in 4-byte words from 24
record: key, steps (u16), playback (1 once, 2 while held, 3 toggle), repeat ms (u16), FF × 6,
        name (20 bytes UTF-8), then steps of [time ms (u16, from macro start), key, 1 press / 0 release]
```

The mapping key table must also point the trigger key at `20` (macro).

## Live input (`EF`)

```
3–10  LX LY RX RY  int16 LE, centre 0, +Y up
11    Up Right Down Left A B View X
12    Y Menu LB RB LT RT L3 R3
13    C Z M1 M2 M3 M4 LM RM
14    Fn 0x01, Turbo 0x02, Home 0x08
15 16 LT RT  0…255
17–22 gyro  int16, 2000 °/s full scale
23–28 accel int16, 4096 = 1 g
```

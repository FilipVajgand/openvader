# Vader 5 Pro over Bluetooth: what a capture shows

Captured on 2026-10-16 with Android's Bluetooth HCI snoop log (Samsung Galaxy S23+, Android 16, Flydigi Game
Center 7.2.10.5). The controller had firmware 7.1.5.0 and its mode switch in the middle (Bluetooth). The app
connected in **Flashplay** mode, the only mode it offers this controller on Android, and showed only a test
page. No settings were changed, so this documents the transport and a few read commands, not configuration.

## GATT layout

| Handles | Service | Notes |
|---|---|---|
| `0x0001–0x0007` | `0x1800` Generic Access | |
| `0x0008–0x000B` | `0x1801` Generic Attribute | |
| `0x000C–0x0010` | `0x180A` Device Information | |
| `0x0011–0x0021` | `0x1812` HID | in Flashplay mode a **touchscreen**, not a gamepad (see below); input reports notify on `0x0017` |
| `0x0022–0x0029` | `6e400001-b5a3-f393-e0a9-e50e24dcca9e` | **Nordic UART Service**: write to `0x0024` (`6e400002`, write without response), notifications on `0x0027` (`6e400003`) |
| `0x002A–0x002E` | `00010203-0405-0607-0809-0a0b0c0d1912` | **Telink OTA service** (characteristic `…2b12` on `0x002C`): the radio chip's firmware update |
| `0x002F–0x0032` | `0x180F` Battery | |

## The vendor pipe (Nordic UART)

Frames are not the `5A A5` frames of the USB configuration interface. They look like Flydigi's older protocol:
a command byte first, and on 20-byte frames an additive checksum in the last byte (sum of bytes 0–18, mod
256). Acknowledgements are `AA CC <status> <checksum of the command>`.

| Sent | Answer | Meaning |
|---|---|---|
| `BA C0 00 00` | `AC C0 11 22 33 44 FF FF 05 00 00 01 00 82 69 00 35 18 FD 10` | device info: `82` = device type 130 (Vader 5 Pro), `35 18` = SI chip 3.5.1.8 |
| `A5 A0 00 00` | `A5 A0` + 13 bytes + checksum | the controller UID, the same 13 bytes command `0x04` returns over USB |
| `41 00 …00 41` | `AA CC 00 41` | unknown; sent after connecting |
| `41 01 …00 42` | `AA CC 00 42` | sent when the test page opened; the input stream below started right after it and `55` |
| `55 00 01 00 FF×15 47` | `AA CC FF 47` | unknown; status `FF` |
| `40 00 …00 40` | `AA CC 00 40` | unknown; the stream kept running after it |

The stream is 20-byte notifications about 45 times a second. Bytes 0–3 are the two sticks as unsigned bytes
centred on `0x81` (left X, left Y, right X, right Y); bytes 11–13 change with motion; byte 18 is `FE`.

## Flashplay is a touchscreen

The HID report map (196 bytes, read with Read Blob) describes a Digitizer / Touch Screen with three fingers:
tip switch, in range, contact ID and 12-bit X/Y each, plus contact count and maximum. There is no gamepad
collection. In Flashplay mode the controller taps the phone's screen at positions the Flydigi app maps, so
games that read a gamepad see nothing. For those games the controller must be in native Bluetooth mode, where
the manual says it pairs as "Xbox Wireless Controller"; the light is blue in native mode and cyan in Flashplay.

## What it means for OpenVader

- macOS could reach this pipe while the controller stays connected: CoreBluetooth's
  `retrieveConnectedPeripherals(withServices:)` returns system-connected peripherals by service UUID. The
  capture is of Flashplay mode only, so whether native mode also offers the Nordic UART service is unknown;
  reading the device info and UID from a Mac is a cheap experiment that would answer it.
- Whether profiles can be read or written over this pipe is unknown. The Android app never configures this
  controller, so a capture of a configuring client (for example Space Station on Windows over Bluetooth, if it
  supports that) would be needed.
- The Telink OTA service means the radio firmware can in principle be updated over Bluetooth. OpenVader does
  not flash firmware.

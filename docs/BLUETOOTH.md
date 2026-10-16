# Vader 5 Pro over Bluetooth: what captures show

Captured with Android's Bluetooth HCI snoop log (Samsung Galaxy S23+, Android 16) with the controller on
firmware 7.1.5.0 and its mode switch in the middle (Bluetooth). With the switch there, the controller has two
modes that look nothing alike to the phone:

| Mode | Light while pairing | Bluetooth | The phone sees |
|---|---|---|---|
| **Flashplay** | cyan | Bluetooth LE | a three-finger touchscreen, plus Flydigi's vendor services |
| **Native** | orange on this unit (the manual says blue) | classic Bluetooth (BR/EDR) | "Xbox Wireless Controller", an Xbox One S gamepad |

The controller remembers its mode. On this unit **Turbo + D-pad Right**, pressed while the light flashed cyan,
switched it from Flashplay to native. A retailer's guide gives Fn + D-pad Right for native and Fn + D-pad Up
for Flashplay; those are not checked here.

## Native mode: an Xbox One S controller

Captured on 2026-10-17 after pairing from Android's Bluetooth settings. The controller answers SDP as:

- Device ID record: vendor `0x045E` (Microsoft), product `0x02E0`, version `0x0903`: the Xbox One S
  controller (model 1708) on its original Bluetooth firmware.
- HID record: service name "Xbox Bluetooth Gamepad", description "Gamepad", provider "Microsoft Corporation".
- HID descriptor (306 bytes), the standard one for that controller:
  - report 1 (input): sticks X/Y/Rx/Ry as 16-bit values centred on `0x8000`, triggers Z/Rz as 10-bit values,
    a hat switch for the D-pad and 10 buttons;
  - report 2 (input): the Xbox button;
  - report 3 (output): rumble, with an enable bit per motor and four magnitudes (left, right, left trigger,
    right trigger), duration, delay and loop count;
  - report 4 (input): battery strength.

The extra buttons (M1–M4, C, Z, LM, RM) are not in the report. In native mode they only work when they are
mapped to standard buttons. Input report 1 arrived about 55 times a second over five minutes, with no gap
longer than 100 ms. Android sent `GET_REPORT` for report 4 (battery) three times, and the controller answered
each with handshake `0x02` (invalid report ID). The phone made no Bluetooth LE connection in native mode, so
the Flydigi services below were not reachable from it.

## Flashplay mode: Bluetooth LE

Captured on 2026-10-16 with Flydigi Game Center 7.2.10.5, which connected in Flashplay mode (the only mode it
offers this controller on Android) and showed only a test page. No settings were changed, so this documents
the transport and a few read commands, not configuration.

### GATT layout

| Handles | Service | Notes |
|---|---|---|
| `0x0001–0x0007` | `0x1800` Generic Access | |
| `0x0008–0x000B` | `0x1801` Generic Attribute | |
| `0x000C–0x0010` | `0x180A` Device Information | |
| `0x0011–0x0021` | `0x1812` HID | a **touchscreen**, not a gamepad (see below); input reports notify on `0x0017` |
| `0x0022–0x0029` | `6e400001-b5a3-f393-e0a9-e50e24dcca9e` | **Nordic UART Service**: write to `0x0024` (`6e400002`, write without response), notifications on `0x0027` (`6e400003`) |
| `0x002A–0x002E` | `00010203-0405-0607-0809-0a0b0c0d1912` | **Telink OTA service** (characteristic `…2b12` on `0x002C`): the radio chip's firmware update |
| `0x002F–0x0032` | `0x180F` Battery | |

### The touchscreen

The HID report map (196 bytes, read with Read Blob) describes a Digitizer / Touch Screen with three fingers:
tip switch, in range, contact ID and 12-bit X/Y each, plus contact count and maximum. There is no gamepad
collection. The controller taps the phone's screen at positions the Flydigi app maps, so games that read a
gamepad see nothing. Games with controller support need native mode.

### The vendor pipe (Nordic UART)

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

## What it means for OpenVader

- Configuring over Bluetooth would go through the Nordic UART pipe, which was only seen in Flashplay mode.
  macOS could reach it with CoreBluetooth; `retrieveConnectedPeripherals(withServices:)` also returns
  peripherals the system already holds. Reading the device info and UID from a Mac is a cheap first
  experiment.
- Whether profiles can be read or written over this pipe is unknown. The Android app never configures this
  controller, so a capture of a configuring client (for example Space Station on Windows over Bluetooth, if it
  supports that) would be needed.
- In native mode a Mac would see an Xbox One S controller (`045E:02E0`). That is untested here.
- The Telink OTA service means the radio firmware can in principle be updated over Bluetooth. OpenVader does
  not flash firmware.

import Testing
@testable import VaderKit

@Suite struct StickCurveTests {
    @Test func linearBankMatchesFactory() {
        let bank = StickCurveCompiler.bank(deadZone: 0, outerDeadZone: 0,
                                           point1: CurvePoint(x: 63, y: 63), point2: CurvePoint(x: 127, y: 127))
        #expect(bank == [50, 62, 75, 87, 100, 112, 125, 137, 150])
    }

    @Test func fullDeadZoneIsSilentUntilTheEnd() {
        let bank = StickCurveCompiler.bank(deadZone: 100, outerDeadZone: 0,
                                           point1: CurvePoint(x: 63, y: 63), point2: CurvePoint(x: 127, y: 127))
        #expect(bank.dropLast().allSatisfy { $0 == 50 })
        #expect(bank.last == 150)
    }

    @Test func banksStayInRangeAndRiseMonotonically() {
        for dz in stride(from: 0, through: 60, by: 5) {
            for preset in StickSettings.Curve.allCases {
                guard let (p1, p2) = preset.points else { continue }
                let bank = StickCurveCompiler.bank(deadZone: dz, outerDeadZone: 10, point1: p1, point2: p2)
                #expect(bank.count == 9)
                #expect(bank.allSatisfy { $0 <= 150 })
                #expect(zip(bank, bank.dropFirst()).allSatisfy { $0 <= $1 })
            }
        }
    }

    @Test func instantRisesFasterThanDelayed() {
        let instant = StickCurveCompiler.bank(deadZone: 0, outerDeadZone: 0, point1: .init(x: 64, y: 96), point2: .init(x: 127, y: 127))
        let delayed = StickCurveCompiler.bank(deadZone: 0, outerDeadZone: 0, point1: .init(x: 64, y: 32), point2: .init(x: 127, y: 127))
        #expect(instant[2] > delayed[2])
    }
}

@Suite struct MacroTests {
    @Test func emptyStoreParses() {
        let store = MacroStore(bytes: [UInt8](repeating: 0xFF, count: 1660))
        #expect(store.macros.isEmpty)
        #expect(store.size == 1660)
    }

    @Test func roundTrip() throws {
        var store = MacroStore(size: 1660)
        store.macros = [
            Macro(trigger: .m1, playback: .once, name: "Jump shot", steps: Macro.tap([.a, .x], hold: 50, gap: 30)),
            Macro(trigger: .rm, playback: .whileHeld, repeatInterval: 120, steps: Macro.tap([.rt])),
        ]
        let bytes = try store.encoded()
        #expect(bytes.count == 1660)
        let back = MacroStore(bytes: bytes)
        #expect(back.macros.count == 2)
        #expect(back.macros[0].name == "Jump shot")
        #expect(back.macros[0].steps.map(\.key) == [.a, .a, .x, .x])
        #expect(back.macros[0].steps.map(\.event) == [.press, .release, .press, .release])
        #expect(back.macros[0].steps.dropLast().map(\.delay) == [50, 30, 50])
        #expect(back.macros[1].playback == .whileHeld && back.macros[1].repeatInterval == 120)
        // Second record sits right after the first: 4 steps + 8 header words.
        #expect(bytes[6] == 12 && bytes[7] == 0)
    }

    @Test func firstStepFiresImmediately() throws {
        let store = MacroStore(macros: [Macro(trigger: .m2, steps: Macro.tap([.b], hold: 80))])
        let bytes = try store.encoded()
        let firstStep = 24 + 32
        #expect(bytes[firstStep] == 0 && bytes[firstStep + 1] == 0)
        #expect(bytes[firstStep + 4] == 80)
    }

    @Test func tooManyMacrosIsRefused() {
        let store = MacroStore(macros: (0..<11).map { _ in Macro(trigger: .m1, steps: Macro.tap([.a])) })
        #expect(throws: VaderError.self) { try store.encoded() }
    }
}

@Suite struct LightingTests {
    func blank(leds: Int = 12, frames: Int = 10) -> LightingConfig {
        var b = [UInt8](repeating: 0, count: LightingConfig.headerSize + leds * frames * 3)
        b[0] = 0; b[1] = 3; b[4] = 9; b[5] = 4; b[6] = 20; b[7] = UInt8(leds); b[8] = 7; b[9] = 1
        for i in 10..<20 { b[i] = 0xFF }
        return LightingConfig(bytes: b)
    }

    @Test func geometryComesFromTheBlob() {
        let l = blank()
        #expect(l.isValid && l.ledCount == 12 && l.frameCount == 10 && l.bytes.count == 380)
        #expect(blank(leds: 8, frames: 10).frameCount == 10)
    }

    @Test func steadyFillsFrameZeroOnly() {
        var l = blank()
        let red = LEDColor(red: 255, green: 0, blue: 0)
        l.apply(.steady, colors: [red])
        #expect(l.effect == .steady && l.loopEnd == 0)
        #expect((0..<12).allSatisfy { l.color(frame: 0, led: $0) == red })
        #expect((1..<10).allSatisfy { f in (0..<12).allSatisfy { l.color(frame: f, led: $0).isBlack } })
        #expect(l.bytes.count == 380)
        #expect(l.bytes[2] == 0)
        #expect(l.gripSync, "header bytes outside the effect are preserved")
    }

    @Test func breathingAlternatesWithDark() {
        var l = blank()
        let a = LEDColor(red: 0, green: 0, blue: 255), b = LEDColor(red: 0, green: 255, blue: 0)
        l.apply(.breathing, colors: [a, b])
        #expect(l.loopEnd == 3)
        #expect(l.color(frame: 0, led: 5) == a && l.color(frame: 1, led: 5).isBlack && l.color(frame: 2, led: 5) == b)
    }

    @Test func gradientUsesOneFramePerColor() {
        var l = blank()
        let colors = [LEDColor(red: 255, green: 0, blue: 0), LEDColor(red: 0, green: 255, blue: 0), LEDColor(red: 0, green: 0, blue: 255)]
        l.apply(.gradient, colors: colors)
        #expect(l.loopEnd == 2)
        #expect(l.paletteGuess == colors)
    }

    @Test func flowFillsEveryFrame() {
        var l = blank()
        l.apply(.flow, colors: [])
        #expect(l.loopEnd == 9)
        #expect((0..<10).allSatisfy { !l.color(frame: $0, led: 0).isBlack })
        #expect(l.color(frame: 0, led: 0) != l.color(frame: 0, led: 6))
    }

    @Test func hexParsing() {
        #expect(LEDColor(hex: "#0078FF") == LEDColor(red: 0, green: 0x78, blue: 0xFF))
        #expect(LEDColor(hex: "12345") == nil)
    }
}

@Suite struct InputStateTests {
    @Test func decodesButtonsSticksAndTriggers() {
        var r = [UInt8](repeating: 0, count: 32)
        r[0] = 0x5A; r[1] = 0xA5; r[2] = 0xEF
        r[3] = 0xFF; r[4] = 0x7F  // LX = +32767
        r[9] = 0x00; r[10] = 0x80  // RY = -32768
        r[11] = 0x10  // A
        r[13] = 0x04 | 0x40  // M1, LM
        r[14] = 0x08  // Home
        r[15] = 255
        r[17] = 0x00; r[18] = 0x40  // gyro x = 16384 → 1000 dps
        r[23] = 0x00; r[24] = 0x10  // accel x = 4096 → 1 g
        let s = InputState(report: r)!
        #expect(s.buttons == [.a, .m1, .lm, .home])
        #expect(abs(s.leftStick.x - 1) < 0.001)
        #expect(s.rightStick.y < -1)
        #expect(s.leftTrigger == 1 && s.rightTrigger == 0)
        #expect(abs(s.gyro.x - 1000) < 0.1)
        #expect(abs(s.accel.x - 1) < 0.001)
        #expect(s.unknownBits.isEmpty)
    }

    @Test func rejectsOtherReports() {
        #expect(InputState(report: Frame.request(0x01)) == nil)
    }
}

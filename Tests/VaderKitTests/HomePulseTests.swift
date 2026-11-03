import Testing
@testable import VaderKit

/// Plays a macro's Home steps through the decoder, with report jitter added to each edge.
private func decode(_ macro: Macro, jitter: [Double] = [0, 0, 0, 0], start: Double = 10) -> ControllerKey? {
    var decoder = HomePulse.Decoder()
    var t = start
    var result: ControllerKey?
    for (i, step) in macro.steps.enumerated() {
        if let k = decoder.update(homeDown: step.event == .press, at: t + jitter[i] / 1000) { result = k }
        t += Double(step.delay) / 1000
    }
    return result
}

@Test func everyExtraButtonHasADistinctTwoPulseCode() {
    #expect(Set(HomePulse.keys) == ControllerKey.extraButtons)
    for key in HomePulse.keys {
        let m = HomePulse.macro(for: key)!
        #expect(m.trigger == key)
        #expect(m.steps.map(\.key) == [.home, .home, .home, .home])
        #expect(m.steps.map(\.event) == [.press, .release, .press, .release])
        #expect(m.duration <= 180)
        #expect(decode(m) == key)
    }
    #expect(HomePulse.macro(for: .a) == nil)
}

@Test func codesSurviveReportJitter() {
    // Reports arrive about every 8 ms, so each edge can land up to a report late.
    for key in HomePulse.keys {
        let m = HomePulse.macro(for: key)!
        #expect(decode(m, jitter: [0, 8, 0, 8]) == key)
        #expect(decode(m, jitter: [0, 14, 0, 14]) == key)
        #expect(decode(m, jitter: [8, 0, 8, 0]) == key)
    }
}

@Test func measuredPulsesDecode() {
    // Lengths seen from the controller on 2026-11-03: 20 ms came back as 15-24, 50 as 48-64, 80 as 80.
    #expect(HomePulse.key(first: 24, second: 16) == .m1)
    #expect(HomePulse.key(first: 16, second: 56) == .m2)
    #expect(HomePulse.key(first: 64, second: 48) == .rm)
    #expect(HomePulse.key(first: 128, second: 20) == nil)
    #expect(HomePulse.key(first: 80, second: 48) == .m4)
    #expect(HomePulse.key(first: 80, second: 80) == nil)
}

@Test func singleOrLongHomePressesSendNothing() {
    var d = HomePulse.Decoder()
    // A person pressing the logo button: one long press.
    #expect(d.update(homeDown: true, at: 1.0) == nil)
    #expect(d.update(homeDown: false, at: 1.15) == nil)
    // A short pulse followed much later by another is two lone pulses, not a code.
    #expect(d.update(homeDown: true, at: 2.0) == nil)
    #expect(d.update(homeDown: false, at: 2.02) == nil)
    #expect(d.update(homeDown: true, at: 2.5) == nil)
    #expect(d.update(homeDown: false, at: 2.52) == nil)
    // Repeated "down" reports while held are ignored.
    #expect(d.update(homeDown: true, at: 3.0) == nil)
    #expect(d.update(homeDown: true, at: 3.008) == nil)
    #expect(d.update(homeDown: false, at: 3.02) == nil)
    #expect(d.update(homeDown: true, at: 3.04) == nil)
    #expect(d.update(homeDown: false, at: 3.06) == .m1)
}

@Test func proControllerReportHomeBit() {
    let idle: [UInt8] = [0x30, 0x70, 0x70, 0x00, 0x80, 0x00]
    let home: [UInt8] = [0x30, 0x72, 0x70, 0x00, 0x90, 0x00]
    let other: [UInt8] = [0x21, 0x00, 0x00, 0x00, 0x90, 0x00]
    idle.withUnsafeBufferPointer { #expect(HomePulse.homePressed(proControllerReport: $0) == false) }
    home.withUnsafeBufferPointer { #expect(HomePulse.homePressed(proControllerReport: $0) == true) }
    other.withUnsafeBufferPointer { #expect(HomePulse.homePressed(proControllerReport: $0) == nil) }
}

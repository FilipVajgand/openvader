import Testing
@testable import VaderKit

/// A layout-3.2 profile filled with the factory values documented by
/// OpenFlydigi's hardware reads.
func factoryProfile() -> MappingProfile {
    var b = [UInt8](repeating: 0xFF, count: MappingProfile.size)
    b[0] = 0x02; b[1] = 0x03
    for i in 0..<32 { b[13 + 3 * i] = 0xFF; b[14 + 3 * i] = 0; b[15 + 3 * i] = 0 }
    let core: [UInt8] = [0, 0, 63, 63, 127, 127, 127]
    b.replaceSubrange(109..<116, with: core)
    b.replaceSubrange(116..<123, with: core)
    let trig: [UInt8] = [0, 0, 0, 0, 255, 255, 255]
    b.replaceSubrange(123..<130, with: trig)
    b.replaceSubrange(130..<137, with: trig)
    b.replaceSubrange(137..<145, with: [0, 12, 0, 4, 25, 20, 0, 0])
    b.replaceSubrange(145..<154, with: [0, 0, 60, 255, 50, 0, 80, 255, 50])
    let gear: [UInt8] = [1, 30, 80, 5, 1, 50, 0, 255, 40, 120, 5, 0, 50, 0]
    b[154] = 0
    b.replaceSubrange(155..<169, with: gear)
    b.replaceSubrange(169..<183, with: gear)
    b[225] = 0xFF; b[226] = 0xFF
    let extra: [UInt8] = [0, 50, 62, 75, 87, 100, 112, 125, 137, 150, 0, 0]
    b.replaceSubrange(790..<802, with: extra)
    b.replaceSubrange(802..<814, with: extra)
    var p = MappingProfile(bytes: b)
    p.name = "Profile 1"
    return p
}

@Suite struct MappingProfileTests {
    @Test func layoutIsRecognised() {
        let p = factoryProfile()
        #expect(p.layoutVersion == 770)
        #expect(p.isLayoutSupported)
        var old = p
        old.bytes[0] = 1
        #expect(!old.isLayoutSupported)
    }

    @Test func nameRoundTrips() {
        var p = factoryProfile()
        p.name = "Elden Ring"
        #expect(p.name == "Elden Ring")
        p.name = "A very long profile name"
        #expect(p.name == "A very lon")
        p.name = "配置3"
        #expect(p.name == "配置3")
        #expect(p.bytes[770 + 6] == 0 && p.bytes[785] == 0)
        p.name = "OpenVader"
        #expect(p.name == "OpenVader")
    }

    @Test func factoryButtonsAreDefault() {
        let p = factoryProfile()
        for key in ControllerKey.allCases { #expect(p.binding(for: key).isDefault) }
    }

    @Test func remapEncodesTargetId() {
        var p = factoryProfile()
        p.setBinding(ButtonBinding(action: .remap(.a)), for: .m1)
        #expect(Array(p.bytes[13 + 18 * 3..<13 + 18 * 3 + 3]) == [4, 0, 0])
        #expect(p.binding(for: .m1).action == .remap(.a))
        p.setBinding(ButtonBinding(), for: .m1)
        #expect(Array(p.bytes[13 + 18 * 3..<13 + 18 * 3 + 3]) == [0xFF, 0, 0])
    }

    @Test func turboOnUnmappedKeyUsesOwnId() {
        var p = factoryProfile()
        p.setBinding(ButtonBinding(turbo: .init(frequency: 15, mode: .toggle)), for: .rt)
        #expect(Array(p.bytes[13 + 13 * 3..<13 + 13 * 3 + 3]) == [13, 2, 15])
        let b = p.binding(for: .rt)
        #expect(b.action == .standard)
        #expect(b.turbo == .init(frequency: 15, mode: .toggle))
    }

    @Test func pointingAtItselfReadsAsDefault() {
        var p = factoryProfile()
        p.bytes[13 + 4 * 3] = 4
        #expect(p.binding(for: .a).isDefault)
    }

    @Test func keyboardBindingsArePreservedAndStrippedForSwitch() {
        var p = factoryProfile()
        p.bytes[13 + 5 * 3] = 0xFE
        #expect(p.binding(for: .b).action == .keyboardMouse)
        #expect(p.normalizedForSwitch().binding(for: .b).isDefault)
    }

    @Test func factorySticksMatchFactoryBank() {
        let p = factoryProfile()
        let s = p.stick(.left)
        #expect(s.curve == .standard && s.deadZone == 0 && s.isStick && !s.circular)
        var q = p
        q.setStick(s, .left)
        #expect(q.bytes == p.bytes, "rewriting the factory stick must change nothing")
    }

    @Test func deadZoneRecompilesBank() {
        var p = factoryProfile()
        var s = p.stick(.right)
        s.deadZone = 25
        s.circular = true
        p.setStick(s, .right)
        let back = p.stick(.right)
        #expect(back.deadZone == 25 && back.circular)
        #expect(back.bank.first! < 50, "inside the dead zone the stick must be silent")
        #expect(back.bank.last == 150)
        #expect(p.stick(.left).bank == [50, 62, 75, 87, 100, 112, 125, 137, 150])
    }

    @Test func outerDeadZoneIsCrossClamped() {
        var s = StickSettings()
        s.deadZone = 70
        s.outerDeadZone = 60
        #expect(s.normalized().outerDeadZone == 30)
    }

    @Test func triggerTravelMirrorsPoints() {
        var p = factoryProfile()
        p.setTrigger(TriggerTravel(start: 200, end: 20), .left)
        #expect(Array(p.bytes[123..<130]) == [0, 20, 20, 20, 200, 200, 200])
        #expect(p.trigger(.left) == TriggerTravel(start: 20, end: 200))
        #expect(p.trigger(.right) == .full)
    }

    @Test func gyroWritesBothSensitivityBytesAndClearsStrayKey() {
        var p = factoryProfile()
        var g = p.gyro
        #expect(g.target == .off && g.enableKey == .lt && g.sensitivity == 25)
        g.target = .rightStick
        g.activation = .toggle
        g.sensitivity = 60
        p.gyro = g
        #expect(Array(p.bytes[137..<145]) == [2, 12, 0, 4, 60, 60, 0, 0xFF])
        g.activation = .hold
        g.secondKey = .lb
        g.target = .leftStick
        p.gyro = g
        #expect(Array(p.bytes[137..<145]) == [1, 12, 1, 4, 60, 60, 1, 10])
    }

    @Test func gripVibrationRoundTrips() {
        var p = factoryProfile()
        var v = p.gripVibration
        #expect(v.enabled && v.left.minimum == 60 && v.right.minimum == 80 && v.left.maximum == 255)
        v.enabled = false
        v.right.enabled = false
        v.left.maximum = 128
        p.gripVibration = v
        #expect(Array(p.bytes[145..<154]) == [0xFF, 0, 60, 128, 50, 0xFF, 80, 255, 50])
    }

    @Test func triggerVibrationUsesOneForOff() {
        var p = factoryProfile()
        var t = p.triggerVibration
        #expect(t.enabled && t.left.scale == 50)
        t.enabled = false
        t.left.scale = 80
        p.triggerVibration = t
        #expect(p.bytes[154] == 1)
        #expect(p.bytes[155 + 5] == 80)
        #expect(p.bytes[155 + 7] == 255, "the micro gear is left alone")
    }
}

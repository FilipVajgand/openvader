import Foundation
import Testing
@testable import VaderKit

@Suite(.serialized) struct DeviceTests {
    func make() throws -> (VaderDevice, VirtualVader) {
        let pad = VirtualVader()
        let device = VaderDevice(connection: pad, connectionKind: .dongle)
        _ = try device.handshake()
        return (device, pad)
    }

    @Test func handshakeReadsIdentity() throws {
        let (device, _) = try make()
        #expect(device.info?.isVader5 == true)
        #expect(device.info?.firmware == "7.2.2.1")
        #expect(try device.hardwareStatus().sleepMinutes == 15)
    }

    @Test func readAllRestoresActiveProfile() throws {
        let (device, pad) = try make()
        try device.activate(profile: 2)
        let snapshots = try device.readAllSnapshots()
        #expect(snapshots.count == 4)
        #expect(snapshots.map(\.mapping.name) == ["Profile 1", "Profile 2", "Profile 3", "Profile 4"])
        #expect(snapshots.allSatisfy { $0.lighting.isValid && $0.lighting.ledCount == 10 && $0.macroBytes.count == 1660 })
        #expect(pad.active == 2)
    }

    @Test func commitWritesSavesAndVerifies() throws {
        let (device, pad) = try make()
        var m = try device.readProfile(1)
        m.setBinding(ButtonBinding(action: .remap(.a)), for: .m1)
        m.name = "Racing"
        try device.activate(profile: 0)
        let after = try device.commit(profile: 1, mapping: m)
        #expect(after.mapping.binding(for: .m1).action == .remap(.a))
        #expect(after.mapping.name == "Racing")
        #expect(pad.active == 1, "0xA6 must hit the profile that was written")
        #expect(pad.tags[1] == after.mapping.dataVersion)
        #expect(pad.tags[0] == 0xFFFF)
        #expect(pad.savedCount == 1)
    }

    @Test func lightingOnlyCommitKeepsMappingTag() throws {
        let (device, pad) = try make()
        var m = try device.readProfile(0)
        m.name = "Main"
        let first = try device.commit(profile: 0, mapping: m)
        var l = try device.readLighting(0)
        l.apply(.steady, colors: [LEDColor(red: 255, green: 0, blue: 0)])
        let second = try device.commit(profile: 0, lighting: l)
        #expect(pad.tags[0] == first.mapping.dataVersion)
        #expect(second.lighting.effect == .steady)
        #expect(second.lighting.color(frame: 0, led: 3) == LEDColor(red: 255, green: 0, blue: 0))
    }

    @Test func macroCommitRoundTrips() throws {
        let (device, _) = try make()
        var store = try device.readMacros(3)
        store.macros = [Macro(trigger: .m2, name: "Combo", steps: Macro.tap([.x, .y, .b]))]
        var m = try device.readProfile(3)
        m.setBinding(ButtonBinding(action: .macro), for: .m2)
        let after = try device.commit(profile: 3, mapping: m, macros: store)
        #expect(after.macros.macros.first?.name == "Combo")
        #expect(after.mapping.binding(for: .m2).action == .macro)
    }

    @Test func unsupportedLayoutIsRefused() throws {
        let (device, pad) = try make()
        var m = try device.readProfile(0)
        m.bytes[0] = 0x01
        #expect(throws: VaderError.self) { try device.commit(profile: 0, mapping: m) }
        #expect(pad.savedCount == 0)
    }

    @Test func backupAndRestore() throws {
        let (device, pad) = try make()
        let backup = try device.backup()
        var m = try device.readProfile(2)
        m.setBinding(ButtonBinding(action: .remap(.b)), for: .a)
        try device.commit(profile: 2, mapping: m)
        #expect(MappingProfile(bytes: pad.mappings[2]).binding(for: .a).action == .remap(.b))
        let json = try backup.encoded()
        try device.restore(try DeviceBackup.decode(json), only: [2])
        #expect(MappingProfile(bytes: pad.mappings[2]).binding(for: .a).isDefault)
    }

    @Test func restoreIsByteExactIncludingFactoryTag() throws {
        let (device, pad) = try make()
        let original = (pad.mappings[3], pad.lightings[3], pad.macroStores[3])
        let backup = try device.backup()
        var m = try device.readProfile(3)
        m.name = "OpenVader"
        try device.commit(profile: 3, mapping: m)
        #expect(pad.tags[3] != 0xFFFF)
        try device.restore(backup, only: [3])
        #expect(pad.mappings[3] == original.0)
        #expect(pad.lightings[3] == original.1)
        #expect(pad.macroStores[3] == original.2)
        #expect(pad.tags[3] == 0xFFFF)
    }

    @Test func untouchedSticksKeepFactoryTable() throws {
        let (device, _) = try make()
        var m = try device.readProfile(0)
        let before = m.bytes
        m.setStick(m.stick(.left), .left)
        m.setStick(m.stick(.right), .right)
        #expect(m.bytes == before)
        #expect(m.stick(.left).bank == [45, 58, 71, 84, 97, 110, 123, 137, 150])
        var s = m.stick(.left)
        s.deadZone = 10
        m.setStick(s, .left)
        #expect(m.stick(.left).bank != [45, 58, 71, 84, 97, 110, 123, 137, 150])
    }

    @Test func retriesSurviveDroppedReplies() throws {
        let (device, pad) = try make()
        pad.dropEvery = 7
        #expect(try device.profileVersions().dataVersions.count == 4)
        #expect(try device.hardwareStatus().sleepMinutes == 15)
    }

    @Test func settingsCommands() throws {
        let (device, pad) = try make()
        try device.setSleepTime(minutes: 60)
        #expect(pad.sleepMinutes == 60)
        try device.setFeature(.turbo, enabled: false)
        #expect(!(try device.hardwareStatus().enabled.contains(.turbo)))
        try device.setDataReport(thirdParty: true)
        #expect(try device.dataReportStatus().thirdPartyControl)
        try device.rumble(gripLeft: 10, gripRight: 20, triggerLeft: 30, triggerRight: 40)
        #expect(pad.lastRumble == [10, 20, 30, 40])
    }

    @Test func inputStreamDelivers() throws {
        let (device, _) = try make()
        let got = NSCondition()
        var count = 0
        device.connection.onInputReport = { r in
            if InputState(report: r) != nil { got.withLock { count += 1; got.broadcast() } }
        }
        try device.setInputStream(true)
        got.withLock { while count < 3 { _ = got.wait(until: Date().addingTimeInterval(1)) } }
        try device.setInputStream(false)
        #expect(count >= 3)
    }

    @Test func forbiddenCommandsNeverLeave() throws {
        let (device, _) = try make()
        #expect(throws: VaderError.self) { try device.connection.write(Frame.request(0xAF, [0])) }
        #expect(throws: VaderError.self) { try device.connection.write(Frame.request(0x1F)) }
    }
}

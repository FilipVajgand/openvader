import Testing
@testable import VaderKit

@Suite struct FrameTests {
    @Test func heartbeatFrame() {
        // The same bytes SDL and ControlLab send to a Vader 5 Pro on macOS.
        #expect(Array(Frame.request(0x01).prefix(5)) == [0x5A, 0xA5, 0x01, 0x02, 0x03])
        #expect(Frame.request(0x01).count == 32)
    }

    @Test func checksumCoversCommandLengthAndPayload() {
        let f = Frame.request(Command.readLighting.rawValue, [0x00, 0x14])
        #expect(Array(f.prefix(7)) == [0x5A, 0xA5, 0xA7, 0x04, 0x00, 0x14, 0xA7 &+ 0x04 &+ 0x14])
        #expect(f[7...].allSatisfy { $0 == 0 })
    }

    @Test func packFrameFits() {
        let f = Frame.request(Command.writeMappingPack.rawValue, [3] + [UInt8](repeating: 0xAB, count: 20))
        #expect(f[3] == 23)
        #expect(f[25] == Frame.checksum(f[2..<25]))
    }

    @Test func heartbeatReplyParses() {
        // A dongle heartbeat reported in uiltonlopes/flydigi-space-station-mac#1.
        let raw: [UInt8] = [0x5a, 0xa5, 0x01, 0x01, 0x00, 0x82, 0x01, 0x00, 0x00, 0x00, 0x00, 0x05, 0x45, 0x01, 0x00, 0x72,
                            0x21, 0x04, 0x83, 0x36, 0x05, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10, 0x43, 0x27, 0x00, 0x9f]
        let reply = Reply(raw)!
        #expect(reply.checksumOK)
        let info = DeviceInfo(reply: reply)
        #expect(info.isVader5)
        #expect(info.firmware == "7.2.2.1")
        #expect(info.receiverFirmware == "0.4.8.3")
        #expect(info.siFirmware == "3.6.0.5")
        #expect(info.rfFirmware == "1.0.4.3")
        #expect(info.batteryPercent == 100)
        #expect(info.batteryState == .discharging)
    }

    @Test func forbiddenCommandsAreListed() {
        for id: UInt8 in [0x1F, 0xAF, 0xFD, 0xFE] { #expect(Command.forbidden.contains(id)) }
        for c in Command.allCases { #expect(!Command.forbidden.contains(c.rawValue)) }
    }
}

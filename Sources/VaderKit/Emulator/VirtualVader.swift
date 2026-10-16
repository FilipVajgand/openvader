import Foundation

/// An in-memory Vader 5 Pro that speaks the configuration protocol.
///
/// It models the behaviour the real controller is documented to have:
/// reads select the profile they read, `0xA6` stamps whichever profile is
/// running, uploads land in the target slot, and the raw stream produces
/// `0xEF` reports. Used by the tests and by the app's demo mode.
public final class VirtualVader: VaderTransport, @unchecked Sendable {
    public let info = HIDInterfaceInfo(
        vendorID: VaderUSB.vendorID, productID: VaderUSB.vader5ProductID, usagePage: VaderUSB.controlUsagePage,
        usage: 1, locationID: 0, product: "Virtual Vader 5 Pro", registryID: 0)

    private let lock = NSCondition()
    private var queue: [[UInt8]] = []
    private var removed = false
    private var handler: (([UInt8]) -> Void)?
    private var removalHandler: (() -> Void)?

    // Device state
    public private(set) var mappings: [[UInt8]]
    public private(set) var lightings: [[UInt8]]
    public private(set) var macroStores: [[UInt8]]
    public private(set) var tags: [UInt16] = [0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF]
    public private(set) var active = 0
    public private(set) var savedCount = 0
    public var sleepMinutes = 15
    public var featureBits: UInt8 = 0b0011_1001
    public var thirdParty = false
    public private(set) var rawStream = false
    public private(set) var lastRumble: [UInt8] = []
    /// Drop every Nth reply packet, to exercise retries.
    public var dropEvery = 0

    private var upload: (cmd: UInt8, profile: Int, packets: Int, data: [UInt8])?
    private var timer: DispatchSourceTimer?
    private var tick = 0
    private var replies = 0

    public init() {
        mappings = (0..<4).map { Self.factoryMapping(profile: $0) }
        lightings = (0..<4).map { _ in Self.factoryLighting() }
        macroStores = (0..<4).map { _ in [UInt8](repeating: 0xFF, count: 1660) }
    }

    deinit { timer?.cancel() }

    // MARK: Factory data

    /// A layout-3.2 profile as a factory-fresh Vader 5 Pro (firmware 7.1.5.0) holds it.
    public static func factoryMapping(profile: Int) -> [UInt8] {
        var b = [UInt8](repeating: 0xFF, count: MappingProfile.size)
        b.replaceSubrange(0..<13, with: [0x02, 0x03, 0x4D, 0x20, 0x04, 0x28, 0xA0, 0, 0, 0xFF, 0, 0, 0])
        for i in 0..<32 { b[13 + 3 * i] = 0xFF; b[14 + 3 * i] = 0; b[15 + 3 * i] = 0 }
        let core: [UInt8] = [0, 5, 63, 63, 127, 127, 127]
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
        b[183] = 0; b[184] = 0
        let force: [UInt8] = [0, 0, 0x0A, 0x0A, 0x64, 0x01, 0xFF, 0x46] + [UInt8](repeating: 0, count: 12)
        b.replaceSubrange(185..<205, with: force)
        b.replaceSubrange(205..<225, with: force)
        b.replaceSubrange(230..<236, with: [UInt8](repeating: 0, count: 6))
        b.replaceSubrange(774..<790, with: [UInt8](repeating: 0, count: 16))
        b.replaceSubrange(820..<825, with: [3, 3, 3, 3, 3])
        b.replaceSubrange(830..<836, with: [0, 63, 63, 127, 127, 127])
        let extra: [UInt8] = [0, 45, 58, 71, 84, 97, 110, 123, 137, 150, 0, 0]
        b.replaceSubrange(790..<802, with: extra)
        b.replaceSubrange(802..<814, with: extra)
        var p = MappingProfile(bytes: b)
        p.name = "Profile \(profile + 1)"
        return p.bytes
    }

    /// 10 LEDs × 10 frames, as the Vader 5 Pro reports it.
    public static func factoryLighting() -> [UInt8] {
        var l = [UInt8](repeating: 0, count: 320)
        l[1] = 3; l[4] = 9; l[5] = 4; l[6] = 20; l[7] = 10; l[8] = 7; l[9] = 0
        for i in 10..<20 { l[i] = 0xFF }
        var config = LightingConfig(bytes: l)
        config.apply(.flow, colors: [])
        config.bytes[8] = 7
        return config.bytes
    }

    // MARK: Transport

    public var onInputReport: (([UInt8]) -> Void)? {
        get { lock.withLock { handler } }
        set { lock.withLock { handler = newValue } }
    }

    public var onRemoval: (() -> Void)? {
        get { lock.withLock { removalHandler } }
        set { lock.withLock { removalHandler = newValue } }
    }

    public var isRemoved: Bool { lock.withLock { removed } }

    public func unplug() {
        lock.withLock { removed = true; lock.broadcast() }
        onRemoval?()
    }

    public func close() {
        timer?.cancel()
        timer = nil
    }

    public func drain() { lock.withLock { queue.removeAll() } }

    public func nextFrame(timeout: TimeInterval) -> [UInt8]? {
        let deadline = Date().addingTimeInterval(timeout)
        lock.lock()
        defer { lock.unlock() }
        while queue.isEmpty {
            if removed { return nil }
            if !lock.wait(until: deadline) { break }
        }
        return queue.isEmpty ? nil : queue.removeFirst()
    }

    public func write(_ frame: [UInt8]) throws {
        guard frame.count >= 5, frame[0] == 0x5A, frame[1] == 0xA5 else { return }
        guard !Command.forbidden.contains(frame[2]) else { throw VaderError.forbiddenCommand(frame[2]) }
        if isRemoved { throw VaderError.disconnected }
        let cmd = frame[2]
        let length = Int(frame[3])
        // Like the real pad, ignore frames with a bad checksum (except the
        // Switch-bank save, whose vendor frame is irregular).
        if cmd != Command.saveSwitchConfig.rawValue, 2 + length < frame.count,
           frame[2 + length] != Frame.checksum(frame[2..<(2 + length)]) { return }
        let payload = Array(frame[4..<min(frame.count, 2 + length)])
        lock.withLock { handle(cmd, payload) }
    }

    // MARK: Behaviour (called with the lock held)

    private func reply(_ cmd: UInt8, total: UInt8 = 1, index: UInt8 = 0, _ body: [UInt8]) {
        replies += 1
        if dropEvery > 0, replies % dropEvery == 0 { return }
        var r = [UInt8](repeating: 0, count: 32)
        r[0] = 0x5A; r[1] = 0xA5; r[2] = cmd; r[3] = total; r[4] = index
        for (i, b) in body.prefix(26).enumerated() { r[5 + i] = b }
        r[31] = Frame.checksum(r[2..<31])
        queue.append(r)
        lock.broadcast()
    }

    private func sendBlob(_ cmd: UInt8, profile: Int, _ blob: [UInt8]) {
        let packets = (blob.count + 19) / 20
        for i in 0..<packets {
            let chunk = Array(blob[(i * 20)..<min(blob.count, i * 20 + 20)])
            reply(cmd, total: UInt8(packets), index: UInt8(i), [UInt8(profile)] + chunk)
        }
    }

    private func handle(_ cmd: UInt8, _ p: [UInt8]) {
        switch Command(rawValue: cmd) {
        case .heartbeat:
            reply(cmd, [0x82, 0x01, 0, 0, 0, 0, 0x04, 0x45, 0x01, 0x00, 0x72, 0x21, 0x04, 0x83, 0x36, 0x05,
                        0, 0, 0, 0, 0, 0, 0x10, 0x43])
        case .readNickname:
            reply(cmd, [0])
        case .readUID:
            reply(cmd, [0x56, 0x69, 0x72, 0x74, 0x75, 0x61, 0x6C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01])
        case .hardwareStatus:
            reply(cmd, [0b0111_1111, featureBits, 0, 0, UInt8(sleepMinutes), 0, 0, 0])
        case .featureToggle where p.count >= 2:
            let bit = UInt8(1) << (p[0] - 1)
            if p[1] == 1 { featureBits |= bit } else { featureBits &= ~bit }
            reply(cmd, [p[0]])
        case .sleepTime where p.count >= 1:
            sleepMinutes = Int(p[0])
            reply(cmd, [p[0]])
        case .dataReportStatus:
            reply(cmd, [1, rawStream ? 1 : 0, 0, 0, thirdParty ? 1 : 0])
        case .setDataReport where p.count >= 5:
            if p[1] != 0xFF { setStream(p[1] == 1) }
            if p[4] != 0xFF { thirdParty = p[4] == 1 }
            reply(cmd, [])
        case .rumble:
            lastRumble = p
        case .profileVersions:
            var body: [UInt8] = [UInt8(active)]
            for t in tags { body += [UInt8(t & 0xFF), UInt8(t >> 8)] }
            reply(cmd, body + [0xFF])
        case .activateProfile where p.count >= 1:
            active = Int(p[0]) % 4
            reply(cmd, [p[0]])
        case .readMapping where p.count >= 1:
            active = Int(p[0]) % 4
            sendBlob(cmd, profile: Int(p[0]), mappings[active])
        case .readLighting where p.count >= 1:
            active = Int(p[0]) % 4
            sendBlob(cmd, profile: Int(p[0]), lightings[active])
        case .readMacros where p.count >= 1:
            active = Int(p[0]) % 4
            sendBlob(cmd, profile: Int(p[0]), macroStores[active])
        case .writeMappingStart, .writeLightingStart, .writeMacrosStart:
            guard p.count >= 4 else { return }
            upload = (cmd, Int(p[0]) % 4, Int(p[2]), [])
            reply(cmd, [p[0]])
        case .writeMappingPack, .writeLightingPack, .writeMacrosPack:
            guard var u = upload, p.count >= 1 else { return }
            u.data += p.dropFirst()
            upload = u
            reply(cmd, [p[0]])
            if Int(p[0]) + 1 == u.packets { finishUpload(u) }
        case .saveConfig where p.count >= 2:
            let tag = UInt16(p[0]) | UInt16(p[1]) << 8
            tags[active] = tag
            savedCount += 1
            reply(cmd, [])
        case .saveSwitchConfig:
            reply(cmd, [])
        default:
            break
        }
    }

    private func finishUpload(_ u: (cmd: UInt8, profile: Int, packets: Int, data: [UInt8])) {
        switch Command(rawValue: u.cmd) {
        case .writeMappingStart: mappings[u.profile] = Array(u.data.prefix(MappingProfile.size))
        case .writeLightingStart: lightings[u.profile] = Array(u.data.prefix(lightings[u.profile].count))
        case .writeMacrosStart: macroStores[u.profile] = Array(u.data.prefix(macroStores[u.profile].count))
        default: break
        }
        upload = nil
    }

    private func setStream(_ on: Bool) {
        rawStream = on
        if on, timer == nil {
            let t = DispatchSource.makeTimerSource(queue: .global(qos: .userInteractive))
            t.schedule(deadline: .now(), repeating: .milliseconds(8))
            t.setEventHandler { [weak self] in self?.emitInput() }
            t.resume()
            timer = t
        } else if !on {
            timer?.cancel()
            timer = nil
        }
    }

    /// A slow demo: sticks circle, triggers breathe, buttons take turns.
    private func emitInput() {
        tick += 1
        let t = Double(tick) * 0.008
        var r = [UInt8](repeating: 0, count: 32)
        r[0] = 0x5A; r[1] = 0xA5; r[2] = 0xEF
        func put(_ o: Int, _ v: Double) {
            let i = UInt16(bitPattern: Int16(max(-32767, min(32767, v * 32767))))
            r[o] = UInt8(i & 0xFF); r[o + 1] = UInt8(i >> 8)
        }
        put(3, cos(t) * 0.8); put(5, sin(t) * 0.8)
        put(7, sin(t * 0.7) * 0.5); put(9, cos(t * 1.3) * 0.5)
        let order = InputState.bitMap
        let (offset, mask, _) = order[Int(t * 1.5) % order.count]
        r[offset] |= mask
        r[15] = UInt8(127 + 127 * sin(t * 0.9))
        r[16] = UInt8(127 + 127 * cos(t * 0.6))
        put(17, sin(t * 2) * 0.05); put(19, cos(t * 1.7) * 0.04); put(21, 0.01)
        put(27, 1.0 / 8)
        r[31] = Frame.checksum(r[2..<31])
        onInputReport?(r)
    }
}

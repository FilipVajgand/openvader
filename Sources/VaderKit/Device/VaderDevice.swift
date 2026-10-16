import Foundation

/// The command layer over one controller's configuration interface.
///
/// Calls block until the controller answers, so drive one instance from a
/// single serial queue. Every profile write is verified by reading it back.
public final class VaderDevice: @unchecked Sendable {
    public static let packetPayload = 20

    public let connection: any VaderTransport
    public let connectionKind: ConnectionKind
    public private(set) var info: DeviceInfo?

    public init(connection: any VaderTransport, connectionKind: ConnectionKind) {
        self.connection = connection
        self.connectionKind = connectionKind
    }

    /// Opens the first attached controller and runs the handshake.
    public static func openFirst() throws -> VaderDevice {
        guard let (device, info) = HIDDiscovery.controllers().first else { throw VaderError.notFound }
        let connection = HIDConnection(device: device, info: info)
        try connection.open()
        let vader = VaderDevice(connection: connection, connectionKind: HIDDiscovery.connectionKind(for: info))
        _ = try vader.handshake()
        return vader
    }

    public func close() { connection.close() }

    // MARK: Transport

    /// Sends a command and waits for the reply carrying the same id.
    @discardableResult
    public func send(
        _ command: Command, _ payload: [UInt8] = [], timeout: TimeInterval = 0.5, retries: Int = 3
    ) throws -> Reply {
        try sendFrame(Frame.request(command.rawValue, payload), expecting: command.rawValue,
                      timeout: timeout, retries: retries)
    }

    func sendFrame(_ frame: [UInt8], expecting ack: UInt8, timeout: TimeInterval, retries: Int) throws -> Reply {
        for _ in 0..<max(1, retries) {
            connection.drain()
            try connection.write(frame)
            let deadline = Date().addingTimeInterval(timeout)
            while true {
                let remaining = deadline.timeIntervalSinceNow
                guard remaining > 0, let raw = connection.nextFrame(timeout: remaining) else { break }
                if let reply = Reply(raw), reply.command == ack { return reply }
            }
            if connection.isRemoved { throw VaderError.disconnected }
        }
        throw VaderError.noReply(command: ack)
    }

    /// Sends without waiting for an answer (rumble has none).
    public func post(_ command: Command, _ payload: [UInt8]) throws {
        try connection.write(Frame.request(command.rawValue, payload))
    }

    // MARK: Identity and status

    /// The same introductions SDL and Space Station make on connect.
    public func handshake() throws -> DeviceInfo {
        let info = try readInfo()
        _ = try? send(.profileVersions)
        _ = try? send(.readNickname)
        _ = try? send(.readUID)
        return info
    }

    public func readInfo() throws -> DeviceInfo {
        let info = DeviceInfo(reply: try send(.heartbeat, timeout: 0.6, retries: 5))
        self.info = info
        return info
    }

    public func readUID() throws -> String {
        try send(.readUID, timeout: 0.6, retries: 3).raw[5..<18].map { String(format: "%02x", $0) }.joined()
    }

    public func hardwareStatus() throws -> HardwareStatus {
        HardwareStatus(reply: try send(.hardwareStatus, timeout: 0.8, retries: 4))
    }

    public func setFeature(_ feature: DeviceFeature, enabled: Bool) throws {
        try send(.featureToggle, [feature.rawValue, enabled ? 1 : 0], timeout: 0.6)
    }

    /// Minutes before the controller sleeps; 0 = never.
    public func setSleepTime(minutes: Int) throws {
        guard (0...255).contains(minutes) else { throw VaderError.invalidArgument("Sleep time must be 0...255 minutes.") }
        try send(.sleepTime, [UInt8(minutes)], timeout: 0.6)
    }

    public func dataReportStatus() throws -> DataReportStatus {
        DataReportStatus(reply: try send(.dataReportStatus, timeout: 0.6, retries: 5))
    }

    /// `nil` leaves a flag unchanged (sent as 0xFF).
    public func setDataReport(
        controller: Bool? = nil, rawStream: Bool? = nil, keyboard: Bool? = nil,
        mouse: Bool? = nil, thirdParty: Bool? = nil
    ) throws {
        func flag(_ v: Bool?) -> UInt8 { v.map { $0 ? 1 : 0 } ?? 0xFF }
        try send(.setDataReport, [flag(controller), flag(rawStream), flag(keyboard), flag(mouse), flag(thirdParty)],
                 timeout: 0.6)
    }

    /// Turns the ~500 Hz live input stream on or off.
    public func setInputStream(_ enabled: Bool) throws {
        try setDataReport(rawStream: enabled)
    }

    /// Drives the four motors directly, 0...255 each. Not stored.
    public func rumble(gripLeft: UInt8, gripRight: UInt8, triggerLeft: UInt8 = 0, triggerRight: UInt8 = 0) throws {
        try post(.rumble, [gripLeft, gripRight, triggerLeft, triggerRight])
    }

    // MARK: Profiles

    public func profileVersions() throws -> ProfileVersions {
        ProfileVersions(reply: try send(.profileVersions, timeout: 0.8, retries: 4))
    }

    /// Makes a profile the running one, and checks that it took.
    public func activate(profile: Int) throws {
        try checkProfile(profile)
        for attempt in 0..<3 {
            try send(.activateProfile, [UInt8(profile)], timeout: 0.6)
            Thread.sleep(forTimeInterval: 0.15 + 0.1 * Double(attempt))
            if try profileVersions().active == profile { return }
        }
        throw VaderError.verificationFailed("profile \(profile + 1) did not become active")
    }

    /// Reads one of the chunked stores (`0xA3`, `0xA7`, `0xAC`).
    public func readBlob(_ command: Command, profile: Int) throws -> [UInt8] {
        let first = try send(command, [UInt8(profile), UInt8(Self.packetPayload)], timeout: 1.5)
        let total = first.total
        guard total > 0 else { return [] }
        var chunks = [[UInt8]?](repeating: nil, count: total)
        func absorb(_ r: Reply) {
            guard r.index < total else { return }
            chunks[r.index] = Array(r.raw[6..<(6 + Self.packetPayload)])
        }
        absorb(first)
        while chunks.contains(where: { $0 == nil }) {
            guard let raw = connection.nextFrame(timeout: 1.5) else {
                if connection.isRemoved { throw VaderError.disconnected }
                throw VaderError.transferStalled(command: command.rawValue,
                                                 received: chunks.compactMap { $0 }.count, expected: total)
            }
            if let r = Reply(raw), r.command == command.rawValue { absorb(r) }
        }
        return chunks.flatMap { $0! }
    }

    /// Uploads a whole store in 20-byte packets.
    public func writeBlob(start: Command, pack: Command, profile: Int, bytes: [UInt8],
                          progress: ((Double) -> Void)? = nil) throws {
        var chunks = stride(from: 0, to: bytes.count, by: Self.packetPayload).map {
            Array(bytes[$0..<min($0 + Self.packetPayload, bytes.count)])
        }
        guard !chunks.isEmpty, chunks.count < 256 else { throw VaderError.invalidArgument("bad blob size") }
        // Mapping and macro stores are whole packets; the lighting store may end short.
        if start != .writeLightingStart, chunks[chunks.count - 1].count < Self.packetPayload {
            chunks[chunks.count - 1] += [UInt8](repeating: 0xFF, count: Self.packetPayload - chunks[chunks.count - 1].count)
        }
        try send(start, [UInt8(profile), 0, UInt8(chunks.count), UInt8(Self.packetPayload)], timeout: 1.0)
        for (i, chunk) in chunks.enumerated() {
            try send(pack, [UInt8(i)] + chunk, timeout: 1.0)
            progress?(Double(i + 1) / Double(chunks.count))
        }
    }

    /// Commits the running profile to flash under the given revision tag.
    public func save(dataVersion: UInt16) throws {
        try send(.saveConfig, [UInt8(dataVersion & 0xFF), UInt8(dataVersion >> 8)], timeout: 10, retries: 2)
    }

    /// Reads one profile. **Side effect:** the controller makes it active.
    public func readProfile(_ profile: Int) throws -> MappingProfile {
        try checkProfile(profile)
        return MappingProfile(bytes: try readBlob(.readMapping, profile: profile))
    }

    public func readLighting(_ profile: Int) throws -> LightingConfig {
        try checkProfile(profile)
        return LightingConfig(bytes: try readBlob(.readLighting, profile: profile))
    }

    public func readMacros(_ profile: Int) throws -> MacroStore {
        try checkProfile(profile)
        return MacroStore(bytes: try readBlob(.readMacros, profile: profile))
    }

    /// Everything stored for one profile.
    public func readSnapshot(_ profile: Int) throws -> ProfileSnapshot {
        let mapping = try readProfile(profile)
        let lighting = try readLighting(profile)
        let macros = try readBlob(.readMacros, profile: profile)
        return ProfileSnapshot(index: profile, mapping: mapping, lighting: lighting, macroBytes: macros)
    }

    /// Reads all four profiles and puts the active one back.
    public func readAllSnapshots(progress: ((Double) -> Void)? = nil) throws -> [ProfileSnapshot] {
        let before = try profileVersions().active
        var out: [ProfileSnapshot] = []
        defer {
            if (try? profileVersions().active) != before { try? activate(profile: before) }
        }
        for i in 0..<ProfileVersions.count {
            out.append(try readSnapshot(i))
            progress?(Double(i + 1) / Double(ProfileVersions.count))
        }
        return out
    }

    /// Writes whatever changed for one profile, saves it to flash, and
    /// verifies by reading back. The profile ends up active.
    ///
    /// Returns what the controller holds afterwards.
    @discardableResult
    ///
    /// `tag` forces the revision tag (restores use the backed-up one); by
    /// default a mapping change gets a fresh tag and anything else keeps it.
    public func commit(
        profile: Int, mapping: MappingProfile? = nil, lighting: LightingConfig? = nil,
        macros: MacroStore? = nil, rawMacros: [UInt8]? = nil, tag forcedTag: UInt16? = nil,
        progress: ((Double) -> Void)? = nil
    ) throws -> ProfileSnapshot {
        try checkProfile(profile)
        if let mapping, !mapping.isLayoutSupported {
            throw VaderError.unsupportedLayout(
                "This profile uses mapping layout \(mapping.layoutDescription). OpenVader has only been "
                    + "checked against layout 3.2 and will not write a layout it does not know.")
        }
        // 0xA6 commits whichever profile is running, so select the target first.
        if try profileVersions().active != profile { try activate(profile: profile) }
        let versions = try profileVersions()
        var tag = versions.dataVersions[profile]
        var mappingToWrite = mapping
        if let forcedTag {
            tag = forcedTag
        } else if mappingToWrite != nil {
            tag = Self.freshTag(excluding: tag)
        } else if tag == ProfileVersions.unwritten {
            tag = Self.freshTag(excluding: tag)
        }
        mappingToWrite?.dataVersion = tag
        let macroBytes = try rawMacros ?? macros?.encoded()
        let steps = Double([mappingToWrite != nil, macroBytes != nil, lighting != nil].filter { $0 }.count + 1)
        var done = 0.0
        func sub(_ p: Double) { progress?((done + p) / steps) }
        if let m = mappingToWrite {
            try writeBlob(start: .writeMappingStart, pack: .writeMappingPack, profile: profile, bytes: m.bytes, progress: sub)
            done += 1
        }
        if let macroBytes {
            try writeBlob(start: .writeMacrosStart, pack: .writeMacrosPack, profile: profile, bytes: macroBytes, progress: sub)
            done += 1
        }
        if let lighting {
            try writeBlob(start: .writeLightingStart, pack: .writeLightingPack, profile: profile, bytes: lighting.bytes, progress: sub)
            done += 1
        }
        try save(dataVersion: tag)
        Thread.sleep(forTimeInterval: 0.2)
        if macroBytes != nil {
            // Stored macros are loaded when a profile is applied.
            try? send(.activateProfile, [UInt8(profile)], timeout: 0.6)
            Thread.sleep(forTimeInterval: 0.15)
        }
        let after = try readSnapshot(profile)
        progress?(1)
        if let m = mappingToWrite, after.mapping.bytes != m.bytes {
            throw VaderError.verificationFailed("profile \(profile + 1) mapping (\(diffSummary(m.bytes, after.mapping.bytes)))")
        }
        if let l = lighting, after.lighting.bytes.prefix(l.bytes.count) != l.bytes[...] {
            throw VaderError.verificationFailed("profile \(profile + 1) lighting (\(diffSummary(l.bytes, after.lighting.bytes)))")
        }
        if let mb = macroBytes, after.macroBytes != mb {
            throw VaderError.verificationFailed("profile \(profile + 1) macros (\(diffSummary(mb, after.macroBytes)))")
        }
        return after
    }

    /// Copies a profile into the Nintendo Switch bank ("Apply to Switch mode").
    /// That bank can be written but never read back over USB.
    public func saveToSwitchMode(profile: Int) throws {
        try checkProfile(profile)
        let current = try readProfile(profile)
        let normalized = current.normalizedForSwitch()
        if normalized != current {
            try writeBlob(start: .writeMappingStart, pack: .writeMappingPack, profile: profile, bytes: normalized.bytes)
        }
        let tag = Self.freshTag(excluding: current.dataVersion)
        // Reproduces the vendor frame byte for byte: the length says 4 and the
        // checksum skips the destination slot. The firmware expects exactly this.
        var frame = [UInt8](repeating: 0, count: Frame.size)
        frame[0] = 0x5A
        frame[1] = 0xA5
        frame[2] = Command.saveSwitchConfig.rawValue
        frame[3] = 0x04
        frame[4] = UInt8(tag & 0xFF)
        frame[5] = UInt8(tag >> 8)
        frame[6] = UInt8(4 + profile)
        frame[7] = Frame.checksum(frame[2..<6])
        _ = try sendFrame(frame, expecting: Command.saveSwitchConfig.rawValue, timeout: 10, retries: 2)
        if normalized != current {
            // Put the XInput profile back the way it was (keyboard bindings included).
            try writeBlob(start: .writeMappingStart, pack: .writeMappingPack, profile: profile, bytes: current.bytes)
        }
    }

    // MARK: Backup

    public func backup(progress: ((Double) -> Void)? = nil) throws -> DeviceBackup {
        let info = try self.info ?? readInfo()
        let snapshots = try readAllSnapshots(progress: progress)
        return DeviceBackup(info: info, uid: try? readUID(), snapshots: snapshots)
    }

    /// Writes saved profiles back. Pass `only` to restore a subset.
    public func restore(_ backup: DeviceBackup, only: Set<Int>? = nil, progress: ((Double) -> Void)? = nil) throws {
        let before = try profileVersions().active
        let selected = backup.profiles.filter { only?.contains($0.index) ?? true }
        for (n, p) in selected.enumerated() {
            guard let mapping = p.mappingProfile else { continue }
            try commit(profile: p.index, mapping: mapping, lighting: p.lightingConfig,
                       rawMacros: p.macroBytes, tag: mapping.dataVersion) { f in
                progress?((Double(n) + f) / Double(selected.count))
            }
        }
        try? activate(profile: before)
    }

    // MARK: Helpers

    func checkProfile(_ profile: Int) throws {
        guard (0..<ProfileVersions.count).contains(profile) else {
            throw VaderError.invalidArgument("Profile must be 1...4.")
        }
    }

    static func freshTag(excluding old: UInt16) -> UInt16 {
        var tag: UInt16
        repeat { tag = UInt16.random(in: 0...0xFFFE) } while tag == old
        return tag
    }

    func diffSummary(_ a: [UInt8], _ b: [UInt8]) -> String {
        let n = min(a.count, b.count)
        let offsets = (0..<n).filter { a[$0] != b[$0] }
        let sizes = a.count == b.count ? "" : ", size \(a.count) vs \(b.count)"
        return "\(offsets.count) bytes differ at \(offsets.prefix(8).map(String.init).joined(separator: ","))\(sizes)"
    }
}

/// Everything stored for one profile.
public struct ProfileSnapshot: Sendable, Equatable {
    public var index: Int
    public var mapping: MappingProfile
    public var lighting: LightingConfig
    public var macroBytes: [UInt8]

    public var macros: MacroStore { MacroStore(bytes: macroBytes) }
}

import Foundation

/// A complete copy of the controller's four profiles (mapping, lighting
/// and macros), stored as JSON.
public struct DeviceBackup: Codable, Sendable {
    public struct Profile: Codable, Sendable {
        public var index: Int
        public var name: String
        public var mapping: Data
        public var lighting: Data?
        public var macros: Data?

        public var mappingProfile: MappingProfile? {
            mapping.count >= MappingProfile.size ? MappingProfile(bytes: [UInt8](mapping)) : nil
        }

        public var lightingConfig: LightingConfig? {
            guard let lighting else { return nil }
            let config = LightingConfig(bytes: [UInt8](lighting))
            return config.isValid ? config : nil
        }

        public var macroBytes: [UInt8]? { macros.map { [UInt8]($0) } }
    }

    public var format = 1
    public var created: Date
    public var app: String
    public var model: String
    public var deviceType: Int
    public var firmware: String?
    public var uid: String?
    public var profiles: [Profile]

    public init(info: DeviceInfo, uid: String?, snapshots: [ProfileSnapshot]) {
        created = Date()
        app = "OpenVader \(OpenVaderVersion.string)"
        model = info.modelName
        deviceType = info.deviceType
        firmware = info.firmware
        self.uid = uid
        profiles = snapshots.map {
            Profile(index: $0.index, name: $0.mapping.name, mapping: Data($0.mapping.bytes),
                    lighting: Data($0.lighting.bytes), macros: Data($0.macroBytes))
        }
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> DeviceBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DeviceBackup.self, from: data)
    }

    /// `~/Library/Application Support/OpenVader/Backups`
    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenVader/Backups", isDirectory: true)
    }

    /// Writes into the default directory with a timestamped name.
    @discardableResult
    public func saveToDefaultLocation(label: String = "backup") throws -> URL {
        let dir = Self.defaultDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter.string(
            from: created, timeZone: .current,
            formatOptions: [.withFullDate, .withTime, .withDashSeparatorInDate])
        let url = dir.appendingPathComponent("\(label)-\(stamp).json")
        try encoded().write(to: url, options: .atomic)
        return url
    }
}

public enum OpenVaderVersion {
    public static let string = "0.1.0"
}

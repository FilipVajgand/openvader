import Foundation

/// One profile saved on the Mac: the profile library and `.ovprofile` files.
public struct ProfileFile: Codable, Sendable, Identifiable {
    public var format = 1
    public var kind = "openvader-profile"
    public var id: UUID
    public var name: String
    public var saved: Date
    public var deviceType: Int
    public var mapping: Data
    public var lighting: Data?
    public var macros: Data?
    /// Keyboard and mouse bindings that OpenVader performs on the Mac.
    public var host: HostProfileMappings?

    public init(name: String, deviceType: Int, mapping: MappingProfile, lighting: LightingConfig?,
                macroBytes: [UInt8]?, host: HostProfileMappings?) {
        id = UUID()
        self.name = name
        saved = Date()
        self.deviceType = deviceType
        self.mapping = Data(mapping.bytes)
        self.lighting = lighting.map { Data($0.bytes) }
        self.macros = macroBytes.map { Data($0) }
        self.host = host
    }

    public var mappingProfile: MappingProfile? {
        mapping.count >= MappingProfile.size ? MappingProfile(bytes: [UInt8](mapping)) : nil
    }

    public var lightingConfig: LightingConfig? {
        lighting.map { LightingConfig(bytes: [UInt8]($0)) }.flatMap { $0.isValid ? $0 : nil }
    }

    public var macroStore: MacroStore? { macros.map { MacroStore(bytes: [UInt8]($0)) } }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> ProfileFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(ProfileFile.self, from: data)
        guard file.kind == "openvader-profile", file.mappingProfile != nil else {
            throw VaderError.invalidArgument("This is not an OpenVader profile.")
        }
        return file
    }

    /// `~/Library/Application Support/OpenVader/Profiles`
    public static var libraryDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenVader/Profiles", isDirectory: true)
    }

    public static func library() -> [ProfileFile] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: libraryDirectory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "ovprofile" }
            .compactMap { try? decode(Data(contentsOf: $0)) }
            .sorted { $0.saved > $1.saved }
    }

    public var libraryURL: URL { Self.libraryDirectory.appendingPathComponent("\(id.uuidString).ovprofile") }

    public func saveToLibrary() throws {
        try FileManager.default.createDirectory(at: Self.libraryDirectory, withIntermediateDirectories: true)
        try encoded().write(to: libraryURL, options: .atomic)
    }

    public func removeFromLibrary() throws {
        try FileManager.default.removeItem(at: libraryURL)
    }
}

import Foundation
import VaderKit

/// Macros saved on the Mac, to reuse across profiles:
/// `~/Library/Application Support/OpenVader/Macros.json`.
enum MacroLibrary {
    static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenVader/Macros.json")
    }

    static func load() -> [Macro] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Macro].self, from: data)) ?? []
    }

    static func save(_ macros: [Macro]) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(macros).write(to: url, options: .atomic)
    }
}

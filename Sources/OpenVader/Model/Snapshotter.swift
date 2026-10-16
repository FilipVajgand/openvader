import AppKit
import SwiftUI

/// `--snapshot <dir>`: renders every pane of the main window to PNG and quits.
/// Used for README screenshots and for checking layouts without a screen recorder.
@MainActor
enum Snapshotter {
    static var directory: URL? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[i + 1], isDirectory: true)
    }

    static func run(model: AppModel) {
        guard let dir = directory else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        Task { @MainActor in
            while !model.isConnected { try? await Task.sleep(for: .milliseconds(200)) }
            NSApp.appearance = NSAppearance(named: CommandLine.arguments.contains("--dark") ? .darkAqua : .aqua)
            for pane in Pane.allCases {
                model.section = pane
                try? await Task.sleep(for: .milliseconds(1500))
                capture(to: dir.appendingPathComponent("\(pane.rawValue).png"))
            }
            NSApp.terminate(nil)
        }
    }

    static func capture(to url: URL) {
        guard let window = NSApp.windows.first(where: { $0.canBecomeMain }),
              let view = window.contentView else { return }
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        view.cacheDisplay(in: bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

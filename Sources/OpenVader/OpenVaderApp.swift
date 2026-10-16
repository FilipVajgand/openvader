import AppKit
import SwiftUI
import VaderKit

@main
struct OpenVaderApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("OpenVader") {
            ContentView()
                .environment(model)
                .frame(minWidth: 1120, minHeight: 720)
                .onAppear { Snapshotter.run(model: model) }
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .saveItem) {
                Button("Save to Controller") { model.save() }
                    .keyboardShortcut("s")
                    .disabled(!model.hasUnsavedChanges || !model.canWrite)
                Button("Revert Changes") { model.revert() }
                    .disabled(!model.hasUnsavedChanges)
            }
            CommandGroup(after: .saveItem) {
                Divider()
                Button("Back Up Controller") { model.backupNow() }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
                    .disabled(!model.isConnected)
                Button("Reload from Controller") { model.reloadAll() }
                    .keyboardShortcut("r")
                    .disabled(!model.isConnected)
            }
            CommandMenu("Profile") {
                ForEach(0..<4, id: \.self) { i in
                    Button("Profile \(i + 1)") { model.selectProfile(i) }
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")))
                        .disabled(!model.isConnected)
                }
            }
        }

        MenuBarExtra {
            MenuBarContent().environment(model)
        } label: {
            Image(systemName: model.isConnected ? "gamecontroller.fill" : "gamecontroller")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // A SwiftPM executable starts as a background process; make it a regular app.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

struct MenuBarContent: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let info = model.info, model.isConnected {
            Text("\(info.modelName) · \(info.batteryDescription)")
            Text(model.connectionKind.rawValue)
            Divider()
            ForEach(0..<4, id: \.self) { i in
                Button {
                    model.selectProfile(i)
                } label: {
                    if model.versions?.active == i {
                        Label(model.profileName(i), systemImage: "checkmark")
                    } else {
                        Text(model.profileName(i))
                    }
                }
            }
        } else {
            Text("No controller connected")
        }
        Divider()
        Button("Open OpenVader") {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
        }
        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

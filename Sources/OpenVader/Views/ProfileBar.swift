import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VaderKit

/// Name and tools for the selected profile, shown above every profile page.
struct ProfileBar: View {
    @Environment(AppModel.self) private var model
    @State private var confirmReset = false
    @State private var showLibrary = false
    @State private var naming: String?

    var body: some View {
        if let draft = model.draft {
            HStack(spacing: 10) {
                Text("Profile \(model.selectedProfile + 1)")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                TextField("Name", text: Binding(
                    get: { draft.mapping.name },
                    set: { model.draft?.mapping.name = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .help("Up to 10 characters, stored on the controller")
                if model.versions?.active == model.selectedProfile {
                    Label("Running", systemImage: "dot.radiowaves.left.and.right")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Menu("Copy to Profile") {
                        ForEach(0..<4, id: \.self) { i in
                            if i != model.selectedProfile {
                                Button("Profile \(i + 1) – \(model.profileName(i))") { model.copySelectedProfile(to: i) }
                            }
                        }
                    }
                    Divider()
                    Button("Save to Library…") { naming = draft.mapping.name }
                    Button("Load from Library…") { showLibrary = true }
                    Divider()
                    Button("Export…") { export() }
                    Button("Import…") { importFile() }
                    Divider()
                    Button("Reset to Factory Settings…", role: .destructive) { confirmReset = true }
                } label: {
                    Label("Profile", systemImage: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(model.busy != nil)
            }
            .confirmationDialog("Reset profile \(model.selectedProfile + 1) to factory settings?", isPresented: $confirmReset) {
                Button("Reset", role: .destructive) { model.resetSelectedProfile() }
            } message: {
                Text("Its buttons, sticks, triggers, gyro, vibration, lighting, macros and name go back to how the controller shipped. It is written immediately; a backup exists from when you connected.")
            }
            .sheet(isPresented: $showLibrary) { LibrarySheet() }
            .sheet(isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
                NameSheet(title: "Save to Library", name: naming ?? "") { name in
                    model.saveToLibrary(name: name)
                    naming = nil
                } cancel: { naming = nil }
            }
        }
    }

    private func export() {
        guard let file = model.profileFile(named: model.profileName(model.selectedProfile)) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "ovprofile") ?? .json]
        panel.nameFieldStringValue = "\(file.name).ovprofile"
        if panel.runModal() == .OK, let url = panel.url {
            do { try file.encoded().write(to: url, options: .atomic) } catch { model.errorMessage = error.localizedDescription }
        }
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "ovprofile") ?? .json, .json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            model.load(try ProfileFile.decode(Data(contentsOf: url)))
        } catch {
            model.errorMessage = "That file is not an OpenVader profile."
        }
    }
}

struct LibrarySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Profile Library").font(.title2.weight(.semibold))
            Text("Profiles saved on this Mac. Loading one replaces the selected profile's unsaved settings; save to write it to the controller.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if model.profileLibrary.isEmpty {
                Text("Nothing saved yet. Use Profile → Save to Library.").foregroundStyle(.secondary).padding(.vertical, 20)
            }
            List {
                ForEach(model.profileLibrary) { file in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(file.name).font(.headline)
                            Text(file.saved.formatted(date: .abbreviated, time: .shortened)
                                 + (file.host == nil ? "" : " · keyboard & mouse"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Load") {
                            model.load(file)
                            dismiss()
                        }
                        Button(role: .destructive) { model.removeFromLibrary(file) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
            }
            .frame(minHeight: 220)
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

struct NameSheet: View {
    var title: String
    @State var name: String
    var save: (String) -> Void
    var cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.title2.weight(.semibold))
            TextField("Name", text: $name).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                Button("Save") { save(name.trimmingCharacters(in: .whitespaces)) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}

/// Explains and requests what keyboard/mouse features need on the Mac.
struct HostAccessBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let d = model.draft, !d.host.isEmpty {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: model.hostPermission ? "keyboard.badge.ellipsis" : "lock.shield")
                    .font(.title3)
                    .foregroundStyle(model.hostPermission ? Color.accentColor : .orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.hostPermission
                         ? "Keyboard and mouse actions run on this Mac"
                         : "Allow OpenVader to control the keyboard and mouse")
                        .font(.callout.weight(.semibold))
                    Text(model.hostPermission
                         ? "They work while OpenVader is running (it stays in the menu bar) and the controller is on the receiver or cable."
                         : "Turn OpenVader on under Privacy & Security → Accessibility. If it is already on, a newer copy of the app needs it again: remove it with −, then click Allow… once more.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if !model.hostPermission {
                    Button("Allow…") { model.requestHostPermission() }
                } else if model.hostEngineRunning {
                    Label("Active", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill((model.hostPermission ? Color.accentColor : .orange).opacity(0.08)))
        }
    }
}

/// Picks a keyboard key, by menu or by pressing it.
struct KeyStrokePicker: View {
    @Binding var stroke: KeyStroke
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Menu(stroke.name) {
                ForEach(KeyStroke.catalog, id: \.group) { group in
                    Menu(group.group) {
                        ForEach(group.keys, id: \.self) { code in
                            Button(KeyStroke.names[code] ?? "\(code)") { stroke = KeyStroke(code, modifiers: stroke.modifiers) }
                        }
                    }
                }
            }
            .frame(width: 130)
            Button(recording ? "Press a key…" : "Record") { recording ? stop() : start() }
            ForEach([("⌘", KeyStroke.Modifiers.command), ("⌥", .option), ("⌃", .control), ("⇧", .shift)], id: \.0) { label, mod in
                Toggle(label, isOn: Binding(get: { stroke.modifiers.contains(mod) }, set: { on in
                    if on { stroke.modifiers.insert(mod) } else { stroke.modifiers.remove(mod) }
                }))
                .toggleStyle(.button)
                .help("Hold \(label) with the key")
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            var mods: KeyStroke.Modifiers = []
            if event.modifierFlags.contains(.command) { mods.insert(.command) }
            if event.modifierFlags.contains(.option) { mods.insert(.option) }
            if event.modifierFlags.contains(.control) { mods.insert(.control) }
            if event.modifierFlags.contains(.shift) { mods.insert(.shift) }
            stroke = KeyStroke(event.keyCode, modifiers: mods)
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

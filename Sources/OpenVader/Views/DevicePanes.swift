import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VaderKit

struct LiveTestView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let s = model.input
        Page(title: "Live test",
             subtitle: "Raw input straight from the controller, before any mapping. Use it to check every button, stick drift and the motion sensor.") {
            HStack(alignment: .top, spacing: 18) {
                Card("Controller", symbol: "gamecontroller") {
                    ControllerDiagram(pressed: s.buttons, leftStick: s.leftStick, rightStick: s.rightStick,
                                      leftTrigger: s.leftTrigger, rightTrigger: s.rightTrigger)
                        .frame(minHeight: 320)
                    Text(s.buttons.isEmpty ? "Press any button" : "Pressed: " + ControllerKey.allCases.filter { s.buttons.contains($0) }.map(\.name).joined(separator: ", "))
                        .foregroundStyle(.secondary)
                    if !s.unknownBits.isEmpty {
                        Text("Unknown input bits: " + s.unknownBits.map { String(format: "byte %d: 0x%02X", $0.key, $0.value) }.joined(separator: ", "))
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                VStack(spacing: 18) {
                    Card("Sticks", symbol: "dot.circle.and.hand.point.up.left.fill") {
                        HStack(spacing: 18) {
                            VStack {
                                StickDot(value: s.leftStick).frame(width: 110, height: 110)
                                Text(String(format: "%+.3f  %+.3f", s.leftStick.x, s.leftStick.y)).font(.caption).monospacedDigit()
                            }
                            VStack {
                                StickDot(value: s.rightStick).frame(width: 110, height: 110)
                                Text(String(format: "%+.3f  %+.3f", s.rightStick.x, s.rightStick.y)).font(.caption).monospacedDigit()
                            }
                        }
                        HStack {
                            Text("LT").font(.caption); LevelBar(value: s.leftTrigger)
                            Text("RT").font(.caption); LevelBar(value: s.rightTrigger)
                        }
                    }
                    Card("Motion", symbol: "gyroscope") {
                        MotionReadout(gyro: s.gyro, accel: s.accel)
                    }
                    Card("Rumble", symbol: "waveform.path") {
                        HStack {
                            Button("Grips") { model.rumble(gripLeft: 200, gripRight: 200) }
                            Button("Triggers") { model.rumble(gripLeft: 0, gripRight: 0, triggerLeft: 200, triggerRight: 200) }
                        }
                    }
                    Text("\(model.inputRate) reports/s").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                .frame(width: 300)
            }
        }
        .listensToInput()
    }
}

struct ControllerSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmSwitch = false

    var body: some View {
        Page(title: "Controller",
             subtitle: "Settings that apply to the whole controller, whichever profile is running.") {
            if let info = model.info {
                Card("About", symbol: "info.circle") {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                        row("Model", "\(info.modelName) (type \(info.deviceType))")
                        row("Connection", model.connectionKind.rawValue)
                        row("Battery", info.batteryDescription)
                        row("Firmware", info.firmware)
                        row("Receiver", info.receiverFirmware)
                        row("SI chip", info.siFirmware)
                        row("RF chip", info.rfFirmware)
                        row("Profile layout", model.draft.map { $0.mapping.layoutDescription })
                        row("USB", String(format: "%04X:%04X", VaderUSB.vendorID, model.productID))
                    }
                    Text("Firmware updates still need Flydigi Space Station on Windows.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if let hw = model.hardware {
                Card("Power", symbol: "powersleep") {
                    Picker("Sleep after", selection: Binding(get: { hw.sleepMinutes }, set: { model.setSleep($0) })) {
                        ForEach(HardwareStatus.sleepChoices, id: \.minutes) { Text($0.label).tag($0.minutes) }
                        if !HardwareStatus.sleepChoices.contains(where: { $0.minutes == hw.sleepMinutes }) {
                            Text("\(hw.sleepMinutes) minutes").tag(hw.sleepMinutes)
                        }
                    }
                    .frame(maxWidth: 320)
                    .disabled(model.busy != nil)
                }

                Card("Features", symbol: "switch.2") {
                    let features = DeviceFeature.allCases.filter { hw.supported.contains($0) && !$0.help.isEmpty }
                    if features.isEmpty { Text("The controller reports no switchable features.").foregroundStyle(.secondary) }
                    ForEach(features) { f in
                        Toggle(isOn: Binding(get: { hw.enabled.contains(f) }, set: { model.setFeature(f, $0) })) {
                            VStack(alignment: .leading) {
                                Text(f.title)
                                Text(f.help).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .disabled(model.busy != nil)
                    }
                }
            }

            if let report = model.dataReport {
                Card("Steam and SDL games", symbol: "arrow.triangle.branch") {
                    Toggle(isOn: Binding(get: { report.thirdPartyControl }, set: { model.setThirdParty($0) })) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Allow apps to take over the controller")
                            Text("Lets Steam and games built on SDL 3 read the controller directly over USB, with paddles, extra buttons and gyro. On a Mac the receiver does not show up as a normal gamepad, so this is how those games see it at all. While an app holds the controller, that app does the mapping.")
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .disabled(model.busy != nil || (model.info?.firmwareNumbers ?? []).lexicographicallyPrecedes([7, 1, 4, 1]))
                    if (model.info?.firmwareNumbers ?? []).lexicographicallyPrecedes([7, 1, 4, 1]) {
                        Text("Needs firmware 7.1.4.1 or newer.").font(.caption).foregroundStyle(.orange)
                    }
                    if !report.controlledBy.isEmpty {
                        Label("Currently held by \(report.controlledBy)", systemImage: "hand.raised").font(.caption)
                    }
                }
            }

            Card("Nintendo Switch mode", symbol: "rectangle.on.rectangle") {
                Text("In Switch mode the controller uses a separate profile, which can be written but not read back. Copy the selected profile, \(model.profileName(model.selectedProfile)), into it.")
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Use for Switch Mode…") { confirmSwitch = true }
                        .disabled(model.busy != nil || model.hasUnsavedChanges)
                }
                if model.hasUnsavedChanges {
                    Text("Save your changes first.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .confirmationDialog("Replace the Switch mode profile?", isPresented: $confirmSwitch) {
                Button("Copy \(model.profileName(model.selectedProfile))") { model.copyToSwitchMode() }
            } message: {
                Text("Keyboard bindings are dropped because Switch mode cannot use them.")
            }
        }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String?) -> some View {
        if let value {
            GridRow {
                Text(label).foregroundStyle(.secondary)
                Text(value).textSelection(.enabled)
            }
        }
    }
}

struct BackupFile: Identifiable, Hashable {
    var url: URL
    var date: Date
    var id: URL { url }
}

struct BackupsView: View {
    @Environment(AppModel.self) private var model
    @State private var files: [BackupFile] = []
    @State private var pending: (DeviceBackup, URL)?
    @State private var profileChoice = -1

    var body: some View {
        Page(title: "Backups",
             subtitle: "OpenVader saves a full copy of all four profiles every time the controller connects. Restore any of them here.") {
            Card("Back up", symbol: "externaldrive.badge.plus") {
                HStack {
                    Button("Back Up Now") { model.backupNow() }
                    Button("Export…") { export() }
                    Button("Restore from File…") { importFile() }
                    Spacer()
                    Button("Show in Finder") {
                        try? FileManager.default.createDirectory(at: DeviceBackup.defaultDirectory, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(DeviceBackup.defaultDirectory)
                    }
                }
                .disabled(model.busy != nil)
            }
            Card("Saved backups", symbol: "clock.arrow.circlepath") {
                if files.isEmpty { Text("None yet.").foregroundStyle(.secondary) }
                ForEach(files) { f in
                    HStack {
                        Image(systemName: f.url.lastPathComponent.hasPrefix("auto-") ? "clock" : "externaldrive")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading) {
                            Text(f.date.formatted(date: .abbreviated, time: .standard))
                            Text(f.url.lastPathComponent).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Restore…") { load(f.url) }.disabled(model.busy != nil)
                    }
                    Divider()
                }
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: model.lastBackupURL) { refresh() }
        .onChange(of: model.busy) { refresh() }
        .sheet(isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            if let (backup, url) = pending {
                RestoreSheet(backup: backup, url: url) { only in
                    pending = nil
                    model.restore(backup, only: only)
                } cancel: { pending = nil }
            }
        }
    }

    private func refresh() {
        let dir = DeviceBackup.defaultDirectory
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        files = urls.filter { $0.pathExtension == "json" }.map { url in
            BackupFile(url: url, date: (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }
        .sorted { $0.date > $1.date }
    }

    private func load(_ url: URL) {
        do {
            pending = (try DeviceBackup.decode(Data(contentsOf: url)), url)
        } catch {
            model.errorMessage = "That file is not an OpenVader backup: \(error.localizedDescription)"
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Vader5Pro-backup.json"
        if panel.runModal() == .OK, let url = panel.url { model.backupNow(to: url) }
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url { load(url) }
    }
}

struct RestoreSheet: View {
    var backup: DeviceBackup
    var url: URL
    var restore: (Set<Int>?) -> Void
    var cancel: () -> Void
    @State private var choice = -1

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Restore backup").font(.title2.weight(.semibold))
            Text("\(backup.model), firmware \(backup.firmware ?? "?"), saved \(backup.created.formatted(date: .abbreviated, time: .shortened)).")
                .foregroundStyle(.secondary)
            Picker("Restore", selection: $choice) {
                Text("All four profiles").tag(-1)
                ForEach(backup.profiles, id: \.index) { p in
                    Text("Profile \(p.index + 1)\(p.name.isEmpty ? "" : " – \(p.name)")").tag(p.index)
                }
            }
            .pickerStyle(.radioGroup)
            Text("The controller's current state is backed up first, so this can be undone.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                Button("Restore") { restore(choice < 0 ? nil : [choice]) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

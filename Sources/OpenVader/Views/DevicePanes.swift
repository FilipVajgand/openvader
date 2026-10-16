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
                    CircularityTest(left: s.leftStick, right: s.rightStick)
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
    @State private var nameDraft: String?

    var body: some View {
        Page(title: "Controller",
             subtitle: "Settings that apply to the whole controller, whichever profile is running.") {
            if let info = model.info {
                Card("About", symbol: "info.circle") {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                        row("Model", "\(info.modelName) (type \(info.deviceType))")
                        GridRow {
                            Text("Name").foregroundStyle(.secondary)
                            HStack {
                                TextField("No name", text: Binding(
                                    get: { nameDraft ?? model.nickname ?? "" }, set: { nameDraft = $0 }))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 200)
                                    .onSubmit(saveName)
                                if let n = nameDraft, n != (model.nickname ?? "") {
                                    Button("Rename", action: saveName).disabled(n.trimmingCharacters(in: .whitespaces).isEmpty)
                                }
                            }
                        }
                        row("Connection", model.connectionKind.rawValue)
                        row("Battery", info.batteryDescription)
                        row("Firmware", info.firmware)
                        row("Receiver", info.receiverFirmware)
                        row("SI chip", info.siFirmware)
                        row("RF chip", info.rfFirmware)
                        row("Profile layout", model.draft.map { $0.mapping.layoutDescription })
                        row("USB", String(format: "%04X:%04X", VaderUSB.vendorID, model.productID))
                    }
                }
                FirmwareCard()
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

                if hw.precisionAdjustable || hw.sensitivityAdjustable {
                    Card("Sticks", symbol: "dot.circle.and.hand.point.up.left.fill") {
                        if hw.precisionAdjustable {
                            Picker("Precision", selection: Binding(get: { hw.joystickPrecision }, set: { model.setPrecision($0) })) {
                                ForEach(HardwareStatus.precisionChoices, id: \.code) { Text($0.label).tag($0.code) }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 420)
                            Text("The smallest step a stick reports to games. Higher is finer.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if hw.sensitivityAdjustable {
                            Picker("Center sensitivity", selection: Binding(
                                get: { hw.joystickSensitivity }, set: { model.setSensitivity($0) })) {
                                ForEach(HardwareStatus.sensitivityChoices, id: \.value) { Text($0.label).tag($0.value) }
                                if !HardwareStatus.sensitivityChoices.contains(where: { $0.value == hw.joystickSensitivity }) {
                                    Text("Custom (\(hw.joystickSensitivity))").tag(hw.joystickSensitivity)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 420)
                            Text("How eagerly the sticks respond around the center.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .disabled(model.busy != nil)
                }

                Card("Features", symbol: "switch.2") {
                    let features = DeviceFeature.allCases.filter { hw.supported.contains($0) && !$0.help.isEmpty }
                    if features.isEmpty { Text("The controller reports no switchable features.").foregroundStyle(.secondary) }
                    ForEach(features) { f in
                        let blocked = f.requires.map { !hw.enabled.contains($0) } ?? false
                        Toggle(isOn: Binding(get: { hw.enabled.contains(f) && !blocked }, set: { model.setFeature(f, $0) })) {
                            VStack(alignment: .leading) {
                                Text(f.title)
                                Text(f.help).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .disabled(model.busy != nil || blocked)
                    }
                }
            }

            if let report = model.dataReport {
                Card("Steam and SDL games", symbol: "arrow.triangle.branch") {
                    Toggle(isOn: Binding(get: { report.thirdPartyControl }, set: { model.setThirdParty($0) })) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Allow apps to take over the controller")
                            Text("Lets Steam and games built on SDL 3 read the controller directly over USB, with paddles, extra buttons and gyro. On a Mac the receiver does not show up as a normal gamepad, so this is how those games see it at all. While one of those apps is open, even in the background, it does the mapping and the controller's own profile is set aside.")
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

    private func saveName() {
        guard let n = nameDraft?.trimmingCharacters(in: .whitespaces), !n.isEmpty, n != model.nickname else { return }
        model.setNickname(n)
        nameDraft = nil
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

struct FirmwareCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Card("Firmware updates", symbol: "arrow.down.circle") {
            if let result = model.firmware {
                let updates = result.desktop.filter(\.isNewer)
                if updates.isEmpty {
                    Label("Up to date for Flydigi's desktop app.", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                } else {
                    ForEach(updates) { c in
                        Label("\(c.label): \(c.installed ?? "none") → \(c.latest)\(c.notes.isEmpty ? "" : " · \(c.notes)")",
                              systemImage: "arrow.up.circle.fill")
                    }
                    Text("Install with Flydigi Space Station on Windows. OpenVader never flashes firmware, because a failed flash can brick the controller.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if let web = result.webApp.first(where: { $0.chip == "main_chip" && $0.isNewer }) {
                    Divider()
                    Text("Flydigi also offers firmware \(web.latest) for its new browser app, Space Station 5.0 (Chrome or Edge, works on a Mac). That firmware switches the controller to a newer config format that OpenVader cannot write yet, and needs reconfiguring.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Link("Open Space Station 5.0", destination: URL(string: "https://space_station.flydigi.com/")!).font(.caption)
                }
            } else if let error = model.firmwareError {
                Text(error).foregroundStyle(.orange)
            } else {
                Text("Asks Flydigi's update service which firmware is current. Only the model and installed versions are sent.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                if model.checkingFirmware { ProgressView().controlSize(.small) }
                Button(model.firmware == nil ? "Check for Updates" : "Check Again") { model.checkFirmware() }
                    .disabled(model.checkingFirmware)
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

/// Roll each stick around its rim to see how round its range is.
struct CircularityTest: View {
    var left: SIMD2<Double>
    var right: SIMD2<Double>
    @State private var reach: [Side: [Double]] = [.left: Array(repeating: 0, count: 72), .right: Array(repeating: 0, count: 72)]

    var body: some View {
        Card("Circularity test", symbol: "circle.dashed", trailing: AnyView(Button("Reset") { clear() })) {
            Text("Roll each stick slowly around its edge a few times.").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 16) {
                ForEach(Side.allCases) { side in
                    let r = reach[side] ?? []
                    VStack(spacing: 4) {
                        Plot(reach: r).frame(width: 110, height: 110)
                        Text(summary(r)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onChange(of: left) { _, v in record(v, .left) }
        .onChange(of: right) { _, v in record(v, .right) }
    }

    private func record(_ v: SIMD2<Double>, _ side: Side) {
        let mag = (v.x * v.x + v.y * v.y).squareRoot()
        guard mag > 0.5 else { return }
        var angle = atan2(v.y, v.x)
        if angle < 0 { angle += 2 * .pi }
        let bucket = min(71, Int(angle / (2 * .pi) * 72))
        if mag > reach[side]![bucket] { reach[side]![bucket] = mag }
    }

    private func clear() {
        reach = [.left: Array(repeating: 0, count: 72), .right: Array(repeating: 0, count: 72)]
    }

    private func summary(_ r: [Double]) -> String {
        let filled = r.filter { $0 > 0 }
        guard !filled.isEmpty else { return "No data yet" }
        let error = filled.map { abs($0 - 1) }.reduce(0, +) / Double(filled.count)
        return String(format: "%d%% covered · avg error %.1f%%", filled.count * 100 / r.count, error * 100)
    }

    struct Plot: View {
        var reach: [Double]

        var body: some View {
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2 * 0.8
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: 2 * radius, height: 2 * radius)),
                           with: .color(.secondary.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                var path = Path()
                var started = false
                for (i, r) in reach.enumerated() where r > 0 {
                    let a = (Double(i) + 0.5) / Double(reach.count) * 2 * .pi
                    let p = CGPoint(x: c.x + cos(a) * r * radius, y: c.y - sin(a) * r * radius)
                    if started { path.addLine(to: p) } else { path.move(to: p); started = true }
                }
                if started { path.closeSubpath() }
                ctx.stroke(path, with: .color(.accentColor), lineWidth: 2)
            }
            .background(Circle().fill(.quaternary.opacity(0.5)))
        }
    }
}

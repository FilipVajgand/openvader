import Foundation
import Observation
import SwiftUI
import VaderKit

/// Editable copy of one profile.
struct ProfileDraft: Equatable {
    var mapping: MappingProfile
    var lighting: LightingConfig
    var macros: MacroStore
    /// Colours the lighting editor is working with.
    var lightingColors: [LEDColor]
    var lightingEffect: LightingEffect
    /// Keyboard and mouse actions OpenVader performs on the Mac.
    var host: HostProfileMappings

    init(_ s: ProfileSnapshot, host: HostProfileMappings = HostProfileMappings()) {
        mapping = s.mapping
        lighting = s.lighting
        macros = s.macros
        self.host = host
        let palette = s.lighting.paletteGuess
        lightingColors = palette.isEmpty ? [LEDColor(red: 0, green: 120, blue: 255)] : Array(palette.prefix(5))
        lightingEffect = s.lighting.effect ?? .factory
    }

    /// A button does something on the Mac (or stops doing so). The
    /// controller's slot is marked "keyboard/mouse" so games stop seeing it.
    mutating func setHostAction(_ action: HostAction?, for key: ControllerKey) {
        host.setAction(action, for: key)
        mapping.setBinding(ButtonBinding(action: action == nil ? .standard : .keyboardMouse), for: key)
    }

    /// A stick drives the Mac's pointer, keys or scrolling, or goes back to being a stick.
    mutating func setStickHost(_ settings: StickHostSettings?, _ side: Side) {
        let previous = host.stick(side)
        if var settings {
            if previous == nil { settings.savedDeadZone = mapping.stick(side).deadZone }
            host.setStick(settings, side)
            mapping.setStickHostControlled(true, side)
        } else {
            host.setStick(nil, side)
            mapping.setStickHostControlled(false, side, restoreDeadZone: previous?.savedDeadZone ?? 5)
        }
    }

    /// Motion moves the Mac's pointer, or not.
    mutating func setGyroMouse(_ settings: GyroMouseSettings?) {
        host.gyro = settings
        var g = mapping.gyro
        if settings != nil {
            g.target = .mouse
            g.enableKey = nil
            g.secondKey = nil
            g.deadZone = 0
        } else if g.target == .mouse {
            g.target = .off
            g.enableKey = .lt
        }
        mapping.gyro = g
    }

    /// Rebuilds the lighting frames from the editor's effect and colours.
    mutating func setLighting(effect: LightingEffect, colors: [LEDColor]) {
        lightingEffect = effect
        lightingColors = colors
        guard effect != .factory, lighting.isValid else { return }
        lighting.apply(effect, colors: colors)
    }
}

enum Pane: String, CaseIterable, Identifiable, Hashable {
    case buttons, sticks, triggers, gyro, vibration, lighting, macros, test, settings, backups
    var id: String { rawValue }

    var title: String {
        switch self {
        case .buttons: "Buttons"
        case .sticks: "Sticks"
        case .triggers: "Triggers"
        case .gyro: "Gyro"
        case .vibration: "Vibration"
        case .lighting: "Lighting"
        case .macros: "Macros"
        case .test: "Live test"
        case .settings: "Controller"
        case .backups: "Backups"
        }
    }

    var symbol: String {
        switch self {
        case .buttons: "circle.grid.cross"
        case .sticks: "dot.circle.and.hand.point.up.left.fill"
        case .triggers: "l2.button.roundedtop.horizontal"
        case .gyro: "gyroscope"
        case .vibration: "waveform.path"
        case .lighting: "light.max"
        case .macros: "repeat.circle"
        case .test: "gamecontroller"
        case .settings: "slider.horizontal.3"
        case .backups: "externaldrive.badge.timemachine"
        }
    }

    /// Sections that edit the selected profile.
    var isProfileSection: Bool {
        switch self {
        case .buttons, .sticks, .triggers, .gyro, .vibration, .lighting, .macros: true
        default: false
        }
    }
}

enum ConnectionState: Equatable {
    case searching
    case connecting
    case connected
    case failed(String)
}

@MainActor @Observable
final class AppModel {
    var state: ConnectionState = .searching
    var info: DeviceInfo?
    var connectionKind: ConnectionKind = .unknown
    var productID = 0
    var uid: String?
    var hardware: HardwareStatus?
    var dataReport: DataReportStatus?
    var versions: ProfileVersions?
    var saved: [ProfileSnapshot] = []
    var drafts: [Int: ProfileDraft] = [:]
    var selectedProfile = 0
    var section: Pane = .buttons

    var busy: String?
    var progress: Double?
    var errorMessage: String?
    var notice: String?

    /// Latest physical input, refreshed at display rate while anything listens.
    var input = InputState()
    var inputRate = 0
    var lastPressed: ControllerKey?
    var lastBackupURL: URL?

    var nickname: String?
    var firmware: FirmwareCheck.Result?
    var firmwareError: String?
    var checkingFirmware = false
    var hostPermission = HostEngine.hasPermission
    var hostEngineRunning = false
    var macroLibrary: [Macro] = MacroLibrary.load()
    var profileLibrary: [ProfileFile] = ProfileFile.library()

    @ObservationIgnored private var device: VaderDevice?
    @ObservationIgnored private let worker = DispatchQueue(label: "openvader.device", qos: .userInitiated)
    @ObservationIgnored private var watcher: DeviceWatcher?
    @ObservationIgnored private var pollTimer: Timer?
    @ObservationIgnored private var inputTimer: Timer?
    @ObservationIgnored private var inputListeners = 0
    @ObservationIgnored private let inputBox = InputBox()
    @ObservationIgnored private var hostStore = HostMappingStore.load()
    @ObservationIgnored let engine = HostEngine()
    @ObservationIgnored private var engineListening = false

    init() {
        watcher = DeviceWatcher { [weak self] in
            MainActor.assumeIsolated { self?.devicesChanged() }
        }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        devicesChanged()
    }

    // MARK: Derived state

    var isConnected: Bool { state == .connected }

    var draft: ProfileDraft? {
        get { drafts[selectedProfile] }
        set { drafts[selectedProfile] = newValue }
    }

    var savedSnapshot: ProfileSnapshot? { saved.first { $0.index == selectedProfile } }

    /// Key under which host mappings are stored for this controller.
    var controllerKey: String { uid ?? "unknown" }

    func savedHost(_ profile: Int) -> HostProfileMappings {
        hostStore.mappings(controller: controllerKey, profile: profile)
    }

    func isDirty(_ profile: Int) -> Bool {
        guard let d = drafts[profile], let s = saved.first(where: { $0.index == profile }) else { return false }
        return d.mapping != s.mapping || d.lighting != s.lighting || d.macros != s.macros || d.host != savedHost(profile)
    }

    var hasUnsavedChanges: Bool { isDirty(selectedProfile) }

    var canWrite: Bool {
        guard let d = draft else { return false }
        return d.mapping.isLayoutSupported && busy == nil
    }

    func profileName(_ i: Int) -> String {
        let name = drafts[i]?.mapping.name ?? saved.first { $0.index == i }?.mapping.name ?? ""
        return name.isEmpty ? "Profile \(i + 1)" : name
    }

    // MARK: Connection

    private func devicesChanged() {
        if device?.connection.isRemoved == true { disconnected() }
        if device == nil, state != .connecting { connect() }
    }

    private func poll() {
        guard let device else {
            if state != .connecting { connect() }
            return
        }
        if device.connection.isRemoved { disconnected(); return }
        let permission = HostEngine.hasPermission
        if permission != hostPermission {
            hostPermission = permission
            updateEngine()
        }
        guard busy == nil else { return }
        worker.async { [weak self] in
            let info = try? device.readInfo()
            let versions = try? device.profileVersions()
            DispatchQueue.main.async {
                guard let self else { return }
                if let info { self.info = info }
                if let versions {
                    let changed = versions.active != self.versions?.active
                    self.versions = versions
                    // Follow profile switches made on the controller itself.
                    if changed, self.busy == nil, !self.hasUnsavedChanges { self.selectedProfile = versions.active }
                    if changed { self.updateEngine() }
                }
            }
        }
    }

    /// `--demo` (or OPENVADER_DEMO=1) runs against the built-in emulator.
    nonisolated static let demo = CommandLine.arguments.contains("--demo") || ProcessInfo.processInfo.environment["OPENVADER_DEMO"] != nil

    func connect() {
        guard Self.demo || HIDDiscovery.controllers().first != nil else {
            if case .failed = state { return }
            state = .searching
            return
        }
        state = .connecting
        worker.async { [weak self] in
            do {
                let vader: VaderDevice
                if Self.demo {
                    vader = VaderDevice(connection: VirtualVader(), connectionKind: .dongle)
                    _ = try vader.handshake()
                } else {
                    vader = try VaderDevice.openFirst()
                }
                let info = try vader.readInfo()
                let uid = try? vader.readUID()
                let hardware = try? vader.hardwareStatus()
                let report = try? vader.dataReportStatus()
                let versions = try vader.profileVersions()
                let snapshots = try vader.readAllSnapshots()
                let nickname = try? vader.readNickname()
                let backup = DeviceBackup(info: info, uid: uid, snapshots: snapshots)
                let backupURL = Self.demo ? nil : try? Self.autoBackup(backup)
                DispatchQueue.main.async {
                    guard let self else { vader.close(); return }
                    self.device = vader
                    vader.connection.onRemoval = { [weak self] in
                        DispatchQueue.main.async { self?.disconnected() }
                    }
                    let box = self.inputBox, engine = self.engine
                    vader.connection.onInputReport = { report in
                        guard let state = InputState(report: report) else { return }
                        box.store(state)
                        engine.process(state)
                    }
                    self.info = info
                    self.uid = uid
                    self.connectionKind = vader.connectionKind
                    self.productID = vader.connection.info.productID
                    self.hardware = hardware
                    self.dataReport = report
                    self.versions = versions
                    self.nickname = nickname ?? nil
                    self.saved = snapshots
                    self.resetDrafts()
                    self.selectedProfile = versions.active
                    self.lastBackupURL = backupURL
                    self.state = .connected
                    if self.inputListeners > 0 { self.setStream(true) }
                    self.updateEngine()
                }
            } catch {
                DispatchQueue.main.async {
                    self?.state = .failed((error as? LocalizedError)?.errorDescription ?? "\(error)")
                }
            }
        }
    }

    func retry() {
        state = .searching
        connect()
    }

    private func disconnected() {
        engine.stop()
        hostEngineRunning = false
        if engineListening {
            engineListening = false
            listen(false)
        }
        let old = device
        device = nil
        worker.async { old?.close() }
        info = nil
        hardware = nil
        dataReport = nil
        versions = nil
        saved = []
        drafts = [:]
        busy = nil
        progress = nil
        state = .searching
    }

    /// One automatic backup per connection, keeping the 20 newest.
    nonisolated private static func autoBackup(_ backup: DeviceBackup) throws -> URL {
        let url = try backup.saveToDefaultLocation(label: "auto")
        let dir = DeviceBackup.defaultDirectory
        let autos = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
            .filter { $0.lastPathComponent.hasPrefix("auto-") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent } ?? []
        for old in autos.dropFirst(20) { try? FileManager.default.removeItem(at: old) }
        return url
    }

    // MARK: Device work

    /// Runs blocking device work off the main thread with a busy indicator.
    func perform<T>(
        _ label: String, showsProgress: Bool = false,
        _ work: @escaping (VaderDevice, @escaping (Double) -> Void) throws -> T,
        then done: @escaping (T) -> Void = { _ in }
    ) {
        guard let device, busy == nil else { return }
        busy = label
        progress = showsProgress ? 0 : nil
        errorMessage = nil
        worker.async { [weak self] in
            let report: (Double) -> Void = { p in DispatchQueue.main.async { self?.progress = showsProgress ? p : nil } }
            let result = Result { try work(device, report) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = nil
                self.progress = nil
                switch result {
                case .success(let value): done(value)
                case .failure(let error):
                    self.errorMessage = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                }
            }
        }
    }

    func selectProfile(_ i: Int) {
        guard i != selectedProfile || versions?.active != i else { return }
        selectedProfile = i
        guard versions?.active != i else { return }
        perform("Switching to profile \(i + 1)…") { device, _ in
            try device.activate(profile: i)
            return try device.profileVersions()
        } then: { self.versions = $0 }
    }

    func save() {
        let i = selectedProfile
        guard let d = draft, let s = savedSnapshot else { return }
        let mapping = d.mapping != s.mapping ? d.mapping : nil
        let lighting = d.lighting != s.lighting ? d.lighting : nil
        let macros = d.macros != s.macros ? d.macros : nil
        perform("Saving profile \(i + 1)…", showsProgress: true) { device, progress in
            let snapshot = try device.commit(profile: i, mapping: mapping, lighting: lighting, macros: macros, progress: progress)
            return (snapshot, try device.profileVersions())
        } then: { snapshot, versions in
            self.hostStore.set(d.host, controller: self.controllerKey, profile: i)
            try? self.hostStore.save()
            self.replaceSaved(snapshot)
            self.drafts[i] = self.makeDraft(snapshot)
            self.versions = versions
            self.notice = "Saved to the controller and verified."
            self.updateEngine()
        }
    }

    func revert() {
        guard let s = savedSnapshot else { return }
        drafts[selectedProfile] = makeDraft(s)
    }

    func makeDraft(_ s: ProfileSnapshot) -> ProfileDraft {
        ProfileDraft(s, host: savedHost(s.index))
    }

    private func resetDrafts() {
        drafts = Dictionary(uniqueKeysWithValues: saved.map { ($0.index, makeDraft($0)) })
    }

    private func replaceSaved(_ s: ProfileSnapshot) {
        if let i = saved.firstIndex(where: { $0.index == s.index }) { saved[i] = s } else { saved.append(s) }
    }

    func reloadAll() {
        perform("Reading profiles…", showsProgress: true) { device, progress in
            (try device.readAllSnapshots(progress: progress), try device.profileVersions(), try device.hardwareStatus())
        } then: { snapshots, versions, hardware in
            self.saved = snapshots
            self.resetDrafts()
            self.versions = versions
            self.hardware = hardware
        }
    }

    // MARK: Settings

    func setSleep(_ minutes: Int) {
        perform("Updating sleep time…") { device, _ in
            try device.setSleepTime(minutes: minutes)
            return try device.hardwareStatus()
        } then: { self.hardware = $0 }
    }

    func setFeature(_ f: DeviceFeature, _ on: Bool) {
        perform("Updating \(f.title.lowercased())…") { device, _ in
            try device.setFeature(f, enabled: on)
            return try device.hardwareStatus()
        } then: { self.hardware = $0 }
    }

    func setThirdParty(_ on: Bool) {
        perform("Updating takeover setting…") { device, _ in
            try device.setDataReport(thirdParty: on)
            return try device.dataReportStatus()
        } then: { self.dataReport = $0 }
    }

    func copyToSwitchMode() {
        let i = selectedProfile
        perform("Copying to Switch mode…") { device, _ in
            try device.saveToSwitchMode(profile: i)
        } then: { self.notice = "Profile \(i + 1) is now the Nintendo Switch mode profile." }
    }

    func rumble(gripLeft: UInt8, gripRight: UInt8, triggerLeft: UInt8 = 0, triggerRight: UInt8 = 0, seconds: Double = 0.5) {
        guard let device else { return }
        worker.async {
            try? device.rumble(gripLeft: gripLeft, gripRight: gripRight, triggerLeft: triggerLeft, triggerRight: triggerRight)
            Thread.sleep(forTimeInterval: seconds)
            try? device.rumble(gripLeft: 0, gripRight: 0)
        }
    }

    func setPrecision(_ code: Int) {
        perform("Updating stick precision…") { device, _ in
            try device.setJoystickPrecision(code)
            return try device.hardwareStatus()
        } then: { self.hardware = $0 }
    }

    func setSensitivity(_ value: Int) {
        perform("Updating center sensitivity…") { device, _ in
            try device.setJoystickSensitivity(value)
            return try device.hardwareStatus()
        } then: { self.hardware = $0 }
    }

    func setNickname(_ name: String) {
        perform("Renaming the controller…") { device, _ in
            try device.writeNickname(name)
            return try device.readNickname()
        } then: { self.nickname = $0 }
    }

    func checkFirmware() {
        guard let info, !checkingFirmware else { return }
        checkingFirmware = true
        firmwareError = nil
        Task {
            do {
                firmware = try await FirmwareCheck.check(info)
            } catch {
                firmwareError = "Could not reach Flydigi's update service: \(error.localizedDescription)"
            }
            checkingFirmware = false
        }
    }

    // MARK: Profile tools

    /// Writes the factory profile, lighting and macros into the selected slot.
    func resetSelectedProfile() {
        let i = selectedProfile
        perform("Resetting profile \(i + 1)…", showsProgress: true) { device, progress in
            (try device.resetToFactory(profile: i, progress: progress), try device.profileVersions())
        } then: { snapshot, versions in
            self.hostStore.set(HostProfileMappings(), controller: self.controllerKey, profile: i)
            try? self.hostStore.save()
            self.replaceSaved(snapshot)
            self.drafts[i] = self.makeDraft(snapshot)
            self.versions = versions
            self.notice = "Profile \(i + 1) is back to factory settings."
            self.updateEngine()
        }
    }

    /// Copies the selected profile's draft into another slot, as unsaved changes there.
    func copySelectedProfile(to target: Int) {
        guard let source = draft, target != selectedProfile, var t = drafts[target] else { return }
        let tag = t.mapping.dataVersion
        t.mapping = source.mapping
        t.mapping.dataVersion = tag
        t.lighting = source.lighting
        t.lightingColors = source.lightingColors
        t.lightingEffect = source.lightingEffect
        t.macros = source.macros
        t.host = source.host
        drafts[target] = t
        selectProfile(target)
        notice = "Copied into profile \(target + 1). Save to write it to the controller."
    }

    func profileFile(named name: String) -> ProfileFile? {
        guard let d = draft else { return nil }
        return ProfileFile(name: name, deviceType: info?.deviceType ?? 130, mapping: d.mapping,
                           lighting: d.lighting.isValid ? d.lighting : nil, macroBytes: try? d.macros.encoded(),
                           host: d.host.isEmpty ? nil : d.host)
    }

    func saveToLibrary(name: String) {
        guard let file = profileFile(named: name) else { return }
        do {
            try file.saveToLibrary()
            profileLibrary = ProfileFile.library()
            notice = "Saved \"\(name)\" to your profile library."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeFromLibrary(_ file: ProfileFile) {
        try? file.removeFromLibrary()
        profileLibrary = ProfileFile.library()
    }

    /// Loads a saved profile into the selected slot's draft.
    func load(_ file: ProfileFile) {
        guard var d = draft, let mapping = file.mappingProfile else { return }
        guard mapping.isLayoutSupported else {
            errorMessage = "That profile uses mapping layout \(mapping.layoutDescription), which OpenVader cannot write."
            return
        }
        let tag = d.mapping.dataVersion
        d.mapping = mapping
        d.mapping.dataVersion = tag
        if let l = file.lightingConfig, l.ledCount == d.lighting.ledCount, l.bytes.count == d.lighting.bytes.count {
            d.lighting = l
            let palette = l.paletteGuess
            d.lightingColors = palette.isEmpty ? d.lightingColors : Array(palette.prefix(5))
            d.lightingEffect = l.effect ?? .factory
        }
        if let m = file.macroStore, m.size == d.macros.size { d.macros = m }
        d.host = file.host ?? HostProfileMappings()
        draft = d
        notice = "Loaded \"\(file.name)\". Save to write it to the controller."
    }

    // MARK: Macro library

    func saveMacroToLibrary(_ macro: Macro) {
        macroLibrary.removeAll { $0.name == macro.name && $0.steps == macro.steps }
        macroLibrary.insert(macro, at: 0)
        MacroLibrary.save(macroLibrary)
        notice = "Saved \"\(macro.name)\" to your macro library."
    }

    /// Puts a macro on another profile's draft (replacing one on the same button).
    func copyMacro(_ macro: Macro, toProfile target: Int) {
        guard var d = drafts[target] else { return }
        d.macros.macros.removeAll { $0.trigger == macro.trigger }
        guard d.macros.macros.count < MacroStore.maxMacros else {
            errorMessage = "Profile \(target + 1) already holds \(MacroStore.maxMacros) macros."
            return
        }
        d.macros.macros.append(macro)
        if d.host.action(for: macro.trigger) != nil { d.host.setAction(nil, for: macro.trigger) }
        d.mapping.setBinding(ButtonBinding(action: .macro), for: macro.trigger)
        drafts[target] = d
        notice = "Copied to profile \(target + 1). Save that profile to write it."
    }

    func removeMacroFromLibrary(at index: Int) {
        guard macroLibrary.indices.contains(index) else { return }
        macroLibrary.remove(at: index)
        MacroLibrary.save(macroLibrary)
    }

    // MARK: Keyboard and mouse on the Mac

    var activeHostMappings: HostProfileMappings? {
        guard let active = versions?.active else { return nil }
        let m = savedHost(active)
        return m.isEmpty ? nil : m
    }

    func requestHostPermission() {
        HostEngine.requestPermission()
        hostPermission = HostEngine.hasPermission
        updateEngine()
    }

    /// Runs the engine while the running profile has Mac actions and access is granted.
    func updateEngine() {
        let mappings = isConnected && hostPermission ? activeHostMappings : nil
        engine.use(mappings)
        hostEngineRunning = mappings != nil
        if hostEngineRunning != engineListening {
            engineListening = hostEngineRunning
            listen(hostEngineRunning)
        }
    }

    // MARK: Backups

    func backupNow(to url: URL? = nil) {
        perform("Backing up…", showsProgress: true) { device, progress in
            let backup = try device.backup(progress: progress)
            if let url {
                try backup.encoded().write(to: url, options: .atomic)
                return url
            }
            return try backup.saveToDefaultLocation()
        } then: { url in
            self.lastBackupURL = url
            self.notice = "Backup saved: \(url.lastPathComponent)"
        }
    }

    func restore(_ backup: DeviceBackup, only: Set<Int>?) {
        perform("Restoring…", showsProgress: true) { device, progress in
            let safety = try device.backup()
            _ = try safety.saveToDefaultLocation(label: "before-restore")
            try device.restore(backup, only: only, progress: progress)
            return (try device.readAllSnapshots(), try device.profileVersions())
        } then: { snapshots, versions in
            self.saved = snapshots
            self.resetDrafts()
            self.versions = versions
            self.notice = "Restored and verified."
            self.updateEngine()
        }
    }

    // MARK: Live input

    /// Views that show live input call this on appear / disappear.
    func listen(_ on: Bool) {
        inputListeners = max(0, inputListeners + (on ? 1 : -1))
        let wanted = inputListeners > 0
        if wanted, inputTimer == nil {
            inputTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.pullInput() }
            }
            setStream(true)
        } else if !wanted, let t = inputTimer {
            t.invalidate()
            inputTimer = nil
            setStream(false)
        }
    }

    private func setStream(_ on: Bool) {
        guard let device else { return }
        worker.async { try? device.setInputStream(on) }
    }

    private var rateWindow: (Date, Int) = (.now, 0)

    private func pullInput() {
        let (state, count) = inputBox.take()
        if let state, state != input {
            let newly = state.buttons.subtracting(input.buttons)
            if let key = ControllerKey.allCases.first(where: { newly.contains($0) }) { lastPressed = key }
            input = state
        }
        let (start, base) = rateWindow
        if Date().timeIntervalSince(start) >= 1 {
            inputRate = count - base
            rateWindow = (.now, count)
        }
    }
}

/// Lock-protected mailbox between the HID queue and the main thread.
final class InputBox: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: InputState?
    private var count = 0

    func store(_ s: InputState) {
        lock.withLock {
            latest = s
            count += 1
        }
    }

    func take() -> (InputState?, Int) {
        lock.withLock { (latest, count) }
    }
}

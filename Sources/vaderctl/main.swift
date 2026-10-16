import Foundation
import VaderKit

let usage = """
    vaderctl — configure a Flydigi Vader 5 Pro from the command line

    Reading
      list                         Flydigi HID interfaces attached
      info                         identity, battery, firmware, settings
      profiles                     the four on-board profiles
      dump <1-4>                   raw bytes of one profile's stores
      monitor [seconds]            live input (sticks, buttons, gyro)

    Writing (every write is read back and verified)
      backup [file.json]           save all profiles (default: ~/Library/Application Support/OpenVader/Backups)
      restore <file.json> [1-4]    write a backup back, optionally one profile
      activate <1-4>               switch the running profile
      remap <1-4> <button> <target|default> [turbo <1-20>]
      light <1-4> <steady|breathing|strobe|gradient|rainbowFade|flow|comet|scanner|fire|off> [#RRGGBB ...] [brightness=0-100] [speed=1-255] [direction=left|right]
      stick <1-4> <left|right> [deadzone=0-100] [outer=0-100] [curve=linear|instant|delayed] [circular=on|off]
      trigger <1-4> <left|right> <start 0-255> <end 0-255>
      vibration <1-4> [grip=on|off] [left=on|off] [right=on|off] [left-gain=0-100] [right-gain=0-100]
      gyro <1-4> <off|left|right> [key=LT] [hold|toggle] [sensitivity=0-100] [deadzone=0-100]
      rename <1-4> <name>
      reset-profile <1-4>          put one profile back to factory settings
      name <text>                  the controller's own name
      precision <8|9|10|11|12>     stick precision in bits
      sensitivity <fast|medium|slow>   stick center sensitivity
      firmware                     ask Flydigi which firmware is current (never flashes)
      sleep <minutes, 0 = never>
      feature <name> <on|off>      names: \(DeviceFeature.allCases.map(cliName).joined(separator: ", "))
      third-party <on|off>         let Steam / SDL games take over the controller
      switch-mode <1-4>            copy a profile into the Nintendo Switch bank
      rumble [milliseconds]

    Buttons: \(ControllerKey.allCases.map(cliName).joined(separator: " "))
    Set OPENVADER_TRACE=1 to print every packet.
    """

func cliName(_ key: ControllerKey) -> String {
    switch key {
    case .select: "view"
    case .start: "menu"
    default: "\(key)"
    }
}

func cliName(_ f: DeviceFeature) -> String {
    switch f {
    case .fastProfileSwap: "quick-switch"
    case .xboxHomeButton: "xbox-home"
    case .motionDebounce: "gyro-debounce"
    case .turbo: "turbo"
    case .joystickDebounce: "stick-debounce"
    case .joystickAutoCalibration: "stick-autocal"
    case .joystickRebound: "stick-rebound"
    case .screenStatusBar: "screen-statusbar"
    case .screenOff: "screen-off"
    case .audio: "audio"
    }
}

func parseKey(_ s: String) -> ControllerKey? {
    let l = s.lowercased()
    return ControllerKey.allCases.first { cliName($0) == l || $0.name.lowercased() == l }
}

struct CLIError: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}

func profileArg(_ args: [String], _ i: Int) throws -> Int {
    guard args.count > i, let n = Int(args[i]), (1...4).contains(n) else { throw CLIError("expected a profile number 1-4") }
    return n - 1
}

func onOff(_ s: String?) throws -> Bool {
    switch s?.lowercased() {
    case "on", "true", "1", "yes": return true
    case "off", "false", "0", "no": return false
    default: throw CLIError("expected on or off")
    }
}

func options(_ args: ArraySlice<String>) -> [String: String] {
    var out: [String: String] = [:]
    for a in args {
        let parts = a.split(separator: "=", maxSplits: 1).map(String.init)
        out[parts[0].lowercased()] = parts.count > 1 ? parts[1] : ""
    }
    return out
}

func progressBar(_ label: String) -> (Double) -> Void {
    { f in
        let width = 30
        let filled = Int(f * Double(width))
        let bar = String(repeating: "█", count: filled) + String(repeating: "·", count: width - filled)
        FileHandle.standardError.write("\r\(label) \(bar) \(Int(f * 100))%".data(using: .utf8)!)
        if f >= 1 { FileHandle.standardError.write("\n".data(using: .utf8)!) }
    }
}

func printInfo(_ v: VaderDevice) throws {
    let info = try v.readInfo()
    print("Model          \(info.modelName) (type \(info.deviceType))")
    print("Connection     \(v.connectionKind.rawValue)   USB \(String(format: "%04x:%04x", v.connection.info.vendorID, v.connection.info.productID))")
    print("Battery        \(info.batteryDescription)")
    for (label, value) in [("Firmware", info.firmware), ("Receiver", info.receiverFirmware), ("SI chip", info.siFirmware),
                           ("RF chip", info.rfFirmware), ("Trigger", info.triggerFirmware)] {
        if let value { print("\(label.padding(toLength: 15, withPad: " ", startingAt: 0))\(value)") }
    }
    if let uid = try? v.readUID() { print("UID            \(uid)") }
    let status = try v.hardwareStatus()
    let sleep = HardwareStatus.sleepChoices.first { $0.minutes == status.sleepMinutes }?.label ?? "\(status.sleepMinutes) minutes"
    print("Sleep after    \(sleep)")
    print("Features")
    for f in DeviceFeature.allCases where status.supported.contains(f) {
        print("  \(cliName(f).padding(toLength: 18, withPad: " ", startingAt: 0)) \(status.enabled.contains(f) ? "on" : "off")   \(f.title)")
    }
    let report = try v.dataReportStatus()
    print("Third-party    \(report.thirdPartyControl ? "allowed" : "not allowed")\(report.controlledBy.isEmpty ? "" : ", held by \(report.controlledBy)")")
    let versions = try v.profileVersions()
    print("Active profile \(versions.active + 1)\(versions.switchModeActive ? " (Switch mode)" : "")")
}

func describe(_ s: ProfileSnapshot, active: Bool) {
    let m = s.mapping
    print("Profile \(s.index + 1)\(active ? "  ← active" : "")   \"\(m.name)\"   layout \(m.layoutDescription)\(m.isLayoutSupported ? "" : " (UNSUPPORTED)")   tag \(m.dataVersion)")
    let changed = ControllerKey.allCases.compactMap { k -> String? in
        let b = m.binding(for: k)
        return b.isDefault ? nil : "\(k.name) → \(b.describe(for: k))"
    }
    print("  Buttons   \(changed.isEmpty ? "all default" : changed.joined(separator: ", "))")
    for side in Side.allCases {
        let st = m.stick(side)
        print("  \(side.title) stick  \(st.curve.title), dead zone \(st.deadZone)%, outer \(st.outerDeadZone)%, \(st.circular ? "circular" : "square"), bank \(st.bank.map(String.init).joined(separator: " "))")
    }
    for side in Side.allCases {
        let t = m.trigger(side)
        print("  \(side.title) trigger travel \(t.start)…\(t.end)")
    }
    let g = m.gyro
    print("  Gyro      \(g.target.title)\(g.target == .off ? "" : ", \(g.activation.title.lowercased()) \(g.enableKey?.name ?? "none"), sensitivity \(g.sensitivity), dead zone \(g.deadZone)")")
    let grip = m.gripVibration
    print("  Rumble    grips \(grip.enabled ? "on" : "off") (L \(grip.left.minimum)-\(grip.left.maximum) ×\(grip.left.scale), R \(grip.right.minimum)-\(grip.right.maximum) ×\(grip.right.scale)), triggers \(m.triggerVibration.enabled ? "on" : "off")")
    let l = s.lighting
    if l.isValid {
        print("  Lighting  \(l.effect?.title ?? "mode \(l.effectRaw)"), brightness \(l.brightness), speed \(l.cycleTime), \(l.ledCount) LEDs × \(l.frameCount) frames, colors \(l.paletteGuess.prefix(5).map(\.hex).joined(separator: " "))")
    } else {
        print("  Lighting  unreadable (\(s.lighting.bytes.count) bytes)")
    }
    let macros = s.macros
    print("  Macros    \(macros.macros.isEmpty ? "none" : macros.macros.map { "\($0.trigger.name): \($0.steps.count) steps" }.joined(separator: ", "))   (\(s.macroBytes.count) bytes)")
}

func hexDump(_ bytes: [UInt8]) {
    for row in stride(from: 0, to: bytes.count, by: 20) {
        print(String(format: "  %4d  ", row) + bytes[row..<min(row + 20, bytes.count)].hexString)
    }
}

func run(_ args: [String]) throws {
    guard let command = args.first else { print(usage); return }
    if command == "help" || command == "-h" || command == "--help" { print(usage); return }

    if command == "list" {
        let all = HIDDiscovery.flydigiInterfaces()
        if all.isEmpty { print("No Flydigi HID interfaces attached.") }
        for (_, i) in all {
            print(String(format: "%04x:%04x  usage page 0x%04X/0x%02X  location 0x%08X  %@", i.vendorID, i.productID,
                         i.usagePage, i.usage, i.locationID, i.product))
        }
        return
    }

    let v = try VaderDevice.openFirst()
    defer { v.close() }

    switch command {
    case "info":
        try printInfo(v)

    case "profiles":
        let active = try v.profileVersions().active
        for s in try v.readAllSnapshots(progress: progressBar("Reading")) {
            describe(s, active: s.index == active)
            print("")
        }

    case "dump":
        let p = try profileArg(args, 1)
        let s = try v.readSnapshot(p)
        print("Mapping (\(s.mapping.bytes.count) bytes)"); hexDump(s.mapping.bytes)
        print("Lighting (\(s.lighting.bytes.count) bytes)"); hexDump(s.lighting.bytes)
        print("Macros (\(s.macroBytes.count) bytes)"); hexDump(s.macroBytes)

    case "backup":
        let backup = try v.backup(progress: progressBar("Reading"))
        let url: URL
        if args.count > 1 {
            url = URL(fileURLWithPath: args[1])
            try backup.encoded().write(to: url, options: .atomic)
        } else {
            url = try backup.saveToDefaultLocation()
        }
        print("Saved \(backup.profiles.count) profiles to \(url.path)")

    case "restore":
        guard args.count > 1 else { throw CLIError("restore needs a backup file") }
        let backup = try DeviceBackup.decode(Data(contentsOf: URL(fileURLWithPath: args[1])))
        let only = args.count > 2 ? Set([try profileArg(args, 2)]) : nil
        let safety = try v.backup(progress: progressBar("Safety backup"))
        print("Current state saved to \(try safety.saveToDefaultLocation(label: "before-restore").path)")
        try v.restore(backup, only: only, progress: progressBar("Restoring"))
        print("Restored and verified.")

    case "activate":
        try v.activate(profile: try profileArg(args, 1))
        print("Profile \(args[1]) is active.")

    case "remap":
        let p = try profileArg(args, 1)
        guard args.count > 3, let source = parseKey(args[2]) else { throw CLIError("remap <1-4> <button> <target|default>") }
        var binding = ButtonBinding()
        if args[3].lowercased() != "default" {
            guard let target = parseKey(args[3]) else { throw CLIError("unknown target \(args[3])") }
            if target != source { binding.action = .remap(target) }
        }
        if args.count > 5, args[4] == "turbo", let f = Int(args[5]) { binding.turbo = .init(frequency: f) }
        var m = try v.readProfile(p)
        m.setBinding(binding, for: source)
        try v.commit(profile: p, mapping: m, progress: progressBar("Writing"))
        print("\(source.name) now does: \(binding.describe(for: source))")

    case "light":
        let p = try profileArg(args, 1)
        let effects = LightingEffect.editable.map(\.rawValue)
        guard args.count > 2,
              let effect = LightingEffect.editable.first(where: { $0.rawValue.lowercased() == args[2].lowercased() }) else {
            throw CLIError("light <1-4> <\(effects.joined(separator: "|"))> [#RRGGBB...]")
        }
        let colors = args.dropFirst(3).compactMap(LEDColor.init(hex:))
        let opts = options(args.dropFirst(3).filter { $0.contains("=") }[...])
        _ = try v.readProfile(p)
        var l = try v.readLighting(p)
        guard l.isValid else { throw CLIError("the controller returned a lighting format OpenVader does not know") }
        l.apply(effect, colors: colors, direction: opts["direction"].flatMap(FlowDirection.init(rawValue:)) ?? .left)
        if let b = opts["brightness"].flatMap(Int.init) { l.brightness = b }
        if let s = opts["speed"].flatMap(Int.init) { l.cycleTime = s }
        try v.commit(profile: p, lighting: l, progress: progressBar("Writing"))
        print("Lighting set: \(effect.title).")

    case "stick":
        let p = try profileArg(args, 1)
        guard args.count > 2, let side = ["left": Side.left, "right": .right][args[2].lowercased()] else {
            throw CLIError("stick <1-4> <left|right> ...")
        }
        let opts = options(args.dropFirst(3))
        var m = try v.readProfile(p)
        var s = m.stick(side)
        if let c = opts["curve"] {
            guard let curve = ["linear": StickSettings.Curve.standard, "instant": .instant, "delayed": .delay][c] else {
                throw CLIError("curve must be linear, instant or delayed")
            }
            s.apply(curve)
        }
        if let d = opts["deadzone"].flatMap(Int.init) { s.deadZone = d }
        if let o = opts["outer"].flatMap(Int.init) { s.outerDeadZone = o }
        if let c = opts["circular"] { s.circular = try onOff(c) }
        m.setStick(s, side)
        try v.commit(profile: p, mapping: m, progress: progressBar("Writing"))
        print("\(side.title) stick: \(m.stick(side).bank.map(String.init).joined(separator: " "))")

    case "trigger":
        let p = try profileArg(args, 1)
        guard args.count > 4, let side = ["left": Side.left, "right": .right][args[2].lowercased()],
              let start = Int(args[3]), let end = Int(args[4]) else { throw CLIError("trigger <1-4> <left|right> <start> <end>") }
        var m = try v.readProfile(p)
        m.setTrigger(TriggerTravel(start: start, end: end), side)
        try v.commit(profile: p, mapping: m, progress: progressBar("Writing"))
        print("\(side.title) trigger travel \(m.trigger(side).start)…\(m.trigger(side).end)")

    case "vibration":
        let p = try profileArg(args, 1)
        let opts = options(args.dropFirst(2)[...])
        var m = try v.readProfile(p)
        var g = m.gripVibration
        if let on = opts["grip"] { g.enabled = on == "on" }
        if let on = opts["left"] { g.left.enabled = on == "on" }
        if let on = opts["right"] { g.right.enabled = on == "on" }
        if let s = opts["left-gain"].flatMap(Int.init) { g.left.scale = max(0, min(100, s)) }
        if let s = opts["right-gain"].flatMap(Int.init) { g.right.scale = max(0, min(100, s)) }
        m.gripVibration = g
        try v.commit(profile: p, mapping: m, progress: progressBar("Writing"))
        let side = { (m: GripVibration.Motor) in m.enabled ? "on, gain \(m.scale)" : "off" }
        print("Grip rumble \(g.enabled ? "on" : "off"): left \(side(g.left)), right \(side(g.right))")

    case "gyro":
        let p = try profileArg(args, 1)
        guard args.count > 2, let target = ["off": GyroSettings.Target.off, "left": .leftStick, "right": .rightStick][args[2].lowercased()] else {
            throw CLIError("gyro <1-4> <off|left|right> ...")
        }
        let opts = options(args.dropFirst(3))
        var m = try v.readProfile(p)
        var g = m.gyro
        g.target = target
        if let k = opts["key"] { g.enableKey = parseKey(k) }
        if opts["hold"] != nil { g.activation = .hold }
        if opts["toggle"] != nil { g.activation = .toggle }
        if let s = opts["sensitivity"].flatMap(Int.init) { g.sensitivity = s }
        if let d = opts["deadzone"].flatMap(Int.init) { g.deadZone = d }
        m.gyro = g
        try v.commit(profile: p, mapping: m, progress: progressBar("Writing"))
        print("Gyro: \(m.gyro.target.title)")

    case "rename":
        let p = try profileArg(args, 1)
        guard args.count > 2 else { throw CLIError("rename <1-4> <name>") }
        var m = try v.readProfile(p)
        m.name = args[2...].joined(separator: " ")
        try v.commit(profile: p, mapping: m, progress: progressBar("Writing"))
        print("Profile \(p + 1) is now \"\(m.name)\".")

    case "reset-profile":
        let p = try profileArg(args, 1)
        let safety = try v.backup(progress: progressBar("Safety backup"))
        print("Current state saved to \(try safety.saveToDefaultLocation(label: "before-reset").path)")
        try v.resetToFactory(profile: p, progress: progressBar("Resetting"))
        print("Profile \(p + 1) is back to factory settings.")

    case "name":
        if args.count > 1 { try v.writeNickname(args[1...].joined(separator: " ")) }
        print("Name: \(try v.readNickname() ?? "(none)")")

    case "precision":
        guard args.count > 1, let choice = HardwareStatus.precisionChoices.first(where: { $0.label == "\(args[1]) bit" }) else {
            throw CLIError("precision <8|9|10|11|12>")
        }
        try v.setJoystickPrecision(choice.code)
        let now = try v.hardwareStatus().joystickPrecision
        print("Stick precision: \(HardwareStatus.precisionChoices.first { $0.code == now }?.label ?? "\(now)")")

    case "sensitivity":
        guard args.count > 1, let choice = HardwareStatus.sensitivityChoices.first(where: { $0.label.lowercased() == args[1].lowercased() }) else {
            throw CLIError("sensitivity <fast|medium|slow>")
        }
        try v.setJoystickSensitivity(choice.value)
        print("Center sensitivity: \(choice.label) (\(try v.hardwareStatus().joystickSensitivity))")

    case "firmware":
        let info = try v.readInfo()
        let sem = DispatchSemaphore(value: 0)
        var outcome: Result<FirmwareCheck.Result, Error>!
        Task {
            outcome = await Result(catching: { try await FirmwareCheck.check(info) })
            sem.signal()
        }
        sem.wait()
        let result = try outcome.get()
        for c in result.desktop {
            print("\(c.label.padding(toLength: 12, withPad: " ", startingAt: 0)) installed \(c.installed ?? "-"), latest \(c.latest)\(c.isNewer ? "  ← update" : "")\(c.notes.isEmpty ? "" : "  (\(c.notes))")")
        }
        if let web = result.webApp.first(where: { $0.chip == "main_chip" }) {
            print("Space Station 5.0 (web) firmware: \(web.latest). It changes the config format; OpenVader cannot write it yet.")
        }
        print("Install updates with Flydigi Space Station. OpenVader never flashes firmware.")

    case "sleep":
        guard args.count > 1, let minutes = Int(args[1]) else { throw CLIError("sleep <minutes>") }
        try v.setSleepTime(minutes: minutes)
        print("Sleep after: \(try v.hardwareStatus().sleepMinutes) min (0 = never)")

    case "feature":
        guard args.count > 2, let f = DeviceFeature.allCases.first(where: { cliName($0) == args[1].lowercased() }) else {
            throw CLIError("feature <name> <on|off>")
        }
        try v.setFeature(f, enabled: try onOff(args[2]))
        print("\(f.title): \(try v.hardwareStatus().enabled.contains(f) ? "on" : "off")")

    case "third-party":
        try v.setDataReport(thirdParty: try onOff(args.count > 1 ? args[1] : nil))
        print("Third-party takeover: \(try v.dataReportStatus().thirdPartyControl ? "allowed" : "not allowed")")

    case "switch-mode":
        let p = try profileArg(args, 1)
        try v.saveToSwitchMode(profile: p)
        print("Profile \(p + 1) copied to the Nintendo Switch bank.")

    case "rumble":
        let ms = args.count > 1 ? Int(args[1]) ?? 400 : 400
        try v.rumble(gripLeft: 200, gripRight: 200, triggerLeft: 120, triggerRight: 120)
        Thread.sleep(forTimeInterval: Double(ms) / 1000)
        try v.rumble(gripLeft: 0, gripRight: 0)

    case "monitor":
        let seconds = args.count > 1 ? Double(args[1]) ?? 10 : 10
        let lock = NSLock()
        var latest: InputState?
        var count = 0
        v.connection.onInputReport = { report in
            guard let s = InputState(report: report) else { return }
            lock.withLock { latest = s; count += 1 }
        }
        try v.setInputStream(true)
        defer { try? v.setInputStream(false) }
        let end = Date().addingTimeInterval(seconds)
        var lastCount = 0
        while Date() < end {
            Thread.sleep(forTimeInterval: 0.1)
            let (s, n) = lock.withLock { (latest, count) }
            guard let s else { continue }
            let rate = (n - lastCount) * 10
            lastCount = n
            let pressed = ControllerKey.allCases.filter { s.buttons.contains($0) }.map(\.short).joined(separator: " ")
            let line = String(format: "\rL %+.2f %+.2f  R %+.2f %+.2f  LT %.2f RT %.2f  gyro %+6.0f %+6.0f %+6.0f  %3d Hz  %@",
                              s.leftStick.x, s.leftStick.y, s.rightStick.x, s.rightStick.y, s.leftTrigger, s.rightTrigger,
                              s.gyro.x, s.gyro.y, s.gyro.z, rate, pressed.padding(toLength: 30, withPad: " ", startingAt: 0))
            FileHandle.standardOutput.write(line.data(using: .utf8)!)
        }
        print("\n\(count) reports.")

    default:
        throw CLIError("unknown command \(command)\n\n\(usage)")
    }
}

do {
    try run(Array(CommandLine.arguments.dropFirst()))
} catch {
    let message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
    FileHandle.standardError.write("error: \(message)\n".data(using: .utf8)!)
    exit(1)
}

extension Result where Failure == Error {
    init(catching body: () async throws -> Success) async {
        do { self = .success(try await body()) } catch { self = .failure(error) }
    }
}

import Foundation

/// A keyboard key with modifiers, as a macOS virtual key code.
public struct KeyStroke: Codable, Hashable, Sendable {
    public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let command = Modifiers(rawValue: 1)
        public static let option = Modifiers(rawValue: 2)
        public static let control = Modifiers(rawValue: 4)
        public static let shift = Modifiers(rawValue: 8)
    }

    public var keyCode: UInt16
    public var modifiers: Modifiers

    public init(_ keyCode: UInt16, modifiers: Modifiers = []) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var name: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + (KeyStroke.names[keyCode] ?? "Key \(keyCode)")
    }

    /// Key codes that are modifiers themselves.
    public static let modifierKeys: [UInt16: Modifiers] = [
        0x37: .command, 0x36: .command, 0x38: .shift, 0x3C: .shift,
        0x3A: .option, 0x3D: .option, 0x3B: .control, 0x3E: .control,
    ]

    /// Every key offered in the picker, in display order.
    public static let catalog: [(group: String, keys: [UInt16])] = [
        ("Letters", [0x00, 0x0B, 0x08, 0x02, 0x0E, 0x03, 0x05, 0x04, 0x22, 0x26, 0x28, 0x25, 0x2E,
                     0x2D, 0x1F, 0x23, 0x0C, 0x0F, 0x01, 0x11, 0x20, 0x09, 0x0D, 0x07, 0x10, 0x06]),
        ("Numbers", [0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19, 0x1D]),
        ("Keys", [0x31, 0x24, 0x35, 0x30, 0x33, 0x75, 0x7E, 0x7D, 0x7B, 0x7C, 0x73, 0x77, 0x74, 0x79]),
        ("Modifiers", [0x38, 0x3B, 0x3A, 0x37]),
        ("Function keys", [0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D, 0x67, 0x6F]),
        ("Symbols", [0x1B, 0x18, 0x21, 0x1E, 0x29, 0x27, 0x2A, 0x2B, 0x2F, 0x2C, 0x32]),
    ]

    public static let names: [UInt16: String] = [
        0x00: "A", 0x0B: "B", 0x08: "C", 0x02: "D", 0x0E: "E", 0x03: "F", 0x05: "G", 0x04: "H", 0x22: "I",
        0x26: "J", 0x28: "K", 0x25: "L", 0x2E: "M", 0x2D: "N", 0x1F: "O", 0x23: "P", 0x0C: "Q", 0x0F: "R",
        0x01: "S", 0x11: "T", 0x20: "U", 0x09: "V", 0x0D: "W", 0x07: "X", 0x10: "Y", 0x06: "Z",
        0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x17: "5", 0x16: "6", 0x1A: "7", 0x1C: "8", 0x19: "9", 0x1D: "0",
        0x31: "Space", 0x24: "Return", 0x35: "Escape", 0x30: "Tab", 0x33: "Delete", 0x75: "Forward Delete",
        0x7E: "↑", 0x7D: "↓", 0x7B: "←", 0x7C: "→", 0x73: "Home", 0x77: "End", 0x74: "Page Up", 0x79: "Page Down",
        0x38: "Shift", 0x3B: "Control", 0x3A: "Option", 0x37: "Command",
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8",
        0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
        0x1B: "-", 0x18: "=", 0x21: "[", 0x1E: "]", 0x29: ";", 0x27: "'", 0x2A: "\\", 0x2B: ",", 0x2F: ".",
        0x2C: "/", 0x32: "`",
    ]

    public static let w = KeyStroke(0x0D), a = KeyStroke(0x00), s = KeyStroke(0x01), d = KeyStroke(0x02)
    public static let up = KeyStroke(0x7E), down = KeyStroke(0x7D), left = KeyStroke(0x7B), right = KeyStroke(0x7C)
}

public enum MouseButton: Int, Codable, Hashable, Sendable, CaseIterable {
    case left = 0, right = 1, middle = 2, back = 3, forward = 4

    public var title: String {
        switch self {
        case .left: "Left click"
        case .right: "Right click"
        case .middle: "Middle click"
        case .back: "Mouse back"
        case .forward: "Mouse forward"
        }
    }
}

public enum ScrollDirection: String, Codable, Hashable, Sendable, CaseIterable {
    case up, down, left, right

    public var title: String { "Scroll \(rawValue)" }
}

/// Something a button does on the Mac instead of on the controller.
public enum HostAction: Codable, Hashable, Sendable {
    case key(KeyStroke)
    case mouse(MouseButton)
    case scroll(ScrollDirection)

    public var title: String {
        switch self {
        case .key(let k): "Key \(k.name)"
        case .mouse(let b): b.title
        case .scroll(let d): d.title
        }
    }
}

/// A stick used as a mouse, as keys, or for scrolling.
public enum StickHostMode: Codable, Hashable, Sendable {
    /// Speed 1...100.
    case mouse(speed: Int)
    case keys(up: KeyStroke, down: KeyStroke, left: KeyStroke, right: KeyStroke, eightWay: Bool)
    /// Speed 1...100.
    case scroll(speed: Int)

    public var title: String {
        switch self {
        case .mouse: "Mouse pointer"
        case .keys(let up, _, _, _, _): up == .w ? "WASD keys" : (up == .up ? "Arrow keys" : "Keys")
        case .scroll: "Scrolling"
        }
    }

    public static let wasd = StickHostMode.keys(up: .w, down: .s, left: .a, right: .d, eightWay: true)
    public static let arrows = StickHostMode.keys(up: .up, down: .down, left: .left, right: .right, eightWay: true)
}

public struct StickHostSettings: Codable, Hashable, Sendable {
    public var mode: StickHostMode
    /// Inner dead zone, percent.
    public var deadZone: Int
    /// The stick's own dead zone before the Mac took it over, to put back later.
    public var savedDeadZone: Int

    public init(mode: StickHostMode, deadZone: Int = 12, savedDeadZone: Int = 5) {
        self.mode = mode
        self.deadZone = deadZone
        self.savedDeadZone = savedDeadZone
    }
}

/// Motion moves the Mac's pointer.
/// Which rotation moves the pointer left and right, like Steam Input's gyro turn axis.
public enum GyroTurnAxis: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Turning the controller flat, as if looking around.
    case yaw
    /// Leaning it sideways, like a steering wheel.
    case roll
    case both

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .yaw: "Turning"
        case .roll: "Leaning"
        case .both: "Both"
        }
    }
}

public struct GyroMouseSettings: Codable, Hashable, Sendable {
    /// nil means always on.
    public var enableKey: ControllerKey?
    public var activation: GyroSettings.Activation
    /// 1...100
    public var sensitivity: Int
    public var invertX: Bool
    public var invertY: Bool
    public var turnAxis: GyroTurnAxis

    public init(enableKey: ControllerKey? = .lt, activation: GyroSettings.Activation = .hold, sensitivity: Int = 40,
                invertX: Bool = false, invertY: Bool = false, turnAxis: GyroTurnAxis = .both) {
        self.enableKey = enableKey
        self.activation = activation
        self.sensitivity = sensitivity
        self.invertX = invertX
        self.invertY = invertY
        self.turnAxis = turnAxis
    }

    private enum CodingKeys: String, CodingKey { case enableKey, activation, sensitivity, invertX, invertY, turnAxis }

    /// Settings saved before `turnAxis` existed read back as `.both`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enableKey = try c.decodeIfPresent(ControllerKey.self, forKey: .enableKey)
        activation = try c.decode(GyroSettings.Activation.self, forKey: .activation)
        sensitivity = try c.decode(Int.self, forKey: .sensitivity)
        invertX = try c.decode(Bool.self, forKey: .invertX)
        invertY = try c.decode(Bool.self, forKey: .invertY)
        turnAxis = try c.decodeIfPresent(GyroTurnAxis.self, forKey: .turnAxis) ?? .both
    }
}

/// Everything one profile does on the Mac. The controller only stores
/// markers for these (as Space Station does): the button's slot points at
/// "keyboard/mouse", the stick is silenced, and the gyro is set to "mouse".
public struct HostProfileMappings: Codable, Hashable, Sendable {
    public var buttons: [String: HostAction] = [:]
    public var leftStick: StickHostSettings?
    public var rightStick: StickHostSettings?
    public var gyro: GyroMouseSettings?

    public init() {}

    public var isEmpty: Bool { buttons.isEmpty && leftStick == nil && rightStick == nil && gyro == nil }

    public func action(for key: ControllerKey) -> HostAction? { buttons[String(key.rawValue)] }

    public mutating func setAction(_ action: HostAction?, for key: ControllerKey) {
        buttons[String(key.rawValue)] = action
    }

    public func stick(_ side: Side) -> StickHostSettings? { side == .left ? leftStick : rightStick }

    public mutating func setStick(_ settings: StickHostSettings?, _ side: Side) {
        if side == .left { leftStick = settings } else { rightStick = settings }
    }
}

/// Host mappings for every controller and profile, kept in
/// `~/Library/Application Support/OpenVader/HostMappings.json`.
public struct HostMappingStore: Codable, Sendable {
    /// Controller UID → profile index → mappings.
    public var controllers: [String: [String: HostProfileMappings]] = [:]

    public init() {}

    public static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenVader/HostMappings.json")
    }

    public static func load() -> HostMappingStore {
        guard let data = try? Data(contentsOf: url),
              let store = try? JSONDecoder().decode(HostMappingStore.self, from: data) else { return HostMappingStore() }
        return store
    }

    public func save() throws {
        try FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: Self.url, options: .atomic)
    }

    public func mappings(controller: String, profile: Int) -> HostProfileMappings {
        controllers[controller]?[String(profile)] ?? HostProfileMappings()
    }

    public mutating func set(_ m: HostProfileMappings, controller: String, profile: Int) {
        controllers[controller, default: [:]][String(profile)] = m.isEmpty ? nil : m
    }
}

extension MappingProfile {
    /// Marks the controller side of a host mapping: silences the stick so
    /// games stop seeing it while the Mac uses it, or restores it.
    public mutating func setStickHostControlled(_ controlled: Bool, _ side: Side, restoreDeadZone: Int = 5) {
        let core = 109 + 7 * side.rawValue
        let extra = 790 + 12 * side.rawValue
        if controlled {
            bytes[core + 1] = StickSettings.notAStick
            for i in 0..<9 { bytes[extra + 1 + i] = 50 }
        } else if bytes[core + 1] == StickSettings.notAStick {
            bytes[core + 1] = UInt8(max(0, min(100, restoreDeadZone)))
            var s = stick(side)
            s.isStick = true
            let bank = StickCurveCompiler.bank(deadZone: s.deadZone, outerDeadZone: s.outerDeadZone,
                                               point1: s.point1, point2: s.point2)
            for (i, v) in bank.enumerated() { bytes[extra + 1 + i] = v }
        }
    }
}

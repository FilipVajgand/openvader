import Foundation

public enum Side: Int, Sendable, CaseIterable, Identifiable, Codable {
    case left = 0, right = 1
    public var id: Int { rawValue }
    public var title: String { self == .left ? "Left" : "Right" }
}

/// One on-board profile: the 840-byte mapping blob (`0xA3` / `0xA4`).
///
/// Every field this type does not interpret is carried through byte for
/// byte. Layout follows Space Station's `MappingConfigParser` as documented
/// by flydigi-vader-pro-5-ctl and OpenFlydigi; see docs/PROTOCOL.md.
public struct MappingProfile: Sendable, Equatable {
    public static let size = 840
    /// Layout 3.2 is what the Vader 5 Pro reports. Writes are refused for
    /// anything else, because the offsets below may not hold.
    public static let supportedLayouts: Set<UInt16> = [770]

    enum Offset {
        static let version = 0
        static let keyTable = 13
        static let stickCore = 109
        static let triggerTravel = 123
        static let motion = 137
        static let grip = 145
        static let triggerMotors = 154
        static let dataVersion = 225
        static let name = 770
        static let stickExtra = 790
    }

    public var bytes: [UInt8]

    public init(bytes: [UInt8]) {
        self.bytes = bytes.count >= Self.size
            ? bytes : bytes + [UInt8](repeating: 0xFF, count: Self.size - bytes.count)
    }

    // MARK: Header

    public var layoutVersion: UInt16 { UInt16(bytes[0]) | UInt16(bytes[1]) << 8 }
    public var layoutDescription: String { "\(bytes[1]).\(bytes[0])" }
    public var isLayoutSupported: Bool { Self.supportedLayouts.contains(layoutVersion) }

    public var dataVersion: UInt16 {
        get { u16(Offset.dataVersion) }
        set { setU16(Offset.dataVersion, newValue) }
    }

    /// Profile title: up to 10 UTF-16 code units.
    public var name: String {
        get {
            let raw = bytes[Offset.name..<Offset.name + 20]
            var units: [UInt16] = []
            for i in stride(from: raw.startIndex, to: raw.endIndex, by: 2) {
                let unit = UInt16(raw[i]) | UInt16(raw[i + 1]) << 8
                if unit == 0 || unit == 0xFFFF { break }
                units.append(unit)
            }
            return String(decoding: units, as: UTF16.self)
        }
        set {
            var units = Array(newValue.utf16.prefix(10))
            // Do not leave half a surrogate pair at the end.
            if let last = units.last, UTF16.isLeadSurrogate(last) { units.removeLast() }
            // The name field is 16 bytes plus 4 spare ones the factory leaves at
            // 0xFF; only spill into those when the name needs them.
            for i in 0..<10 {
                let o = Offset.name + 2 * i
                let spareUntouched = i >= 8 && bytes[o] == 0xFF && bytes[o + 1] == 0xFF
                if i >= units.count && spareUntouched { continue }
                let unit = i < units.count ? units[i] : 0
                bytes[o] = UInt8(unit & 0xFF)
                bytes[o + 1] = UInt8(unit >> 8)
            }
        }
    }

    // MARK: Buttons

    public func binding(for key: ControllerKey) -> ButtonBinding {
        let base = Offset.keyTable + Int(key.rawValue) * 3
        return ButtonBinding(source: key, target: bytes[base], mode: bytes[base + 1], frequency: bytes[base + 2])
    }

    public mutating func setBinding(_ binding: ButtonBinding, for key: ControllerKey) {
        let base = Offset.keyTable + Int(key.rawValue) * 3
        let encoded = binding.encoded(for: key)
        bytes[base] = encoded.0
        bytes[base + 1] = encoded.1
        bytes[base + 2] = encoded.2
    }

    // MARK: Sticks

    public func stick(_ side: Side) -> StickSettings {
        let core = Offset.stickCore + 7 * side.rawValue
        let extra = Offset.stickExtra + 12 * side.rawValue
        let centerByte = bytes[core + 1]
        let edgeByte = bytes[extra + 11]
        return StickSettings(
            curve: StickSettings.Curve(rawValue: bytes[core]) ?? .custom,
            deadZone: centerByte <= 100 ? Int(centerByte) : 0,
            outerDeadZone: edgeByte <= 100 ? Int(edgeByte) : 0,
            point1: CurvePoint(x: Int(bytes[core + 2]), y: Int(bytes[core + 3])),
            point2: CurvePoint(x: Int(bytes[core + 4]), y: Int(bytes[core + 5])),
            circular: bytes[extra + 10] == 1,
            isStick: centerByte != StickSettings.notAStick,
            bank: Array(bytes[extra + 1..<extra + 10]))
    }

    public mutating func setStick(_ settings: StickSettings, _ side: Side) {
        let core = Offset.stickCore + 7 * side.rawValue
        let extra = Offset.stickExtra + 12 * side.rawValue
        let s = settings.normalized()
        let current = stick(side)
        bytes[core] = s.curve.rawValue
        bytes[extra] = s.curve.rawValue
        bytes[core + 1] = UInt8(s.deadZone)
        bytes[core + 2] = UInt8(s.point1.x)
        bytes[core + 3] = UInt8(s.point1.y)
        bytes[core + 4] = UInt8(s.point2.x)
        bytes[core + 5] = UInt8(s.point2.y)
        // Recompile only when the curve changed: Flydigi's factory tables round a
        // little differently, and untouched sticks should keep their bytes.
        if !current.isStick || current.deadZone != s.deadZone || current.outerDeadZone != s.outerDeadZone
            || current.point1 != s.point1 || current.point2 != s.point2 {
            let bank = StickCurveCompiler.bank(
                deadZone: s.deadZone, outerDeadZone: s.outerDeadZone, point1: s.point1, point2: s.point2)
            for (i, value) in bank.enumerated() { bytes[extra + 1 + i] = value }
        }
        bytes[extra + 10] = s.circular ? 1 : 0
        bytes[extra + 11] = UInt8(s.outerDeadZone)
    }

    // MARK: Triggers

    /// Physical travel window, 0...255 (Space Station's "Stroke setting").
    public func trigger(_ side: Side) -> TriggerTravel {
        let base = Offset.triggerTravel + 7 * side.rawValue
        return TriggerTravel(start: Int(bytes[base + 1]), end: Int(bytes[base + 6]))
    }

    public mutating func setTrigger(_ travel: TriggerTravel, _ side: Side) {
        let base = Offset.triggerTravel + 7 * side.rawValue
        let lo = UInt8(clamping: min(travel.start, travel.end))
        let hi = UInt8(clamping: max(travel.start, travel.end))
        // Space Station writes the two curve points onto the same line.
        bytes[base + 1] = lo
        bytes[base + 2] = lo
        bytes[base + 3] = lo
        bytes[base + 4] = hi
        bytes[base + 5] = hi
        bytes[base + 6] = hi
    }

    // MARK: Gyro

    public var gyro: GyroSettings {
        get {
            let b = Offset.motion
            return GyroSettings(
                target: GyroSettings.Target(rawValue: bytes[b]) ?? .off,
                enableKey: ControllerKey(rawValue: bytes[b + 1]),
                activation: bytes[b + 2] == 1 ? .hold : .toggle,
                deadZone: Int(min(bytes[b + 3], 100)),
                sensitivity: Int(min(max(bytes[b + 4], bytes[b + 5]), 100)),
                // While gyro is off, byte 7 still holds the factory's 0 (D-pad Up),
                // which would become a live second switch once gyro is enabled.
                secondKey: bytes[b] == GyroSettings.Target.off.rawValue ? nil : ControllerKey(rawValue: bytes[b + 7]))
        }
        set {
            let b = Offset.motion
            bytes[b] = newValue.target.rawValue
            bytes[b + 2] = newValue.activation == .hold ? 1 : 0
            bytes[b + 1] = newValue.enableKey?.rawValue ?? 0xFF
            // The factory stores D-pad Up here, which would silently act as a
            // second gyro switch. Write an explicit "none" instead.
            bytes[b + 7] = newValue.activation == .hold ? (newValue.secondKey?.rawValue ?? 0xFF) : 0xFF
            bytes[b + 3] = UInt8(clamping: max(0, min(100, newValue.deadZone)))
            let sensitivity = UInt8(clamping: max(0, min(100, newValue.sensitivity)))
            bytes[b + 4] = sensitivity
            bytes[b + 5] = sensitivity
            switch newValue.target {
            case .leftStick: bytes[b + 6] = 1  // racing
            case .rightStick, .mouse: bytes[b + 6] = 0  // FPS
            case .off: break
            }
        }
    }

    // MARK: Vibration

    public var gripVibration: GripVibration {
        get {
            let b = Offset.grip
            func motor(_ o: Int) -> GripVibration.Motor {
                GripVibration.Motor(
                    enabled: bytes[o] == 0,
                    minimum: Int(min(bytes[o + 1], bytes[o + 2])),
                    maximum: Int(max(bytes[o + 1], bytes[o + 2])),
                    scale: Int(bytes[o + 3]))
            }
            return GripVibration(enabled: bytes[b] == 0, left: motor(b + 1), right: motor(b + 5))
        }
        set {
            let b = Offset.grip
            bytes[b] = newValue.enabled ? 0 : 0xFF
            for (o, m) in [(b + 1, newValue.left), (b + 5, newValue.right)] {
                bytes[o] = m.enabled ? 0 : 0xFF
                bytes[o + 1] = UInt8(clamping: min(m.minimum, m.maximum))
                bytes[o + 2] = UInt8(clamping: max(m.minimum, m.maximum))
                bytes[o + 3] = UInt8(clamping: m.scale)
            }
        }
    }

    public var triggerVibration: TriggerVibration {
        get {
            let b = Offset.triggerMotors
            func gear(_ o: Int) -> TriggerVibration.Gear {
                TriggerVibration.Gear(
                    minimum: Int(min(bytes[o + 1], bytes[o + 2])),
                    maximum: Int(max(bytes[o + 1], bytes[o + 2])),
                    filter: Int(bytes[o + 3]), scale: Int(bytes[o + 5]))
            }
            return TriggerVibration(enabled: bytes[b] == 0, left: gear(b + 1), right: gear(b + 15))
        }
        set {
            let b = Offset.triggerMotors
            bytes[b] = newValue.enabled ? 0 : 1
            // Only the first ("linear") gear is written, as Space Station does.
            for (o, g) in [(b + 1, newValue.left), (b + 15, newValue.right)] {
                bytes[o + 1] = UInt8(clamping: min(g.minimum, g.maximum))
                bytes[o + 2] = UInt8(clamping: max(g.minimum, g.maximum))
                bytes[o + 3] = UInt8(clamping: g.filter)
                bytes[o + 5] = UInt8(clamping: g.scale)
            }
        }
    }

    /// Prepares a copy for the Nintendo Switch bank: keyboard bindings are
    /// host-side only, so they fall back to the button's default.
    public func normalizedForSwitch() -> MappingProfile {
        var copy = self
        for key in ControllerKey.allCases where copy.binding(for: key).action == .keyboardMouse {
            copy.setBinding(ButtonBinding(), for: key)
        }
        return copy
    }

    // MARK: Helpers

    func u16(_ o: Int) -> UInt16 { UInt16(bytes[o]) | UInt16(bytes[o + 1]) << 8 }

    mutating func setU16(_ o: Int, _ v: UInt16) {
        bytes[o] = UInt8(v & 0xFF)
        bytes[o + 1] = UInt8(v >> 8)
    }
}

// MARK: - Field types

/// What one physical button does.
public struct ButtonBinding: Sendable, Equatable, Hashable, Codable {
    public enum Action: Sendable, Equatable, Hashable, Codable {
        /// The button does what it is labelled.
        case standard
        case remap(ControllerKey)
        case macro
        /// A host-side keyboard/mouse binding from Space Station on Windows.
        case keyboardMouse
        case unknown(UInt8)
    }

    public enum TurboMode: UInt8, Sendable, Codable, CaseIterable {
        case whileHeld = 1
        case toggle = 2

        public var title: String { self == .whileHeld ? "While held" : "Toggle on press" }
    }

    public struct Turbo: Sendable, Equatable, Hashable, Codable {
        /// Presses per second.
        public var frequency: Int
        public var mode: TurboMode

        public init(frequency: Int = 10, mode: TurboMode = .whileHeld) {
            self.frequency = frequency
            self.mode = mode
        }
    }

    public var action: Action
    public var turbo: Turbo?

    public init(action: Action = .standard, turbo: Turbo? = nil) {
        self.action = action
        self.turbo = turbo
    }

    init(source: ControllerKey, target: UInt8, mode: UInt8, frequency: UInt8) {
        if target == KeySentinel.macro {
            self.init(action: .macro)
            return
        }
        let turbo = frequency > 0
            ? Turbo(frequency: Int(frequency), mode: TurboMode(rawValue: mode) ?? .whileHeld) : nil
        switch target {
        case KeySentinel.identity, source.rawValue:
            self.init(action: .standard, turbo: turbo)
        case KeySentinel.keyboardMouse:
            self.init(action: .keyboardMouse)
        default:
            if let key = ControllerKey(rawValue: target) {
                self.init(action: .remap(key), turbo: turbo)
            } else {
                self.init(action: .unknown(target), turbo: turbo)
            }
        }
    }

    func encoded(for source: ControllerKey) -> (UInt8, UInt8, UInt8) {
        var target: UInt8
        switch action {
        case .standard: target = KeySentinel.identity
        case .remap(let key): target = key.rawValue
        case .macro: return (KeySentinel.macro, 0, 0)
        case .keyboardMouse: return (KeySentinel.keyboardMouse, 0, 0)
        case .unknown(let raw): target = raw
        }
        guard let turbo, turbo.frequency > 0 else { return (target, 0, 0) }
        // A turbo entry needs a real key id, not the identity sentinel.
        if target == KeySentinel.identity { target = source.rawValue }
        return (target, turbo.mode.rawValue, UInt8(clamping: turbo.frequency))
    }

    public var isDefault: Bool { action == .standard && turbo == nil }

    public func describe(for source: ControllerKey) -> String {
        var text: String
        switch action {
        case .standard: text = source.name
        case .remap(let key): text = key.name
        case .macro: text = "Macro"
        case .keyboardMouse: text = "Keyboard/mouse (Windows only)"
        case .unknown(let raw): text = String(format: "Unknown (0x%02X)", raw)
        }
        if let turbo { text += " · turbo \(turbo.frequency)/s" }
        return text
    }
}

public struct CurvePoint: Sendable, Equatable, Hashable, Codable {
    /// 0...127 on both axes.
    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

public struct StickSettings: Sendable, Equatable, Codable {
    public enum Curve: UInt8, Sendable, CaseIterable, Codable, Identifiable {
        case standard = 0, instant = 1, delay = 2, custom = 3
        public var id: UInt8 { rawValue }

        public var title: String {
            switch self {
            case .standard: "Linear"
            case .instant: "Instant"
            case .delay: "Delayed"
            case .custom: "Custom"
            }
        }

        public var help: String {
            switch self {
            case .standard: "Output follows the stick one to one."
            case .instant: "Small movements produce more output, for fast turning."
            case .delay: "Small movements produce less output, for precise aiming."
            case .custom: "Drag the two points to shape your own curve."
            }
        }

        /// Interior points of each preset, from Space Station's renderer.
        public var points: (CurvePoint, CurvePoint)? {
            switch self {
            case .standard: (CurvePoint(x: 63, y: 63), CurvePoint(x: 127, y: 127))
            case .instant: (CurvePoint(x: 64, y: 96), CurvePoint(x: 127, y: 127))
            case .delay: (CurvePoint(x: 64, y: 32), CurvePoint(x: 127, y: 127))
            case .custom: nil
            }
        }
    }

    /// The center byte is forced to this when a stick is mapped to
    /// something that is not a stick.
    public static let notAStick: UInt8 = 127

    public var curve: Curve
    /// Inner dead zone, percent of travel.
    public var deadZone: Int
    /// Outer dead zone: the last part of the travel that already reads as full.
    public var outerDeadZone: Int
    public var point1: CurvePoint
    public var point2: CurvePoint
    /// Circular limits the diagonal to the unit circle; square lets it reach the corners.
    public var circular: Bool
    public var isStick: Bool
    /// The compiled nine-point response the controller actually plays.
    public var bank: [UInt8]

    public init(
        curve: Curve = .standard, deadZone: Int = 0, outerDeadZone: Int = 0,
        point1: CurvePoint = CurvePoint(x: 63, y: 63), point2: CurvePoint = CurvePoint(x: 127, y: 127),
        circular: Bool = false, isStick: Bool = true, bank: [UInt8] = []
    ) {
        self.curve = curve
        self.deadZone = deadZone
        self.outerDeadZone = outerDeadZone
        self.point1 = point1
        self.point2 = point2
        self.circular = circular
        self.isStick = isStick
        self.bank = bank
    }

    /// Applies a preset's interior points.
    public mutating func apply(_ preset: Curve) {
        curve = preset
        if let (p1, p2) = preset.points {
            point1 = p1
            point2 = p2
        }
    }

    /// Clamps values into the ranges the firmware accepts.
    public func normalized() -> StickSettings {
        var s = self
        s.deadZone = max(0, min(100, s.deadZone))
        s.outerDeadZone = max(0, min(100 - s.deadZone, s.outerDeadZone))
        for keyPath in [\StickSettings.point1, \StickSettings.point2] {
            s[keyPath: keyPath].x = max(0, min(127, s[keyPath: keyPath].x))
            s[keyPath: keyPath].y = max(0, min(127, s[keyPath: keyPath].y))
        }
        if s.point1.x > s.point2.x { swap(&s.point1, &s.point2) }
        return s
    }
}

public struct TriggerTravel: Sendable, Equatable, Codable {
    /// 0...255; travel before `start` reads as released.
    public var start: Int
    /// 0...255; travel past `end` reads as fully pressed.
    public var end: Int

    public init(start: Int = 0, end: Int = 255) {
        self.start = start
        self.end = end
    }

    public static let full = TriggerTravel()
    public static let hairTrigger = TriggerTravel(start: 0, end: 40)
}

public struct GyroSettings: Sendable, Equatable, Codable {
    public enum Target: UInt8, Sendable, CaseIterable, Codable, Identifiable {
        case off = 0, leftStick = 1, rightStick = 2, mouse = 3
        public var id: UInt8 { rawValue }

        public var title: String {
            switch self {
            case .off: "Off"
            case .leftStick: "Left stick"
            case .rightStick: "Right stick"
            case .mouse: "Mouse (Windows only)"
            }
        }
    }

    public enum Activation: Sendable, Codable, CaseIterable {
        case hold, toggle
        public var title: String { self == .hold ? "While held" : "Toggle on press" }
    }

    public var target: Target
    public var enableKey: ControllerKey?
    public var activation: Activation
    /// 0...100
    public var deadZone: Int
    /// 0...100
    public var sensitivity: Int
    /// Optional second switch key, honoured in hold mode.
    public var secondKey: ControllerKey?

    public init(
        target: Target = .off, enableKey: ControllerKey? = .lt, activation: Activation = .hold,
        deadZone: Int = 4, sensitivity: Int = 25, secondKey: ControllerKey? = nil
    ) {
        self.target = target
        self.enableKey = enableKey
        self.activation = activation
        self.deadZone = deadZone
        self.sensitivity = sensitivity
        self.secondKey = secondKey
    }
}

public struct GripVibration: Sendable, Equatable, Codable {
    public struct Motor: Sendable, Equatable, Codable {
        public var enabled: Bool
        /// 0...255 floor of the motor's strength window.
        public var minimum: Int
        /// 0...255 ceiling of the motor's strength window.
        public var maximum: Int
        public var scale: Int
    }

    public var enabled: Bool
    public var left: Motor
    public var right: Motor
}

public struct TriggerVibration: Sendable, Equatable, Codable {
    public struct Gear: Sendable, Equatable, Codable {
        public var minimum: Int
        public var maximum: Int
        /// Rumble below this stays off the trigger motor.
        public var filter: Int
        /// Strength, 1...100 %.
        public var scale: Int
    }

    public var enabled: Bool
    public var left: Gear
    public var right: Gear
}

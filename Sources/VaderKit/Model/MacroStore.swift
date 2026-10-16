import Foundation

/// On-board macros (layout 3.2 and later): a separate blob per profile,
/// moved with `0xAC` / `0xAD` / `0xAE`. The controller replays them by
/// itself, so a macro can only press controller buttons.
///
/// Layout, ported from flydigi-vader-pro-5-ctl's `macros.py` (MIT):
///
///     [0..1]  version, u16 LE
///     [2..3]  macro count, u16 LE, at most 10
///     [4..23] ten u16 offsets, in 4-byte words from byte 24
///     [24..]  records: key, step count (u16), enable type, repeat
///             interval ms (u16), 6 x 0xFF, 20-byte UTF-8 name,
///             then 4 bytes per step: cumulative ms (u16), key, event
public struct MacroStore: Sendable, Equatable {
    public static let maxMacros = 10
    public static let maxSteps = 256
    static let dataStart = 24
    static let recordHeader = 32
    static let nameOffset = 12
    static let nameLength = 20

    public var macros: [Macro]
    /// Size the controller served; writes reuse it.
    public var size: Int
    public var version: UInt16

    public init(macros: [Macro] = [], size: Int = 1660, version: UInt16 = 0x0100) {
        self.macros = macros
        self.size = size
        self.version = version
    }

    public init(bytes: [UInt8]) {
        size = bytes.count
        version = bytes.count >= 2 ? UInt16(bytes[0]) | UInt16(bytes[1]) << 8 : 0x0100
        if version == 0xFFFF { version = 0x0100 }
        macros = Self.parse(bytes)
    }

    public func macro(for key: ControllerKey) -> Macro? { macros.first { $0.trigger == key } }

    static func parse(_ blob: [UInt8]) -> [Macro] {
        guard blob.count >= dataStart else { return [] }
        func u16(_ o: Int) -> Int { Int(blob[o]) | Int(blob[o + 1]) << 8 }
        let count = u16(2)
        guard count != 0, count != 0xFFFF else { return [] }
        var out: [Macro] = []
        for i in 0..<min(count, maxMacros) {
            let offset = u16(4 + 2 * i)
            guard offset != 0xFFFF else { continue }
            let base = dataStart + offset * 4
            guard base + recordHeader <= blob.count, let key = ControllerKey(rawValue: blob[base]) else { continue }
            var steps = u16(base + 1)
            guard steps != 0, steps != 0xFFFF else { continue }
            steps = min(steps, (blob.count - base - recordHeader) / 4)
            let enable = Macro.Playback(rawValue: blob[base + 3]) ?? .once
            let interval = u16(base + 4)
            let nameBytes = blob[(base + nameOffset)..<(base + nameOffset + nameLength)].prefix { $0 != 0 && $0 != 0xFF }
            var parsed: [Macro.Step] = []
            var previous = 0
            for k in 0..<steps {
                let s = base + recordHeader + k * 4
                guard blob[s + 2] != 0xFF else { break }
                let cumulative = u16(s)
                if !parsed.isEmpty { parsed[parsed.count - 1].delay = max(0, cumulative - previous) }
                previous = cumulative
                parsed.append(Macro.Step(
                    key: ControllerKey(rawValue: blob[s + 2]) ?? .a,
                    event: Macro.Event(rawValue: blob[s + 3]) ?? .press, delay: 0))
            }
            guard !parsed.isEmpty else { continue }
            out.append(Macro(
                trigger: key, playback: enable, repeatInterval: interval == 0xFFFF ? 0 : interval,
                name: String(decoding: nameBytes, as: UTF8.self), steps: parsed))
        }
        return out
    }

    public func encoded() throws -> [UInt8] {
        guard macros.count <= Self.maxMacros else {
            throw VaderError.invalidArgument("A profile holds at most \(Self.maxMacros) macros.")
        }
        var blob = [UInt8](repeating: 0xFF, count: size)
        func put16(_ o: Int, _ v: Int) {
            blob[o] = UInt8(v & 0xFF)
            blob[o + 1] = UInt8((v >> 8) & 0xFF)
        }
        put16(0, Int(version))
        put16(2, macros.count)
        var running = 0
        for (i, macro) in macros.enumerated() {
            guard macro.steps.count <= Self.maxSteps else {
                throw VaderError.invalidArgument("A macro holds at most \(Self.maxSteps) steps.")
            }
            put16(4 + 2 * i, running)
            let base = Self.dataStart + running * 4
            guard base + Self.recordHeader + macro.steps.count * 4 <= blob.count else {
                throw VaderError.invalidArgument("These macros do not fit in the controller's macro memory.")
            }
            blob[base] = macro.trigger.rawValue
            put16(base + 1, macro.steps.count)
            blob[base + 3] = macro.playback.rawValue
            put16(base + 4, max(0, min(0xFFFE, macro.repeatInterval)))
            var name = [UInt8](repeating: 0, count: Self.nameLength)
            for (j, b) in Array(macro.name.utf8.prefix(Self.nameLength)).enumerated() { name[j] = b }
            blob.replaceSubrange((base + Self.nameOffset)..<(base + Self.nameOffset + Self.nameLength), with: name)
            var cumulative = 0
            for (k, step) in macro.steps.enumerated() {
                let s = base + Self.recordHeader + k * 4
                put16(s, min(cumulative, 0xFFFF))
                blob[s + 2] = step.key.rawValue
                blob[s + 3] = step.event.rawValue
                cumulative += max(0, step.delay)
            }
            running += macro.steps.count + Self.recordHeader / 4
        }
        return blob
    }
}

public struct Macro: Sendable, Equatable, Identifiable, Codable {
    public enum Playback: UInt8, Sendable, CaseIterable, Codable {
        case once = 1
        case whileHeld = 2
        case toggle = 3

        public var title: String {
            switch self {
            case .once: "Once per press"
            case .whileHeld: "Repeat while held"
            case .toggle: "Repeat until pressed again"
            }
        }
    }

    public enum Event: UInt8, Sendable, Codable, CaseIterable {
        case release = 0
        case press = 1

        public var title: String { self == .press ? "Press" : "Release" }
    }

    public struct Step: Sendable, Equatable, Codable, Identifiable {
        public var id = UUID()
        public var key: ControllerKey
        public var event: Event
        /// Milliseconds before the next step.
        public var delay: Int

        public init(key: ControllerKey, event: Event, delay: Int) {
            self.key = key
            self.event = event
            self.delay = delay
        }

        public static func == (a: Step, b: Step) -> Bool {
            a.key == b.key && a.event == b.event && a.delay == b.delay
        }
    }

    public var id: UInt8 { trigger.rawValue }
    /// The physical button that plays the macro.
    public var trigger: ControllerKey
    public var playback: Playback
    /// Pause between repeats, ms.
    public var repeatInterval: Int
    public var name: String
    public var steps: [Step]

    public init(trigger: ControllerKey, playback: Playback = .once, repeatInterval: Int = 0, name: String = "", steps: [Step] = []) {
        self.trigger = trigger
        self.playback = playback
        self.repeatInterval = repeatInterval
        self.name = name
        self.steps = steps
    }

    public var duration: Int { steps.reduce(0) { $0 + $1.delay } }

    /// A press and a release per button, `hold` ms apart, `gap` ms between buttons.
    public static func tap(_ keys: [ControllerKey], hold: Int = 40, gap: Int = 40) -> [Step] {
        keys.flatMap { [Step(key: $0, event: .press, delay: hold), Step(key: $0, event: .release, delay: gap)] }
    }
}

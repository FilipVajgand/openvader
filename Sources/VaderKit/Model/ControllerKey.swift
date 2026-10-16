import Foundation

/// Flydigi's `ControllerKey` ids. The same numbers index the mapping blob's
/// key table, name remap targets, macro steps and gyro enable keys.
public enum ControllerKey: UInt8, CaseIterable, Sendable, Codable, Identifiable {
    case up = 0, right = 1, down = 2, left = 3
    case a = 4, b = 5, select = 6, x = 7, y = 8, start = 9
    case lb = 10, rb = 11, lt = 12, rt = 13
    case l3 = 14, r3 = 15
    case c = 16, z = 17
    case m1 = 18, m2 = 19, m3 = 20, m4 = 21
    /// The LM / RM shoulder buttons are M5 / M6 in Flydigi's numbering.
    case lm = 22, rm = 23
    case fn = 24, turbo = 25, home = 27

    public var id: UInt8 { rawValue }

    public var name: String {
        switch self {
        case .up: "D-pad Up"
        case .right: "D-pad Right"
        case .down: "D-pad Down"
        case .left: "D-pad Left"
        case .a: "A"
        case .b: "B"
        case .select: "View"
        case .x: "X"
        case .y: "Y"
        case .start: "Menu"
        case .lb: "LB"
        case .rb: "RB"
        case .lt: "LT"
        case .rt: "RT"
        case .l3: "Left stick click"
        case .r3: "Right stick click"
        case .c: "C"
        case .z: "Z"
        case .m1: "M1"
        case .m2: "M2"
        case .m3: "M3"
        case .m4: "M4"
        case .lm: "LM"
        case .rm: "RM"
        case .fn: "Fn"
        case .turbo: "Turbo"
        case .home: "Home"
        }
    }

    /// A compact label for drawing on the controller.
    public var short: String {
        switch self {
        case .up: "↑"
        case .right: "→"
        case .down: "↓"
        case .left: "←"
        case .select: "View"
        case .start: "Menu"
        case .l3: "L3"
        case .r3: "R3"
        default: name
        }
    }

    /// Buttons whose on-board mapping can be changed.
    public static let remappable: [ControllerKey] = [
        .m1, .m2, .m3, .m4, .lm, .rm, .c, .z,
        .a, .b, .x, .y, .lb, .rb, .lt, .rt, .l3, .r3,
        .up, .down, .left, .right, .select, .start,
    ]

    /// Outputs a remapped button may produce: the standard Xbox-layout
    /// inputs every host understands.
    public static let targets: [ControllerKey] = [
        .a, .b, .x, .y, .lb, .rb, .lt, .rt, .l3, .r3,
        .up, .down, .left, .right, .select, .start,
    ]

    /// Buttons that can switch gyro aiming on.
    public static let gyroEnableKeys: [ControllerKey] = [
        .lt, .rt, .lb, .rb, .lm, .rm, .m1, .m2, .m3, .m4, .c, .z, .l3, .r3,
        .a, .b, .x, .y, .up, .down, .left, .right,
    ]

    /// Buttons a macro step may press.
    public static let macroOutputs: [ControllerKey] = targets

    public static let extraButtons: Set<ControllerKey> = [.m1, .m2, .m3, .m4, .lm, .rm, .c, .z]
}

/// Sentinel values used in the key table.
public enum KeySentinel {
    public static let macro: UInt8 = 0x20
    public static let keyboardMouse: UInt8 = 0xFE
    public static let identity: UInt8 = 0xFF
}

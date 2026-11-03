import Foundation

/// Carries the extra buttons to the Mac in Nintendo Switch mode.
///
/// Over the cable in Switch mode the controller is a "Pro Controller", which has
/// no paddles and no spare buttons except Home and Capture, and the Vader can
/// only send Home. So each extra button plays a macro of exactly two Home
/// pulses, each short, medium or long, and OpenVader reads the pair from the
/// raw HID reports and performs the Mac action saved for that button.
///
/// Exactly two pulses, because macOS opens the Games app on any single Home
/// press (16-150 ms all did on macOS 26) but ignores a double press. Games never
/// see Home through GameController, so the pulses do not leak into the game.
/// Measured over the cable, pulses come back up to about 15 ms long or 8 ms short
/// (50 ms read as 48-64 ms); a person tapping the logo button holds it 120 ms or more.
public enum HomePulse {
    /// The buttons that can send a code, shortest code first.
    public static let keys: [ControllerKey] = [.m1, .m2, .lm, .rm, .c, .z, .m3, .m4]

    /// Pulse lengths in milliseconds: short, medium, long.
    static let lengths = [20, 50, 90]
    /// Gap between the two pulses.
    static let gap = 20
    /// Length levels of the two pulses for each key in `keys`, by total duration.
    static let codes: [(Int, Int)] = [(0, 0), (0, 1), (1, 0), (1, 1), (0, 2), (2, 0), (1, 2), (2, 1)]

    /// The macro an extra button plays to send its code.
    public static func macro(for key: ControllerKey) -> Macro? {
        guard let i = keys.firstIndex(of: key) else { return nil }
        let (a, b) = codes[i]
        return Macro(trigger: key, name: "Mac key (Switch mode)", steps: [
            .init(key: .home, event: .press, delay: lengths[a]),
            .init(key: .home, event: .release, delay: gap),
            .init(key: .home, event: .press, delay: lengths[b]),
            .init(key: .home, event: .release, delay: 0),
        ])
    }

    /// The button whose code is this pair of pulse lengths, if any.
    public static func key(first: Double, second: Double) -> ControllerKey? {
        guard let a = level(first), let b = level(second),
              let i = codes.firstIndex(where: { $0 == (a, b) }) else { return nil }
        return keys[i]
    }

    /// Thresholds sit halfway between the lengths; anything longer is a person pressing Home.
    static func level(_ ms: Double) -> Int? {
        switch ms {
        case ..<36: 0
        case ..<72: 1
        case ..<118: 2
        default: nil
        }
    }

    /// The Home button in a Pro Controller full input report (`0x30`), or nil for other reports.
    public static func homePressed(proControllerReport r: UnsafeBufferPointer<UInt8>) -> Bool? {
        guard r.count > 4, r[0] == 0x30 else { return nil }
        return r[4] & 0x10 != 0
    }

    /// Turns Home press/release edges into button codes.
    public struct Decoder: Sendable {
        /// Longest gap between the two pulses of one code, in seconds.
        static let maxGap = 0.07

        private var pressedAt: Double?
        private var releasedAt: Double?
        private var first: Double?

        public init() {}

        /// Feeds the Home state from one report; returns a button when a code completes.
        public mutating func update(homeDown down: Bool, at time: Double) -> ControllerKey? {
            if down {
                guard pressedAt == nil else { return nil }
                if let releasedAt, time - releasedAt > Self.maxGap { first = nil }
                pressedAt = time
                return nil
            }
            guard let start = pressedAt else { return nil }
            pressedAt = nil
            releasedAt = time
            let ms = (time - start) * 1000
            guard let a = first else {
                first = HomePulse.level(ms) == nil ? nil : ms
                return nil
            }
            first = nil
            return HomePulse.key(first: a, second: ms)
        }
    }
}

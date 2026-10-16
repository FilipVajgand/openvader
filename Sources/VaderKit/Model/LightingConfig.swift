import Foundation

public struct LEDColor: Sendable, Equatable, Hashable, Codable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(red: UInt8(value >> 16 & 0xFF), green: UInt8(value >> 8 & 0xFF), blue: UInt8(value & 0xFF))
    }

    public var hex: String { String(format: "#%02X%02X%02X", red, green, blue) }

    /// The same colour at a fraction (0...1) of its brightness.
    public func scaled(_ k: Double) -> LEDColor {
        LEDColor(red: UInt8(Double(red) * k), green: UInt8(Double(green) * k), blue: UInt8(Double(blue) * k))
    }

    /// Hue in 0..<1, or nil for greys.
    public var hue: Double? {
        let r = Double(red), g = Double(green), b = Double(blue)
        let hi = max(r, g, b), lo = min(r, g, b)
        guard hi > lo else { return nil }
        let d = hi - lo
        let h: Double = hi == r ? (g - b) / d : hi == g ? 2 + (b - r) / d : 4 + (r - g) / d
        return (h / 6 + 1).truncatingRemainder(dividingBy: 1)
    }
    public var isBlack: Bool { red == 0 && green == 0 && blue == 0 }

    public static let black = LEDColor(red: 0, green: 0, blue: 0)

    /// h, s, v in 0...1.
    public static func hsv(_ h: Double, _ s: Double, _ v: Double) -> LEDColor {
        let h6 = (h - floor(h)) * 6
        let i = Int(h6) % 6
        let f = h6 - floor(h6)
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        let (r, g, b): (Double, Double, Double) = switch i {
        case 0: (v, t, p)
        case 1: (q, v, p)
        case 2: (p, v, t)
        case 3: (p, q, v)
        case 4: (t, p, v)
        default: (v, p, q)
        }
        return LEDColor(red: UInt8(r * 255), green: UInt8(g * 255), blue: UInt8(b * 255))
    }
}

/// Lighting effects. The controller only plays frames, so every effect is a frame generator here; the
/// effect byte stored with them is the closest Space Station `LedType`, so a profile written here still
/// reads back sensibly there. OpenVader's own extra effects are recognised from their frames.
public enum LightingEffect: String, Sendable, CaseIterable, Codable, Identifiable {
    case steady, breathing, strobe, gradient, rainbowFade, flow, comet, scanner, fire, off, factory

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .steady: "Steady"
        case .breathing: "Breathing"
        case .strobe: "Strobe"
        case .gradient: "Color cycle"
        case .rainbowFade: "Rainbow fade"
        case .flow: "Rainbow flow"
        case .comet: "Comet"
        case .scanner: "Scanner"
        case .fire: "Fire"
        case .off: "Off"
        case .factory: "Factory animation"
        }
    }

    /// Space Station's `LedType` for the effect byte.
    public var ledType: UInt8 {
        switch self {
        case .flow, .comet, .scanner, .fire: 1
        case .breathing, .strobe: 2
        case .gradient, .rainbowFade: 3
        case .steady: 5
        case .off: 6
        case .factory: 7
        }
    }

    public var colorRange: ClosedRange<Int> {
        switch self {
        case .steady, .comet, .scanner: 1...1
        case .breathing: 1...5
        case .strobe: 1...2
        case .gradient: 2...5
        case .rainbowFade, .flow, .fire, .off, .factory: 0...0
        }
    }

    public var isAnimated: Bool { self != .steady && self != .off }
    public var hasDirection: Bool { self == .flow || self == .comet }

    /// Effects the editor offers. Factory frames can only be kept, not generated.
    public static let editable: [LightingEffect] =
        [.steady, .breathing, .strobe, .gradient, .rainbowFade, .flow, .comet, .scanner, .fire, .off]
}

/// Which way the rainbow travels along the light bar. LED 0 is the left end.
public enum FlowDirection: String, Sendable, CaseIterable, Identifiable {
    case left, right
    public var id: String { rawValue }
    public var title: String { self == .left ? "Left" : "Right" }
}

/// The per-profile lighting blob (`0xA7` / `0xA8`).
///
/// The controller has no effect generator: it plays the stored colour
/// frames, cycling `loopStart...loopEnd`. Every effect is therefore built
/// here as frames. Geometry (LED count, frame count) is read from the blob,
/// never assumed.
public struct LightingConfig: Sendable, Equatable {
    public static let headerSize = 20
    public var bytes: [UInt8]

    public init(bytes: [UInt8]) { self.bytes = bytes }

    public var isValid: Bool {
        bytes.count > Self.headerSize && bytes[0] == 0 && (bytes[1] == 2 || bytes[1] == 3) && ledCount > 0
    }

    public var version: Int { Int(bytes[1]) }
    public var ledCount: Int { bytes.count > 7 ? Int(bytes[7]) : 0 }
    public var frameCount: Int { ledCount > 0 ? (bytes.count - Self.headerSize) / (ledCount * 3) : 0 }

    public var effectRaw: UInt8 { bytes[8] }

    /// The effect, from the stored `LedType` and, for OpenVader's own effects, from the frames themselves.
    public var effect: LightingEffect? {
        switch bytes[8] {
        case 5: return .steady
        case 6: return .off
        case 7: return .factory
        case 2: return reproduces(.strobe, colors: strobeColors) ? .strobe : .breathing
        case 3: return reproduces(.rainbowFade, colors: []) ? .rainbowFade : .gradient
        case 1:
            if reproduces(.fire, colors: []) { return .fire }
            if reproduces(.scanner, colors: [headColor]) { return .scanner }
            if FlowDirection.allCases.contains(where: { reproduces(.comet, colors: [headColor], direction: $0) }) {
                return .comet
            }
            return .flow
        default: return nil
        }
    }

    /// The brightest LED of the first frame: the head of a comet or scanner.
    private var headColor: LEDColor {
        (0..<ledCount).map { color(frame: 0, led: $0) }
            .max { Int($0.red) + Int($0.green) + Int($0.blue) < Int($1.red) + Int($1.green) + Int($1.blue) } ?? .black
    }

    private var strobeColors: [LEDColor] { [color(frame: 0, led: 0), color(frame: frameCount / 2, led: 0)] }

    /// True when generating `effect` would give exactly these frames and loop window.
    private func reproduces(_ effect: LightingEffect, colors: [LEDColor], direction: FlowDirection = .left) -> Bool {
        var copy = self
        copy.apply(effect, colors: colors, direction: direction)
        return copy.bytes[2...4] == bytes[2...4] && copy.bytes[Self.headerSize...] == bytes[Self.headerSize...]
    }

    /// 0...100
    public var brightness: Int {
        get { Int(min(bytes[6], 100)) }
        set { bytes[6] = UInt8(max(0, min(100, newValue))) }
    }

    /// Frame period; larger is slower.
    public var cycleTime: Int {
        get { Int(bytes[5]) }
        set { bytes[5] = UInt8(max(1, min(255, newValue))) }
    }

    /// Flydigi's `GripSync` flag ("Vibration light effect"). On an Apex 5 it dims part of the bar while the
    /// grips rumble; on a Vader 5 Pro (fw 7.1.5.0) a steady white bar at full brightness stayed unchanged
    /// through game rumble with it set, so OpenVader does not offer it. Kept as read.
    public var gripSync: Bool {
        get { bytes[9] == 1 }
        set { bytes[9] = newValue ? 1 : 0 }
    }

    public var loopStart: Int { Int(bytes[3]) }
    public var loopEnd: Int { Int(bytes[4]) }

    public func color(frame: Int, led: Int) -> LEDColor {
        let o = Self.headerSize + (frame * ledCount + led) * 3
        guard o + 2 < bytes.count else { return .black }
        return LEDColor(red: bytes[o], green: bytes[o + 1], blue: bytes[o + 2])
    }

    mutating func setColor(_ c: LEDColor, frame: Int, led: Int) {
        let o = Self.headerSize + (frame * ledCount + led) * 3
        guard o + 2 < bytes.count else { return }
        bytes[o] = c.red
        bytes[o + 1] = c.green
        bytes[o + 2] = c.blue
    }

    mutating func fill(frame: Int, with c: LEDColor) {
        for led in 0..<ledCount { setColor(c, frame: frame, led: led) }
    }

    /// The distinct colours of the stored frames, for seeding the editor.
    public var paletteGuess: [LEDColor] {
        var out: [LEDColor] = []
        for frame in 0..<frameCount {
            let c = color(frame: frame, led: 0)
            if !c.isBlack, !out.contains(c) { out.append(c) }
        }
        return out
    }

    /// Which way a rainbow flow or comet travels, read back from its frames; nil for other effects.
    public var direction: FlowDirection? {
        switch effect {
        case .flow:
            guard frameCount > 1, let h0 = color(frame: 0, led: 0).hue, let h1 = color(frame: 1, led: 0).hue
            else { return nil }
            // A left flow raises each LED's hue from frame to frame (colours move towards LED 0).
            let step = (h1 - h0 + 1).truncatingRemainder(dividingBy: 1)
            guard step > 0.01, step < 0.99 else { return nil }
            return step < 0.5 ? .left : .right
        case .comet:
            return FlowDirection.allCases.first { reproduces(.comet, colors: [headColor], direction: $0) }
        default:
            return nil
        }
    }

    /// Rebuilds the frames for an effect, keeping the header geometry.
    public mutating func apply(_ effect: LightingEffect, colors: [LEDColor], direction: FlowDirection = .left) {
        guard isValid, effect != .factory else { return }
        let frames = frameCount
        for f in 0..<frames { fill(frame: f, with: .black) }
        bytes[2] = 0  // click feedback latches the display; keep it off
        bytes[3] = 0
        bytes[8] = effect.ledType
        var palette = colors.isEmpty ? [LEDColor(red: 0, green: 120, blue: 255)] : colors
        let lastFrame = UInt8(max(0, frames - 1))
        switch effect {
        case .steady:
            fill(frame: 0, with: palette[0])
            bytes[4] = 0
        case .off:
            bytes[4] = 0
        case .breathing:
            // Colour, dark, colour, dark... so the controller fades in and out.
            palette = Array(palette.prefix(max(1, frames / 2)))
            for (i, c) in palette.enumerated() { fill(frame: i * 2, with: c) }
            bytes[4] = UInt8(palette.count * 2 - 1)
        case .gradient:
            if palette.count < 2 { palette.append(palette[0]) }
            palette = Array(palette.prefix(frames))
            for (i, c) in palette.enumerated() { fill(frame: i, with: c) }
            bytes[4] = UInt8(palette.count - 1)
        case .flow:
            // Each frame shifts the hue wheel one step; the sign decides which end the colours travel to.
            let step = direction == .left ? 1.0 : -1.0
            for f in 0..<frames {
                for led in 0..<ledCount {
                    let hue = Double(led) / Double(ledCount) + step * Double(f) / Double(frames)
                    setColor(.hsv(hue, 1, 1), frame: f, led: led)
                }
            }
            bytes[4] = lastFrame
        case .strobe:
            // Two quick flashes, a pause, then two more; with two colours they take turns.
            let a = palette[0], b = palette.count > 1 ? palette[1] : palette[0]
            let half = frames / 2
            for (f, c) in [(0, a), (2, a), (half, b), (half + 2, b)] where f < frames { fill(frame: f, with: c) }
            bytes[4] = lastFrame
        case .rainbowFade:
            // The whole bar is one colour that fades around the hue wheel.
            for f in 0..<frames { fill(frame: f, with: .hsv(Double(f) / Double(frames), 1, 1)) }
            bytes[4] = lastFrame
        case .comet:
            // A bright head with a fading tail runs along the bar and wraps around.
            for f in 0..<frames {
                let h = Int((Double(f) * Double(ledCount) / Double(frames)).rounded()) % ledCount
                for (k, level) in [1.0, 0.35, 0.12].enumerated() {
                    // Going left the head counts down and the tail trails to its right; going right, the reverse.
                    let led = direction == .left ? (ledCount - 1 - h + k) % ledCount : (h - k + ledCount) % ledCount
                    setColor(palette[0].scaled(level), frame: f, led: led)
                }
            }
            bytes[4] = lastFrame
        case .scanner:
            // A light sweeping out and back, sampled evenly along the round trip.
            let trip = Double(2 * (ledCount - 1))
            for f in 0..<frames {
                let p = Double(f) * trip / Double(frames)
                let pos = Int((p <= Double(ledCount - 1) ? p : trip - p).rounded())
                for (d, level) in [(0, 1.0), (-1, 0.25), (1, 0.25)] where (0..<ledCount).contains(pos + d) {
                    setColor(palette[0].scaled(level), frame: f, led: pos + d)
                }
            }
            bytes[4] = lastFrame
        case .fire:
            // Warm flicker from a fixed seed, so the frames come out the same every time and can be recognised.
            var seed: UInt32 = 0x5EED
            func random() -> Double {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                return Double(seed >> 8) / Double(1 << 24)
            }
            for f in 0..<frames {
                for led in 0..<ledCount {
                    setColor(.hsv(0.01 + 0.09 * random(), 1, 0.35 + 0.65 * random()), frame: f, led: led)
                }
            }
            bytes[4] = lastFrame
        case .factory:
            break
        }
    }
}

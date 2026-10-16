import Foundation

/// Compiles a stick response curve into the nine-point bank the controller
/// plays.
///
/// The controller does not evaluate the curve fields (dead zone, edge and
/// the two interior points); it plays nine output samples taken at evenly
/// spaced stick travel. Hardware measurements by OpenFlydigi showed that
/// editing the curve fields alone changes nothing you can feel, so every
/// stick edit must recompile the bank. Ported from OpenFlydigi's
/// `stick_nodes` / `stick_bank` (MIT).
public enum StickCurveCompiler {
    public static let points = 9

    /// Polyline nodes in percent (x = stick travel, y = output).
    public static func nodes(
        deadZone: Int, outerDeadZone: Int, point1: CurvePoint, point2: CurvePoint
    ) -> [(x: Double, y: Double)] {
        let start = (x: Double(max(0, deadZone)), y: 0.0)
        let end = (x: 100.0 - Double(max(0, outerDeadZone)), y: 100.0)
        let span = end.x - start.x
        guard span > 0 else { return [start, end] }
        let scale = 100.0 / 127.0
        func interior(_ p: CurvePoint) -> (x: Double, y: Double) {
            (start.x + span * (Double(p.x) * scale) / 100.0, Double(p.y) * scale)
        }
        return [start, interior(point1), interior(point2), end]
    }

    /// Output at `x`, extrapolating the end segments past either end.
    public static func sample(_ nodes: [(x: Double, y: Double)], at x: Double) -> Double {
        for i in 0..<(nodes.count - 1) {
            let (a, b) = (nodes[i], nodes[i + 1])
            if x <= b.x || i == nodes.count - 2 {
                if a.x == b.x { return x < a.x ? a.y : b.y }
                return a.y + (b.y - a.y) * (x - a.x) / (b.x - a.x)
            }
        }
        return nodes.last!.y
    }

    /// Bank bytes are `output percent + 50`, truncated, clamped to 0...150.
    /// Truncation reproduces the factory bank `50 62 75 87 100 112 125 137 150`.
    public static func bank(
        deadZone: Int, outerDeadZone: Int, point1: CurvePoint, point2: CurvePoint
    ) -> [UInt8] {
        let n = nodes(deadZone: deadZone, outerDeadZone: outerDeadZone, point1: point1, point2: point2)
        return (0..<points).map { i in
            let value = sample(n, at: 100.0 * Double(i) / Double(points - 1))
            return UInt8(Int(max(-50, min(100, value))) + 50)
        }
    }

    /// The response the controller will produce, 0...1, for drawing.
    public static func response(bank: [UInt8], at travel: Double) -> Double {
        guard bank.count == points else { return travel }
        let position = max(0, min(1, travel)) * Double(points - 1)
        let i = min(points - 2, Int(position))
        let t = position - Double(i)
        let a = Double(bank[i]) - 50, b = Double(bank[i + 1]) - 50
        return max(0, min(100, a + (b - a) * t)) / 100
    }
}

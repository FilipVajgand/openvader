import SwiftUI
import VaderKit

/// A schematic of the Vader 5 Pro: front face, shoulder row and back paddles.
/// Drawn from scratch; no vendor artwork.
struct ControllerDiagram: View {
    var pressed: Set<ControllerKey> = []
    var selected: ControllerKey?
    var marked: Set<ControllerKey> = []
    var leftStick = SIMD2<Double>(0, 0)
    var rightStick = SIMD2<Double>(0, 0)
    var leftTrigger = 0.0
    var rightTrigger = 0.0
    var showsBack = true
    var onTap: ((ControllerKey) -> Void)?

    /// Design space; everything is laid out in these units and scaled.
    static let size = CGSize(width: 640, height: 470)

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / Self.size.width, geo.size.height / Self.size.height)
            canvas
                .frame(width: Self.size.width, height: Self.size.height)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: Self.size.width * scale, height: Self.size.height * scale, alignment: .topLeading)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(Self.size.width / Self.size.height, contentMode: .fit)
    }

    private var canvas: some View {
        ZStack(alignment: .topLeading) {
            // Shoulder row
            trigger(.lt, x: 70, value: leftTrigger)
            trigger(.rt, x: 500, value: rightTrigger)
            pill(.lb, x: 170, y: 22, w: 78)
            pill(.lm, x: 252, y: 22, w: 44)
            pill(.rm, x: 344, y: 22, w: 44)
            pill(.rb, x: 392, y: 22, w: 78)

            // Body
            BodyShape()
                .fill(.quaternary.opacity(0.55))
                .overlay(BodyShape().stroke(.secondary.opacity(0.5), lineWidth: 1.5))
                .frame(width: 600, height: 270)
                .position(x: 320, y: 195)

            stick(.l3, center: CGPoint(x: 175, y: 140), value: leftStick)
            stick(.r3, center: CGPoint(x: 400, y: 215), value: rightStick)
            dpad(center: CGPoint(x: 240, y: 215))
            face(.y, x: 470, y: 102)
            face(.x, x: 432, y: 140)
            face(.b, x: 508, y: 140)
            face(.a, x: 470, y: 178)
            round(.c, x: 378, y: 108, r: 13)
            round(.z, x: 404, y: 84, r: 13)
            pill(.select, x: 262, y: 120, w: 34, h: 18)
            pill(.start, x: 344, y: 120, w: 34, h: 18)
            round(.home, x: 320, y: 88, r: 17, symbol: "house.fill")
            round(.fn, x: 320, y: 158, r: 11, caption: "Fn")

            if showsBack {
                Text("BACK").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                    .position(x: 320, y: 352)
                BackShape()
                    .fill(.quaternary.opacity(0.35))
                    .overlay(BackShape().stroke(.secondary.opacity(0.4), lineWidth: 1))
                    .frame(width: 600, height: 100)
                    .position(x: 320, y: 412)
                paddle(.m3, x: 128, y: 418)
                paddle(.m1, x: 228, y: 400)
                paddle(.m2, x: 412, y: 400)
                paddle(.m4, x: 512, y: 418)
                round(.turbo, x: 320, y: 432, r: 11, caption: "T")
            }
        }
    }

    // MARK: Pieces

    private func fill(_ key: ControllerKey) -> AnyShapeStyle {
        if pressed.contains(key) { return AnyShapeStyle(Color.accentColor) }
        if selected == key { return AnyShapeStyle(Color.accentColor.opacity(0.35)) }
        if marked.contains(key) { return AnyShapeStyle(Color.orange.opacity(0.35)) }
        return AnyShapeStyle(.background)
    }

    private func stroke(_ key: ControllerKey) -> Color {
        selected == key ? .accentColor : (marked.contains(key) ? .orange : .secondary.opacity(0.7))
    }

    private func textColor(_ key: ControllerKey) -> Color {
        pressed.contains(key) ? .white : .primary
    }

    private func tappable<V: View>(_ key: ControllerKey, _ view: V) -> some View {
        view
            .contentShape(Rectangle())
            .onTapGesture { onTap?(key) }
            .help(key.name)
            .accessibilityLabel(key.name)
            .accessibilityAddTraits(onTap == nil ? [] : .isButton)
    }

    private func round(_ key: ControllerKey, x: CGFloat, y: CGFloat, r: CGFloat, caption: String? = nil,
                       symbol: String? = nil) -> some View {
        tappable(key, ZStack {
            Circle().fill(fill(key))
            Circle().stroke(stroke(key), lineWidth: selected == key ? 2.5 : 1.2)
            if let symbol {
                Image(systemName: symbol).font(.system(size: r * 0.8, weight: .bold)).foregroundStyle(textColor(key))
            } else {
                Text(caption ?? key.short).font(.system(size: r * 0.85, weight: .bold, design: .rounded))
                    .foregroundStyle(textColor(key))
            }
        }
        .frame(width: r * 2, height: r * 2))
        .position(x: x, y: y)
    }

    private func face(_ key: ControllerKey, x: CGFloat, y: CGFloat) -> some View {
        round(key, x: x, y: y, r: 18)
    }

    private func pill(_ key: ControllerKey, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat = 24) -> some View {
        tappable(key, ZStack {
            Capsule().fill(fill(key))
            Capsule().stroke(stroke(key), lineWidth: selected == key ? 2.5 : 1.2)
            Text(key.short).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(textColor(key))
        }
        .frame(width: w, height: h))
        .position(x: x, y: y)
    }

    private func paddle(_ key: ControllerKey, x: CGFloat, y: CGFloat) -> some View {
        tappable(key, ZStack {
            RoundedRectangle(cornerRadius: 9).fill(fill(key))
            RoundedRectangle(cornerRadius: 9).stroke(stroke(key), lineWidth: selected == key ? 2.5 : 1.2)
            Text(key.short).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(textColor(key))
        }
        .frame(width: 64, height: 34))
        .position(x: x, y: y)
    }

    private func trigger(_ key: ControllerKey, x: CGFloat, value: Double) -> some View {
        tappable(key, ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 8).fill(fill(key))
            RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.85))
                .frame(height: max(0, 30 * value))
            RoundedRectangle(cornerRadius: 8).stroke(stroke(key), lineWidth: selected == key ? 2.5 : 1.2)
            Text(key.short).font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(value > 0.5 || pressed.contains(key) ? .white : .primary)
                .frame(maxHeight: .infinity)
        }
        .frame(width: 70, height: 30))
        .position(x: x + 35, y: 22)
    }

    private func stick(_ key: ControllerKey, center: CGPoint, value: SIMD2<Double>) -> some View {
        let travel: CGFloat = 16
        return tappable(key, ZStack {
            Circle().fill(.background.opacity(0.6))
            Circle().stroke(.secondary.opacity(0.5), lineWidth: 1)
            ZStack {
                Circle().fill(fill(key))
                Circle().stroke(stroke(key), lineWidth: selected == key ? 2.5 : 1.5)
                Text(key.short).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(textColor(key))
            }
            .frame(width: 42, height: 42)
            .offset(x: CGFloat(value.x) * travel, y: CGFloat(-value.y) * travel)
        }
        .frame(width: 76, height: 76))
        .position(center)
    }

    private func dpad(center: CGPoint) -> some View {
        ZStack {
            Circle().fill(.background.opacity(0.6)).frame(width: 84, height: 84)
            Circle().stroke(.secondary.opacity(0.5), lineWidth: 1).frame(width: 84, height: 84)
            dpadArm(.up).offset(y: -22)
            dpadArm(.down).offset(y: 22)
            dpadArm(.left).offset(x: -22)
            dpadArm(.right).offset(x: 22)
        }
        .position(center)
    }

    private func dpadArm(_ key: ControllerKey) -> some View {
        tappable(key, ZStack {
            RoundedRectangle(cornerRadius: 5).fill(fill(key))
            RoundedRectangle(cornerRadius: 5).stroke(stroke(key), lineWidth: selected == key ? 2.5 : 1.2)
            Text(key.short).font(.system(size: 12, weight: .bold)).foregroundStyle(textColor(key))
        }
        .frame(width: 26, height: 26))
    }
}

/// Outline of the controller's face: a wide body flowing into two grips.
struct BodyShape: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.22, y: h * 0.04))
        p.addCurve(to: CGPoint(x: w * 0.78, y: h * 0.04),
                   control1: CGPoint(x: w * 0.40, y: -h * 0.02), control2: CGPoint(x: w * 0.60, y: -h * 0.02))
        p.addCurve(to: CGPoint(x: w * 0.99, y: h * 0.62),
                   control1: CGPoint(x: w * 0.93, y: h * 0.08), control2: CGPoint(x: w * 0.99, y: h * 0.38))
        p.addCurve(to: CGPoint(x: w * 0.86, y: h * 0.98),
                   control1: CGPoint(x: w * 1.0, y: h * 0.86), control2: CGPoint(x: w * 0.94, y: h * 1.0))
        p.addCurve(to: CGPoint(x: w * 0.68, y: h * 0.70),
                   control1: CGPoint(x: w * 0.78, y: h * 0.96), control2: CGPoint(x: w * 0.74, y: h * 0.72))
        p.addCurve(to: CGPoint(x: w * 0.32, y: h * 0.70),
                   control1: CGPoint(x: w * 0.56, y: h * 0.66), control2: CGPoint(x: w * 0.44, y: h * 0.66))
        p.addCurve(to: CGPoint(x: w * 0.14, y: h * 0.98),
                   control1: CGPoint(x: w * 0.26, y: h * 0.72), control2: CGPoint(x: w * 0.22, y: h * 0.96))
        p.addCurve(to: CGPoint(x: w * 0.01, y: h * 0.62),
                   control1: CGPoint(x: w * 0.06, y: h * 1.0), control2: CGPoint(x: w * 0.0, y: h * 0.86))
        p.addCurve(to: CGPoint(x: w * 0.22, y: h * 0.04),
                   control1: CGPoint(x: w * 0.01, y: h * 0.38), control2: CGPoint(x: w * 0.07, y: h * 0.08))
        p.closeSubpath()
        return p
    }
}

/// The back of the controller, seen from behind (left paddles stay on the left).
struct BackShape: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.06, y: h * 0.10))
        p.addCurve(to: CGPoint(x: w * 0.94, y: h * 0.10),
                   control1: CGPoint(x: w * 0.35, y: -h * 0.05), control2: CGPoint(x: w * 0.65, y: -h * 0.05))
        p.addCurve(to: CGPoint(x: w * 0.88, y: h * 0.95),
                   control1: CGPoint(x: w * 1.02, y: h * 0.40), control2: CGPoint(x: w * 0.98, y: h * 0.90))
        p.addCurve(to: CGPoint(x: w * 0.12, y: h * 0.95),
                   control1: CGPoint(x: w * 0.65, y: h * 0.75), control2: CGPoint(x: w * 0.35, y: h * 0.75))
        p.addCurve(to: CGPoint(x: w * 0.06, y: h * 0.10),
                   control1: CGPoint(x: w * 0.02, y: h * 0.90), control2: CGPoint(x: -w * 0.02, y: h * 0.40))
        p.closeSubpath()
        return p
    }
}

import SwiftUI
import VaderKit

/// The Vader 5 Pro, front and back.
///
/// Outlines come from the line drawings on the official manual's appearance page (see
/// `VaderOutline`), and every control sits where the manual draws it. All drawing is original:
/// no vendor artwork is bundled.
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
    static let width: CGFloat = 640
    /// The front silhouette's box, in the manual drawing's proportions (1234 × 820).
    static var frontRect: CGRect { CGRect(x: 20, y: 14, width: 600, height: 600 * 820 / 1234) }
    /// The back silhouette's box (1320 × 870 in the manual).
    static var backRect: CGRect { CGRect(x: 140, y: 472, width: 360, height: 360 * 870 / 1320) }
    private var height: CGFloat { showsBack ? 724 : 428 }

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / Self.width, geo.size.height / height)
            canvas
                .frame(width: Self.width, height: height, alignment: .topLeading)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: Self.width * scale, height: height * scale, alignment: .topLeading)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(Self.width / height, contentMode: .fit)
    }

    private var canvas: some View {
        ZStack(alignment: .topLeading) {
            frontBody
            frontShoulders
            frontControls
            if showsBack {
                Text("BACK  ·  seen through the controller, so left stays left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .position(x: Self.width / 2, y: Self.backRect.minY - 18)
                backBody
                backControls
            }
        }
    }

    // MARK: Coordinates

    /// A point on the front, in fractions of the silhouette's box.
    private func f(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: Self.frontRect.minX + x * Self.frontRect.width, y: Self.frontRect.minY + y * Self.frontRect.height)
    }

    private func b(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: Self.backRect.minX + x * Self.backRect.width, y: Self.backRect.minY + y * Self.backRect.height)
    }

    // MARK: Colours

    private static let shell = LinearGradient(colors: [Color(white: 0.2), Color(white: 0.1)], startPoint: .top, endPoint: .bottom)
    private static let part = LinearGradient(colors: [Color(white: 0.25), Color(white: 0.11)], startPoint: .top, endPoint: .bottom)
    private static let gold = LinearGradient(colors: [Color(red: 0.84, green: 0.70, blue: 0.45), Color(red: 0.55, green: 0.42, blue: 0.22)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)
    private static let goldLine = Color(red: 0.82, green: 0.66, blue: 0.36)
    private static let rim = Color(white: 0.34)

    private func base(_ key: ControllerKey) -> Color {
        pressed.contains(key) ? .accentColor : Color(white: 0.09)
    }

    private func ring(_ key: ControllerKey) -> Color? {
        if selected == key { return .accentColor }
        if marked.contains(key) { return .orange }
        return nil
    }

    private func label(_ key: ControllerKey) -> Color {
        pressed.contains(key) ? .white : Color(white: 0.8)
    }

    private func tappable<V: View>(_ key: ControllerKey, _ view: V) -> some View {
        view
            .contentShape(Rectangle())
            .onTapGesture { onTap?(key) }
            .help(key.name)
            .accessibilityElement()
            .accessibilityLabel(key.name)
            .accessibilityAddTraits(onTap == nil ? [] : .isButton)
    }

    // MARK: Front

    private var frontBody: some View {
        ZStack(alignment: .topLeading) {
            TracedShape(points: VaderOutline.front)
                .fill(Self.shell)
                .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                .overlay(TracedShape(points: VaderOutline.front).stroke(Color(white: 0.32), lineWidth: 1))
                .frame(width: Self.frontRect.width, height: Self.frontRect.height)
                .offset(x: Self.frontRect.minX, y: Self.frontRect.minY)
            // The gold trim along the inner bottom edge.
            InnerTrim()
                .stroke(Self.goldLine, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .frame(width: Self.frontRect.width, height: Self.frontRect.height)
                .offset(x: Self.frontRect.minX, y: Self.frontRect.minY)
            // V panel with its speckled finish, from the top edge down to a point below the logo.
            VPanelShape()
                .fill(Color(white: 0.15))
                .overlay(VPanelShape().stroke(Color(white: 0.3), lineWidth: 1))
                .overlay(Speckles().fill(Self.goldLine.opacity(0.8)).clipShape(VPanelShape()))
                .frame(width: 0.348 * Self.frontRect.width, height: 0.271 * Self.frontRect.height)
                .position(f(0.5, 0.0525 + 0.271 / 2))
            Text("VADER 5 PRO")
                .font(.system(size: 9, weight: .semibold))
                .tracking(2)
                .foregroundStyle(Color(white: 0.75))
                .rotationEffect(.degrees(72))
                .position(f(0.93, 0.70))
        }
    }

    private var frontShoulders: some View {
        let r = Self.frontRect
        return ZStack(alignment: .topLeading) {
            outlineKey(.lt, VaderOutline.frontTriggerTip, mirrored: false, in: r, level: leftTrigger,
                       label: f(0.223, 0.028), size: 8, hitPadding: 10)
            outlineKey(.rt, VaderOutline.frontTriggerTip, mirrored: true, in: r, level: rightTrigger,
                       label: f(0.777, 0.028), size: 8, hitPadding: 10)
            outlineKey(.lb, VaderOutline.frontBumper, mirrored: false, in: r, label: f(0.262, 0.058), size: 10, rotation: -10)
            outlineKey(.rb, VaderOutline.frontBumper, mirrored: true, in: r, label: f(0.738, 0.058), size: 10, rotation: 10)
            pillKey(.lm, center: f(0.445, 0.025), size: CGSize(width: 28, height: 12))
            pillKey(.rm, center: f(0.555, 0.025), size: CGSize(width: 28, height: 12))
        }
    }

    private var frontControls: some View {
        ZStack(alignment: .topLeading) {
            homeKey(center: f(0.501, 0.174))
            smallKey(.select, center: f(0.419, 0.278), size: CGSize(width: 44, height: 19), rotation: 46,
                     symbol: "rectangle.on.rectangle")
            smallKey(.start, center: f(0.581, 0.278), size: CGSize(width: 44, height: 19), rotation: -46,
                     symbol: "line.3.horizontal")
            stickKey(.l3, center: f(0.2467, 0.3093), value: leftStick)
            stickKey(.r3, center: f(0.6245, 0.5416), value: rightStick)
            dpad(center: f(0.3706, 0.5390))
            faceKey(.y, center: f(0.7510, 0.2057))
            faceKey(.x, center: f(0.6847, 0.3072))
            faceKey(.b, center: f(0.8185, 0.3080))
            faceKey(.a, center: f(0.7509, 0.4020))
            roundKey(.z, center: f(0.8532, 0.4771), radius: 16)
            roundKey(.c, center: f(0.7877, 0.5598), radius: 16)
        }
    }

    // MARK: Back

    private var backBody: some View {
        let r = Self.backRect
        return ZStack(alignment: .topLeading) {
            TracedShape(points: VaderOutline.back)
                .fill(LinearGradient(colors: [Color(white: 0.17), Color(white: 0.09)], startPoint: .top, endPoint: .bottom))
                .overlay(TracedShape(points: VaderOutline.back).stroke(Color(white: 0.32), lineWidth: 1))
                .frame(width: r.width, height: r.height)
                .offset(x: r.minX, y: r.minY)
            TracedShape(points: VaderOutline.backPlate)
                .fill(Color.white.opacity(0.025))
                .overlay(TracedShape(points: VaderOutline.backPlate).stroke(Color(white: 0.27), lineWidth: 1))
                .frame(width: r.width, height: r.height)
                .offset(x: r.minX, y: r.minY)
            // Holder slot with its latch.
            RoundedRectangle(cornerRadius: 4).stroke(Color(white: 0.3), lineWidth: 1)
                .frame(width: 0.217 * r.width, height: 0.209 * r.height)
                .position(b(0.5, 0.167))
            RoundedRectangle(cornerRadius: 2).fill(Color(white: 0.3)).frame(width: 14, height: 4).position(b(0.5, 0.255))
            slider(center: b(0.328, 0.342), vertical: true, help: "Left trigger switch: click or travel")
            slider(center: b(0.672, 0.342), vertical: true, help: "Right trigger switch: click or travel")
            slider(center: b(0.5, 0.539), vertical: false, help: "Mode switch: receiver/cable · Bluetooth · Switch")
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(Self.goldLine.opacity(0.9)).frame(width: 5, height: 5)
                    .position(b(0.468 + CGFloat(i) * 0.032, 0.643))
            }
        }
    }

    private var backControls: some View {
        let r = Self.backRect
        return ZStack(alignment: .topLeading) {
            outlineKey(.lt, VaderOutline.backTrigger, mirrored: false, in: r, level: leftTrigger, label: b(0.229, 0.066), size: 9)
            outlineKey(.rt, VaderOutline.backTrigger, mirrored: true, in: r, level: rightTrigger, label: b(0.771, 0.066), size: 9)
            outlineKey(.lb, VaderOutline.backBumper, mirrored: false, in: r, label: b(0.343, 0.041), size: 8)
            outlineKey(.rb, VaderOutline.backBumper, mirrored: true, in: r, label: b(0.657, 0.041), size: 8)
            outlineKey(.m1, VaderOutline.upperPaddle, mirrored: false, in: r, label: b(0.283, 0.516), size: 11)
            outlineKey(.m2, VaderOutline.upperPaddle, mirrored: true, in: r, label: b(0.717, 0.516), size: 11)
            outlineKey(.m3, VaderOutline.lowerPaddle, mirrored: false, in: r, label: b(0.301, 0.687), size: 11)
            outlineKey(.m4, VaderOutline.lowerPaddle, mirrored: true, in: r, label: b(0.699, 0.687), size: 11)
            // Seen through the controller, Turbo is on the left and Fn on the right.
            smallKey(.turbo, center: b(0.448, 0.741), size: CGSize(width: 24, height: 11), rotation: 0, symbol: "forward.end")
            smallKey(.fn, center: b(0.552, 0.741), size: CGSize(width: 24, height: 11), rotation: 0, symbol: "circle")
        }
    }

    // MARK: Pieces

    private func selection(_ key: ControllerKey) -> some View {
        Group {
            if let c = ring(key) { Circle().stroke(c, lineWidth: 3).padding(-3) }
        }
    }

    /// A part drawn from a traced outline that fills `rect`; `level` fills it from the bottom (triggers).
    private func outlineKey(_ key: ControllerKey, _ points: [(CGFloat, CGFloat)], mirrored: Bool, in rect: CGRect,
                            level: Double? = nil, label at: CGPoint, size: CGFloat, rotation: Double = 0,
                            hitPadding: CGFloat = 0) -> some View {
        let shape = TracedShape(points: points, mirrored: mirrored)
        let ys = points.map(\.1), top = ys.min() ?? 0, bottom = ys.max() ?? 1
        let filled = CGFloat(max(0, min(1, level ?? 0)))
        let xs = points.map { mirrored ? 1 - $0.0 : $0.0 }
        let box = CGRect(x: rect.minX + (xs.min() ?? 0) * rect.width, y: rect.minY + top * rect.height,
                         width: ((xs.max() ?? 1) - (xs.min() ?? 0)) * rect.width, height: (bottom - top) * rect.height)
        return ZStack(alignment: .topLeading) {
            shape.fill(pressed.contains(key) ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Self.part))
                .frame(width: rect.width, height: rect.height)
            if filled > 0 {
                shape.fill(Color.accentColor.opacity(0.9))
                    .frame(width: rect.width, height: rect.height)
                    .mask(alignment: .topLeading) {
                        Rectangle()
                            .frame(width: rect.width, height: (bottom - top) * filled * rect.height)
                            .offset(y: (bottom - (bottom - top) * filled) * rect.height)
                    }
            }
            shape.stroke(ring(key) ?? Self.rim, lineWidth: ring(key) == nil ? 1 : 2.5)
                .frame(width: rect.width, height: rect.height)
            Text(key.short)
                .font(.system(size: size, weight: .bold, design: .rounded))
                .foregroundStyle(pressed.contains(key) || filled > 0.5 ? .white : Color(white: 0.8))
                .rotationEffect(.degrees(rotation))
                .position(x: at.x - rect.minX, y: at.y - rect.minY)
        }
        .frame(width: rect.width, height: rect.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .offset(x: rect.minX, y: rect.minY)
        .overlay(alignment: .topLeading) {
            // Hit area: the part itself, grown for the small trigger tips.
            tappable(key, Color.clear.frame(width: box.width + 2 * hitPadding, height: box.height + 2 * hitPadding))
                .offset(x: box.minX - hitPadding, y: box.minY - hitPadding)
        }
    }

    private func faceKey(_ key: ControllerKey, center: CGPoint) -> some View {
        let r: CGFloat = 18.5
        return tappable(key, ZStack {
            Circle().fill(Color.black.opacity(0.5)).offset(y: 1.5)
            Circle().fill(pressed.contains(key) ? AnyShapeStyle(Color.accentColor)
                          : AnyShapeStyle(LinearGradient(colors: [Color(white: 0.2), Color(white: 0.06)],
                                                         startPoint: .top, endPoint: .bottom)))
            Circle().stroke(Self.rim, lineWidth: 1)
            Text(key.short).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(label(key))
            selection(key)
        }
        .frame(width: 2 * r, height: 2 * r))
        .position(center)
    }

    private func roundKey(_ key: ControllerKey, center: CGPoint, radius r: CGFloat) -> some View {
        tappable(key, ZStack {
            Circle().fill(Color.black.opacity(0.5)).offset(y: 1.5)
            Circle().fill(pressed.contains(key) ? AnyShapeStyle(Color.accentColor)
                          : AnyShapeStyle(LinearGradient(colors: [Color(white: 0.17), Color(white: 0.05)],
                                                         startPoint: .top, endPoint: .bottom)))
            Circle().stroke(Self.rim, lineWidth: 1)
            Text(key.short).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(label(key))
            selection(key)
        }
        .frame(width: 2 * r, height: 2 * r))
        .position(center)
    }

    private func smallKey(_ key: ControllerKey, center: CGPoint, size: CGSize, rotation: Double, symbol: String) -> some View {
        tappable(key, ZStack {
            Capsule().fill(base(key))
            Capsule().stroke(ring(key) ?? Self.rim, lineWidth: ring(key) == nil ? 1 : 2.5)
            Image(systemName: symbol).font(.system(size: min(9, size.height * 0.5), weight: .bold)).foregroundStyle(label(key))
                .rotationEffect(.degrees(-rotation))
        }
        .frame(width: size.width, height: size.height)
        .rotationEffect(.degrees(rotation)))
        .position(center)
    }

    private func homeKey(center: CGPoint) -> some View {
        tappable(.home, ZStack {
            if pressed.contains(.home) { Circle().fill(Color.accentColor.opacity(0.85)) }
            LogoMark().fill(pressed.contains(.home) ? .white : Color(white: 0.95)).frame(width: 44, height: 38)
            selection(.home)
        }
        .frame(width: 54, height: 54))
        .position(center)
    }

    private func pillKey(_ key: ControllerKey, center: CGPoint, size: CGSize) -> some View {
        tappable(key, ZStack {
            Capsule().fill(base(key))
            Capsule().stroke(ring(key) ?? Self.rim, lineWidth: ring(key) == nil ? 1 : 2.5)
            Text(key.short).font(.system(size: 8, weight: .bold, design: .rounded)).foregroundStyle(label(key))
        }
        .frame(width: size.width, height: size.height))
        .position(center)
    }

    /// A stick under its gold tension dial: the dial is 17.5 % of the body's width, the cap 40 % of the dial.
    private func stickKey(_ key: ControllerKey, center: CGPoint, value: SIMD2<Double>) -> some View {
        let d: CGFloat = 105, r = d / 2, travel: CGFloat = 12
        return tappable(key, ZStack {
            // Dark bezel with the dial's scale marks.
            Circle().fill(Color.black.opacity(0.6))
            ForEach(0..<12, id: \.self) { i in
                Rectangle().fill(Color(white: 0.55)).frame(width: 1.2, height: 0.09 * r)
                    .offset(y: -0.93 * r)
                    .rotationEffect(.degrees(Double(i) * 30))
            }
            // Knurled gold dial.
            Circle().stroke(Self.gold, lineWidth: 0.3 * r).padding(0.15 * r + 0.15 * r)
            ForEach(0..<60, id: \.self) { i in
                Rectangle().fill(Color.black.opacity(0.3)).frame(width: 1, height: 0.26 * r)
                    .offset(y: -0.71 * r)
                    .rotationEffect(.degrees(Double(i) * 6))
            }
            Circle().fill(Color(white: 0.05)).padding(0.44 * r)
            ZStack {
                Circle().fill(pressed.contains(key) ? AnyShapeStyle(Color.accentColor)
                              : AnyShapeStyle(RadialGradient(colors: [Color(white: 0.2), Color(white: 0.07)],
                                                             center: .init(x: 0.4, y: 0.35), startRadius: 2, endRadius: 26)))
                Circle().stroke(Color(white: 0.26), lineWidth: 1)
                Circle().stroke(Color(white: 0.18), style: StrokeStyle(lineWidth: 3, dash: [1.5, 1.5])).padding(4)
                Text(key.short).font(.system(size: 9, weight: .bold, design: .rounded)).foregroundStyle(label(key).opacity(0.8))
                selection(key)
            }
            .frame(width: 0.8 * r, height: 0.8 * r)
            .offset(x: CGFloat(value.x) * travel, y: CGFloat(-value.y) * travel)
        }
        .frame(width: d, height: d))
        .position(center)
    }

    /// The rotational D-pad: a rounded square turned 45°, with a plus cut into it.
    private func dpad(center: CGPoint) -> some View {
        let s: CGFloat = 103
        return ZStack {
            DpadShape()
                .fill(LinearGradient(colors: [Color(white: 0.17), Color(white: 0.04)], startPoint: .top, endPoint: .bottom))
                .overlay(DpadShape().stroke(Self.rim, lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 2, y: 2)
            CrossShape().stroke(Color.black.opacity(0.7), lineWidth: 1.5).clipShape(DpadShape())
            ForEach([(ControllerKey.up, 0.0), (.right, 90.0), (.down, 180.0), (.left, 270.0)], id: \.0) { key, angle in
                dpadArm(key, angle: angle)
            }
        }
        .frame(width: s, height: s)
        .position(center)
    }

    /// One tappable arm, drawn pointing up in a D-pad-sized box and rotated into place.
    private func dpadArm(_ key: ControllerKey, angle: Double) -> some View {
        ZStack {
            ArmShape().fill(pressed.contains(key) ? Color.accentColor : .clear).clipShape(DpadShape())
            if let c = ring(key) { ArmShape().stroke(c, lineWidth: 2.5).clipShape(DpadShape()) }
            Image(systemName: "arrowtriangle.up.fill").font(.system(size: 7))
                .foregroundStyle(pressed.contains(key) ? .white : Color(white: 0.4))
                .position(x: 51.5, y: 16)
            tappable(key, Color.clear.frame(width: 34, height: 36)).position(x: 51.5, y: 18)
        }
        .frame(width: 103, height: 103)
        .rotationEffect(.degrees(angle))
    }

    private func slider(center: CGPoint, vertical: Bool, help: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3).fill(Color.black)
            RoundedRectangle(cornerRadius: 2).fill(Color(white: 0.45))
                .frame(width: vertical ? 5 : 9, height: vertical ? 9 : 5)
        }
        .frame(width: vertical ? 9 : 24, height: vertical ? 23 : 11)
        .help(help)
        .position(center)
    }
}

// MARK: - Shapes

/// A closed outline in fractions of its frame, optionally mirrored left-right, smoothed with a Catmull-Rom spline.
struct TracedShape: Shape {
    var points: [(CGFloat, CGFloat)]
    var mirrored = false

    func path(in r: CGRect) -> Path {
        CatmullRom.closed(points.map {
            CGPoint(x: r.minX + (mirrored ? 1 - $0.0 : $0.0) * r.width, y: r.minY + $0.1 * r.height)
        })
    }
}

/// The gold line that follows the body's inner bottom edge, a little inside it.
struct InnerTrim: Shape {
    func path(in r: CGRect) -> Path {
        let pts = VaderOutline.front.filter { $0.1 > 0.77 && $0.1 < 0.9 && $0.0 > 0.19 && $0.0 < 0.81 }
            .sorted { $0.0 < $1.0 }
        return CatmullRom.open(pts.map { CGPoint(x: r.minX + $0.0 * r.width, y: r.minY + ($0.1 - 0.022) * r.height) })
    }
}

enum CatmullRom {
    static func closed(_ p: [CGPoint]) -> Path {
        var path = Path()
        guard p.count > 2 else { return path }
        path.move(to: p[0])
        for i in 0..<p.count {
            let p0 = p[(i - 1 + p.count) % p.count], p1 = p[i], p2 = p[(i + 1) % p.count], p3 = p[(i + 2) % p.count]
            path.addCurve(to: p2, control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                          control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        path.closeSubpath()
        return path
    }

    static func open(_ p: [CGPoint]) -> Path {
        var path = Path()
        guard p.count > 1 else { return path }
        path.move(to: p[0])
        for i in 0..<(p.count - 1) {
            let p0 = p[max(0, i - 1)], p1 = p[i], p2 = p[i + 1], p3 = p[min(p.count - 1, i + 2)]
            path.addCurve(to: p2, control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                          control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        return path
    }
}

/// The V-shaped panel around the logo: a wide top edge narrowing to a rounded point.
struct VPanelShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + 8, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - 8, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - 5, y: r.minY + 8), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX + 9, y: r.maxY - 7))
        p.addQuadCurve(to: CGPoint(x: r.midX - 9, y: r.maxY - 7), control: CGPoint(x: r.midX, y: r.maxY + 2))
        p.addLine(to: CGPoint(x: r.minX + 5, y: r.minY + 8))
        p.addQuadCurve(to: CGPoint(x: r.minX + 8, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.closeSubpath()
        return p
    }
}

/// A fine scatter of dots for the V panel's finish (deterministic).
struct Speckles: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        var seed: UInt64 = 0x5EED
        for _ in 0..<70 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let x = CGFloat((seed >> 33) % 1000) / 1000
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let y = CGFloat((seed >> 33) % 1000) / 1000
            p.addEllipse(in: CGRect(x: r.minX + x * r.width, y: r.minY + y * r.height, width: 1.1, height: 1.1))
        }
        return p
    }
}

/// A stylised emblem for the home button.
struct LogoMark: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: w * 0.38, y: h * 0.2))
        p.addLine(to: CGPoint(x: w * 0.5, y: h * 0.56))
        p.addLine(to: CGPoint(x: w * 0.62, y: h * 0.2))
        p.addLine(to: CGPoint(x: w, y: 0))
        p.addLine(to: CGPoint(x: w * 0.5, y: h))
        p.closeSubpath()
        return p.offsetBy(dx: r.minX, dy: r.minY)
    }
}

/// The D-pad's body: a square with large rounded corners, turned 45° and filling its frame corner to corner.
struct DpadShape: Shape {
    func path(in r: CGRect) -> Path {
        // With corner radius 0.28 × side, the turned square's corner-to-corner extent is 1.1823 × side.
        let side = r.width / 1.1823
        let square = CGRect(x: r.midX - side / 2, y: r.midY - side / 2, width: side, height: side)
        let p = Path(roundedRect: square, cornerRadius: 0.28 * side)
        let turn = CGAffineTransform(translationX: r.midX, y: r.midY).rotated(by: .pi / 4).translatedBy(x: -r.midX, y: -r.midY)
        return p.applying(turn)
    }
}

/// The plus cut into the D-pad, as an outline spanning the whole frame.
struct CrossShape: Shape {
    func path(in r: CGRect) -> Path {
        let a = r.width * 0.165   // half the arm width
        let c = CGPoint(x: r.midX, y: r.midY)
        var p = Path()
        p.addLines([
            CGPoint(x: c.x - a, y: r.minY), CGPoint(x: c.x + a, y: r.minY), CGPoint(x: c.x + a, y: c.y - a),
            CGPoint(x: r.maxX, y: c.y - a), CGPoint(x: r.maxX, y: c.y + a), CGPoint(x: c.x + a, y: c.y + a),
            CGPoint(x: c.x + a, y: r.maxY), CGPoint(x: c.x - a, y: r.maxY), CGPoint(x: c.x - a, y: c.y + a),
            CGPoint(x: r.minX, y: c.y + a), CGPoint(x: r.minX, y: c.y - a), CGPoint(x: c.x - a, y: c.y - a),
        ])
        p.closeSubpath()
        return p
    }
}

/// The upper arm of the plus, from the top edge to the centre square.
struct ArmShape: Shape {
    func path(in r: CGRect) -> Path {
        let a = r.width * 0.165
        return Path(CGRect(x: r.midX - a, y: r.minY, width: 2 * a, height: r.height / 2 - a))
    }
}

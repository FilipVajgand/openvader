import SwiftUI
import VaderKit

/// The Vader 5 Pro, front and back.
///
/// The body outline was traced from a product photo (left half, mirrored)
/// and the controls are placed where they sit on the real controller; the
/// back follows the official manual's appearance page. All drawing is
/// original: no vendor artwork is bundled.
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
    static var frontRect: CGRect { CGRect(x: 20, y: 46, width: 600, height: 442) }
    static var backRect: CGRect { CGRect(x: 160, y: 548, width: 320, height: 236) }
    private var height: CGFloat { showsBack ? 800 : 500 }

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
            shoulders
            frontBody
            frontControls
            if showsBack {
                Text("BACK  ·  seen through the controller, so left stays left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .position(x: Self.width / 2, y: 505)
                backBody
                backControls
            }
        }
    }

    // MARK: Coordinates

    /// A point on the front, in fractions of the body's bounding box.
    private func f(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: Self.frontRect.minX + x * Self.frontRect.width, y: Self.frontRect.minY + y * Self.frontRect.height)
    }

    private func b(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: Self.backRect.minX + x * Self.backRect.width, y: Self.backRect.minY + y * Self.backRect.height)
    }

    // MARK: Colours

    private static let shell = LinearGradient(colors: [Color(white: 0.2), Color(white: 0.1)], startPoint: .top, endPoint: .bottom)
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

    private var shoulders: some View {
        ZStack(alignment: .topLeading) {
            triggerKey(.lt, center: f(0.205, -0.05), value: leftTrigger, mirrored: false)
            triggerKey(.rt, center: f(0.795, -0.05), value: rightTrigger, mirrored: true)
            bumperKey(.lb, center: f(0.2, 0.0), width: 118, mirrored: false, rotation: -9)
            bumperKey(.rb, center: f(0.8, 0.0), width: 118, mirrored: true, rotation: 9)
            pillKey(.lm, center: f(0.345, -0.018), size: CGSize(width: 36, height: 16))
            pillKey(.rm, center: f(0.655, -0.018), size: CGSize(width: 36, height: 16))
        }
    }

    private var frontBody: some View {
        ZStack(alignment: .topLeading) {
            BodyOutline()
                .fill(Self.shell)
                .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                .overlay(BodyOutline().stroke(Color(white: 0.32), lineWidth: 1))
                .frame(width: Self.frontRect.width, height: Self.frontRect.height)
                .offset(x: Self.frontRect.minX, y: Self.frontRect.minY)
            // The gold trim along the inner bottom edge.
            InnerTrim()
                .stroke(Self.goldLine, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .frame(width: Self.frontRect.width, height: Self.frontRect.height)
                .offset(x: Self.frontRect.minX, y: Self.frontRect.minY)
            // V panel with its speckled finish.
            VPanelShape()
                .fill(Color(white: 0.15))
                .overlay(VPanelShape().stroke(Color(white: 0.28), lineWidth: 1))
                .overlay(Speckles().fill(Self.goldLine.opacity(0.8)).clipShape(VPanelShape()))
                .frame(width: 0.33 * Self.frontRect.width, height: 0.2 * Self.frontRect.height)
                .position(x: f(0.5, 0.115).x, y: f(0.5, 0.115).y)
            Text("VADER 5 PRO")
                .font(.system(size: 9, weight: .semibold))
                .tracking(2)
                .foregroundStyle(Color(white: 0.75))
                .rotationEffect(.degrees(-62))
                .position(f(0.885, 0.70))
        }
    }

    private var frontControls: some View {
        ZStack(alignment: .topLeading) {
            homeKey(center: f(0.5, 0.085))
            smallKey(.select, center: f(0.42, 0.178), rotation: -40, symbol: "rectangle.on.rectangle")
            smallKey(.start, center: f(0.58, 0.178), rotation: 40, symbol: "line.3.horizontal")
            stickKey(.l3, center: f(0.238, 0.21), value: leftStick)
            stickKey(.r3, center: f(0.65, 0.42), value: rightStick)
            dpad(center: f(0.397, 0.40))
            faceKey(.y, center: f(0.746, 0.14))
            faceKey(.x, center: f(0.694, 0.215))
            faceKey(.b, center: f(0.818, 0.222))
            faceKey(.a, center: f(0.767, 0.297))
            roundKey(.z, center: f(0.868, 0.374), radius: 15)
            roundKey(.c, center: f(0.82, 0.435), radius: 15)
        }
    }

    // MARK: Back

    private var backBody: some View {
        ZStack(alignment: .topLeading) {
            triggerKey(.lt, center: b(0.2, -0.01), value: leftTrigger, mirrored: false, scale: 0.55)
            triggerKey(.rt, center: b(0.8, -0.01), value: rightTrigger, mirrored: true, scale: 0.55)
            BodyOutline()
                .fill(LinearGradient(colors: [Color(white: 0.17), Color(white: 0.09)], startPoint: .top, endPoint: .bottom))
                .overlay(BodyOutline().stroke(Color(white: 0.32), lineWidth: 1))
                .frame(width: Self.backRect.width, height: Self.backRect.height)
                .offset(x: Self.backRect.minX, y: Self.backRect.minY)
            RoundedRectangle(cornerRadius: 2).fill(Color.black).frame(width: 26, height: 7).position(b(0.5, 0.02))
            RoundedRectangle(cornerRadius: 6).stroke(Color(white: 0.3), lineWidth: 1)
                .frame(width: 0.17 * Self.backRect.width, height: 0.15 * Self.backRect.height)
                .position(b(0.5, 0.15))
            slider(center: b(0.33, 0.27), vertical: true, help: "Left trigger: click or travel")
            slider(center: b(0.67, 0.27), vertical: true, help: "Right trigger: click or travel")
            slider(center: b(0.5, 0.36), vertical: false, help: "Mode: receiver/cable · Bluetooth · Switch")
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(Self.goldLine.opacity(0.9)).frame(width: 5, height: 5)
                    .position(b(0.47 + CGFloat(i) * 0.03, 0.47))
            }
        }
    }

    private var backControls: some View {
        ZStack(alignment: .topLeading) {
            paddleKey(.m1, center: b(0.30, 0.42), size: CGSize(width: 46, height: 38), lower: false, mirrored: false)
            paddleKey(.m2, center: b(0.70, 0.42), size: CGSize(width: 46, height: 38), lower: false, mirrored: true)
            paddleKey(.m3, center: b(0.25, 0.62), size: CGSize(width: 62, height: 32), lower: true, mirrored: false)
            paddleKey(.m4, center: b(0.75, 0.62), size: CGSize(width: 62, height: 32), lower: true, mirrored: true)
            smallKey(.fn, center: b(0.44, 0.58), rotation: 0, symbol: "circle")
            smallKey(.turbo, center: b(0.56, 0.58), rotation: 0, symbol: "forward.end")
        }
    }

    // MARK: Pieces

    private func selection(_ key: ControllerKey) -> some View {
        Group {
            if let c = ring(key) { Circle().stroke(c, lineWidth: 3).padding(-3) }
        }
    }

    private func faceKey(_ key: ControllerKey, center: CGPoint) -> some View {
        let r: CGFloat = 19
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

    private func smallKey(_ key: ControllerKey, center: CGPoint, rotation: Double, symbol: String) -> some View {
        tappable(key, ZStack {
            Capsule().fill(base(key))
            Capsule().stroke(ring(key) ?? Self.rim, lineWidth: ring(key) == nil ? 1 : 2.5)
            Image(systemName: symbol).font(.system(size: 8, weight: .bold)).foregroundStyle(label(key))
                .rotationEffect(.degrees(-rotation))
        }
        .frame(width: 30, height: 15)
        .rotationEffect(.degrees(rotation)))
        .position(center)
    }

    private func homeKey(center: CGPoint) -> some View {
        tappable(.home, ZStack {
            if pressed.contains(.home) { Circle().fill(Color.accentColor.opacity(0.85)) }
            LogoMark().fill(pressed.contains(.home) ? .white : Color(white: 0.95)).frame(width: 30, height: 24)
            selection(.home)
        }
        .frame(width: 40, height: 40))
        .position(center)
    }

    private func pillKey(_ key: ControllerKey, center: CGPoint, size: CGSize) -> some View {
        tappable(key, ZStack {
            Capsule().fill(base(key))
            Capsule().stroke(ring(key) ?? Self.rim, lineWidth: ring(key) == nil ? 1 : 2.5)
            Text(key.short).font(.system(size: 9, weight: .bold, design: .rounded)).foregroundStyle(label(key))
        }
        .frame(width: size.width, height: size.height))
        .position(center)
    }

    private func bumperKey(_ key: ControllerKey, center: CGPoint, width: CGFloat, mirrored: Bool, rotation: Double = 0) -> some View {
        tappable(key, ZStack {
            BumperShape().fill(pressed.contains(key) ? AnyShapeStyle(Color.accentColor)
                                : AnyShapeStyle(LinearGradient(colors: [Color(white: 0.24), Color(white: 0.1)],
                                                               startPoint: .top, endPoint: .bottom)))
                .overlay(BumperShape().stroke(ring(key) ?? Self.rim, lineWidth: ring(key) == nil ? 1 : 2.5))
                .scaleEffect(x: mirrored ? -1 : 1)
            Text(key.short).font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(label(key)).offset(y: -5)
        }
        .frame(width: width, height: 26)
        .rotationEffect(.degrees(rotation)))
        .position(center)
    }

    private func triggerKey(_ key: ControllerKey, center: CGPoint, value: Double, mirrored: Bool, scale: CGFloat = 1) -> some View {
        let size = CGSize(width: 86 * scale, height: 40 * scale)
        return tappable(key, ZStack {
            ZStack(alignment: .bottom) {
                TriggerShape().fill(LinearGradient(colors: [Color(white: 0.22), Color(white: 0.08)], startPoint: .top, endPoint: .bottom))
                TriggerShape().fill(Color.accentColor.opacity(0.9))
                    .mask(alignment: .bottom) { Rectangle().frame(height: size.height * max(0, min(1, value))) }
                TriggerShape().stroke(ring(key) ?? Self.rim, lineWidth: ring(key) == nil ? 1 : 2.5)
            }
            .scaleEffect(x: mirrored ? -1 : 1)
            Text(key.short).font(.system(size: 10 * max(scale, 0.8), weight: .bold, design: .rounded))
                .foregroundStyle(pressed.contains(key) || value > 0.5 ? .white : Color(white: 0.8))
        }
        .frame(width: size.width, height: size.height))
        .position(center)
    }

    private func stickKey(_ key: ControllerKey, center: CGPoint, value: SIMD2<Double>) -> some View {
        let travel: CGFloat = 11
        return tappable(key, ZStack {
            Circle().fill(Color.black.opacity(0.55))
            // Gold tension dial with knurling.
            Circle().stroke(Self.gold, lineWidth: 11).padding(6)
            ForEach(0..<48, id: \.self) { i in
                Rectangle().fill(Color.black.opacity(0.35)).frame(width: 1, height: 9)
                    .offset(y: -(58 / 2 - 2))
                    .rotationEffect(.degrees(Double(i) * 7.5))
            }
            Circle().fill(Color(white: 0.05)).padding(17)
            ZStack {
                Circle().fill(pressed.contains(key) ? AnyShapeStyle(Color.accentColor)
                              : AnyShapeStyle(RadialGradient(colors: [Color(white: 0.2), Color(white: 0.07)],
                                                             center: .init(x: 0.4, y: 0.35), startRadius: 2, endRadius: 26)))
                Circle().stroke(Color(white: 0.26), lineWidth: 1)
                Circle().stroke(Color(white: 0.18), style: StrokeStyle(lineWidth: 3, dash: [1.5, 1.5])).padding(4)
                Text(key.short).font(.system(size: 9, weight: .bold, design: .rounded)).foregroundStyle(label(key).opacity(0.8))
                selection(key)
            }
            .frame(width: 42, height: 42)
            .offset(x: CGFloat(value.x) * travel, y: CGFloat(-value.y) * travel)
        }
        .frame(width: 80, height: 80))
        .position(center)
    }

    private func dpad(center: CGPoint) -> some View {
        ZStack {
            DpadShape()
                .fill(LinearGradient(colors: [Color(white: 0.17), Color(white: 0.04)], startPoint: .top, endPoint: .bottom))
                .overlay(DpadShape().stroke(Self.rim, lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 2, y: 2)
                .frame(width: 92, height: 92)
            ForEach([(ControllerKey.up, 0.0), (.right, 90.0), (.down, 180.0), (.left, 270.0)], id: \.0) { key, angle in
                dpadArm(key, angle: angle)
            }
        }
        .frame(width: 92, height: 92)
        .position(center)
    }

    /// One tappable arm, drawn pointing up in a dpad-sized box and rotated into place.
    private func dpadArm(_ key: ControllerKey, angle: Double) -> some View {
        ZStack {
            tappable(key, ZStack {
                RoundedRectangle(cornerRadius: 6).fill(pressed.contains(key) ? Color.accentColor : .clear)
                if let c = ring(key) { RoundedRectangle(cornerRadius: 6).stroke(c, lineWidth: 2.5) }
                Image(systemName: "arrowtriangle.up.fill").font(.system(size: 7))
                    .foregroundStyle(pressed.contains(key) ? .white : Color(white: 0.4))
            }
            .frame(width: 28, height: 30))
            .position(x: 46, y: 18)
        }
        .frame(width: 92, height: 92)
        .rotationEffect(.degrees(angle))
    }

    private func paddleKey(_ key: ControllerKey, center: CGPoint, size: CGSize, lower: Bool, mirrored: Bool) -> some View {
        tappable(key, ZStack {
            Group {
                if lower {
                    LowerPaddle().fill(base(key) == .accentColor ? AnyShapeStyle(Color.accentColor)
                                        : AnyShapeStyle(LinearGradient(colors: [Color(white: 0.24), Color(white: 0.1)],
                                                                       startPoint: .top, endPoint: .bottom)))
                        .overlay(LowerPaddle().stroke(ring(key) ?? Self.rim, lineWidth: ring(key) == nil ? 1 : 2.5))
                } else {
                    UpperPaddle().fill(base(key) == .accentColor ? AnyShapeStyle(Color.accentColor)
                                        : AnyShapeStyle(LinearGradient(colors: [Color(white: 0.24), Color(white: 0.1)],
                                                                       startPoint: .top, endPoint: .bottom)))
                        .overlay(UpperPaddle().stroke(ring(key) ?? Self.rim, lineWidth: ring(key) == nil ? 1 : 2.5))
                }
            }
            .scaleEffect(x: mirrored ? -1 : 1)
            Text(key.short).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(label(key))
        }
        .frame(width: size.width, height: size.height))
        .position(center)
    }

    private func slider(center: CGPoint, vertical: Bool, help: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4).fill(Color.black)
            RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.45))
                .frame(width: vertical ? 6 : 10, height: vertical ? 9 : 6)
        }
        .frame(width: vertical ? 11 : 34, height: vertical ? 24 : 11)
        .help(help)
        .position(center)
    }
}

// MARK: - Shapes

/// The controller's outline, traced from a product photo, smoothed with a Catmull-Rom spline.
struct BodyOutline: Shape {
    static let points: [(CGFloat, CGFloat)] = [
        (0.4991, 0.6678), (0.4785, 0.6683), (0.4355, 0.6598), (0.4045, 0.6604), (0.3528, 0.6673), (0.3220, 0.6826),
        (0.3093, 0.6956), (0.2986, 0.7116), (0.2707, 0.7696), (0.2425, 0.7944), (0.2311, 0.8079), (0.1299, 0.9731),
        (0.1152, 0.9895), (0.0998, 0.9988), (0.0843, 1.0000), (0.0637, 0.9919), (0.0413, 0.9721), (0.0279, 0.9539),
        (0.0163, 0.9314), (0.0071, 0.9035), (0.0013, 0.8706), (0.0000, 0.8401), (0.0036, 0.7463), (0.0190, 0.6009),
        (0.0491, 0.4414), (0.0733, 0.3358), (0.1126, 0.1875), (0.1298, 0.1388), (0.1626, 0.0722), (0.1859, 0.0457),
        (0.2134, 0.0270), (0.2444, 0.0131), (0.2919, 0.0000), (0.3150, 0.0001), (0.3614, 0.0164), (0.4991, 0.0256),
        (0.5009, 0.0256), (0.6386, 0.0164), (0.6850, 0.0001), (0.7081, 0.0000), (0.7556, 0.0131), (0.7866, 0.0270),
        (0.8141, 0.0457), (0.8374, 0.0722), (0.8702, 0.1388), (0.8874, 0.1875), (0.9267, 0.3358), (0.9509, 0.4414),
        (0.9810, 0.6009), (0.9964, 0.7463), (1.0000, 0.8401), (0.9987, 0.8706), (0.9929, 0.9035), (0.9837, 0.9314),
        (0.9721, 0.9539), (0.9587, 0.9721), (0.9363, 0.9919), (0.9157, 1.0000), (0.9002, 0.9988), (0.8848, 0.9895),
        (0.8701, 0.9731), (0.7689, 0.8079), (0.7575, 0.7944), (0.7293, 0.7696), (0.7014, 0.7116), (0.6907, 0.6956),
        (0.6780, 0.6826), (0.6472, 0.6673), (0.5955, 0.6604), (0.5645, 0.6598), (0.5215, 0.6683), (0.5009, 0.6678)
    ]

    func path(in r: CGRect) -> Path {
        let p = Self.points.map { CGPoint(x: r.minX + $0.0 * r.width, y: r.minY + $0.1 * r.height) }
        return CatmullRom.closed(p)
    }
}

/// The gold line that follows the body's inner bottom edge, a little inside it.
struct InnerTrim: Shape {
    func path(in r: CGRect) -> Path {
        let pts = BodyOutline.points.filter { $0.1 > 0.62 && $0.1 < 0.80 && $0.0 > 0.27 && $0.0 < 0.73 }
            .sorted { $0.0 < $1.0 }
        guard pts.count > 2 else { return Path() }
        // The traced inner edge has a notch at the centre; a wide average gives the trim an even
        // sweep, and taking the higher of the two keeps the line on the body.
        let smooth = pts.indices.map { i -> (CGFloat, CGFloat) in
            let near = pts[max(0, i - 3)...min(pts.count - 1, i + 3)]
            return (pts[i].0, min(pts[i].1, near.map(\.1).reduce(0, +) / CGFloat(near.count)))
        }
        let p = smooth.map { CGPoint(x: r.minX + $0.0 * r.width, y: r.minY + ($0.1 - 0.018) * r.height) }
        return CatmullRom.open(p)
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

/// The V-shaped panel around the logo.
struct VPanelShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + 10, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - 10, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - 6, y: r.minY + 9), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX + 10, y: r.maxY - 6))
        p.addQuadCurve(to: CGPoint(x: r.midX - 10, y: r.maxY - 6), control: CGPoint(x: r.midX, y: r.maxY + 3))
        p.addLine(to: CGPoint(x: r.minX + 6, y: r.minY + 9))
        p.addQuadCurve(to: CGPoint(x: r.minX + 10, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
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

/// A plus-shaped D-pad with softly rounded ends.
struct DpadShape: Shape {
    func path(in r: CGRect) -> Path {
        let arm = r.width * 0.42, c = CGPoint(x: r.midX, y: r.midY)
        var p = Path()
        p.addRoundedRect(in: CGRect(x: c.x - arm / 2, y: r.minY, width: arm, height: r.height), cornerSize: CGSize(width: 13, height: 13))
        p.addRoundedRect(in: CGRect(x: r.minX, y: c.y - arm / 2, width: r.width, height: arm), cornerSize: CGSize(width: 13, height: 13))
        return p
    }
}

struct TriggerShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.06, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.minX + r.width * 0.5, y: r.minY),
                   control1: CGPoint(x: r.minX, y: r.minY + r.height * 0.35), control2: CGPoint(x: r.minX + r.width * 0.2, y: r.minY))
        p.addCurve(to: CGPoint(x: r.maxX - r.width * 0.06, y: r.maxY),
                   control1: CGPoint(x: r.maxX - r.width * 0.15, y: r.minY), control2: CGPoint(x: r.maxX, y: r.minY + r.height * 0.5))
        p.closeSubpath()
        return p
    }
}

/// A bumper that follows the curve of the top edge.
struct BumperShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.15),
                   control1: CGPoint(x: r.minX + r.width * 0.1, y: r.minY), control2: CGPoint(x: r.maxX - r.width * 0.3, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - r.height * 0.15))
        p.addCurve(to: CGPoint(x: r.minX + r.width * 0.12, y: r.maxY),
                   control1: CGPoint(x: r.maxX - r.width * 0.3, y: r.maxY - r.height * 0.4), control2: CGPoint(x: r.minX + r.width * 0.3, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// The smaller upper back buttons.
struct UpperPaddle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.15, y: r.minY + r.height * 0.1))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.45),
                   control1: CGPoint(x: r.minX + r.width * 0.6, y: r.minY - r.height * 0.05),
                   control2: CGPoint(x: r.maxX, y: r.minY + r.height * 0.15))
        p.addCurve(to: CGPoint(x: r.minX + r.width * 0.35, y: r.maxY),
                   control1: CGPoint(x: r.maxX, y: r.maxY - r.height * 0.1),
                   control2: CGPoint(x: r.minX + r.width * 0.6, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.minX + r.width * 0.15, y: r.minY + r.height * 0.1),
                   control1: CGPoint(x: r.minX, y: r.maxY), control2: CGPoint(x: r.minX - r.width * 0.05, y: r.minY + r.height * 0.3))
        p.closeSubpath()
        return p
    }
}

/// The larger, detachable lower paddles.
struct LowerPaddle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.05, y: r.minY + r.height * 0.35))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.15),
                   control1: CGPoint(x: r.minX + r.width * 0.3, y: r.minY), control2: CGPoint(x: r.maxX - r.width * 0.2, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - r.width * 0.05, y: r.maxY - r.height * 0.2))
        p.addCurve(to: CGPoint(x: r.minX + r.width * 0.12, y: r.maxY),
                   control1: CGPoint(x: r.maxX - r.width * 0.3, y: r.maxY - r.height * 0.15),
                   control2: CGPoint(x: r.minX + r.width * 0.4, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.minX + r.width * 0.05, y: r.minY + r.height * 0.35),
                   control1: CGPoint(x: r.minX, y: r.maxY), control2: CGPoint(x: r.minX - r.width * 0.02, y: r.minY + r.height * 0.6))
        p.closeSubpath()
        return p
    }
}

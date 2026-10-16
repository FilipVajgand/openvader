import SwiftUI
import VaderKit

struct SticksView: View {
    @Environment(AppModel.self) private var model
    @Binding var draft: ProfileDraft

    var body: some View {
        Page(title: "Sticks",
             subtitle: "Dead zones and response curves run on the controller. OpenVader compiles your curve into the nine-point table the firmware plays.") {
            HStack(alignment: .top, spacing: 18) {
                ForEach(Side.allCases) { side in
                    StickEditor(
                        side: side,
                        settings: Binding(get: { draft.mapping.stick(side) }, set: { draft.mapping.setStick($0, side) }),
                        live: side == .left ? model.input.leftStick : model.input.rightStick)
                }
            }
        }
        .listensToInput()
    }
}

struct StickEditor: View {
    var side: Side
    @Binding var settings: StickSettings
    var live: SIMD2<Double>

    var body: some View {
        Card("\(side.title) stick", symbol: side == .left ? "l.joystick" : "r.joystick") {
            if !settings.isStick {
                Label("This stick is mapped to keyboard or mouse output by Flydigi's Windows app, so it has no curve here.",
                      systemImage: "info.circle")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Response", selection: Binding(get: { settings.curve }, set: { c in
                    var s = settings
                    s.apply(c)
                    if c != .custom { s.deadZone = settings.deadZone; s.outerDeadZone = settings.outerDeadZone }
                    settings = s
                })) {
                    ForEach(StickSettings.Curve.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(settings.curve.help).font(.caption).foregroundStyle(.secondary)

                CurveGraph(settings: $settings, liveTravel: min(1, (live.x * live.x + live.y * live.y).squareRoot()))
                    .frame(height: 220)

                ValueSlider(title: "Dead zone", value: $settings.deadZone, range: 0...50, unit: " %",
                            help: "Movement inside this range is ignored. Raise it if the stick drifts.")
                ValueSlider(title: "Outer dead zone", value: $settings.outerDeadZone, range: 0...50, unit: " %",
                            help: "The last part of the travel already counts as full deflection.")
                Toggle("Circular range", isOn: $settings.circular)
                Text(settings.circular
                     ? "Diagonals stop at the unit circle, like most console controllers."
                     : "Diagonals can reach the corners (about 1.19× on the diagonal).")
                    .font(.caption).foregroundStyle(.secondary)

                HStack(alignment: .center, spacing: 14) {
                    StickDot(value: live, deadZone: Double(settings.deadZone) / 100)
                        .frame(width: 96, height: 96)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Live").font(.caption.weight(.semibold))
                        Text(String(format: "x %+.2f  y %+.2f", live.x, live.y)).monospacedDigit()
                        Text("Table: " + settings.bank.map(String.init).joined(separator: " "))
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .font(.caption)
                }
            }
        }
    }
}

/// Draws the compiled response and lets the custom points be dragged.
struct CurveGraph: View {
    @Binding var settings: StickSettings
    var liveTravel: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let bank = StickCurveCompiler.bank(deadZone: settings.deadZone, outerDeadZone: settings.outerDeadZone,
                                               point1: settings.point1, point2: settings.point2)
            let nodes = StickCurveCompiler.nodes(deadZone: settings.deadZone, outerDeadZone: settings.outerDeadZone,
                                                 point1: settings.point1, point2: settings.point2)
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.4))
                Path { p in
                    for i in 1..<4 {
                        let f = CGFloat(i) / 4
                        p.move(to: CGPoint(x: w * f, y: 0)); p.addLine(to: CGPoint(x: w * f, y: h))
                        p.move(to: CGPoint(x: 0, y: h * f)); p.addLine(to: CGPoint(x: w, y: h * f))
                    }
                }
                .stroke(.secondary.opacity(0.15), lineWidth: 0.5)
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: w, y: 0))
                }
                .stroke(.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                if settings.deadZone > 0 {
                    Rectangle().fill(.orange.opacity(0.12))
                        .frame(width: w * CGFloat(settings.deadZone) / 100)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if settings.outerDeadZone > 0 {
                    Rectangle().fill(.orange.opacity(0.12))
                        .frame(width: w * CGFloat(settings.outerDeadZone) / 100)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                Path { p in
                    for i in 0...100 {
                        let t = Double(i) / 100
                        let y = StickCurveCompiler.response(bank: bank, at: t)
                        let pt = CGPoint(x: w * t, y: h * (1 - y))
                        i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                    }
                }
                .stroke(Color.accentColor, lineWidth: 2.5)
                // Live position on the curve.
                let ly = StickCurveCompiler.response(bank: bank, at: liveTravel)
                Circle().fill(.green).frame(width: 9, height: 9)
                    .position(x: w * liveTravel, y: h * (1 - ly))
                if settings.curve == .custom, nodes.count == 4 {
                    handle(index: 1, node: nodes[1], size: geo.size)
                    handle(index: 2, node: nodes[2], size: geo.size)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Text("stick travel →").font(.caption2).foregroundStyle(.tertiary).padding(4)
            }
            .overlay(alignment: .topLeading) {
                Text("output").font(.caption2).foregroundStyle(.tertiary).padding(4)
            }
        }
    }

    private func handle(index: Int, node: (x: Double, y: Double), size: CGSize) -> some View {
        Circle()
            .fill(.background)
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
            .frame(width: 14, height: 14)
            .position(x: size.width * node.x / 100, y: size.height * (1 - node.y / 100))
            .gesture(DragGesture().onChanged { g in
                // Convert back from the remapped span to the stored 0...127 point.
                let start = Double(settings.deadZone), end = 100 - Double(settings.outerDeadZone)
                let xPct = max(0, min(100, g.location.x / size.width * 100))
                let yPct = max(0, min(100, (1 - g.location.y / size.height) * 100))
                let span = max(1, end - start)
                let px = Int(((xPct - start) / span * 127).rounded())
                let py = Int((yPct * 127 / 100).rounded())
                var s = settings
                if index == 1 { s.point1 = CurvePoint(x: max(0, min(s.point2.x, px)), y: max(0, min(127, py))) }
                else { s.point2 = CurvePoint(x: max(s.point1.x, min(127, px)), y: max(0, min(127, py))) }
                settings = s
            })
    }
}

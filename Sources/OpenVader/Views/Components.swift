import SwiftUI
import VaderKit

/// Scrollable page with a title row for profile panes.
struct Page<Content: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.largeTitle.weight(.semibold))
                    if let subtitle {
                        Text(subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                LayoutWarning()
                content
            }
            .padding(24)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct LayoutWarning: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.section.isProfileSection, let d = model.draft, !d.mapping.isLayoutSupported {
            Label("This profile uses mapping layout \(d.mapping.layoutDescription), which OpenVader has not been checked against. It is shown read-only so nothing can be written to the wrong place.",
                  systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(.orange.opacity(0.1)))
        }
    }
}

/// A titled card.
struct Card<Content: View>: View {
    var title: String
    var symbol: String?
    var trailing: AnyView?
    @ViewBuilder var content: Content

    init(_ title: String, symbol: String? = nil, trailing: AnyView? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if let symbol {
                    Label(title, systemImage: symbol).font(.headline)
                } else {
                    Text(title).font(.headline)
                }
                Spacer()
                if let trailing { trailing }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.background.secondary))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator, lineWidth: 0.5))
    }
}

/// A labelled slider with its value.
struct ValueSlider: View {
    var title: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    var unit: String = ""
    var help: String?
    var format: ((Int) -> String)?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(format?(value) ?? "\(value)\(unit)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }),
                   in: Double(range.lowerBound)...Double(range.upperBound))
            if let help {
                Text(help).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Pick a controller button, or none.
struct KeyPicker: View {
    var title: String
    @Binding var key: ControllerKey?
    var choices: [ControllerKey]
    var allowsNone = true

    var body: some View {
        Picker(title, selection: $key) {
            if allowsNone { Text("None").tag(ControllerKey?.none) }
            ForEach(choices) { k in Text(k.name).tag(ControllerKey?.some(k)) }
        }
    }
}

/// A bar that fills to a 0...1 value.
struct LevelBar: View {
    var value: Double
    var window: ClosedRange<Double>?
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                if let window {
                    Rectangle().fill(Color.accentColor.opacity(0.18))
                        .frame(width: max(2, geo.size.width * (window.upperBound - window.lowerBound)))
                        .offset(x: geo.size.width * window.lowerBound)
                }
                Capsule().fill(Color.accentColor)
                    .frame(width: max(0, geo.size.width * min(1, max(0, value))))
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
    }
}

/// Live stick position inside its circle.
struct StickDot: View {
    var value: SIMD2<Double>
    var deadZone: Double = 0

    var body: some View {
        GeometryReader { geo in
            let r = min(geo.size.width, geo.size.height) / 2
            ZStack {
                Circle().fill(.quaternary.opacity(0.6))
                Circle().stroke(.secondary.opacity(0.4))
                if deadZone > 0 {
                    Circle().fill(.orange.opacity(0.18)).frame(width: 2 * r * deadZone, height: 2 * r * deadZone)
                }
                Path { p in
                    p.move(to: CGPoint(x: r, y: 0)); p.addLine(to: CGPoint(x: r, y: 2 * r))
                    p.move(to: CGPoint(x: 0, y: r)); p.addLine(to: CGPoint(x: 2 * r, y: r))
                }
                .stroke(.secondary.opacity(0.25), lineWidth: 0.5)
                Circle().fill(Color.accentColor)
                    .frame(width: 12, height: 12)
                    .offset(x: CGFloat(max(-1, min(1, value.x))) * r, y: CGFloat(-max(-1, min(1, value.y))) * r)
            }
            .frame(width: 2 * r, height: 2 * r)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Starts the live input stream while the view is on screen.
struct ListensToInput: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content
            .onAppear { model.listen(true) }
            .onDisappear { model.listen(false) }
    }
}

extension View {
    func listensToInput() -> some View { modifier(ListensToInput()) }
}

extension LEDColor {
    var color: Color { Color(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255) }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        self.init(red: UInt8(max(0, min(255, ns.redComponent * 255))),
                  green: UInt8(max(0, min(255, ns.greenComponent * 255))),
                  blue: UInt8(max(0, min(255, ns.blueComponent * 255))))
    }
}

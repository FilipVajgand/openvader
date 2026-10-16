import SwiftUI
import VaderKit

struct LightingView: View {
    @Binding var draft: ProfileDraft

    var body: some View {
        Page(title: "Lighting",
             subtitle: "Each profile has its own lighting. The controller plays colour frames that OpenVader generates for the effect you pick.") {
            if !draft.lighting.isValid {
                Card("Not available", symbol: "exclamationmark.triangle") {
                    Text("The controller returned a lighting format OpenVader does not recognise (\(draft.lighting.bytes.count) bytes), so lighting is read-only for this profile.")
                }
            } else {
                HStack(alignment: .top, spacing: 18) {
                    Card("Effect", symbol: "light.max") {
                        Picker("Effect", selection: Binding(
                            get: { draft.lightingEffect },
                            set: { e in
                                var colors = draft.lightingColors
                                if colors.count < e.colorRange.lowerBound {
                                    colors += Array(Self.defaults.dropFirst(colors.count).prefix(e.colorRange.lowerBound - colors.count))
                                }
                                draft.setLighting(effect: e, colors: colors)
                            })) {
                            ForEach(LightingEffect.editable) { Text($0.title).tag($0) }
                            if draft.lightingEffect == .factory { Text("Factory animation (keep)").tag(LightingEffect.factory) }
                        }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()

                        if draft.lightingEffect.hasDirection {
                            Divider()
                            Picker("Direction", selection: Binding(
                                get: { draft.lighting.direction ?? .left },
                                set: { draft.setLighting(effect: draft.lightingEffect, colors: draft.lightingColors,
                                                         direction: $0) })) {
                                ForEach(FlowDirection.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                        }

                        let range = draft.lightingEffect.colorRange
                        if range.upperBound > 0 {
                            Divider()
                            Text(range.upperBound == 1 ? "Color" : "Colors").font(.subheadline.weight(.semibold))
                            HStack(spacing: 10) {
                                ForEach(Array(visibleColors.enumerated()), id: \.offset) { i, c in
                                    ColorPicker("", selection: Binding(
                                        get: { c.color },
                                        set: { newColor in
                                            var colors = visibleColors
                                            colors[i] = LEDColor(newColor)
                                            draft.setLighting(effect: draft.lightingEffect, colors: colors)
                                        }), supportsOpacity: false)
                                        .labelsHidden()
                                }
                                if visibleColors.count < range.upperBound {
                                    Button { addColor() } label: { Image(systemName: "plus") }
                                        .help("Add a color")
                                }
                                if visibleColors.count > max(1, range.lowerBound) {
                                    Button { removeColor() } label: { Image(systemName: "minus") }
                                        .help("Remove the last color")
                                }
                            }
                            HStack(spacing: 6) {
                                ForEach(Self.defaults, id: \.self) { preset in
                                    Button {
                                        var colors = visibleColors
                                        if colors.isEmpty { colors = [preset] } else { colors[colors.count - 1] = preset }
                                        draft.setLighting(effect: draft.lightingEffect, colors: colors)
                                    } label: {
                                        Circle().fill(preset.color).frame(width: 16, height: 16)
                                            .overlay(Circle().stroke(.separator))
                                    }
                                    .buttonStyle(.plain)
                                    .help(preset.hex)
                                }
                            }
                        }
                    }
                    .frame(width: 300)

                    VStack(spacing: 18) {
                        Card("Preview", symbol: "eye") {
                            LightPreview(config: draft.lighting)
                                .frame(height: 70)
                            Text("\(draft.lighting.ledCount) LEDs, \(draft.lighting.frameCount) frames. The preview is an approximation of the controller's timing.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Card("Settings", symbol: "slider.horizontal.3") {
                            ValueSlider(title: "Brightness", value: Binding(
                                get: { draft.lighting.brightness }, set: { draft.lighting.brightness = $0 }),
                                range: 0...100, unit: " %")
                            if draft.lightingEffect.isAnimated {
                                ValueSlider(title: "Speed", value: Binding(
                                    get: { 256 - draft.lighting.cycleTime }, set: { draft.lighting.cycleTime = 256 - $0 }),
                                    range: 156...255,
                                    help: "Frame time stored on the controller; smaller is faster.",
                                    format: { "\(256 - $0)" })
                            }
                        }
                    }
                }
            }
        }
    }

    static let defaults: [LEDColor] = [
        LEDColor(red: 0, green: 120, blue: 255), LEDColor(red: 255, green: 0, blue: 60),
        LEDColor(red: 0, green: 230, blue: 120), LEDColor(red: 255, green: 160, blue: 0),
        LEDColor(red: 170, green: 0, blue: 255), LEDColor(red: 255, green: 255, blue: 255),
    ]

    private var visibleColors: [LEDColor] {
        let range = draft.lightingEffect.colorRange
        var colors = Array(draft.lightingColors.prefix(range.upperBound))
        while colors.count < range.lowerBound { colors.append(Self.defaults[colors.count % Self.defaults.count]) }
        return colors
    }

    private func addColor() {
        var colors = visibleColors
        colors.append(Self.defaults[colors.count % Self.defaults.count])
        draft.setLighting(effect: draft.lightingEffect, colors: colors)
    }

    private func removeColor() {
        var colors = visibleColors
        colors.removeLast()
        draft.setLighting(effect: draft.lightingEffect, colors: colors)
    }
}

/// Plays the stored frames as a strip of LEDs, cross-fading between frames.
struct LightPreview: View {
    var config: LightingConfig

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let first = config.loopStart, last = max(config.loopStart, config.loopEnd)
            let count = last - first + 1
            // Assume one frame per cycleTime × 25 ms; a guess until measured.
            let frameTime = max(0.08, Double(config.cycleTime) * 0.025)
            let position = count > 1 ? (t / frameTime).truncatingRemainder(dividingBy: Double(count)) : 0
            let a = first + Int(position), b = first + (Int(position) + 1) % count
            let f = position - floor(position)
            // Screens are far dimmer than LEDs; lift the floor so low settings stay visible.
            let brightness = 0.35 + 0.65 * Double(config.brightness) / 100
            HStack(spacing: 4) {
                ForEach(0..<max(1, config.ledCount), id: \.self) { led in
                    let ca = config.color(frame: a, led: led), cb = config.color(frame: b, led: led)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(red: mix(ca.red, cb.red, f) * brightness,
                                    green: mix(ca.green, cb.green, f) * brightness,
                                    blue: mix(ca.blue, cb.blue, f) * brightness))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.separator))
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.85)))
        }
    }

    private func mix(_ a: UInt8, _ b: UInt8, _ f: Double) -> Double {
        (Double(a) * (1 - f) + Double(b) * f) / 255
    }
}

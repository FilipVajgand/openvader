import SwiftUI
import VaderKit

struct ButtonsView: View {
    @Environment(AppModel.self) private var model
    @Binding var draft: ProfileDraft
    @State private var selected: ControllerKey = .m1

    private var remapped: Set<ControllerKey> {
        Set(ControllerKey.remappable.filter { !draft.mapping.binding(for: $0).isDefault })
    }

    var body: some View {
        Page(title: "Buttons",
             subtitle: "Mappings are stored on the controller, so they work in every game and on every device, including over Bluetooth. Press a button on the controller, or click one below, to change what it does.") {
            HStack(alignment: .top, spacing: 18) {
                Card("Layout", symbol: "gamecontroller") {
                    ControllerDiagram(pressed: model.input.buttons, selected: selected, marked: remapped,
                                      leftStick: model.input.leftStick, rightStick: model.input.rightStick,
                                      leftTrigger: model.input.leftTrigger, rightTrigger: model.input.rightTrigger) { key in
                        if ControllerKey.remappable.contains(key) { selected = key }
                    }
                    .frame(minHeight: 300)
                    HStack(spacing: 14) {
                        Label("Changed", systemImage: "circle.fill").foregroundStyle(.orange)
                        Label("Selected", systemImage: "circle").foregroundStyle(.tint)
                        Label("Pressed now", systemImage: "circle.fill").foregroundStyle(Color.accentColor)
                    }
                    .font(.caption)
                    .labelStyle(.titleAndIcon)
                }
                .frame(minWidth: 420)

                ButtonInspector(draft: $draft, key: selected)
                    .frame(width: 300)
            }

            Card("All buttons", symbol: "list.bullet") {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                    ForEach(rows, id: \.self) { row in
                        GridRow {
                            ForEach(row) { key in
                                let binding = draft.mapping.binding(for: key)
                                Button { selected = key } label: {
                                    HStack(spacing: 6) {
                                        Text(key.name).fontWeight(selected == key ? .bold : .regular)
                                        Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                                        Text(binding.describe(for: key))
                                            .foregroundStyle(binding.isDefault ? .secondary : Color.orange)
                                    }
                                    .lineLimit(1)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                HStack {
                    Spacer()
                    Button("Reset All Buttons") {
                        for key in ControllerKey.remappable where draft.mapping.binding(for: key).action != .macro {
                            draft.mapping.setBinding(ButtonBinding(), for: key)
                        }
                    }
                    .disabled(remapped.isEmpty)
                }
            }
        }
        .listensToInput()
        .onChange(of: model.lastPressed) { _, key in
            if let key, ControllerKey.remappable.contains(key) { selected = key }
        }
    }

    private var rows: [[ControllerKey]] {
        stride(from: 0, to: ControllerKey.remappable.count, by: 3).map {
            Array(ControllerKey.remappable[$0..<min($0 + 3, ControllerKey.remappable.count)])
        }
    }
}

struct ButtonInspector: View {
    @Binding var draft: ProfileDraft
    var key: ControllerKey

    private var binding: Binding<ButtonBinding> {
        Binding(get: { draft.mapping.binding(for: key) }, set: { draft.mapping.setBinding($0, for: key) })
    }

    private enum Choice: Hashable {
        case standard, target(ControllerKey), macro, other
    }

    private var choice: Binding<Choice> {
        Binding(get: {
            switch binding.wrappedValue.action {
            case .standard: .standard
            case .remap(let k): .target(k)
            case .macro: .macro
            default: .other
            }
        }, set: { new in
            var b = binding.wrappedValue
            switch new {
            case .standard: b.action = .standard
            case .target(let k): b.action = k == key ? .standard : .remap(k)
            case .macro, .other: return
            }
            binding.wrappedValue = b
        })
    }

    var body: some View {
        Card(key.name, symbol: ControllerKey.extraButtons.contains(key) ? "plus.circle" : "circle.circle") {
            Text(description).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            if binding.wrappedValue.action == .macro {
                Label("This button plays a macro. Edit or remove it under Macros.", systemImage: "repeat.circle")
                    .foregroundStyle(.tint)
            } else {
                Picker("Acts as", selection: choice) {
                    Text(ControllerKey.targets.contains(key) ? "\(key.name) (default)" : "Nothing extra (default)")
                        .tag(Choice.standard)
                    Divider()
                    ForEach(ControllerKey.targets) { t in
                        Text(t.name).tag(Choice.target(t))
                    }
                    if case .other = choice.wrappedValue {
                        Text(binding.wrappedValue.describe(for: key)).tag(Choice.other)
                    }
                }

                Divider()
                Toggle("Turbo (rapid fire)", isOn: Binding(
                    get: { binding.wrappedValue.turbo != nil },
                    set: { on in binding.wrappedValue.turbo = on ? ButtonBinding.Turbo() : nil }))
                if let turbo = binding.wrappedValue.turbo {
                    ValueSlider(title: "Speed", value: Binding(
                        get: { turbo.frequency },
                        set: { binding.wrappedValue.turbo?.frequency = $0 }), range: 1...20, unit: " / s")
                    Picker("Fires", selection: Binding(
                        get: { turbo.mode }, set: { binding.wrappedValue.turbo?.mode = $0 })) {
                        ForEach(ButtonBinding.TurboMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }

            HStack {
                Spacer()
                Button("Reset") { binding.wrappedValue = ButtonBinding() }
                    .disabled(binding.wrappedValue.isDefault || binding.wrappedValue.action == .macro)
            }
        }
    }

    private var description: String {
        switch key {
        case .m1, .m2, .m3, .m4:
            "Back paddle. Unmapped paddles send nothing to most games, so give it a job here."
        case .lm, .rm:
            "Extra shoulder button next to \(key == .lm ? "LB" : "RB")."
        case .c, .z:
            "Extra face button."
        default:
            "Standard button. Remapping it changes what games receive."
        }
    }
}

import SwiftUI
import VaderKit

struct ButtonsView: View {
    @Environment(AppModel.self) private var model
    @Binding var draft: ProfileDraft
    @State private var selected: ControllerKey = .m1

    private var remapped: Set<ControllerKey> {
        Set(ControllerKey.remappable.filter { !draft.mapping.binding(for: $0).isDefault || draft.host.action(for: $0) != nil })
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
                                let host = draft.host.action(for: key)
                                Button { selected = key } label: {
                                    HStack(spacing: 6) {
                                        Text(key.name).fontWeight(selected == key ? .bold : .regular)
                                        Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                                        Text(host.map { "\($0.title) (Mac)" } ?? binding.describe(for: key))
                                            .foregroundStyle(binding.isDefault && host == nil ? .secondary : Color.orange)
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
                            if draft.host.action(for: key) != nil { draft.setHostAction(nil, for: key) }
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

    private var hostAction: HostAction? { draft.host.action(for: key) }

    private enum Choice: Hashable {
        case standard, target(ControllerKey), macro, other
        case key, mouse(MouseButton), scroll(ScrollDirection)
    }

    private var choice: Binding<Choice> {
        Binding(get: {
            switch hostAction {
            case .key: return .key
            case .mouse(let b): return .mouse(b)
            case .scroll(let d): return .scroll(d)
            case nil: break
            }
            switch binding.wrappedValue.action {
            case .standard: return .standard
            case .remap(let k): return .target(k)
            case .macro: return .macro
            default: return .other
            }
        }, set: { new in
            switch new {
            case .key:
                if case .key = hostAction { return }
                draft.setHostAction(.key(KeyStroke(0x31)), for: key)
            case .mouse(let b): draft.setHostAction(.mouse(b), for: key)
            case .scroll(let d): draft.setHostAction(.scroll(d), for: key)
            case .standard, .target:
                if hostAction != nil { draft.setHostAction(nil, for: key) }
                var b = binding.wrappedValue
                if case .target(let k) = new, k != key { b.action = .remap(k) } else { b.action = .standard }
                if b.action == .keyboardMouse { b.action = .standard }
                binding.wrappedValue = b
            case .macro, .other: return
            }
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
                    Section("Controller button") {
                        ForEach(ControllerKey.targets) { t in
                            Text(t.name).tag(Choice.target(t))
                        }
                    }
                    Section("Keyboard and mouse (Mac)") {
                        Text("Keyboard key…").tag(Choice.key)
                        ForEach(MouseButton.allCases, id: \.self) { Text($0.title).tag(Choice.mouse($0)) }
                        ForEach([ScrollDirection.up, .down], id: \.self) { Text($0.title).tag(Choice.scroll($0)) }
                    }
                    if case .other = choice.wrappedValue {
                        Text(binding.wrappedValue.describe(for: key)).tag(Choice.other)
                    }
                }

                if case .key(let stroke) = hostAction {
                    KeyStrokePicker(stroke: Binding(get: { stroke }, set: { draft.setHostAction(.key($0), for: key) }))
                }
                if hostAction != nil {
                    Text("Games no longer see this button; OpenVader presses the key or mouse button on the Mac instead.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else if binding.wrappedValue.action == .keyboardMouse {
                    Text("Set to a keyboard or mouse action by Flydigi's Windows app. Pick a Mac action to use it here.")
                        .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }

                if hostAction == nil {
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
                        Text("Turbo needs the Turbo switch on under Controller.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Reset") {
                    if hostAction != nil { draft.setHostAction(nil, for: key) }
                    binding.wrappedValue = ButtonBinding()
                }
                .disabled((binding.wrappedValue.isDefault && hostAction == nil) || binding.wrappedValue.action == .macro)
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

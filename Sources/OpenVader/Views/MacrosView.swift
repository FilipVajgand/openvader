import SwiftUI
import VaderKit

struct MacrosView: View {
    @Environment(AppModel.self) private var model
    @Binding var draft: ProfileDraft
    @State private var editing: ControllerKey?

    private static let triggers: [ControllerKey] = [.m1, .m2, .m3, .m4, .lm, .rm, .c, .z, .lb, .rb, .a, .b, .x, .y]

    var body: some View {
        Page(title: "Macros",
             subtitle: "A macro is a sequence of button presses the controller plays by itself when you press its trigger button. Up to \(MacroStore.maxMacros) per profile.") {
            Label("Macro storage on the Vader 5 Pro is reverse-engineered and has had less testing than the other pages. Your profiles are backed up automatically each time you connect.",
                  systemImage: "flask")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 18) {
                Card("On this profile", symbol: "list.bullet") {
                    if draft.macros.macros.isEmpty {
                        Text("No macros yet.").foregroundStyle(.secondary)
                    }
                    ForEach(draft.macros.macros) { m in
                        Button { editing = m.trigger } label: {
                            HStack {
                                Text(m.trigger.name).font(.headline).frame(width: 44, alignment: .leading)
                                VStack(alignment: .leading) {
                                    Text(m.name.isEmpty ? "Untitled" : m.name)
                                    Text("\(m.steps.count) steps · \(m.duration) ms · \(m.playback.title.lowercased())")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(editing == m.trigger ? Color.accentColor.opacity(0.15) : .clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Divider()
                    Menu("New Macro On…") {
                        ForEach(Self.triggers.filter { draft.macros.macro(for: $0) == nil }) { key in
                            Button(key.name) { create(on: key) }
                        }
                    }
                    .disabled(draft.macros.macros.count >= MacroStore.maxMacros)
                    if !model.macroLibrary.isEmpty {
                        Menu("Add from Library") {
                            ForEach(Array(model.macroLibrary.enumerated()), id: \.offset) { i, m in
                                Menu(m.name.isEmpty ? "Untitled" : m.name) {
                                    ForEach(Self.triggers.filter { draft.macros.macro(for: $0) == nil }) { key in
                                        Button("On \(key.name)") { add(m, on: key) }
                                    }
                                    Divider()
                                    Button("Remove from Library", role: .destructive) { model.removeMacroFromLibrary(at: i) }
                                }
                            }
                        }
                        .disabled(draft.macros.macros.count >= MacroStore.maxMacros)
                    }
                }
                .frame(width: 300)

                if let key = editing, let index = draft.macros.macros.firstIndex(where: { $0.trigger == key }) {
                    MacroEditor(macro: $draft.macros.macros[index]) {
                        delete(key)
                    }
                } else {
                    Card("Editor", symbol: "pencil") {
                        Text("Select a macro or create a new one.").foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func create(on key: ControllerKey) {
        draft.macros.macros.append(Macro(trigger: key, name: "Macro \(key.name)", steps: Macro.tap([.a])))
        if draft.host.action(for: key) != nil { draft.host.setAction(nil, for: key) }
        draft.mapping.setBinding(ButtonBinding(action: .macro), for: key)
        editing = key
    }

    private func add(_ macro: Macro, on key: ControllerKey) {
        var m = macro
        m.trigger = key
        draft.macros.macros.append(m)
        if draft.host.action(for: key) != nil { draft.host.setAction(nil, for: key) }
        draft.mapping.setBinding(ButtonBinding(action: .macro), for: key)
        editing = key
    }

    private func delete(_ key: ControllerKey) {
        draft.macros.macros.removeAll { $0.trigger == key }
        if draft.mapping.binding(for: key).action == .macro {
            draft.mapping.setBinding(ButtonBinding(), for: key)
        }
        editing = nil
    }
}

struct MacroEditor: View {
    @Environment(AppModel.self) private var model
    @Binding var macro: Macro
    var onDelete: () -> Void
    @State private var recording = false
    @State private var recorded: [Macro.Step] = []
    @State private var lastEvent: Date?
    @State private var held: Set<ControllerKey> = []

    var body: some View {
        Card("Macro on \(macro.trigger.name)", symbol: "repeat.circle",
             trailing: AnyView(HStack {
                 Menu("Copy") {
                     Button("Save to Library") { model.saveMacroToLibrary(macro) }
                     Divider()
                     ForEach(0..<4, id: \.self) { i in
                         if i != model.selectedProfile {
                             Button("To Profile \(i + 1) – \(model.profileName(i))") { model.copyMacro(macro, toProfile: i) }
                         }
                     }
                 }
                 .fixedSize()
                 Button("Delete", role: .destructive, action: onDelete)
             })) {
            TextField("Name", text: Binding(get: { macro.name }, set: { name in
                // 20 bytes of UTF-8 fit on the controller; never cut a character in half.
                var trimmed = name
                while trimmed.utf8.count > 20 { trimmed.removeLast() }
                macro.name = trimmed
            }))
            Picker("Plays", selection: $macro.playback) {
                ForEach(Macro.Playback.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            if macro.playback != .once {
                ValueSlider(title: "Pause between repeats", value: $macro.repeatInterval, range: 0...2000, unit: " ms")
            }

            HStack {
                Text("Steps").font(.subheadline.weight(.semibold))
                Spacer()
                if recording {
                    Text("Recording… press buttons on the controller").foregroundStyle(.red).font(.caption)
                    Button("Stop") { stopRecording() }
                } else {
                    Button { startRecording() } label: { Label("Record", systemImage: "record.circle") }
                    Button { macro.steps += Macro.tap([.a]) } label: { Image(systemName: "plus") }
                        .help("Add a tap")
                }
            }

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(Array((recording ? recorded : macro.steps).enumerated()), id: \.element.id) { i, step in
                        if recording {
                            HStack { Text("\(step.event.title) \(step.key.name)"); Spacer(); Text("\(step.delay) ms") }
                                .font(.callout)
                        } else {
                            StepRow(step: $macro.steps[i]) { macro.steps.remove(at: i) }
                        }
                    }
                }
            }
            .frame(minHeight: 160, maxHeight: 320)
            Text("Total \(macro.duration) ms. Delays are the wait after each step.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: model.input.buttons) { old, new in
            guard recording else { return }
            let now = Date()
            let changes = new.subtracting(old).map { ($0, Macro.Event.press) } + old.subtracting(new).map { ($0, Macro.Event.release) }
            for (key, event) in changes where key != macro.trigger && ControllerKey.macroOutputs.contains(key) {
                if let last = lastEvent, !recorded.isEmpty {
                    recorded[recorded.count - 1].delay = max(1, Int(now.timeIntervalSince(last) * 1000))
                }
                recorded.append(Macro.Step(key: key, event: event, delay: 0))
                if event == .press { held.insert(key) } else { held.remove(key) }
                lastEvent = now
            }
        }
        .onDisappear { if recording { stopRecording() } }
    }

    private func startRecording() {
        recorded = []
        held = []
        lastEvent = nil
        recording = true
        model.listen(true)
    }

    private func stopRecording() {
        recording = false
        model.listen(false)
        for key in held { recorded.append(Macro.Step(key: key, event: .release, delay: 0)) }
        if !recorded.isEmpty {
            if recorded[recorded.count - 1].delay == 0 { recorded[recorded.count - 1].delay = 20 }
            macro.steps = Array(recorded.prefix(MacroStore.maxSteps))
        }
    }
}

struct StepRow: View {
    @Binding var step: Macro.Step
    var onDelete: () -> Void

    var body: some View {
        HStack {
            Picker("", selection: $step.event) {
                ForEach(Macro.Event.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .labelsHidden().frame(width: 90)
            Picker("", selection: $step.key) {
                ForEach(ControllerKey.macroOutputs) { Text($0.name).tag($0) }
            }
            .labelsHidden().frame(width: 140)
            Text("then wait")
            TextField("ms", value: $step.delay, format: .number).frame(width: 60)
            Text("ms")
            Spacer()
            Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                .buttonStyle(.borderless)
        }
    }
}

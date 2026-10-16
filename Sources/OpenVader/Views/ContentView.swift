import SwiftUI
import VaderKit

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 230, ideal: 250, max: 300)
        } detail: {
            Group {
                switch model.state {
                case .connected:
                    DetailView(section: model.section)
                case .searching:
                    WaitingView()
                case .connecting:
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Reading the controller…").foregroundStyle(.secondary)
                    }
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Could not talk to the controller", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try Again") { model.retry() }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar { Toolbar() }
        .safeAreaInset(edge: .bottom) { StatusBar() }
        .alert("Something went wrong", isPresented: .init(
            get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

struct DetailView: View {
    @Environment(AppModel.self) private var model
    var section: Pane

    var body: some View {
        if section.isProfileSection {
            if model.drafts[model.selectedProfile] != nil {
                let i = model.selectedProfile
                let draft = Binding(get: { model.drafts[i]! }, set: { model.drafts[i] = $0 })
                profilePane(draft).id(i)
            } else {
                ContentUnavailableView("Profile not loaded", systemImage: "questionmark.folder")
            }
        } else {
            switch section {
            case .test: LiveTestView()
            case .settings: ControllerSettingsView()
            default: BackupsView()
            }
        }
    }

    @ViewBuilder
    private func profilePane(_ draft: Binding<ProfileDraft>) -> some View {
        switch section {
        case .buttons: ButtonsView(draft: draft)
        case .sticks: SticksView(draft: draft)
        case .triggers: TriggersView(draft: draft)
        case .gyro: GyroView(draft: draft)
        case .vibration: VibrationView(draft: draft)
        case .lighting: LightingView(draft: draft)
        default: MacrosView(draft: draft)
        }
    }
}

struct Toolbar: ToolbarContent {
    @Environment(AppModel.self) private var model

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if model.isConnected, model.section.isProfileSection {
                Button("Revert") { model.revert() }
                    .disabled(!model.hasUnsavedChanges || model.busy != nil)
                Button {
                    model.save()
                } label: {
                    Label("Save to Controller", systemImage: "square.and.arrow.down")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.hasUnsavedChanges || !model.canWrite)
                .help(model.draft?.mapping.isLayoutSupported == false
                      ? "This profile uses a layout OpenVader does not know, so it is read-only."
                      : "Write this profile to the controller's memory (⌘S)")
            }
        }
    }
}

struct StatusBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.busy != nil || model.notice != nil {
            HStack(spacing: 10) {
                if let busy = model.busy {
                    if let p = model.progress {
                        ProgressView(value: p).frame(width: 140)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    Text(busy)
                } else if let notice = model.notice {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(notice)
                    Spacer()
                    Button("Dismiss") { model.notice = nil }.buttonStyle(.borderless)
                }
                Spacer()
            }
            .font(.callout)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.bar)
            .task(id: model.notice) {
                guard model.notice != nil else { return }
                try? await Task.sleep(for: .seconds(4))
                model.notice = nil
            }
        }
    }
}

struct WaitingView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Connect your Vader 5 Pro", systemImage: "cable.connector")
        } description: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Plug in the 2.4 GHz receiver, or connect the controller with a USB-C cable, then switch it on.")
                Text("Bluetooth works for playing but cannot be used to change settings; that needs the receiver or the cable.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 420)
        } actions: {
            ProgressView().controlSize(.small)
        }
    }
}

struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: Binding(get: { model.section }, set: { if let s = $0 { model.section = s } })) {
            if model.isConnected {
                Section("Profile") {
                    ProfilePicker()
                        .selectionDisabled()
                }
            }
            Section("Configure") {
                ForEach(Pane.allCases.filter(\.isProfileSection)) { s in
                    Label(s.title, systemImage: s.symbol).tag(s)
                }
            }
            Section("Device") {
                ForEach(Pane.allCases.filter { !$0.isProfileSection }) { s in
                    Label(s.title, systemImage: s.symbol).tag(s)
                }
            }
        }
        .listStyle(.sidebar)
        .disabled(!model.isConnected)
        .safeAreaInset(edge: .top) {
            if model.isConnected {
                DeviceCard()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 4)
            }
        }
    }
}

struct DeviceCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let info = model.info {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "gamecontroller.fill").foregroundStyle(.tint)
                    Text(info.modelName).font(.headline)
                }
                HStack(spacing: 6) {
                    Image(systemName: batterySymbol(info))
                    Text(info.batteryDescription)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                Text("\(model.connectionKind.rawValue) · firmware \(info.firmware ?? "?")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if model.productID != VaderUSB.vader5ProductID {
                    Text(String(format: "Untested USB product 0x%04X", model.productID))
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            .padding(.vertical, 4)
        }
    }

    func batterySymbol(_ info: DeviceInfo) -> String {
        if info.batteryState == .charging { return "battery.100percent.bolt" }
        switch info.batteryPercent {
        case 80...: return "battery.100percent"
        case 60..<80: return "battery.75percent"
        case 30..<60: return "battery.50percent"
        case 10..<30: return "battery.25percent"
        default: return "battery.0percent"
        }
    }
}

struct ProfilePicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ForEach(0..<4, id: \.self) { i in
            Button {
                model.selectProfile(i)
            } label: {
                HStack {
                    Text("\(i + 1)")
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(model.selectedProfile == i ? Color.accentColor : Color.secondary.opacity(0.25)))
                        .foregroundStyle(model.selectedProfile == i ? .white : .primary)
                    Text(model.profileName(i)).lineLimit(1)
                    Spacer()
                    if model.isDirty(i) {
                        Circle().fill(.orange).frame(width: 7, height: 7).help("Unsaved changes")
                    }
                    if model.versions?.active == i {
                        Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(.secondary)
                            .help("Running on the controller")
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.busy != nil)
        }
    }
}

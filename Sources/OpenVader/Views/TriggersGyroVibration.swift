import SwiftUI
import VaderKit

struct TriggersView: View {
    @Environment(AppModel.self) private var model
    @Binding var draft: ProfileDraft

    var body: some View {
        Page(title: "Triggers",
             subtitle: "Shorten the physical travel of LT and RT. Games still see the full 0–100 % range, so a short window works like a hair trigger.") {
            HStack(alignment: .top, spacing: 18) {
                ForEach(Side.allCases) { side in
                    TriggerEditor(
                        side: side,
                        travel: Binding(get: { draft.mapping.trigger(side) }, set: { draft.mapping.setTrigger($0, side) }),
                        live: side == .left ? model.input.leftTrigger : model.input.rightTrigger)
                }
            }
            TriggerMotorEditor(draft: $draft)
        }
        .listensToInput()
    }
}

struct TriggerEditor: View {
    var side: Side
    @Binding var travel: TriggerTravel
    var live: Double

    var body: some View {
        Card("\(side.title) trigger (\(side == .left ? "LT" : "RT"))", symbol: side == .left ? "l2.button.roundedtop.horizontal" : "r2.button.roundedtop.horizontal") {
            Picker("Preset", selection: Binding(get: {
                travel == .full ? 0 : (travel == .hairTrigger ? 1 : 2)
            }, set: { v in
                if v == 0 { travel = .full } else if v == 1 { travel = .hairTrigger }
            })) {
                Text("Full travel").tag(0)
                Text("Hair trigger").tag(1)
                Text("Custom").tag(2)
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 4) {
                Text("Live: \(Int(live * 100)) % pulled").font(.caption).foregroundStyle(.secondary)
                LevelBar(value: live, window: Double(travel.start) / 255...Double(travel.end) / 255, height: 14)
            }
            ValueSlider(title: "Starts responding at", value: Binding(
                get: { travel.start }, set: { travel.start = min($0, travel.end) }), range: 0...255,
                format: { "\(Int(Double($0) / 2.55)) %" })
            ValueSlider(title: "Full press at", value: Binding(
                get: { travel.end }, set: { travel.end = max($0, travel.start) }), range: 0...255,
                format: { "\(Int(Double($0) / 2.55)) %" })
            Text("Only matters with the trigger switch on the back set to travel; in click mode the trigger acts as a button. Stored on the controller, but its effect on games is not yet confirmed on the Vader 5 Pro.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct TriggerMotorEditor: View {
    @Environment(AppModel.self) private var model
    @Binding var draft: ProfileDraft

    var body: some View {
        let v = Binding(get: { draft.mapping.triggerVibration }, set: { draft.mapping.triggerVibration = $0 })
        Card("Trigger vibration", symbol: "waveform") {
            Toggle("Vibrate the triggers with game rumble", isOn: v.enabled)
            if v.wrappedValue.enabled {
                ValueSlider(title: "Strength", value: Binding(
                    get: { v.wrappedValue.left.scale },
                    set: { s in v.wrappedValue.left.scale = s; v.wrappedValue.right.scale = s }),
                    range: 1...100, unit: " %", help: "Applies to both triggers, as in Flydigi's app.")
                ValueSlider(title: "Ignore rumble weaker than", value: Binding(
                    get: { v.wrappedValue.left.filter },
                    set: { f in v.wrappedValue.left.filter = f; v.wrappedValue.right.filter = f }),
                    range: 0...100)
            }
            HStack {
                Spacer()
                Button("Test") { model.rumble(gripLeft: 0, gripRight: 0, triggerLeft: 180, triggerRight: 180) }
            }
        }
    }
}

struct GyroView: View {
    @Environment(AppModel.self) private var model
    @Binding var draft: ProfileDraft

    var body: some View {
        let g = Binding(get: { draft.mapping.gyro }, set: { draft.mapping.gyro = $0 })
        Page(title: "Gyro aiming",
             subtitle: "The controller turns its motion sensor into stick movement by itself, so gyro aiming works in any game, including over Bluetooth and on a Mac, with nothing running in the background.") {
            HStack(alignment: .top, spacing: 18) {
                Card("Motion control", symbol: "gyroscope") {
                    Picker("Drive", selection: Binding(get: { g.wrappedValue.target }, set: { t in
                        if t == .mouse {
                            draft.setGyroMouse(draft.host.gyro ?? GyroMouseSettings())
                        } else {
                            if draft.host.gyro != nil { draft.setGyroMouse(nil) }
                            g.wrappedValue.target = t
                        }
                    })) {
                        Text("Off").tag(GyroSettings.Target.off)
                        Text("Left stick").tag(GyroSettings.Target.leftStick)
                        Text("Right stick").tag(GyroSettings.Target.rightStick)
                        Text("Mouse (Mac)").tag(GyroSettings.Target.mouse)
                    }
                    .pickerStyle(.segmented)
                    if g.wrappedValue.target == .mouse {
                        GyroMouseEditor(settings: Binding(
                            get: { draft.host.gyro ?? GyroMouseSettings() }, set: { draft.setGyroMouse($0) }))
                    } else if g.wrappedValue.target != .off {
                        KeyPicker(title: "Activate with", key: g.enableKey, choices: ControllerKey.gyroEnableKeys)
                        Picker("Activation", selection: g.activation) {
                            ForEach(GyroSettings.Activation.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        if g.wrappedValue.activation == .hold {
                            KeyPicker(title: "Also with", key: g.secondKey, choices: ControllerKey.gyroEnableKeys)
                        }
                        ValueSlider(title: "Sensitivity", value: g.sensitivity, range: 0...100)
                        ValueSlider(title: "Dead zone", value: g.deadZone, range: 0...100,
                                    help: "Ignores small hand tremor.")
                        Text("Tip: aiming with the right stick while holding LT is the classic shooter setup. When you let go of the key, the stick can stay where the gyro left it until you move it again.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Card("Live motion", symbol: "move.3d") {
                    MotionReadout(gyro: model.input.gyro, accel: model.input.accel)
                }
                .frame(width: 300)
            }
        }
        .listensToInput()
    }
}

struct GyroMouseEditor: View {
    @Binding var settings: GyroMouseSettings

    var body: some View {
        Text("Tilt and turn the controller to move the Mac's pointer. Runs in OpenVader while the controller is on the receiver or cable.")
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        KeyPicker(title: "Activate with", key: $settings.enableKey, choices: ControllerKey.gyroEnableKeys)
            .help("None keeps the gyro pointer on all the time")
        if settings.enableKey != nil {
            Picker("Activation", selection: $settings.activation) {
                ForEach(GyroSettings.Activation.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        ValueSlider(title: "Sensitivity", value: $settings.sensitivity, range: 1...100)
        HStack {
            Toggle("Invert horizontal", isOn: $settings.invertX)
            Toggle("Invert vertical", isOn: $settings.invertY)
        }
    }
}

struct MotionReadout: View {
    var gyro: SIMD3<Double>
    var accel: SIMD3<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rotation (°/s)").font(.caption.weight(.semibold))
            axis("X", gyro.x / 500)
            axis("Y", gyro.y / 500)
            axis("Z", gyro.z / 500)
            Text(String(format: "%+.0f  %+.0f  %+.0f", gyro.x, gyro.y, gyro.z)).font(.caption).monospacedDigit()
            Text("Acceleration (g)").font(.caption.weight(.semibold)).padding(.top, 6)
            axis("X", accel.x / 2)
            axis("Y", accel.y / 2)
            axis("Z", accel.z / 2)
            Text(String(format: "%+.2f  %+.2f  %+.2f", accel.x, accel.y, accel.z)).font(.caption).monospacedDigit()
        }
    }

    private func axis(_ label: String, _ v: Double) -> some View {
        HStack {
            Text(label).font(.caption).frame(width: 14)
            GeometryReader { geo in
                let half = geo.size.width / 2
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Rectangle().fill(Color.accentColor)
                        .frame(width: half * min(1, abs(v)))
                        .offset(x: v >= 0 ? half : half - half * min(1, abs(v)))
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)
        }
    }
}

struct VibrationView: View {
    @Environment(AppModel.self) private var model
    @Binding var draft: ProfileDraft

    var body: some View {
        let v = Binding(get: { draft.mapping.gripVibration }, set: { draft.mapping.gripVibration = $0 })
        Page(title: "Vibration",
             subtitle: "The controller squeezes game rumble into the window you set for each grip motor.") {
            Card("Grip motors", symbol: "waveform.path") {
                Toggle("Rumble", isOn: v.enabled)
                if v.wrappedValue.enabled {
                    HStack(alignment: .top, spacing: 24) {
                        motor("Left (heavy)", v.left)
                        motor("Right (light)", v.right)
                    }
                }
            }
            Card("Test", symbol: "play.circle") {
                HStack {
                    Button("Left") { model.rumble(gripLeft: 200, gripRight: 0) }
                    Button("Right") { model.rumble(gripLeft: 0, gripRight: 200) }
                    Button("Both") { model.rumble(gripLeft: 200, gripRight: 200) }
                    Button("Triggers") { model.rumble(gripLeft: 0, gripRight: 0, triggerLeft: 200, triggerRight: 200) }
                    Button("Everything") { model.rumble(gripLeft: 255, gripRight: 255, triggerLeft: 255, triggerRight: 255) }
                }
                Text("Tests drive the motors directly. Saved settings shape the rumble games send.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func motor(_ title: String, _ m: Binding<GripVibration.Motor>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(title, isOn: m.enabled).font(.subheadline.weight(.semibold))
            if m.wrappedValue.enabled {
                ValueSlider(title: "Weakest", value: Binding(
                    get: { m.wrappedValue.minimum }, set: { m.wrappedValue.minimum = min($0, m.wrappedValue.maximum) }),
                    range: 0...255, format: { "\(Int(Double($0) / 2.55)) %" })
                ValueSlider(title: "Strongest", value: Binding(
                    get: { m.wrappedValue.maximum }, set: { m.wrappedValue.maximum = max($0, m.wrappedValue.minimum) }),
                    range: 0...255, format: { "\(Int(Double($0) / 2.55)) %" })
                ValueSlider(title: "Gain", value: m.scale, range: 0...100,
                            help: "Factory setting is 50.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

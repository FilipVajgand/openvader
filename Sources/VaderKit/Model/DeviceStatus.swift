import Foundation

/// Identity, battery and firmware versions from the heartbeat (`0x01`) reply.
public struct DeviceInfo: Sendable, Equatable, Codable {
    public var deviceType: Int
    public var connectByte: Int
    /// 0...5, each step is 20 %.
    public var batteryLevel: Int
    public var batteryState: BatteryState
    public var firmware: String?
    public var receiverFirmware: String?
    public var siFirmware: String?
    public var triggerFirmware: String?
    public var screenFirmware: String?
    public var adcFirmware: String?
    public var rfFirmware: String?
    public var raw: [UInt8]

    public enum BatteryState: Int, Sendable, Codable {
        case discharging = 0, charging = 1, full = 2, unknown = 0xF
    }

    public static let vader5Types: [Int: String] = [
        130: "Vader 5 Pro",
        144: "Vader 5 Pro Dragon Ball",
        145: "Vader 5 Pro Honkai Impact 3rd",
    ]

    public var isVader5: Bool { Self.vader5Types[deviceType] != nil }

    public var modelName: String {
        Self.vader5Types[deviceType] ?? "Flydigi device (type \(deviceType))"
    }

    public var batteryPercent: Int { min(100, batteryLevel * 20) }

    public var batteryDescription: String {
        switch batteryState {
        case .full: "Charged"
        case .charging: "\(batteryPercent) %, charging"
        case .discharging: "\(batteryPercent) %"
        case .unknown: "Unknown"
        }
    }

    /// The main firmware as a comparable tuple, e.g. (7, 2, 2, 1).
    public var firmwareNumbers: [Int] {
        (firmware ?? "").split(separator: ".").compactMap { Int($0) }
    }

    public init(reply: Reply) {
        raw = reply.raw
        deviceType = Int(reply[5])
        connectByte = Int(reply[6])
        let battery = reply[11]
        batteryState = BatteryState(rawValue: Int(battery >> 4)) ?? .unknown
        batteryLevel = Int(battery & 0x0F)
        func version(_ i: Int) -> String? {
            let hi = reply[i], lo = reply[i + 1]
            guard hi != 0 || lo != 0 else { return nil }
            return "\(hi >> 4).\(hi & 0xF).\(lo >> 4).\(lo & 0xF)"
        }
        firmware = version(15)
        receiverFirmware = version(17)
        siFirmware = version(19)
        triggerFirmware = version(21)
        screenFirmware = version(23)
        adcFirmware = version(25)
        rfFirmware = version(27)
    }
}

/// On-device toggles, each with an "is supported" and an "is on" bit (`0x03`).
public enum DeviceFeature: UInt8, CaseIterable, Sendable, Identifiable {
    case fastProfileSwap = 1
    case xboxHomeButton = 2
    case motionDebounce = 3
    case turbo = 4
    case joystickDebounce = 5
    case joystickAutoCalibration = 6
    case joystickRebound = 7
    case screenStatusBar = 8
    case screenOff = 9
    case audio = 10

    public var id: UInt8 { rawValue }

    public var title: String {
        switch self {
        case .fastProfileSwap: "Quick profile switching"
        case .xboxHomeButton: "Xbox Home button"
        case .motionDebounce: "Gyro debounce"
        case .turbo: "Turbo button"
        case .joystickDebounce: "Stick debounce"
        case .joystickAutoCalibration: "Stick auto-calibration"
        case .joystickRebound: "Stick snap-back filter"
        case .screenStatusBar: "Screen status bar always on"
        case .screenOff: "Screen off"
        case .audio: "Audio"
        }
    }

    public var help: String {
        switch self {
        case .fastProfileSwap:
            "Hold Fn and press A, B, X or Y on the controller to switch between the four profiles."
        case .xboxHomeButton: "Use the Home button as the Xbox Guide button."
        case .motionDebounce: "Filters small gyro jitter while the controller is held still."
        case .turbo: "Master switch for turbo. Buttons set to turbo only fire repeatedly while this is on."
        case .joystickDebounce:
            "Steadies the sticks at rest. Turning it off makes tiny movements register but adds jitter, and stops auto-calibration."
        case .joystickAutoCalibration: "Re-centers the sticks automatically when they are idle. Needs stick debounce."
        case .joystickRebound: "Filters the reverse flick a stick's spring causes when you let go."
        case .screenStatusBar, .screenOff, .audio: ""
        }
    }

    /// A feature that only works while another one is on.
    public var requires: DeviceFeature? { self == .joystickAutoCalibration ? .joystickDebounce : nil }

    var bytes: (supported: Int, enabled: Int, bit: Int) {
        let index = Int(rawValue) - 1
        return index < 8 ? (5, 6, index) : (7, 8, index - 8)
    }
}

/// Settings block from the hardware status (`0x03`) reply.
public struct HardwareStatus: Sendable, Equatable {
    public var supported: Set<DeviceFeature> = []
    public var enabled: Set<DeviceFeature> = []
    /// 0 means never.
    public var sleepMinutes: Int
    /// 0 means not adjustable on this device.
    public var reportRate: Int
    public var joystickPrecision: Int
    public var joystickSensitivity: Int
    public var raw: [UInt8]

    /// The values Flydigi's own app offers.
    public static let sleepChoices: [(minutes: Int, label: String)] = [
        (1, "1 minute"), (5, "5 minutes"), (15, "15 minutes"),
        (60, "1 hour"), (180, "3 hours"), (0, "Never"),
    ]

    /// Stick precision as Flydigi's app offers it: wire code and bit depth.
    /// The codes are an enum index, not the bit depth.
    public static let precisionChoices: [(code: Int, label: String)] = [
        (1, "8 bit"), (4, "9 bit"), (2, "10 bit"), (5, "11 bit"), (3, "12 bit"),
    ]

    /// Center sensitivity; a larger wire value is slower.
    public static let sensitivityChoices: [(value: Int, label: String)] = [(14, "Fast"), (17, "Medium"), (19, "Slow")]

    public var precisionAdjustable: Bool { joystickPrecision != 0 }
    public var sensitivityAdjustable: Bool { joystickSensitivity != 0 }

    public init(reply: Reply) {
        raw = reply.raw
        sleepMinutes = Int(reply[9])
        reportRate = Int(reply[10])
        joystickPrecision = Int(reply[11])
        joystickSensitivity = Int(reply[12])
        for feature in DeviceFeature.allCases {
            let (s, e, bit) = feature.bytes
            if (reply[s] >> bit) & 1 == 1 { supported.insert(feature) }
            if (reply[e] >> bit) & 1 == 1 { enabled.insert(feature) }
        }
    }
}

/// Who receives the controller's data streams (`0x10`).
public struct DataReportStatus: Sendable, Equatable {
    public var controllerData: Bool
    public var rawInputStream: Bool
    public var keyboardData: Bool
    public var mouseData: Bool
    /// "Allow third-party apps to take over" — lets SDL and Steam read the
    /// full input report over USB, including paddles and gyro.
    public var thirdPartyControl: Bool
    /// Name of the app currently holding the controller, e.g. "SDL".
    public var controlledBy: String

    public init(reply: Reply) {
        controllerData = reply[5] == 1
        rawInputStream = reply[6] == 1
        keyboardData = reply[7] == 1
        mouseData = reply[8] == 1
        thirdPartyControl = reply[9] == 1
        let name = reply.raw[10..<30].prefix { $0 != 0 && $0 != 0xFF }
        controlledBy = String(decoding: name, as: UTF8.self)
    }
}

/// Active profile and each profile's revision tag (`0xA1`).
public struct ProfileVersions: Sendable, Equatable {
    public static let count = 4
    public static let unwritten: UInt16 = 0xFFFF

    public var active: Int
    public var switchModeActive: Bool
    public var dataVersions: [UInt16]

    public init(reply: Reply) {
        let raw = Int(reply[5])
        switchModeActive = (4...7).contains(raw)
        active = switchModeActive ? raw - 4 : (raw <= 3 ? raw : 0)
        dataVersions = (0..<Self.count).map { reply.u16(6 + 2 * $0) }
    }

    public func isFactoryDefault(_ profile: Int) -> Bool {
        profile < dataVersions.count && dataVersions[profile] == Self.unwritten
    }
}

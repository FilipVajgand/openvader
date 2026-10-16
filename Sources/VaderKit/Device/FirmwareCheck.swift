import Foundation

/// Asks Flydigi's public update service which firmware is current. Read-only:
/// OpenVader never flashes firmware. The request carries the model and the
/// installed versions, as Space Station's does, and nothing that identifies
/// the controller.
public enum FirmwareCheck {
    public struct Component: Sendable, Identifiable, Equatable {
        public var id: String { chip }
        public var chip: String
        public var label: String
        public var installed: String?
        public var latest: String
        public var notes: String

        public var isNewer: Bool {
            guard let installed else { return true }
            return Self.compare(latest, installed) > 0
        }

        static func compare(_ a: String, _ b: String) -> Int {
            let pa = a.split(separator: ".").map { Int($0) ?? 0 }, pb = b.split(separator: ".").map { Int($0) ?? 0 }
            for i in 0..<max(pa.count, pb.count) {
                let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
                if x != y { return x < y ? -1 : 1 }
            }
            return 0
        }
    }

    public struct Result: Sendable {
        /// Updates for the desktop (Space Station 4) firmware line OpenVader speaks.
        public var desktop: [Component]
        /// The Space Station 5.0 line, which moves the pad to Flydigi's web app.
        public var webApp: [Component]
    }

    static let endpoint = URL(string: "https://api.flydigi.com/pc/Update/firmware")!
    static let labels = ["main_chip": "Controller", "dongle_chip": "Receiver", "si_chip": "SI chip",
                         "rf_chip": "RF chip", "trigger_chip": "Trigger", "screen_chip": "Screen", "adc_chip": "ADC"]
    /// Flydigi's notes are in Chinese; these are the common ones.
    static let translations = ["修复部分已知问题": "Fixes some known issues.", "优化连接稳定性": "Improves connection stability."]

    public static func check(_ info: DeviceInfo) async throws -> Result {
        async let desktop = query(info, appVersion: "4.2.2.3")
        async let web = query(info, appVersion: "5.0.0.0")
        return try await Result(desktop: desktop, webApp: (try? web) ?? [])
    }

    static func query(_ info: DeviceInfo, appVersion: String) async throws -> [Component] {
        let installed: [String: String?] = [
            "main_chip": info.firmware, "dongle_chip": info.receiverFirmware, "si_chip": info.siFirmware,
            "rf_chip": info.rfFirmware, "trigger_chip": info.triggerFirmware,
        ]
        var body: [String: Any] = ["device_code": "f5", "device_id": info.deviceType, "app_version": appVersion]
        for (k, v) in installed { body[k] = v ?? "" }
        var request = URLRequest(url: endpoint, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chips = (json["data"] as? [String: Any])?["chip_list"] as? [String: Any] else {
            throw VaderError.invalidArgument("Flydigi's update service sent an unexpected answer.")
        }
        return chips.compactMap { key, value in
            guard let entry = value as? [String: Any], let latest = entry["version"] as? String else { return nil }
            let note = entry["info"] as? String ?? ""
            return Component(chip: key, label: labels[key] ?? key, installed: installed[key] ?? nil, latest: latest,
                             notes: translations[note] ?? note)
        }
        .sorted { $0.label < $1.label }
    }
}

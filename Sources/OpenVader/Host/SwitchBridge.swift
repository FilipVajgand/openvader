import Foundation
import IOKit.hid
import OSLog
import VaderKit

let switchLog = Logger(subsystem: "io.github.openvader.OpenVader", category: "switch")

/// Watches for the controller in Nintendo Switch mode over the cable, where it
/// is a "Pro Controller" (057E:2009), and decodes the Home-pulse codes its extra
/// buttons send (see `HomePulse`).
///
/// It opens the device without seizing it, so games keep using the controller
/// through GameController as usual. Callbacks arrive on the main run loop.
final class SwitchBridge {
    static let vendorID = 0x057E
    static let productID = 0x2009

    /// A controller in Switch mode came or went.
    var onPresenceChange: ((Bool) -> Void)?
    /// An extra button's code arrived.
    var onKey: ((ControllerKey) -> Void)?

    private(set) var isPresent = false
    private let manager: IOHIDManager
    private var devices = 0
    private var decoder = HomePulse.Decoder()
    private var buffers: [UnsafeMutablePointer<UInt8>] = []

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: Self.vendorID, kIOHIDProductIDKey: Self.productID,
        ] as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            Unmanaged<SwitchBridge>.fromOpaque(context!).takeUnretainedValue().attached(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, _ in
            Unmanaged<SwitchBridge>.fromOpaque(context!).takeUnretainedValue().removed()
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        switchLog.log("Switch-mode listener open: 0x\(String(UInt32(bitPattern: result), radix: 16), privacy: .public)")
    }

    deinit {
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        buffers.forEach { $0.deallocate() }
    }

    private func attached(_ device: IOHIDDevice) {
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
        buffers.append(buffer)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, { context, _, _, _, _, report, length in
            Unmanaged<SwitchBridge>.fromOpaque(context!).takeUnretainedValue()
                .report(UnsafeBufferPointer(start: report, count: length))
        }, context)
        devices += 1
        switchLog.log("Pro Controller attached")
        setPresent(true)
    }

    private func removed() {
        devices = max(0, devices - 1)
        decoder = HomePulse.Decoder()
        if devices == 0 { setPresent(false) }
    }

    private func setPresent(_ present: Bool) {
        guard present != isPresent else { return }
        isPresent = present
        onPresenceChange?(present)
    }

    private func report(_ bytes: UnsafeBufferPointer<UInt8>) {
        guard let home = HomePulse.homePressed(proControllerReport: bytes) else { return }
        if let key = decoder.update(homeDown: home, at: ProcessInfo.processInfo.systemUptime) {
            switchLog.log("Code for \(key.name, privacy: .public)")
            onKey?(key)
        }
    }
}

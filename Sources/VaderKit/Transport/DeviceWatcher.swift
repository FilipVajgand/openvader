import Foundation
import IOKit.hid

/// Calls back on the main run loop whenever a controller's configuration
/// interface appears or disappears.
public final class DeviceWatcher {
    private let manager: IOHIDManager
    private let onChange: () -> Void

    public init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: VaderUSB.vendorID,
            kIOHIDPrimaryUsagePageKey: VaderUSB.controlUsagePage,
        ] as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, _ in
            guard let context else { return }
            Unmanaged<DeviceWatcher>.fromOpaque(context).takeUnretainedValue().onChange()
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, _ in
            guard let context else { return }
            Unmanaged<DeviceWatcher>.fromOpaque(context).takeUnretainedValue().onChange()
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }

    deinit {
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }
}

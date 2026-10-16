import Foundation
import IOKit
import IOKit.hid

public enum VaderError: Error, LocalizedError, Sendable {
    case notFound
    case openFailed(IOReturn)
    case writeFailed(IOReturn)
    case noReply(command: UInt8)
    case transferStalled(command: UInt8, received: Int, expected: Int)
    case forbiddenCommand(UInt8)
    case disconnected
    case unsupportedLayout(String)
    case verificationFailed(String)
    case invalidArgument(String)

    public var errorDescription: String? {
        switch self {
        case .notFound:
            "No Flydigi Vader 5 Pro found. Plug in the 2.4 GHz receiver or a USB-C cable and switch the controller on."
        case .openFailed(let r):
            "Could not open the controller's configuration interface (\(String(format: "0x%08X", r)))."
        case .writeFailed(let r):
            "Sending to the controller failed (\(String(format: "0x%08X", r)))."
        case .noReply(let c):
            String(format: "The controller did not answer command 0x%02X.", c)
        case .transferStalled(let c, let got, let want):
            String(format: "Transfer 0x%02X stalled after %d of %d packets.", c, got, want)
        case .forbiddenCommand(let c):
            String(format: "Command 0x%02X is blocked because it can wipe or brick the controller.", c)
        case .disconnected:
            "The controller was disconnected."
        case .unsupportedLayout(let s):
            s
        case .verificationFailed(let s):
            "Read-back did not match what was written: \(s)"
        case .invalidArgument(let s):
            s
        }
    }
}

/// Identity of one HID interface, read from IOKit properties.
public struct HIDInterfaceInfo: Sendable, Hashable {
    public var vendorID: Int
    public var productID: Int
    public var usagePage: Int
    public var usage: Int
    public var locationID: Int
    public var product: String
    public var registryID: UInt64
}

public enum VaderUSB {
    public static let vendorID = 0x37D7
    public static let vader5ProductID = 0x2401
    public static let controlUsagePage = 0xFFA0
    public static let wiredMarkerUsagePage = 0xFFEF
    public static let dongleMarkerUsagePage = 0xFFEE
}

enum HIDProperties {
    static func int(_ device: IOHIDDevice, _ key: String) -> Int {
        (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0
    }

    static func string(_ device: IOHIDDevice, _ key: String) -> String {
        (IOHIDDeviceGetProperty(device, key as CFString) as? String) ?? ""
    }

    static func info(_ device: IOHIDDevice) -> HIDInterfaceInfo {
        var entryID: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &entryID)
        return HIDInterfaceInfo(
            vendorID: int(device, kIOHIDVendorIDKey),
            productID: int(device, kIOHIDProductIDKey),
            usagePage: int(device, kIOHIDPrimaryUsagePageKey),
            usage: int(device, kIOHIDPrimaryUsageKey),
            locationID: int(device, kIOHIDLocationIDKey),
            product: string(device, kIOHIDProductKey),
            registryID: entryID)
    }
}

/// Enumerates Flydigi HID interfaces currently attached.
public enum HIDDiscovery {
    /// Every HID interface with the Flydigi vendor ID.
    public static func flydigiInterfaces() -> [(IOHIDDevice, HIDInterfaceInfo)] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: VaderUSB.vendorID] as CFDictionary)
        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
        return set.map { ($0, HIDProperties.info($0)) }
            .sorted { ($0.1.locationID, $0.1.usagePage) < ($1.1.locationID, $1.1.usagePage) }
    }

    /// Configuration interfaces of attached controllers (the charging dock is excluded).
    public static func controllers() -> [(IOHIDDevice, HIDInterfaceInfo)] {
        flydigiInterfaces().filter { _, info in
            info.usagePage == VaderUSB.controlUsagePage && (info.productID >> 12) == 2
        }
    }

    public static func connectionKind(for control: HIDInterfaceInfo) -> ConnectionKind {
        let siblings = flydigiInterfaces().map(\.1).filter {
            $0.locationID == control.locationID && $0.productID == control.productID
        }
        if siblings.contains(where: { $0.usagePage == VaderUSB.wiredMarkerUsagePage }) { return .cable }
        if siblings.contains(where: { $0.usagePage == VaderUSB.dongleMarkerUsagePage }) { return .dongle }
        return .unknown
    }
}

public enum ConnectionKind: String, Sendable, Codable {
    case cable = "USB cable"
    case dongle = "2.4 GHz receiver"
    case unknown = "USB"
}

/// What `VaderDevice` needs from a link to the controller. The real one is
/// `HIDConnection`; `VirtualVader` emulates a controller for tests and demos.
public protocol VaderTransport: AnyObject, Sendable {
    var info: HIDInterfaceInfo { get }
    var onInputReport: (([UInt8]) -> Void)? { get set }
    var onRemoval: (() -> Void)? { get set }
    var isRemoved: Bool { get }
    func write(_ frame: [UInt8]) throws
    func drain()
    func nextFrame(timeout: TimeInterval) -> [UInt8]?
    func close()
}

/// An open connection to one controller's configuration interface.
///
/// Reports arrive on a private dispatch queue. Live input reports (`0xEF`)
/// go to `onInputReport`; everything else is queued for the blocking
/// request/response calls made by `VaderDevice` from its own thread.
public final class HIDConnection: VaderTransport, @unchecked Sendable {
    public let info: HIDInterfaceInfo
    private let device: IOHIDDevice
    private let queue = DispatchQueue(label: "openvader.hid.input", qos: .userInteractive)
    private let reportBuffer: UnsafeMutablePointer<UInt8>
    private let reportBufferSize = 64
    private let condition = NSCondition()
    private var pending: [[UInt8]] = []
    private var isOpen = false
    private var removed = false
    private let inputLock = NSLock()
    private var inputHandler: (([UInt8]) -> Void)?
    private var removalHandler: (() -> Void)?

    public static var trace = ProcessInfo.processInfo.environment["OPENVADER_TRACE"] != nil

    public init(device: IOHIDDevice, info: HIDInterfaceInfo) {
        self.device = device
        self.info = info
        reportBuffer = .allocate(capacity: reportBufferSize)
        reportBuffer.initialize(repeating: 0, count: reportBufferSize)
    }

    deinit {
        close()
        reportBuffer.deallocate()
    }

    public var onInputReport: (([UInt8]) -> Void)? {
        get { inputLock.withLock { inputHandler } }
        set { inputLock.withLock { inputHandler = newValue } }
    }

    public var onRemoval: (() -> Void)? {
        get { inputLock.withLock { removalHandler } }
        set { inputLock.withLock { removalHandler = newValue } }
    }

    public var isRemoved: Bool { condition.withLock { removed } }

    public func open() throws {
        guard !isOpen else { return }
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { throw VaderError.openFailed(result) }
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            device, reportBuffer, reportBufferSize,
            { context, _, _, _, _, report, length in
                guard let context else { return }
                let me = Unmanaged<HIDConnection>.fromOpaque(context).takeUnretainedValue()
                me.received(Array(UnsafeBufferPointer(start: report, count: length)))
            }, context)
        IOHIDDeviceRegisterRemovalCallback(
            device,
            { context, _, _ in
                guard let context else { return }
                Unmanaged<HIDConnection>.fromOpaque(context).takeUnretainedValue().wasRemoved()
            }, context)
        IOHIDDeviceSetDispatchQueue(device, queue)
        IOHIDDeviceActivate(device)
        isOpen = true
    }

    public func close() {
        guard isOpen else { return }
        isOpen = false
        let done = DispatchSemaphore(value: 0)
        IOHIDDeviceSetCancelHandler(device) { done.signal() }
        IOHIDDeviceCancel(device)
        _ = done.wait(timeout: .now() + 1)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    private func received(_ report: [UInt8]) {
        guard Frame.isFrame(report) else { return }
        if report[2] == Command.inputReport.rawValue {
            inputLock.withLock { inputHandler }?(report)
            return
        }
        if Self.trace { FileHandle.standardError.write("  <- \(report.hexString)\n".data(using: .utf8)!) }
        condition.withLock {
            pending.append(report)
            if pending.count > 512 { pending.removeFirst(pending.count - 512) }
            condition.broadcast()
        }
    }

    private func wasRemoved() {
        condition.withLock {
            removed = true
            condition.broadcast()
        }
        inputLock.withLock { removalHandler }?()
    }

    /// Sends one 32-byte frame.
    public func write(_ frame: [UInt8]) throws {
        guard frame.count >= 3 else { throw VaderError.invalidArgument("frame too short") }
        guard !Command.forbidden.contains(frame[2]) else { throw VaderError.forbiddenCommand(frame[2]) }
        if isRemoved { throw VaderError.disconnected }
        if Self.trace { FileHandle.standardError.write("  -> \(frame.hexString)\n".data(using: .utf8)!) }
        let result = frame.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, $0.baseAddress!, $0.count)
        }
        guard result == kIOReturnSuccess else { throw VaderError.writeFailed(result) }
    }

    /// Drops any reply frames that are already queued.
    public func drain() {
        condition.withLock { pending.removeAll() }
    }

    /// Waits for the next queued reply frame, or nil on timeout.
    public func nextFrame(timeout: TimeInterval) -> [UInt8]? {
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        defer { condition.unlock() }
        while pending.isEmpty {
            if removed { return nil }
            if !condition.wait(until: deadline) { break }
        }
        return pending.isEmpty ? nil : pending.removeFirst()
    }
}

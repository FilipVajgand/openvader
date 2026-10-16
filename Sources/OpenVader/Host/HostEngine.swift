import AppKit
import CoreGraphics
import VaderKit

/// Turns live controller input into keyboard and mouse events on the Mac.
///
/// This is the Mac side of Space Station's keyboard/mouse mappings: the
/// controller only stores a marker, and the computer produces the key
/// presses and pointer movement. It runs on the HID queue for every input
/// report (about 500 per second) and needs Accessibility access.
final class HostEngine: @unchecked Sendable {
    private let lock = NSLock()
    private var mappings: HostProfileMappings?
    private var heldButtons: Set<ControllerKey> = []
    private var stickKeys: [Side: Set<UInt16>] = [:]
    private var heldModifierKeys: Set<UInt16> = []
    private var mouseDown: Set<MouseButton> = []
    private var gyroToggled = false
    private var gyroKeyWasDown = false
    private var pointerRemainder = SIMD2<Double>(0, 0)
    private var scrollRemainder = SIMD2<Double>(0, 0)
    private var scrollRepeat: [ControllerKey: Double] = [:]
    private var lastTime: Double?
    private let source = CGEventSource(stateID: .hidSystemState)

    static var hasPermission: Bool { CGPreflightPostEventAccess() }

    @discardableResult
    static func requestPermission() -> Bool { CGRequestPostEventAccess() }

    var isActive: Bool { lock.withLock { mappings != nil } }

    /// Switches to another profile's mappings (nil stops), releasing anything held.
    func use(_ m: HostProfileMappings?) {
        lock.withLock {
            releaseAllLocked()
            mappings = (m?.isEmpty ?? true) ? nil : m
            gyroToggled = false
            lastTime = nil
        }
    }

    func stop() { use(nil) }

    func process(_ s: InputState) {
        lock.withLock {
            guard let m = mappings, Self.hasPermission else { return }
            let now = ProcessInfo.processInfo.systemUptime
            let dt = min(0.05, max(0, now - (lastTime ?? now)))
            lastTime = now
            var pointer = SIMD2<Double>(0, 0)
            var scroll = SIMD2<Double>(0, 0)

            // Buttons
            for (raw, action) in m.buttons {
                guard let id = UInt8(raw), let key = ControllerKey(rawValue: id) else { continue }
                let down = isDown(key, s)
                let was = heldButtons.contains(key)
                if down && !was {
                    heldButtons.insert(key)
                    press(action, down: true)
                    if case .scroll = action { scrollRepeat[key] = now + 0.35 }
                } else if !down && was {
                    heldButtons.remove(key)
                    press(action, down: false)
                    scrollRepeat[key] = nil
                } else if down, case .scroll(let dir) = action, let next = scrollRepeat[key], now >= next {
                    scrollNotch(dir)
                    scrollRepeat[key] = now + 0.08
                }
            }

            // Sticks
            for side in Side.allCases {
                guard let settings = m.stick(side) else { continue }
                let v = side == .left ? s.leftStick : s.rightStick
                let dz = Double(settings.deadZone) / 100
                let mag = min(1, (v.x * v.x + v.y * v.y).squareRoot())
                let amount = mag > dz ? (mag - dz) / max(0.01, 1 - dz) : 0
                let dir = mag > 0 ? v / mag : SIMD2(0, 0)
                switch settings.mode {
                case .mouse(let speed):
                    let pps = Double(speed) / 100 * 2600 * amount * amount
                    pointer += SIMD2(dir.x, -dir.y) * pps * dt
                case .scroll(let speed):
                    let pps = Double(speed) / 100 * 1600 * amount * amount
                    scroll += SIMD2(dir.x, dir.y) * pps * dt
                case .keys(let up, let down, let left, let right, let eightWay):
                    var want: Set<UInt16> = []
                    if amount > 0 {
                        let t = eightWay ? 0.38 : 0.0
                        if eightWay {
                            if dir.y > t { want.insert(up.keyCode) }
                            if dir.y < -t { want.insert(down.keyCode) }
                            if dir.x < -t { want.insert(left.keyCode) }
                            if dir.x > t { want.insert(right.keyCode) }
                        } else if abs(dir.x) > abs(dir.y) {
                            want.insert(dir.x > 0 ? right.keyCode : left.keyCode)
                        } else {
                            want.insert(dir.y > 0 ? up.keyCode : down.keyCode)
                        }
                    }
                    let had = stickKeys[side] ?? []
                    for code in had.subtracting(want) { key(KeyStroke(code), down: false) }
                    for code in want.subtracting(had) { key(KeyStroke(code), down: true) }
                    stickKeys[side] = want
                }
            }

            // Gyro
            if let g = m.gyro {
                var on = true
                if let k = g.enableKey {
                    let down = isDown(k, s)
                    if g.activation == .hold {
                        on = down
                    } else {
                        if down && !gyroKeyWasDown { gyroToggled.toggle() }
                        on = gyroToggled
                    }
                    gyroKeyWasDown = down
                }
                if on {
                    // Yaw turns the pointer sideways, pitch moves it up and down.
                    var yaw = -s.gyro.y, pitch = -s.gyro.x
                    if abs(yaw) < 1.2 { yaw = 0 }
                    if abs(pitch) < 1.2 { pitch = 0 }
                    let pxPerDegree = Double(g.sensitivity) / 100 * 30
                    pointer += SIMD2(g.invertX ? -yaw : yaw, g.invertY ? -pitch : pitch) * pxPerDegree * dt
                }
            }

            movePointer(pointer)
            scrollBy(scroll)
        }
    }

    // MARK: Output

    private func isDown(_ key: ControllerKey, _ s: InputState) -> Bool {
        switch key {
        case .lt: s.leftTrigger > 0.3 || s.buttons.contains(.lt)
        case .rt: s.rightTrigger > 0.3 || s.buttons.contains(.rt)
        default: s.buttons.contains(key)
        }
    }

    private func press(_ action: HostAction, down: Bool) {
        switch action {
        case .key(let stroke): key(stroke, down: down)
        case .mouse(let button): mouse(button, down: down)
        case .scroll(let dir): if down { scrollNotch(dir) }
        }
    }

    private var modifierFlags: CGEventFlags {
        var flags: CGEventFlags = []
        for code in heldModifierKeys {
            guard let m = KeyStroke.modifierKeys[code] else { continue }
            flags.formUnion(Self.flags(m))
        }
        return flags
    }

    private static func flags(_ m: KeyStroke.Modifiers) -> CGEventFlags {
        var f: CGEventFlags = []
        if m.contains(.command) { f.insert(.maskCommand) }
        if m.contains(.option) { f.insert(.maskAlternate) }
        if m.contains(.control) { f.insert(.maskControl) }
        if m.contains(.shift) { f.insert(.maskShift) }
        return f
    }

    private func key(_ stroke: KeyStroke, down: Bool) {
        if KeyStroke.modifierKeys[stroke.keyCode] != nil {
            if down { heldModifierKeys.insert(stroke.keyCode) } else { heldModifierKeys.remove(stroke.keyCode) }
        }
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: stroke.keyCode, keyDown: down) else { return }
        event.flags = modifierFlags.union(Self.flags(stroke.modifiers))
        event.post(tap: .cghidEventTap)
    }

    private var cursor: CGPoint { CGEvent(source: nil)?.location ?? .zero }

    private func mouse(_ button: MouseButton, down: Bool) {
        let types: (CGEventType, CGEventType, CGMouseButton) = switch button {
        case .left: (.leftMouseDown, .leftMouseUp, .left)
        case .right: (.rightMouseDown, .rightMouseUp, .right)
        default: (.otherMouseDown, .otherMouseUp, CGMouseButton(rawValue: UInt32(button.rawValue))!)
        }
        if down { mouseDown.insert(button) } else { mouseDown.remove(button) }
        guard let event = CGEvent(mouseEventSource: source, mouseType: down ? types.0 : types.1,
                                  mouseCursorPosition: cursor, mouseButton: types.2) else { return }
        event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button.rawValue))
        event.flags = modifierFlags
        event.post(tap: .cghidEventTap)
    }

    private func movePointer(_ delta: SIMD2<Double>) {
        pointerRemainder += delta
        let dx = pointerRemainder.x.rounded(.towardZero), dy = pointerRemainder.y.rounded(.towardZero)
        guard dx != 0 || dy != 0 else { return }
        pointerRemainder -= SIMD2(dx, dy)
        let bounds = Self.desktopBounds
        var p = cursor
        p.x = min(max(p.x + dx, bounds.minX), bounds.maxX - 1)
        p.y = min(max(p.y + dy, bounds.minY), bounds.maxY - 1)
        let (type, button): (CGEventType, CGMouseButton) =
            mouseDown.contains(.left) ? (.leftMouseDragged, .left)
            : mouseDown.contains(.right) ? (.rightMouseDragged, .right)
            : mouseDown.isEmpty ? (.mouseMoved, .left) : (.otherMouseDragged, .center)
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: button)
        else { return }
        event.setIntegerValueField(.mouseEventDeltaX, value: Int64(dx))
        event.setIntegerValueField(.mouseEventDeltaY, value: Int64(dy))
        event.flags = modifierFlags
        event.post(tap: .cghidEventTap)
    }

    private func scrollBy(_ delta: SIMD2<Double>) {
        scrollRemainder += delta
        let dx = scrollRemainder.x.rounded(.towardZero), dy = scrollRemainder.y.rounded(.towardZero)
        guard dx != 0 || dy != 0 else { return }
        scrollRemainder -= SIMD2(dx, dy)
        CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                wheel1: Int32(dy), wheel2: Int32(-dx), wheel3: 0)?.post(tap: .cghidEventTap)
    }

    private func scrollNotch(_ dir: ScrollDirection) {
        let (v, h): (Int32, Int32) = switch dir {
        case .up: (1, 0)
        case .down: (-1, 0)
        case .left: (0, 1)
        case .right: (0, -1)
        }
        CGEvent(scrollWheelEvent2Source: source, units: .line, wheelCount: 2, wheel1: v, wheel2: h, wheel3: 0)?
            .post(tap: .cghidEventTap)
    }

    private func releaseAllLocked() {
        guard let m = mappings else { return }
        for key in heldButtons { if let a = m.action(for: key) { press(a, down: false) } }
        heldButtons = []
        for (_, codes) in stickKeys { for c in codes { key(KeyStroke(c), down: false) } }
        stickKeys = [:]
        for b in mouseDown { mouse(b, down: false) }
        heldModifierKeys = []
        scrollRepeat = [:]
    }

    /// Union of all displays, in global (top-left origin) coordinates.
    private static var desktopBounds: CGRect {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return ids.map { CGDisplayBounds($0) }.reduce(CGRect.null) { $0.union($1) }
    }
}

import AppKit
import CoreGraphics
import Mango

public struct KeyEvent {
    public var keyCode: UInt16
    public var mods: Modifiers
    public var isDown: Bool
    public var isRepeat: Bool
    public var isModifierKey: Bool
    public var ageMs: Double? = nil
}

func eventAgeMs(_ event: CGEvent) -> Double? {
    let ts = event.timestamp
    guard ts > 0 else { return nil }
    let nowNs = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    if nowNs >= ts, nowNs - ts < 60_000_000_000 { return Double(nowNs - ts) / 1e6 }
    var tb = mach_timebase_info_data_t()
    mach_timebase_info(&tb)
    let nowTicks = mach_absolute_time()
    if nowTicks >= ts {
        let ns = Double(nowTicks - ts) * Double(tb.numer) / Double(tb.denom)
        if ns < 60e9 { return ns / 1e6 }
    }
    return nil
}

public struct MouseButtonEvent {
    public var button: Int
    public var mods: Modifiers
    public var isDown: Bool
    public var location: CGPoint
}

public struct ScrollEvent {
    public var direction: Direction
    public var mods: Modifiers
    public var location: CGPoint
}

public extension Modifiers {
    init(cgFlags f: CGEventFlags) {
        var m: Modifiers = []
        if f.contains(.maskCommand) { m.insert(.superKey) }
        if f.contains(.maskControl) { m.insert(.ctrl) }
        if f.contains(.maskShift) { m.insert(.shift) }
        if f.contains(.maskAlternate) { m.insert(.alt) }
        if f.contains(.maskSecondaryFn) { m.insert(.fn) }
        self = m
    }
}

public final class EventTap: @unchecked Sendable {
    public var onKey: ((KeyEvent) -> Bool)?
    public var onMouseButton: ((MouseButtonEvent) -> Bool)?
    public var onMouseDragged: ((CGPoint) -> Void)?
    public var onMouseMoved: ((CGPoint) -> Void)?
    public var onScroll: ((ScrollEvent) -> Bool)?

    private let thread = AXThread(name: "mango.eventtap")

    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var movePort: CFMachPort?
    private var moveSource: CFRunLoopSource?
    private var swallowingDrag = false
    private var lastKeyWasModifierOnly = true

    public init() {}

    public func start() -> Bool {
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) | (1 << CGEventType.rightMouseUp.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) | (1 << CGEventType.otherMouseUp.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) | (1 << CGEventType.rightMouseDragged.rawValue) |
            (1 << CGEventType.otherMouseDragged.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let p = CGEvent.tapCreate(tap: .cgAnnotatedSessionEventTap, place: .tailAppendEventTap, options: .defaultTap,
                                        eventsOfInterest: mask, callback: eventTapCallback, userInfo: refcon) else {
            return false
        }
        thread.startAndWait()
        let loop = thread.runLoop
        port = p
        source = CFMachPortCreateRunLoopSource(nil, p, 0)
        CFRunLoopAddSource(loop, source, .commonModes)
        CGEvent.tapEnable(tap: p, enable: true)

        let moveMask: CGEventMask = 1 << CGEventType.mouseMoved.rawValue
        if let mp = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                      eventsOfInterest: moveMask, callback: eventTapCallback, userInfo: refcon) {
            movePort = mp
            moveSource = CFMachPortCreateRunLoopSource(nil, mp, 0)
            CFRunLoopAddSource(loop, moveSource, .commonModes)
            CGEvent.tapEnable(tap: mp, enable: true)
        }
        CFRunLoopWakeUp(loop)
        return true
    }

    public func stop() {
        for p in [port, movePort].compactMap({ $0 }) { CGEvent.tapEnable(tap: p, enable: false) }
        for s in [source, moveSource].compactMap({ $0 }) { CFRunLoopRemoveSource(thread.runLoop, s, .commonModes) }
        port = nil; source = nil; movePort = nil; moveSource = nil
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            for p in [port, movePort].compactMap({ $0 }) { CGEvent.tapEnable(tap: p, enable: true) }
            return false
        }
        let mods = Modifiers(cgFlags: event.flags)
        let loc = event.location
        switch type {
        case .keyDown, .keyUp:
            let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            lastKeyWasModifierOnly = false
            let ev = KeyEvent(keyCode: code, mods: mods, isDown: type == .keyDown, isRepeat: isRepeat, isModifierKey: false,
                              ageMs: eventAgeMs(event))
            return onKey?(ev) ?? false
        case .flagsChanged:
            let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let down = modifierIsDown(code: code, flags: event.flags)
            if down { lastKeyWasModifierOnly = true }
            let ev = KeyEvent(keyCode: code, mods: mods, isDown: down, isRepeat: false, isModifierKey: true,
                              ageMs: eventAgeMs(event))
            let swallow = onKey?(ev) ?? false
            if !down { lastKeyWasModifierOnly = true }
            return swallow
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if event.getIntegerValueField(.eventSourceUnixProcessID) == Int64(getpid()) { return false }
            let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            let ev = MouseButtonEvent(button: button, mods: mods, isDown: true, location: loc)
            let swallow = onMouseButton?(ev) ?? false
            swallowingDrag = swallow
            return swallow
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            if event.getIntegerValueField(.eventSourceUnixProcessID) == Int64(getpid()) { return false }
            let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            let ev = MouseButtonEvent(button: button, mods: mods, isDown: false, location: loc)
            let swallow = onMouseButton?(ev) ?? false
            let wasSwallowing = swallowingDrag
            swallowingDrag = false
            return swallow || wasSwallowing
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            onMouseDragged?(loc)
            return swallowingDrag
        case .mouseMoved:
            onMouseMoved?(loc)
            return false
        case .scrollWheel:
            guard let onScroll else { return false }
            let dy = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
            let dx = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
            let dir: Direction
            if abs(dy) >= abs(dx) { dir = dy > 0 ? .up : .down } else { dir = dx > 0 ? .left : .right }
            if dx == 0 && dy == 0 { return false }
            return onScroll(ScrollEvent(direction: dir, mods: mods, location: loc))
        default:
            return false
        }
    }

    public var lastKeyPressWasModifierOnly: Bool { lastKeyWasModifierOnly }

    private func modifierIsDown(code: UInt16, flags: CGEventFlags) -> Bool {
        switch code {
        case 54, 55: return flags.contains(.maskCommand)
        case 56, 60: return flags.contains(.maskShift)
        case 58, 61: return flags.contains(.maskAlternate)
        case 59, 62: return flags.contains(.maskControl)
        case 63: return flags.contains(.maskSecondaryFn)
        case 57: return flags.contains(.maskAlphaShift)
        default: return false
        }
    }
}

private func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                              refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue()
    return tap.handle(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
}

public final class HotkeyMatcher {
    public var bindings: [KeyBinding] = []
    public var mode = "default"

    public init() {}

    public func match(_ ev: KeyEvent, lastHeldIsThisKey: Bool) -> [KeyBinding] {
        Keyboard.keyboardCheckKeybinding(bindings, mode: mode, keyCode: ev.keyCode, mods: ev.mods, isDown: ev.isDown,
                                         keyModifier: ev.isModifierKey ? Self.modifier(forKeyCode: ev.keyCode) : nil,
                                         lastHoldKeycodeIsThisKey: lastHeldIsThisKey)
    }

    static func modifier(forKeyCode code: UInt16) -> Modifiers {
        switch code {
        case 54, 55: return .superKey
        case 56, 60: return .shift
        case 58, 61: return .alt
        case 59, 62: return .ctrl
        case 63: return .fn
        default: return []
        }
    }
}

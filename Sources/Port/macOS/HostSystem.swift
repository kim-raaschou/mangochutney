import AppKit
import Mango

/// What the port asks of the machine itself, outside any window: the pointer and its buttons, the
/// keyboard's modifiers, key codes and key mapping, the screens, the input devices, the event tap and gestures,
/// screen capture permission, spawning programs, scanning the apps again, and quitting. The seam
/// between MacWindowSystem and macOS (the event system, IOKit, the process); MacHostSystem in the app;
/// the tests give their own, which reads no hardware and starts nothing.
@MainActor
protocol HostSystem: AnyObject {
    /// The pointer, in the scene's coordinates where a scene panel is up.
    var pointer: CGPoint { get }
    func warp(to p: CGPoint)
    /// keyboard_hard_modifiers: the keyboards' own modifiers, without posted events (mango leaves out
    /// virtual keyboards).
    func keyboardHardModifiers() -> Modifiers
    var mouseButtons: Int { get }
    /// The screens, as the outputs mango gets.
    var screens: [Screen] { get }
    var inputDevices: [InputDevice] { get }
    /// xkb_rules_options, and the hyper key, as the keyboard's key mapping.
    func setKeyboardOptions(_ options: String)
    func findKeycodesForKeysym(_ keysym: Character) -> MultiKeycode
    /// The event tap, the gestures and the session's notifications started.
    func startInput()
    func watchGestures(_ on: Bool)
    var canCapture: Bool { get }
    func askToCapture()
    func spawn(_ command: String)
    func spawnShell(_ command: String)
    /// The apps and their windows read again once the frame clock is idle.
    func rescan()
    func quit()
}

/// The machine as macOS gives it.
@MainActor
final class MacHostSystem: HostSystem {
    private unowned let mac: MacWindowSystem

    init(_ mac: MacWindowSystem) { self.mac = mac }

    var pointer: CGPoint { mac.scenePointer(Screens.mouseLocation) }

    func warp(to p: CGPoint) {
        guard mac.server.drawsOverlays else { return }
        NativeFocus.warpCursor(to: p)
    }

    func keyboardHardModifiers() -> Modifiers {
        KeyboardOptions.hyperMods(Modifiers(cgFlags: CGEventSource.flagsState(.hidSystemState)),
                                  hyper: KeyboardOptions.hyperSet(mac.server.config), keyHeld: mac.router.hyperKeyHeld)
    }

    var mouseButtons: Int { Int(NSEvent.pressedMouseButtons) }

    var screens: [Screen] { Screens.all() }

    var inputDevices: [InputDevice] { InputDevices.all() }

    func setKeyboardOptions(_ options: String) {
        var m = KeyboardOptions.mappings(KeyboardOptions.xkbOptions(options))
        if let h = KeyboardOptions.hyperKeyMapping(mac.server.config.chutneyHyperKey), !m.contains(where: { $0.src == h.src }) {
            m.append(h)
        }
        if mac.userKeyMappings == nil {
            let now = KeyboardOptions.current() ?? []
            mac.userKeyMappings = now.filter { $0.dst != KeyboardOptions.f18 }
            mac.appliedKeyMappings = now
        }
        let all = KeyboardOptions.merged(user: mac.userKeyMappings ?? [], mango: m)
        mac.keyMappings = m
        guard all != mac.appliedKeyMappings else { return }
        mac.appliedKeyMappings = all
        KeyboardOptions.apply(all)
        if KeyboardOptions.takesCapsLock(m) { KeyboardOptions.capsLockOff() }
        wlrLog(.info, m.isEmpty ? "xkb_rules_options: the keyboard's key mapping cleared"
                           : "xkb_rules_options: \(m.count) key(s) moved")
    }

    func findKeycodesForKeysym(_ keysym: Character) -> MultiKeycode {
        let codes = KeyNames.keyCodes(forName: String(keysym))
        return MultiKeycode(keycode1: codes.first, keycode2: codes.dropFirst().first, keycode3: codes.dropFirst(2).first)
    }

    func startInput() {
        let server = mac.server, tap = mac.tap
        CursorHider.prepareTapCursors()
        mac.router.server = server
        let r = mac.router
        tap.onKey = { [unowned tap] ev in r.key(ev, modifierOnlySinceDown: tap.lastKeyPressWasModifierOnly) }
        tap.onMouseButton = { ev in r.mouseButton(ev) }
        tap.onMouseDragged = { p in r.dragged(p) }
        tap.onMouseMoved = { p in r.mouseMoved(p) }
        tap.onScroll = { ev in r.scroll(ev) }
        if !tap.start() { wlrLog(.error, "could not create event tap (Accessibility permission missing?)") }
        mac.gestures.onEvent = { [weak mac] event, time in
            MainActor.assumeIsolated {
                switch event {
                case .update(let s): mac?.swipeUpdate(s, time)
                case .end(_, let cancelled): mac?.swipeEnd(cancelled: cancelled)
                }
            }
        }
        let close: @Sendable (Notification) -> Void = { [weak server] _ in
            MainActor.assumeIsolated { server?.switcherClose() }
        }
        let dnc = DistributedNotificationCenter.default(), ws = NSWorkspace.shared.notificationCenter
        let layoutChanged: @Sendable (Notification) -> Void = { [weak server] _ in
            MainActor.assumeIsolated { server?.printstatus(.kbLayout) }
        }
        // Behind a locked screen Accessibility gives no windows: they are read again once it is unlocked.
        let unlocked: @Sendable (Notification) -> Void = { [weak mac] _ in
            MainActor.assumeIsolated { mac?.watcher.refreshAll(recheckRejected: true) }
        }
        mac.observers = [
            dnc.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main, using: close),
            dnc.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main, using: unlocked),
            ws.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main, using: close),
            dnc.addObserver(forName: Notification.Name("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"),
                            object: nil, queue: .main, using: layoutChanged),
        ]
    }

    func watchGestures(_ on: Bool) {
        if on { mac.gestures.start() } else { mac.gestures.stop() }
    }

    var canCapture: Bool { WindowSnapshot.hasPermission }

    func askToCapture() { Permissions.shared.askForCapture() }

    func spawn(_ command: String) { Spawn.run(command) }

    func spawnShell(_ command: String) { Spawn.shell(command) }

    func rescan() {
        mac.frameClock.whenIdle { [weak mac] in mac?.watcher.refreshAll(recheckRejected: true) }
    }

    func quit() { NSApp.terminate(nil) }
}

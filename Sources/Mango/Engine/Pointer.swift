import CoreGraphics

/// Not in mango: mango's pointer decisions, taken on the port's event-tap thread.
package enum Pointer {
    package enum ButtonPress: Equatable {
        case switcher
        case overview
        case mouseBinding(MouseBinding)
        case borderResize
        case none
    }

    package static func pointerProcessButtonPress(button: Int, at p: CGPoint, mods: Modifiers, switcherActive: Bool,
                                                  overviewFrame: CGRect?, mouseBindings: [MouseBinding],
                                                  mode: String, hoverResizeEdge: Bool = false) -> ButtonPress {
        if switcherActive && (button == 0 || button == 1) { return .switcher }
        if let f = overviewFrame, f.contains(p), button == 0 || button == 1 { return .overview }
        let mods = mods.subtracting(.fn)
        if let b = mouseBindings.first(where: {
            ($0.mode == "common" || $0.mode == mode) && $0.mods == mods && $0.button.cgButtonNumber == button
        }) {
            return .mouseBinding(b)
        }
        if button == 0 && hoverResizeEdge { return .borderResize }
        return .none
    }

    package static func handleCursorAxis(direction: Direction, mods: Modifiers, now: Double, applyTime: Double,
                                         applyDir: Int, axisBindings: [AxisBinding], mode: String,
                                         timeout: Double) -> (binding: AxisBinding, fires: Bool, dir: Int)? {
        let mods = mods.subtracting(.fn)
        guard let b = axisBindings.first(where: {
            ($0.mode == "common" || $0.mode == mode) && $0.mods == mods && !$0.isUndir
                && ($0.direction == nil || $0.direction == direction)
        }) else { return nil }
        let dir = direction == .down || direction == .right ? 1 : -1
        return (b, now - applyTime > timeout || applyDir * dir < 0, dir)
    }
}

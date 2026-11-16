import AppKit
import Mango

/// The part of a window mango shows at its monitor's edge, where the port parks the window because the
/// rest would land on another monitor (macOS cannot clip another app's window): a still picture of the
/// window taken when it is parked, cut at the edge; the app's icon until the picture comes, or without
/// Screen Recording. Its border is the window's, cut at the edge with it. A click focuses the window, as
/// a click on mango's clipped window does.
@MainActor
final class EdgePlates {
    private final class Plate {
        let window: NSWindow
        let root: ClickView
        let frame = CALayer()
        let picture = CALayer()
        let icon = CALayer()

        init(id: ClientID, onClick: @escaping (ClientID) -> Void) {
            window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.animationBehavior = .none
            window.level = .normal
            window.collectionBehavior = [.ignoresCycle, .fullScreenNone, .transient]
            root = ClickView(frame: .zero)
            root.wantsLayer = true
            root.onClick = { onClick(id) }
            window.contentView = root
            picture.backgroundColor = NSColor.windowBackgroundColor.cgColor
            picture.contentsGravity = .resize
            picture.masksToBounds = true
            icon.contentsGravity = .resizeAspect
            picture.addSublayer(icon)
            frame.addSublayer(picture)
            root.layer?.addSublayer(frame)
        }
    }

    private var plates: [ClientID: Plate] = [:]
    var onClick: ((ClientID) -> Void)?

    /// The plate for window `id`: `box` is the window's whole box, `monitor` the box it is cut at, and
    /// the border as the port draws the window's.
    func show(_ id: ClientID, pid: pid_t, box: CGRect, monitor: CGRect, border: Border) {
        let outer = box.insetBy(dx: -border.width, dy: -border.width)
        let visible = outer.intersection(monitor)
        guard !visible.isNull, !visible.isEmpty else { hide(id); return }
        let plate: Plate
        var new = false
        if let p = plates[id] {
            plate = p
        } else {
            plate = Plate(id: id) { [weak self] id in self?.onClick?(id) }
            plates[id] = plate
            new = true
        }
        let h = Screens.primaryHeight
        plate.window.setFrame(CGRect(x: visible.minX, y: h - visible.maxY, width: visible.width, height: visible.height),
                              display: false)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // The window's whole box and border in the plate's (AppKit, bottom-up) coordinates: the plate
        // shows its part.
        plate.frame.frame = CGRect(x: outer.minX - visible.minX, y: visible.maxY - outer.maxY,
                                   width: outer.width, height: outer.height)
        plate.picture.frame = CGRect(x: border.width, y: border.width, width: box.width, height: box.height)
        plate.picture.cornerRadius = border.innerRadius
        apply(border, to: plate)
        let side = min(64, box.width * 0.4, box.height * 0.4)
        let shown = box.intersection(monitor)
        plate.icon.frame = CGRect(x: (shown.midX - box.minX) - side / 2, y: (box.maxY - shown.midY) - side / 2,
                                  width: side, height: side)
        CATransaction.commit()
        guard new else { return }
        plate.icon.contents = NSRunningApplication(processIdentifier: pid)?.icon
        plate.window.orderFrontRegardless()
        guard WindowSnapshot.hasPermission else { return }
        let scale = NSScreen.screens.first { $0.frame.contains(CGPoint(x: visible.midX, y: h - visible.midY)) }?
            .backingScaleFactor ?? 2
        WindowSnapshot.capture([id], pixelSize: [id: CGSize(width: box.width * scale, height: box.height * scale)]) {
            [weak self] id, image in
            guard let plate = self?.plates[id] else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            plate.picture.contents = image
            plate.icon.isHidden = true
            CATransaction.commit()
        }
    }

    struct Border: Equatable {
        var color: CGColor
        var width: CGFloat
        var radius: CGFloat
        var innerRadius: CGFloat
    }

    /// The border again, as the window's is drawn now (focus, urgency).
    func setBorder(_ id: ClientID, _ border: Border) {
        guard let plate = plates[id] else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        apply(border, to: plate)
        CATransaction.commit()
    }

    private func apply(_ border: Border, to plate: Plate) {
        plate.frame.borderColor = border.color
        plate.frame.borderWidth = border.width
        plate.frame.cornerRadius = border.radius
    }

    func hide(_ id: ClientID) {
        guard let plate = plates.removeValue(forKey: id) else { return }
        plate.window.orderOut(nil)
        plate.window.close()
    }

    func hideAll() {
        for id in Array(plates.keys) { hide(id) }
    }
}

private final class ClickView: NSView {
    var onClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

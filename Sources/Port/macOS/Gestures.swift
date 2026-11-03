import Foundation
import MangoPrivate
import Mango

/// Multi-finger swipes from the trackpad (the private MultitouchSupport framework), as
/// libinput's swipe gestures reach mango: updates while the fingers move and the end, in
/// libinput's units (SwipeTracker). LiveGestures.swift does what mango does with them.
public final class GestureRecognizer {
    /// Each swipe update and end, with its time in milliseconds (main thread).
    var onEvent: ((SwipeEvent, UInt32) -> Void)?

    private var devices: [MTDeviceRef] = []
    /// Each device's sensor, in millimetres.
    private var sizes: [UnsafeMutableRawPointer: CGSize] = [:]
    private var tracker = SwipeTracker()
    /// Keeps the device refs alive while they are registered.
    private var deviceList: CFArray?

    public init() {}

    public func start() {
        guard devices.isEmpty, let cfList = MTDeviceCreateList()?.takeRetainedValue() else { return }
        deviceList = cfList
        shared = self
        let count = CFArrayGetCount(cfList)
        for i in 0..<count {
            guard let raw = CFArrayGetValueAtIndex(cfList, i) else { continue }
            let dev = MTDeviceRef(mutating: raw)
            var w: Int32 = 0, h: Int32 = 0
            _ = MTDeviceGetSensorSurfaceDimensions(dev, &w, &h)
            // A built-in trackpad is about 160 × 100 mm, should the device not say.
            sizes[dev] = w > 0 && h > 0 ? CGSize(width: Double(w) / 100, height: Double(h) / 100)
                                        : CGSize(width: 160, height: 100)
            MTRegisterContactFrameCallback(dev, gestureCallback)
            MTDeviceStart(dev, 0)
            devices.append(dev)
        }
    }

    public func stop() {
        for dev in devices {
            MTUnregisterContactFrameCallback(dev, gestureCallback)
            MTDeviceStop(dev)
        }
        devices.removeAll()
        sizes.removeAll()
        deviceList = nil
        if shared === self { shared = nil }
    }

    fileprivate func frame(device: MTDeviceRef?, touches: [MTTouch], timestamp: Double) {
        // state 4 = touching, 1..3 = starting, 5..7 = leaving
        let active = touches.filter { $0.state == 4 || $0.state == 3 }
        let n = active.count
        let size = device.flatMap { sizes[$0] } ?? CGSize(width: 160, height: 100)
        var centre = CGPoint.zero
        if n > 0 {
            // Normalised positions have y up; the centre is in millimetres with y down.
            let x = active.map { Double($0.normalized.pos.x) }.reduce(0, +) / Double(n)
            let y = active.map { Double($0.normalized.pos.y) }.reduce(0, +) / Double(n)
            centre = CGPoint(x: x * size.width, y: (1 - y) * size.height)
        }
        guard let event = tracker.frame(fingers: n, centre: centre) else { return }
        let ms = UInt32((timestamp * 1000).truncatingRemainder(dividingBy: Double(UInt32.max)))
        DispatchQueue.main.async { [weak self] in self?.onEvent?(event, ms) }
    }
}

private var shared: GestureRecognizer?

private func gestureCallback(_ device: MTDeviceRef?, _ touches: UnsafeMutablePointer<MTTouch>?, _ count: Int32,
                             _ timestamp: Double, _ frame: Int32) -> Int32 {
    guard let touches, let g = shared else { return 0 }
    let arr = Array(UnsafeBufferPointer(start: touches, count: Int(count)))
    g.frame(device: device, touches: arr, timestamp: timestamp)
    return 0
}

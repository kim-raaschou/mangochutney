import AppKit
import ScreenCaptureKit
import Mango

public enum WindowSnapshot {
    public static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    static func fitted(_ window: CGSize, in target: CGSize) -> CGSize {
        guard window.width > 0, window.height > 0 else { return target }
        let scale = min(target.width / window.width, target.height / window.height)
        return CGSize(width: (window.width * scale).rounded(), height: (window.height * scale).rounded())
    }

    public static func capture(_ ids: [CGWindowID], pixelSize: [CGWindowID: CGSize], onlyOnScreen: Set<CGWindowID> = [],
                               onImage: @escaping @MainActor (CGWindowID, CGImage) -> Void) {
        capture(ids, pixelSize: pixelSize, onlyOnScreen: onlyOnScreen) { id, image, _ in onImage(id, image) }
    }

    /// The pictures with the size each window had when it was taken.
    public static func capture(_ ids: [CGWindowID], pixelSize: [CGWindowID: CGSize], onlyOnScreen: Set<CGWindowID> = [],
                               onShot: @escaping @MainActor (CGWindowID, CGImage, CGSize) -> Void) {
        Task.detached(priority: .userInitiated) {
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) else {
                return
            }
            let byID = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { a, _ in a })
            await withTaskGroup(of: Void.self) { group in
                // A window in macOS fullscreen on another Space gives no picture: its card keeps its app's
                // icon and title.
                for id in ids {
                    guard let w = byID[id], w.isOnScreen || !onlyOnScreen.contains(id) else { continue }
                    group.addTask {
                        let filter = SCContentFilter(desktopIndependentWindow: w)
                        let cfg = SCStreamConfiguration()
                        let size = fitted(w.frame.size, in: pixelSize[id] ?? CGSize(width: 800, height: 600))
                        cfg.width = max(32, Int(size.width))
                        cfg.height = max(32, Int(size.height))
                        cfg.showsCursor = false
                        cfg.ignoreShadowsSingleWindow = true
                        if let img = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg) {
                            await MainActor.run { onShot(id, img, w.frame.size) }
                        }
                    }
                }
            }
        }
    }
}

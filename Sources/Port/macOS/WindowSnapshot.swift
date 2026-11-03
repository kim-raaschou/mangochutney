import AppKit
import ScreenCaptureKit
import Mango

/// Window pictures for the overview overlay (ScreenCaptureKit). mango scales the real
/// surfaces as a compositor; macOS cannot, so the overview shows pictures of the
/// windows instead of moving and resizing the apps (which refuse small sizes).
/// Needs the Screen Recording permission.
public enum WindowSnapshot {
    public static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// The largest size with `window`'s proportions inside `target`.
    static func fitted(_ window: CGSize, in target: CGSize) -> CGSize {
        guard window.width > 0, window.height > 0 else { return target }
        let scale = min(target.width / window.width, target.height / window.height)
        return CGSize(width: (window.width * scale).rounded(), height: (window.height * scale).rounded())
    }

    /// Captures each window at about `pixelSize`, in the window's own proportions. Results
    /// arrive one by one on the main thread as they are ready.
    public static func capture(_ ids: [CGWindowID], pixelSize: [CGWindowID: CGSize],
                               onImage: @escaping @MainActor (CGWindowID, CGImage) -> Void) {
        Task.detached(priority: .userInitiated) {
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) else {
                return
            }
            let byID = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { a, _ in a })
            await withTaskGroup(of: Void.self) { group in
                for id in ids {
                    guard let w = byID[id] else { continue }
                    group.addTask {
                        let filter = SCContentFilter(desktopIndependentWindow: w)
                        let cfg = SCStreamConfiguration()
                        // In the window's own proportions: asked for others, the window
                        // lies in the top-left corner of the picture and the rest is empty.
                        let size = fitted(w.frame.size, in: pixelSize[id] ?? CGSize(width: 800, height: 600))
                        cfg.width = max(32, Int(size.width))
                        cfg.height = max(32, Int(size.height))
                        cfg.showsCursor = false
                        cfg.ignoreShadowsSingleWindow = true
                        if let img = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg) {
                            await MainActor.run { onImage(id, img) }
                        }
                    }
                }
            }
        }
    }
}

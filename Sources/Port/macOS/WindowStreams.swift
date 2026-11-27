import AppKit
import CoreMedia
import ScreenCaptureKit
import VideoToolbox
import Mango

/// Live pictures of windows (ScreenCaptureKit streams): a frame comes when the app has drawn the window,
/// with the size the window has in it. A window that does not change sends no frames.
@MainActor
final class WindowStreams {
    private let onFrame: (ClientID, CGImage, CGSize) -> Void
    private var live: [ClientID: Live] = [:]
    /// The windows whose stream could not start: not tried again.
    private var failedIDs: Set<ClientID> = []

    /// `onFrame`: a window's picture and the window's size (points) when it was drawn.
    init(onFrame: @escaping (ClientID, CGImage, CGSize) -> Void) {
        self.onFrame = onFrame
    }

    var ids: Set<ClientID> { Set(live.keys) }

    /// The windows streamed: the missing ones started, the others stopped. `pixelSize` is the largest
    /// picture a stream gives; a larger window is scaled into it.
    func stream(_ ids: Set<ClientID>, pixelSize: CGSize) {
        for (id, l) in live where !ids.contains(id) {
            l.stop()
            live[id] = nil
        }
        let new = ids.subtracting(live.keys).subtracting(failedIDs)
        guard !new.isEmpty, pixelSize.width >= 1, pixelSize.height >= 1 else { return }
        for id in new { live[id] = Live(id: id, onFrame: onFrame) }
        let started = new.compactMap { live[$0] }
        Task.detached(priority: .userInitiated) {
            let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            let byID = Dictionary((content?.windows ?? []).map { ($0.windowID, $0) }, uniquingKeysWith: { a, _ in a })
            for l in started {
                let running = if let w = byID[l.id] { await l.start(w, pixelSize: pixelSize) } else { false }
                if !running { await self.failed(l) }
            }
        }
    }

    /// A stream that could not start is forgotten and not tried again: the window keeps its still picture.
    private func failed(_ l: Live) {
        guard live[l.id] === l else { return }
        live[l.id] = nil
        failedIDs.insert(l.id)
    }

    func stopAll() { stream([], pixelSize: .zero) }
}

/// One window's stream. Its frames are read on the stream's queue and handed to the main actor.
private final class Live: NSObject, SCStreamOutput, @unchecked Sendable {
    let id: ClientID
    private let onFrame: @MainActor (ClientID, CGImage, CGSize) -> Void
    private let queue = DispatchQueue(label: "mango.stream", qos: .userInitiated)
    private let lock = NSLock()
    private var stream: SCStream?
    private var stopped = false

    init(id: ClientID, onFrame: @escaping @MainActor (ClientID, CGImage, CGSize) -> Void) {
        self.id = id
        self.onFrame = onFrame
    }

    /// Whether the stream runs (false: it could not start, or it was stopped meanwhile).
    func start(_ window: SCWindow, pixelSize: CGSize) async -> Bool {
        let cfg = SCStreamConfiguration()
        cfg.width = Int(pixelSize.width)
        cfg.height = Int(pixelSize.height)
        cfg.showsCursor = false
        cfg.ignoreShadowsSingleWindow = true
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 15)
        cfg.queueDepth = 4
        let s = SCStream(filter: SCContentFilter(desktopIndependentWindow: window), configuration: cfg, delegate: nil)
        guard (try? s.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)) != nil else { return false }
        let wasStopped = lock.withLock { () -> Bool in
            if !stopped { stream = s }
            return stopped
        }
        guard !wasStopped else { return true }
        do { try await s.startCapture() } catch { return false }
        // stopped while it started
        if lock.withLock({ stopped }) { try? await s.stopCapture() }
        return true
    }

    func stop() {
        let s = lock.withLock { () -> SCStream? in
            stopped = true
            defer { stream = nil }
            return stream
        }
        s?.stopCapture { _ in }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let info = (CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false)
                  as? [[SCStreamFrameInfo: Any]])?.first,
              (info[.status] as? Int).flatMap(SCFrameStatus.init(rawValue:)) == .complete,
              let pixels = CMSampleBufferGetImageBuffer(buffer),
              let rectInfo = info[.contentRect] as? NSDictionary, let content = CGRect(dictionaryRepresentation: rectInfo),
              let contentScale = info[.contentScale] as? CGFloat, contentScale > 0,
              let scaleFactor = info[.scaleFactor] as? CGFloat, scaleFactor > 0 else { return }
        // the window is drawn in the frame's top left, at contentRect (points of the frame), scaled by contentScale
        var image: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixels, options: nil, imageOut: &image)
        let crop = CGRect(x: content.minX * scaleFactor, y: content.minY * scaleFactor,
                          width: content.width * scaleFactor, height: content.height * scaleFactor).integral
        guard let picture = image?.cropping(to: crop) else { return }
        let size = CGSize(width: (content.width / contentScale).rounded(), height: (content.height / contentScale).rounded())
        let (id, onFrame) = (self.id, self.onFrame)
        DispatchQueue.main.async {
            MainActor.assumeIsolated { onFrame(id, picture, size) }
        }
    }
}

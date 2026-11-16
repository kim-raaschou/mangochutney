import CoreGraphics

package extension MangoServer {
    func handleOutputFrame(_ m: Monitor) {
        var needMoreFrames = false

        // not in mango: no layers and no fade-out clients to draw (macOS draws them)

        for c in clientsAll {
            needMoreFrames = clientDrawFrame(c) || needMoreFrames
        }

        // not in mango: no frame skipping while clients resize; the port commits nothing

        // not in mango: the port draws every client's border at once
        if bordersDirty {
            bordersDirty = false
            updateBorders()
        }

        // If more frames are needed, ensure the next frame is scheduled.
        if needMoreFrames {
            requestFreshAllMonitors()
        }
    }
}

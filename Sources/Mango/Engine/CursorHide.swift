import QuartzCore

package extension MangoServer {
    func pointerCursorActivity() {
        lastPointerActivity = CACurrentMediaTime()
        if cursorHidden {
            cursorHidden = false
            publishInputState()
            if drawsOverlays { system.setCursorHidden(false) }
        }
        armCursorHideTimer()
    }

/// mango pointer_cursor_activity (pointer.c)
    func armCursorHideTimer() {
        guard config.cursorHideTimeout > 0, !cursorHideTimerArmed, !cursorHidden else { return }
        cursorHideTimerArmed = true
        let due = lastPointerActivity + Double(config.cursorHideTimeout)
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.05, due - CACurrentMediaTime())) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.cursorHideTimerArmed = false
                guard self.config.cursorHideTimeout > 0 else { return }
                if CACurrentMediaTime() - self.lastPointerActivity >= Double(self.config.cursorHideTimeout) - 0.01 {
                    self.pointerHideCursor()
                } else {
                    self.armCursorHideTimer()
                }
            }
        }
    }

    func pointerHideCursor() {
        guard !cursorHidden else { return }
        cursorHidden = true
        publishInputState()
        if drawsOverlays { system.setCursorHidden(true) }
    }
}

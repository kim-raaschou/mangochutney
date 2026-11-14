import Foundation

let CONFIG_WATCH_DEBOUNCE_MS: Int32 = 150
private let CONFIG_WATCH_MAX_SYMLINK_DEPTH = 40

package struct WatchedFile {
    var path: String
    var fd: Int32
    var seen: Bool
    var exists: Bool
    var dev: dev_t = 0
    var ino: ino_t = 0
    var size: off_t = 0
    var mtime = timespec()
}

private func refreshFileState(_ file: inout WatchedFile) -> Bool {
    var st = stat()
    let exists = stat(file.path, &st) == 0
    var changed = false

    if file.seen {
        if file.exists != exists {
            changed = true
        } else if exists {
            changed = file.dev != st.st_dev || file.ino != st.st_ino ||
                file.size != st.st_size ||
                file.mtime.tv_sec != st.st_mtimespec.tv_sec ||
                file.mtime.tv_nsec != st.st_mtimespec.tv_nsec
        }
    }

    file.seen = true
    file.exists = exists
    if exists {
        file.dev = st.st_dev
        file.ino = st.st_ino
        file.size = st.st_size
        file.mtime = st.st_mtimespec
    }

    return changed
}

private func pathDirname(_ path: String) -> String {
    guard let slash = path.lastIndex(of: "/") else { return "." }
    if slash == path.startIndex { return "/" }
    return String(path[..<slash])
}

private func pathJoin(_ dir: String, _ name: String) -> String {
    dir.hasSuffix("/") ? dir + name : dir + "/" + name
}

private func readSymlinkTarget(_ path: String) -> String? {
    try? FileManager.default.destinationOfSymbolicLink(atPath: path)
}

func resolveWatchPath(_ path: String) -> String? {
    var current = path

    var depth = 0
    while true {
        var st = stat()
        if lstat(current, &st) != 0 || (st.st_mode & S_IFMT) != S_IFLNK {
            return current
        }

        if depth >= CONFIG_WATCH_MAX_SYMLINK_DEPTH {
            mangoError(false, .error, "config auto reload: too many symlinks in \u{1B}[1m\u{1B}[31m\(path)\u{1B}[0m\n")
            return nil
        }

        guard let target = readSymlinkTarget(current) else {
            mangoError(false, .error, "config auto reload: failed to read symlink \u{1B}[1m\u{1B}[31m\(current)\u{1B}[0m: \(String(cString: strerror(errno)))\n")
            return nil
        }

        current = target.hasPrefix("/") ? target : pathJoin(pathDirname(current), target)
        depth += 1
    }
}

package extension MangoServer {
    private func scheduleCheck() {
        if watcherActive, let watchTimer { watchTimer.timerUpdate(CONFIG_WATCH_DEBOUNCE_MS) }
    }

    private func clearWatchedFiles() {
        for file in watchedFiles where file.fd >= 0 { close(file.fd) }
        watchedFiles = []
    }

    private func fileIsTracked(_ path: String) -> Bool {
        watchedFiles.contains { $0.path == path }
    }

    private func trackPath(_ path: String) {
        if fileIsTracked(path) { return }

        guard let resolved = resolveWatchPath(path) else { return }
        var file = WatchedFile(path: resolved, fd: -1, seen: false, exists: false)
        _ = refreshFileState(&file)
        watchedFiles.append(file)
    }

    private func addFileWatch(_ i: Int) {
        watchedFiles[i].fd = open(watchedFiles[i].path, O_RDONLY | O_CLOEXEC)
        if watchedFiles[i].fd < 0 { return }

        var change = kevent(ident: UInt(watchedFiles[i].fd), filter: Int16(EVFILT_VNODE), flags: UInt16(EV_ADD | EV_CLEAR),
                            fflags: UInt32(NOTE_DELETE | NOTE_WRITE | NOTE_EXTEND | NOTE_ATTRIB | NOTE_RENAME | NOTE_REVOKE),
                            data: 0, udata: nil)
        if kevent(kqueueFd, &change, 1, nil, 0, nil) < 0 {
            close(watchedFiles[i].fd)
            watchedFiles[i].fd = -1
        }
    }

    private func onKqueueEvent(_ fd: Int32) {
        var events = Array(repeating: Darwin.kevent(ident: 0, filter: 0, flags: 0, fflags: 0, data: 0, udata: nil), count: 8)
        var timeout = timespec(tv_sec: 0, tv_nsec: 0)
        var pending = false

        while true {
            let count = kevent(fd, nil, 0, &events, 8, &timeout)
            if count < 0 {
                if errno == EINTR { continue }
                break
            }
            if count == 0 { break }
            pending = true
        }

        if pending { scheduleCheck() }
    }

    private func backendInit(_ loop: EventLoop) -> Bool {
        kqueueFd = kqueue()
        if kqueueFd < 0 { return false }

        let fd = kqueueFd
        kqueueSource = loop.addFd(fd) { [weak self] in self?.onKqueueEvent(fd) }

        return true
    }

    private func backendDestroy() {
        if let kqueueSource {
            kqueueSource.remove()
            self.kqueueSource = nil
        }
        if kqueueFd >= 0 {
            close(kqueueFd)
            kqueueFd = -1
        }
    }

    private func backendSync() {
        if kqueueFd < 0 { return }

        for i in watchedFiles.indices { addFileWatch(i) }
    }

    private func onWatchTimer() {
        var changed = false
        var changedPaths: [String] = []   // not in mango: which files, for the port's own writes
        for i in watchedFiles.indices {
            if refreshFileState(&watchedFiles[i]) {
                changed = true
                changedPaths.append(watchedFiles[i].path)
            }
        }

        if changed && portHooks.configWriteIsOwn?(changedPaths) != true { reloadConfig() }   // Port extension: chutney_menu_config
    }

    func configWatcherInit(_ loop: EventLoop) {
        if watchTimer != nil { return }

        watchTimer = loop.addTimer { [weak self] in self?.onWatchTimer() }

        if !backendInit(loop) {
            mangoError(false, .error, "config auto reload disabled: no filesystem event backend available\n")
            return
        }

        watcherActive = true
        configWatcherUpdate()
    }

    func configWatcherUpdate() {
        clearWatchedFiles()

        if !watcherActive || !config.autoReloadConfig { return }

        for path in configGetFilePaths() { trackPath(path) }

        backendSync()
    }

    func configWatcherDestroy() {
        backendDestroy()

        if let watchTimer {
            watchTimer.remove()
            self.watchTimer = nil
        }

        watcherActive = false
        clearWatchedFiles()
    }
}

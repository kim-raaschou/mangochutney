import Foundation
import Mango

public final class ConfigWatcher {
    private var sources: [DispatchSourceFileSystemObject] = []
    private var pending: DispatchWorkItem?
    private let onChange: ([URL]) -> Void
    private let files: [URL]
    struct FileState: Equatable {
        var dev: dev_t, ino: ino_t, size: off_t, mtime: timespec
        static func == (a: Self, b: Self) -> Bool {
            a.dev == b.dev && a.ino == b.ino && a.size == b.size
                && a.mtime.tv_sec == b.mtime.tv_sec && a.mtime.tv_nsec == b.mtime.tv_nsec
        }
    }
    private var states: [URL: FileState?] = [:]

    static func state(_ url: URL) -> FileState? {
        var st = stat()
        guard stat(url.path, &st) == 0 else { return nil }
        return FileState(dev: st.st_dev, ino: st.st_ino, size: st.st_size, mtime: st.st_mtimespec)
    }

    public init(files: [URL], onChange: @escaping ([URL]) -> Void) {
        self.onChange = onChange
        self.files = files
        for url in files {
            states[url] = Self.state(url)
            let fd = open(url.path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd,
                                                                eventMask: [.write, .delete, .rename, .extend],
                                                                queue: .main)
            src.setEventHandler { [weak self] in self?.schedule() }
            src.setCancelHandler { close(fd) }
            src.resume()
            sources.append(src)
        }
    }

    private func schedule() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            var changed: [URL] = []
            for url in self.files {
                let now = Self.state(url)
                if now != self.states[url] { changed.append(url); self.states[url] = now }
            }
            if !changed.isEmpty { self.onChange(changed) }
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
    }

    deinit {
        for s in sources { s.cancel() }
    }
}

import Foundation
import Mango

/// Watches the config file (and sourced files) for writes; debounced 200ms.
public final class ConfigWatcher {
    private var sources: [DispatchSourceFileSystemObject] = []
    private var pending: DispatchWorkItem?
    private let onChange: ([URL]) -> Void
    private let files: [URL]
    /// Each file's contents when watching began (or last changed): what changed is told.
    private var contents: [URL: Data] = [:]

    public init(files: [URL], onChange: @escaping ([URL]) -> Void) {
        self.onChange = onChange
        self.files = files
        for url in files {
            contents[url] = try? Data(contentsOf: url)
            let fd = open(url.path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd,
                                                                eventMask: [.write, .delete, .rename, .extend],
                                                                queue: .main)
            src.setEventHandler { [weak self] in self?.schedule() }
            // The descriptor must stay open until the source is really cancelled
            // (cancel() is asynchronous), so it is closed in the cancel handler.
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
                let now = try? Data(contentsOf: url)
                if now != self.contents[url] { changed.append(url); self.contents[url] = now }
            }
            if !changed.isEmpty { self.onChange(changed) }
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: item)
    }

    deinit {
        for s in sources { s.cancel() }
    }
}

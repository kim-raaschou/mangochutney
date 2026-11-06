import Foundation

private let configWatchMaxSymlinkDepth = 40

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

/// mango resolve_watch_path (watcher.c): the file a config path names, through its symlinks.
func resolveWatchPath(_ path: String) -> String? {
    var current = path

    var depth = 0
    while true {
        var st = stat()
        if lstat(current, &st) != 0 || (st.st_mode & S_IFMT) != S_IFLNK {
            return current
        }

        if depth >= configWatchMaxSymlinkDepth {
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

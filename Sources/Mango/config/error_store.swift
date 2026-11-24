import Foundation

private var storePath = ""
private var storeFile: UnsafeMutablePointer<FILE>?
private var storeActive = false

private func storeDirOk(_ path: String) -> Bool {
    var st = stat()
    if lstat(path, &st) != 0 { return false }
    if (st.st_mode & S_IFMT) != S_IFDIR { return false }
    if st.st_uid != getuid() { return false }
    if (st.st_mode & 0o077) != 0 { chmod(path, 0o700) }
    return true
}

private func storeDirPrepare(_ path: String) -> Bool {
    if storeDirOk(path) { return true }
    if mkdir(path, 0o700) == 0 { return true }
    return storeDirOk(path)
}

public func configErrorStorePath() -> String {
    if storePath.isEmpty {
        var dir = ""

        if let runtime = ProcessInfo.processInfo.environment["XDG_RUNTIME_DIR"], runtime.hasPrefix("/") {
            dir = "\(runtime)/mango"
            if !storeDirPrepare(dir) { dir = "" }
        }
        if dir.isEmpty {
            dir = "/tmp/mango-\(getuid())"
            if !storeDirPrepare(dir) { dir = "" }
        }
        if dir.isEmpty { return storePath }
        storePath = "\(dir)/config-errors.log"
    }
    return storePath
}

public func configErrorStoreBegin() {
    configErrorStoreEnd()

    let path = configErrorStorePath()
    if path.isEmpty { return }

    let fd = open(path, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW | O_CLOEXEC, 0o600)
    if fd < 0 { return }
    storeFile = fdopen(fd, "w")
    if storeFile == nil {
        close(fd)
        return
    }
    storeActive = true
}

public func configErrorStoreEnd() {
    if let f = storeFile {
        fclose(f)
        storeFile = nil
    }
    storeActive = false
}

public func configErrorStoreActive() -> Bool { storeActive }

public func configErrorStoreRecord(_ message: String) {
    guard storeActive, let storeFile else { return }

    var clean = Substring.UnicodeScalarView(message.unicodeScalars)
    while let last = clean.last, last == "\n" || last == "\r" || last == " " || last == "\t" {
        clean.removeLast()
    }

    if !clean.isEmpty {
        let text = String(clean)
        fputs(text, storeFile)
        if clean.contains("\u{1B}") && !(clean.count >= 4 && clean.suffix(4).elementsEqual("\u{1B}[0m".unicodeScalars)) {
            fputs("\u{1B}[0m", storeFile)
        }
        fputc(0x0A, storeFile)
        fflush(storeFile)
    }
}

import Foundation
import Carbon.HIToolbox
import Mango

public enum KeyNames {
    public static var systemKeyBase: UInt16 { KeySyms.systemKeyBase }

    public static func keyCodes(forName name: String) -> [UInt16] { KeySyms.parseKey(forName: name, layout: layoutTable) }

    public static func name(forKeyCode code: UInt16) -> String {
        if let n = KeySyms.namedKeyReverse[code] { return n }
        if let ch = layoutTable.reverse[code] { return String(ch) }
        if let ch = KeySyms.ansiUSReverse[code] { return String(ch) }
        return "code:\(code)"
    }

    static func install() { KeySyms.layout = { layoutTable } }

    public static func currentLayoutName() -> String {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else {
            return "US"
        }
        if let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
            let id = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
            if let last = id.split(separator: ".").last, !last.isEmpty { return String(last) }
            return id
        }
        if let ptr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) {
            return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
        }
        return "US"
    }

    public static func invalidateLayoutCache() {
        tableLock.lock(); cachedTable = nil; tableLock.unlock()
    }

    typealias LayoutTable = KeySyms.LayoutTable

    private static let tableLock = NSLock()
    private static var cachedTable: LayoutTable?

    static var layoutTable: LayoutTable {
        tableLock.lock(); defer { tableLock.unlock() }
        if let t = cachedTable { return t }
        let t = buildLayoutTable()
        cachedTable = t
        return t
    }

    private static let keypadCodes: Set<UInt16> = [65, 67, 69, 71, 75, 76, 78, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 95]

    private static func buildLayoutTable() -> LayoutTable {
        var table = LayoutTable()
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let dataPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return fallbackTable()
        }
        let data = Unmanaged<CFData>.fromOpaque(dataPtr).takeUnretainedValue() as Data
        let kbdType = UInt32(LMGetKbdType())
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            let layout = base.assumingMemoryBound(to: UCKeyboardLayout.self)
            for modifiers: UInt32 in [0, UInt32((shiftKey >> 8) & 0xFF)] {
                for code: UInt16 in 0..<128 where !keypadCodes.contains(code) {
                    var deadKeyState: UInt32 = 0
                    var chars = [UniChar](repeating: 0, count: 4)
                    var length = 0
                    let err = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDisplay), modifiers,
                                             kbdType, OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                             &deadKeyState, chars.count, &length, &chars)
                    guard err == noErr, length > 0 else { continue }
                    let s = String(utf16CodeUnits: chars, count: length)
                    guard let ch = s.first, s.count == 1, !ch.isWhitespace, ch.asciiValue != 0,
                          !(ch.asciiValue.map { $0 < 32 || $0 == 127 } ?? false) else { continue }
                    if table.chars[ch] == nil { table.chars[ch] = code }
                    if modifiers == 0, table.reverse[code] == nil { table.reverse[code] = ch }
                }
            }
        }
        if table.chars.isEmpty { return fallbackTable() }
        return table
    }

    private static func fallbackTable() -> LayoutTable {
        LayoutTable(chars: KeySyms.ansiUSFallback, reverse: KeySyms.ansiUSReverse)
    }

}

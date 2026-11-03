/// The boundary, not in mango: what mango's config reader asks the system it runs on. The
/// port's own keys and dispatchers, its notes for `mango -p` on mango's keys, window-rule
/// fields and dispatchers it cannot honour, and what HYPER is (mango's Mod3; a Mac has none).
/// The port sets `ConfigParser.port` before a config is read; without it the reader is
/// mango's alone.
package protocol ConfigPort: Sendable {
    /// The setter of a key of the port's own; nil: not the port's.
    func setter(_ key: String) -> ConfigOptions.Setter?
    var keys: Set<String> { get }
    /// A key of mango's the port reads and ignores (blur, libinput, …).
    func isIgnored(_ key: String) -> Bool
    /// A note on a key, read (`applied`) or ignored; nil: none.
    func optionNote(_ key: String, applied: Bool) -> (ConfigNote.Kind, String)?
    /// A note on a window-rule field; nil: none.
    func windowRuleNote(_ field: String) -> (ConfigNote.Kind, String)?
    /// A window-rule field the port reads and ignores.
    func knowsWindowRuleField(_ field: String) -> Bool
    /// A note on a dispatcher the port lacks or has of its own; nil: none.
    func dispatcherNote(_ name: String) -> (ConfigNote.Kind, String)?
    /// A dispatcher of the port's own.
    func knowsDispatcher(_ name: String) -> Bool
    /// The key codes of a key name in the keyboard layout (xkb's keysym to keycode); empty:
    /// no such key.
    func keyCodes(_ name: String) -> [UInt16]
    /// A modifier name of the port's own (cmd, option, fn); nil: none.
    func modifier(_ name: String) -> Modifiers?
    /// The modifiers HYPER stands for, in mango's names.
    func hyperModifier(_ config: Config) -> String
}

/// Something worth knowing about a line that is not an error: a mango name that has no
/// effect on macOS, or a name of the port that mango does not have. `mango -p` lists them.
public struct ConfigNote: CustomStringConvertible, Equatable {
    public enum Kind: Equatable {
        /// A mango option, keyword or rule field that is accepted and cannot work on macOS.
        case noEffect
        /// A mango name that is accepted and does nothing yet: macOS would allow it.
        case notYet
        /// A mango dispatcher in a binding that does nothing here.
        case unsupportedDispatcher
        /// A name of the port that mango does not have.
        case portExtension
    }
    public var file: String
    public var line: Int
    public var kind: Kind
    /// The option, rule field or dispatcher.
    public var name: String
    /// Why, or empty when the kind says it all (not implemented yet).
    public var reason: String

    public init(file: String, line: Int, kind: Kind, name: String, reason: String) {
        self.file = file; self.line = line; self.kind = kind; self.name = name; self.reason = reason
    }

    public var description: String {
        let at = line > 0 ? "\(file):\(line)" : file
        return "\(at): \(name): \(reason)"
    }
}

extension ConfigParser {
    /// The port's answers (ConfigPort); nil: mango's reader alone. Set once at start.
    package nonisolated(unsafe) static var port: (any ConfigPort)?
}

extension Config {
    /// What HYPER stands for (the port's; none without it).
    package var hyperModifier: String { ConfigParser.port?.hyperModifier(self) ?? "" }
}

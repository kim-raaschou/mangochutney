package protocol ConfigPort: Sendable {
    func setter(_ key: String) -> ConfigOptions.Setter?
    var keys: Set<String> { get }
    func isIgnored(_ key: String) -> Bool
    func optionNote(_ key: String, applied: Bool) -> (ConfigNote.Kind, String)?
    func windowRuleNote(_ field: String) -> (ConfigNote.Kind, String)?
    func knowsWindowRuleField(_ field: String) -> Bool
    func dispatcherNote(_ name: String) -> (ConfigNote.Kind, String)?
    func knowsDispatcher(_ name: String) -> Bool
    func keyCodes(_ name: String) -> [UInt16]
    func modifier(_ name: String) -> Modifiers?
    func hyperModifier(_ config: Config) -> String
}

public struct ConfigNote: CustomStringConvertible, Equatable {
    public enum Kind: Equatable {
        case noEffect
        case notYet
        case unsupportedDispatcher
        case portExtension
    }
    public var file: String
    public var line: Int
    public var kind: Kind
    public var name: String
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
    package nonisolated(unsafe) static var port: (any ConfigPort)?
}

extension Config {
    package var hyperModifier: String { ConfigParser.port?.hyperModifier(self) ?? "" }
}

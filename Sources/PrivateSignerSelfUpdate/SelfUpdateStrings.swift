import Foundation

enum SelfUpdateStrings {
    static func string(_ key: String, _ arguments: CVarArg...) -> String {
        let format = NSLocalizedString(key, bundle: .module, comment: "")
        guard !arguments.isEmpty else { return format }
        return String(format: format, arguments: arguments)
    }
}

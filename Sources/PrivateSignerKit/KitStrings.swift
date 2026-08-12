import Foundation


enum KitStrings {
    /// Resolved once: the user's language does not change while the process runs, and doing this
    /// per string would mean a directory lookup on every error message.
    private static let bundle = PackageLocalization.bundle(for: .module)

    static func string(_ key: String, _ arguments: CVarArg...) -> String {
        let format = NSLocalizedString(key, bundle: bundle, comment: "")
        guard !arguments.isEmpty else { return format }
        return String(format: format, arguments: arguments)
    }
}

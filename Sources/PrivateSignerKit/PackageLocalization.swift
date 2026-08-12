import Foundation

/// Resolves this package's strings against the user's language rather than the host app's.
///
/// `NSLocalizedString(_:bundle:comment:)` resolves through the *app's* effective localization. An
/// app whose Chinese is hardcoded in Swift — no `.lproj`, `CFBundleDevelopmentRegion` left at
/// `en` — is an English app as far as iOS is concerned, so a package that localizes properly ends
/// up showing English inside a Chinese interface. The host is misconfigured, but the person
/// reading the screen is not the one who can fix that.
///
/// So the match is made here, between what the user asked for and what this package actually
/// ships, and the host's declaration never enters into it.
public enum PackageLocalization {
    /// The `.lproj` inside `module` that best matches `preferences`.
    ///
    /// Falls back to the module bundle itself, which resolves to the package's
    /// `defaultLocalization` — never to nothing.
    public static func bundle(
        for module: Bundle,
        preferring preferences: [String] = Locale.preferredLanguages
    ) -> Bundle {
        let available = module.localizations
        guard !available.isEmpty else { return module }

        // Foundation's own matching, so `zh-Hans` answers `zh-Hans-CN`, `zh_CN`, and plain `zh`
        // the same way the system would.
        let matched = Bundle.preferredLocalizations(from: available, forPreferences: preferences)
        guard let best = matched.first,
              let path = module.path(forResource: best, ofType: "lproj"),
              let localized = Bundle(path: path) else {
            return module
        }
        return localized
    }
}

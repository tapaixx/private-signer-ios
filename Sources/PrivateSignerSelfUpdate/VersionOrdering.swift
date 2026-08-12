import Foundation

/// Compares two version strings in whatever scheme the host project uses.
public protocol VersionOrdering {
    /// Returns `nil` when either side cannot be parsed, so callers can skip unparseable releases
    /// rather than guess at their order.
    func compare(_ lhs: String, _ rhs: String) -> ComparisonResult?
}

/// `[v]MAJOR.MINOR.PATCH-BUILD`, e.g. `v1.0.5-0006`.
///
/// The build component is compared numerically but rendered with its original digit count, so a
/// parsed tag round-trips to the exact string the release was published under.
public struct BuildTaggedVersion: Comparable, Equatable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let build: Int
    public let buildDigits: Int

    public init?(_ rawValue: String) {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("v") { value.removeFirst() }
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2,
              (1...8).contains(parts[1].count),
              parts[1].allSatisfy({ $0.isNumber }),
              let build = Int(parts[1]) else { return nil }
        let base = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard base.count == 3,
              let major = Int(base[0]), major >= 0,
              let minor = Int(base[1]), minor >= 0,
              let patch = Int(base[2]), patch >= 0 else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
        self.build = build
        self.buildDigits = parts[1].count
    }

    public var description: String {
        let padded = String(build)
        let padding = String(repeating: "0", count: max(0, buildDigits - padded.count))
        return "\(major).\(minor).\(patch)-\(padding)\(padded)"
    }

    public var tagName: String { "v\(description)" }

    public static func < (lhs: BuildTaggedVersion, rhs: BuildTaggedVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch, lhs.build) < (rhs.major, rhs.minor, rhs.patch, rhs.build)
    }
}

/// Default ordering. Use it when releases are tagged `vX.Y.Z-NNNN`.
public struct BuildTaggedVersionOrdering: VersionOrdering {
    public init() {}

    public func compare(_ lhs: String, _ rhs: String) -> ComparisonResult? {
        guard let left = BuildTaggedVersion(lhs), let right = BuildTaggedVersion(rhs) else { return nil }
        if left == right { return .orderedSame }
        return left < right ? .orderedAscending : .orderedDescending
    }
}

/// Plain dot-separated numeric versions, e.g. `1.4` or `2.0.11`. Use it for projects tagged with
/// ordinary semantic versions and no build component.
public struct DottedVersionOrdering: VersionOrdering {
    public init() {}

    public func compare(_ lhs: String, _ rhs: String) -> ComparisonResult? {
        guard let left = Self.components(lhs), let right = Self.components(rhs) else { return nil }
        let width = max(left.count, right.count)
        for index in 0..<width {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r { return l < r ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    private static func components(_ rawValue: String) -> [Int]? {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("v") { value.removeFirst() }
        guard !value.isEmpty else { return nil }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        var result: [Int] = []
        for part in parts {
            guard let number = Int(part), number >= 0 else { return nil }
            result.append(number)
        }
        return result.isEmpty ? nil : result
    }
}

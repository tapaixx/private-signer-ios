import Foundation

/// The unauthenticated `GET /health` response.
public struct ServiceHealth: Decodable, Equatable {
    /// The single contract identifier this package speaks.
    public static let supportedContracts: Set<String> = ["v2"]

    public let ok: Bool
    public let contract: String?
    public let version: String?

    public init(ok: Bool, contract: String?, version: String? = nil) {
        self.ok = ok
        self.contract = contract
        self.version = version
    }
}

/// The outcome of checking a hand-entered Worker URL and token together.
public enum ConfigurationVerification: Equatable {
    case usable
    case usableWithUndeclaredContract
    case notASigner
    case unsupportedContract(String)
    case invalidToken
    case unreachable(String)

    public var isUsable: Bool {
        self == .usable || self == .usableWithUndeclaredContract
    }

    public var code: String {
        switch self {
        case .usable: return "usable"
        case .usableWithUndeclaredContract: return "usable_undeclared_contract"
        case .notASigner: return "not_a_signer"
        case .unsupportedContract: return "unsupported_contract"
        case .invalidToken: return "invalid_token"
        case .unreachable: return "unreachable"
        }
    }

    public var message: String {
        switch self {
        case .usable:
            return KitStrings.string("verify.usable")
        case .usableWithUndeclaredContract:
            return KitStrings.string("verify.usable_undeclared_contract")
        case .notASigner:
            return KitStrings.string("verify.not_a_signer")
        case .unsupportedContract(let contract):
            return KitStrings.string("verify.unsupported_contract", contract)
        case .invalidToken:
            return KitStrings.string("verify.invalid_token")
        case .unreachable(let detail):
            return KitStrings.string("verify.unreachable", detail)
        }
    }
}

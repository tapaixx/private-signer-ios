import Foundation

public enum OTAInstallation {
    /// Wraps an HTTPS manifest URL in the `itms-services://` URL iOS needs to start an OTA
    /// install. Returns `nil` for a non-HTTPS manifest, which iOS would refuse anyway.
    public static func installationURL(manifestURL: URL) -> URL? {
        guard manifestURL.scheme?.lowercased() == "https" else { return nil }
        var components = URLComponents()
        components.scheme = "itms-services"
        components.host = ""
        components.queryItems = [
            URLQueryItem(name: "action", value: "download-manifest"),
            URLQueryItem(name: "url", value: manifestURL.absoluteString),
        ]
        return components.url
    }
}

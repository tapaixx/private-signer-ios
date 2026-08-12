# Private Signer for iOS

**English** · [简体中文](README.zh-CN.md)

A Swift package for iOS/iPadOS clients of [Private IPA Signer](https://github.com/nnnmdzz/private-signer).
The v3 contract makes the Worker authoritative for projects, source versions, and signing profiles.

## Contract

A project-aware app compiles only a stable `projectID`. It does **not** discover GitHub Releases,
carry an IPA URL, or hard-code a provisioning profile ID. The Worker returns the latest
`ProjectVersion` and the profiles the authenticated principal may use, and the SDK asks the Worker
to sign that immutable version.

Generic URL/file signing remains available as a separate capability for principals that explicitly
have `generic-url-sign` or `upload-sign` scope.

## Products

| Product | What it gives you |
| --- | --- |
| `PrivateSignerKit` | v3 configuration, project/version/profile discovery, project and generic signing jobs, delivery links, OTA URLs. |
| `PrivateSignerSelfUpdate` | Worker-driven `SelfUpdateCoordinator`, renewal of the installed ProjectVersion, signature inspection. |
| `PrivateSignerUI` | SwiftUI configuration, project self-update, profile Picker, and optional generic signing screens. |

## Install

```swift
.package(url: "https://github.com/nnnmdzz/private-signer-ios.git", exact: "0.3.0")
```

Pin an exact version. `0.3.0` is a breaking bug-fix release and requires a v3 Worker.

## Minimal project self-update

```swift
import PrivateSignerKit
import PrivateSignerSelfUpdate

let store = SignerConfigurationStore(
    keychain: SignerKeychainConfiguration(
        service: "com.example.app.private-signer",
        configurationAccessGroup: "TEAMID.com.example.app"
    )
)

let coordinator = SelfUpdateCoordinator(
    store: store,
    projectID: "my-app",
    currentVersion: currentVersion,
    userAgent: "MyApp/\(currentVersion)"
)

if let candidate = try await coordinator.checkForUpdate() {
    let profiles = try await coordinator.availableProfiles()
    let profileID = profiles.first(where: \.isDefault)?.id ?? profiles.first?.id
    var result = try await coordinator.requestSignedBuild(of: candidate, profileID: profileID)
    while result.job.isActive {
        try await Task.sleep(nanoseconds: 5_000_000_000)
        result = try await coordinator.refresh(jobID: result.job.jobID)
    }
    if let installURL = result.installationURL {
        await UIApplication.shared.open(installURL)
    }
}
```

The unsigned IPA URL never enters this flow.

## Documentation

- [Client integration guide](docs/client-integration-guide.md) · [中文](docs/client-integration-guide.zh-CN.md)
- [API reference](docs/api-reference.md) · [中文](docs/api-reference.zh-CN.md)
- [v3 contract notes](docs/v3-contract.md) · [中文](docs/v3-contract.zh-CN.md)

## Removed v2 assumptions

`/v2`, `GitHubReleaseSource`, `ReleaseSource`, `SignerUIContext.defaultProfileID`, and the magic
`personal-main` profile identifier are not part of this release.

CI compiles the package and runs its unit tests. Real-device install/upgrade remains the final
acceptance gate.

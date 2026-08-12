# Private Signer for iOS

**English** · [简体中文](README.zh-CN.md)

A Swift package for iOS/iPadOS clients of [Private IPA Signer](https://github.com/nnnmdzz/private-signer). The package maintains **one service contract: v2**.

## Contract

A project-aware app compiles only a stable `projectID`. It does not discover GitHub Releases, carry an unsigned IPA URL, or hard-code a provisioning Profile ID. The Worker owns the project/version catalog and allowed/default Profile policy; the SDK asks it to sign a selected `ProjectVersion`.

All project discovery, Profile discovery, project signing, generic URL/upload signing, job history and delivery-link operations use `/v2/*` and the same `SIGNING_REQUEST_TOKEN` stored in the app configuration.

There is no second client-token system. `personal-main` has no special meaning; Profile IDs come from Worker discovery.

## Products

| Product | What it gives you |
| --- | --- |
| `PrivateSignerKit` | v2 configuration, project/version/Profile discovery, project and generic signing jobs, delivery links, OTA URLs. |
| `PrivateSignerSelfUpdate` | Worker-driven `SelfUpdateCoordinator`, renewal of the installed ProjectVersion, signature inspection. |
| `PrivateSignerUI` | SwiftUI configuration, project self-update, Profile Picker, and optional generic signing screens. |

## Install

Pin an immutable release/tag or commit approved by your app. During development, a fixed revision is preferred over a floating range.

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

The unsigned IPA URL never enters the self-update flow.

## Documentation

- [Client integration guide](docs/client-integration-guide.md) · [中文](docs/client-integration-guide.zh-CN.md)
- [API reference](docs/api-reference.md) · [中文](docs/api-reference.zh-CN.md)
- [v2 contract notes](docs/v2-contract.md) · [中文](docs/v2-contract.zh-CN.md)

CI compiles the package and runs its unit tests. Real-device install/upgrade remains the final acceptance gate.

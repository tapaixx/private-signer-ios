# Private Signer for iOS

A Swift package that lets an iOS/iPadOS app request private IPA signing from a
[Private IPA Signer](https://github.com/nnnmdzz/private-signer) deployment, and install the signed
result over the air — including updating itself.

中文文档：[README.zh-CN.md](README.zh-CN.md)

## What this is for

The signing service is application-agnostic: it takes a resignable IPA and gives back a
device-gated signed one. This package is the client half of that contract, so a project does not
have to reimplement the upload protocol, the job state machine, the Keychain rules that let a
configuration survive re-signing, or the identity checks that keep a "self-update" from quietly
installing a second copy of the app.

**Nothing in this package is a secret.** The Worker URL and Signing Request Token are entered by
the person operating the app and stored in the device Keychain. That is why this repository can be
public while the signing service stays private.

## Products

| Product | Depends on | What it gives you |
| --- | --- | --- |
| `PrivateSignerKit` | — | The contract: configuration storage, the `/v2` client, delivery links, OTA install URLs, the error model. |
| `PrivateSignerSelfUpdate` | Kit | `ReleaseSource`, `GitHubReleaseSource`, version ordering, and `SelfUpdateCoordinator`. |
| `PrivateSignerUI` | Kit + SelfUpdate | Ready-made SwiftUI screens (zh-Hans + en). A convenience — build your own on Kit if you need different wording. |

## Install

```swift
.package(url: "https://github.com/nnnmdzz/private-signer-ios.git", exact: "0.1.1")
```

Pin an exact version. A self-update path that breaks cannot be fixed by self-updating.

## Integrate

Read **[docs/client-integration-guide.md](docs/client-integration-guide.md)** — it is written for an
AI agent to follow step by step, and ends with acceptance assertions you can actually run.
[中文版](docs/client-integration-guide.zh-CN.md).

## Minimal self-update

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
    releaseSource: GitHubReleaseSource(
        repository: "owner/name",
        assetNameTemplate: "MyApp-{tag}-unsigned.ipa",
        userAgent: "MyApp/\(currentVersion)"
    ),
    currentVersion: currentVersion,
    userAgent: "MyApp/\(currentVersion)"
)

if let candidate = try await coordinator.checkForUpdate() {
    var result = try await coordinator.requestSignedBuild(of: candidate)   // .installedApp
    while result.job.isActive {
        try await Task.sleep(nanoseconds: 5_000_000_000)
        result = try await coordinator.refresh(jobID: result.job.jobID)
    }
    if let installURL = result.installationURL {
        await UIApplication.shared.open(installURL)
    }
}
```

## Domain model

Terms used throughout this package are defined in [CONTEXT.md](CONTEXT.md). They match the signing
service's own glossary word for word.

## Verification status

CI compiles the package and runs its unit tests on every push. **CI cannot prove that a signed IPA
installs on a real device.** Real-device install, upgrade, and side-by-side clone testing is the
final acceptance gate and has to be done by a human with a phone.

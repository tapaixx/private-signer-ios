# PrivateSigner iOS v3 integration guide

v3 is a breaking bug-fix contract. A project-aware app knows its stable `projectID`; the Worker owns the project version catalog, source IPA identity, and signing-profile policy.

## 1. Add the package

```swift
.package(url: "https://github.com/nnnmdzz/private-signer-ios.git", exact: "0.3.0")
```

Use `PrivateSignerKit` and `PrivateSignerSelfUpdate`; add `PrivateSignerUI` only when the stock SwiftUI screens are useful.

## 2. Persist Worker configuration

```swift
let keychain = SignerKeychainConfiguration(
    service: "com.example.app.private-signer",
    configurationAccessGroup: "TEAMID.com.example.app"
)
let store = SignerConfigurationStore(keychain: keychain)
```

Store a v3 Worker URL and scoped client token with `SignerConfigurationStore`. A self-update app token normally needs:

- `catalog:read`
- `sign:create`
- `jobs:control`
- access to the app's project
- access to the project's allowed signing profiles

Do not give a project self-update token `generic-url-sign` or `upload-sign` unless the app is intentionally a general-purpose signer.

## 3. Compile only the stable project identity

```swift
let coordinator = SelfUpdateCoordinator(
    store: store,
    projectID: "my-app",
    currentVersion: currentVersion,
    userAgent: "MyApp/\(currentVersion)",
    installedBundleIdentifier: Bundle.main.bundleIdentifier ?? ""
)
```

Do not compile a profile ID, GitHub repository, asset URL, latest version, or source digest into the app. Those values are Worker state.

## 4. Check for an update

```swift
let update = try await coordinator.updateStatus()
let candidate = update.updateAvailable ? update.targetVersion : nil
let profiles = update.profiles.filter(\.signable)
let selectedProfile = profiles.first(where: \.isDefault)?.id ?? profiles.first?.id
```

The Worker decides whether an update is available. The SDK does not compare GitHub releases itself.

## 5. Request a project signing job

```swift
if let candidate, let selectedProfile {
    var result = try await coordinator.requestSignedBuild(
        of: candidate,
        target: .installedApp,
        profileID: selectedProfile
    )
    while result.job.isActive {
        try await Task.sleep(nanoseconds: 5_000_000_000)
        result = try await coordinator.refresh(jobID: result.job.jobID)
    }
}
```

Project signing submits `project_id`, `version_id`, profile selection, and signing behavior only. `source_url`, source digest, expected source version, and expected source build are deliberately absent from `ProjectSigningOptions`.

## 6. Renew the installed version

```swift
if coordinator.needsRenewal(within: 3) {
    let result = try await coordinator.requestRenewal(profileID: selectedProfile)
}
```

Renewal asks the Worker to sign the exact ProjectVersion represented by `currentVersion`. If that version is unknown or no longer signable, the request fails rather than guessing a source IPA.

## 7. SwiftUI integration

```swift
let context = SignerUIContext(
    keychain: keychain,
    userAgent: "MyApp/\(currentVersion)"
)

SelfUpdateView(
    context: context,
    projectID: "my-app",
    currentVersion: currentVersion
)
```

The view obtains the Worker profile list and renders a Picker. There is no `defaultProfileID` host parameter.

## 8. Generic signing is separate

For a principal that explicitly has generic scopes:

```swift
let profiles = try await client.profiles()
let options = SigningOptions(profileID: profiles.first!.id)
let job = try await client.createURLJob(sourceURL: ipaURL, options: options)
```

Generic signing should still use a profile ID returned by the Worker; do not invent or hard-code one.

## 9. Removed v2 integration points

The following are intentionally gone:

- `/v2` client contract
- `ReleaseSource`
- `GitHubReleaseSource`
- `SignerUIContext.defaultProfileID`
- any special meaning for `personal-main`

## Acceptance checks

An integration is correct when:

1. `verifyConfiguration()` reports a v3 Worker as usable.
2. The app contains a stable project ID but no profile ID or unsigned IPA URL for self-update.
3. `projectUpdate` returns a Worker-managed target ProjectVersion and signable profiles.
4. Project signing succeeds using that `versionID` and profile.
5. A project-scoped token receives `403` for generic URL/upload signing.
6. Updating profile configuration on the Worker does not require rebuilding the app.
7. Real-device OTA install replaces the installed app when `.installedApp` is used.

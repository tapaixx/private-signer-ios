# PrivateSigner iOS v2 integration guide

A project-aware app knows its stable `projectID`; the Worker owns the project version catalog, source IPA identity, and signing Profile policy. All client operations use the single v2 contract and the existing `SIGNING_REQUEST_TOKEN`.

## 1. Add the package

Pin an immutable tag or commit approved by your app. Use `PrivateSignerKit` and `PrivateSignerSelfUpdate`; add `PrivateSignerUI` only when the stock SwiftUI screens are useful.

## 2. Persist Worker configuration

```swift
let keychain = SignerKeychainConfiguration(
    service: "com.example.app.private-signer",
    configurationAccessGroup: "TEAMID.com.example.app"
)
let store = SignerConfigurationStore(keychain: keychain)
```

Store the Worker URL and the existing v2 Signing Request Token with `SignerConfigurationStore`. Project discovery, Profile discovery, self-update and generic signing all use this same credential.

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

Do not compile a Profile ID, GitHub repository, asset URL, latest version, or source digest into the app. Those values are Worker state.

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

Project signing submits `project_id`, `version_id`, Profile selection, and signing behavior through `POST /v2/sign/jobs`. `source_url`, source digest, expected source version, and expected source build are deliberately absent from `ProjectSigningOptions`.

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

The view obtains the Worker Profile list and renders a Picker. There is no host-supplied magic default Profile ID.

## 8. Generic signing

```swift
let profiles = try await client.profiles()
let options = SigningOptions(profileID: profiles.first!.id)
let job = try await client.createURLJob(sourceURL: ipaURL, options: options)
```

Generic signing uses the same v2 token and should use a Profile ID returned by the Worker.

## Acceptance checks

An integration is correct when:

1. `verifyConfiguration()` reports a v2 Worker as usable with the existing Signing Request Token.
2. The app contains a stable project ID but no hard-coded Profile ID or unsigned IPA URL for self-update.
3. `projectUpdate` returns a Worker-managed target ProjectVersion and signable Profiles.
4. Project signing succeeds using that `versionID` and Profile.
5. Updating Profile configuration on the Worker does not require rebuilding the app.
6. Real-device OTA install replaces the installed app when `.installedApp` is used.

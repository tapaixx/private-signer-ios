# PrivateSigner iOS v3 API reference

## PrivateSignerKit

### `SignerConfiguration`
Stores the HTTPS Worker URL and scoped v3 client token.

### `SignerConfigurationStore`
Persists configuration in the configured Keychain access group. A stable access group is required if the app is re-signed repeatedly.

### `SigningClient`
The v3 HTTP client.

Project catalog:

- `projects() -> [SigningProject]`
- `project(id:) -> ProjectDetail`
- `projectVersions(projectID:) -> [ProjectVersion]`
- `projectUpdate(projectID:currentVersion:) -> ProjectUpdate`
- `profiles(projectID:) -> [ProfileCapability]`

Project signing:

- `createProjectJob(projectID:versionID:options:) -> SigningJob`

Generic signing, when the principal has the relevant scope:

- `createURLJob(sourceURL:options:)`
- `uploadAndCreateJob(filename:data:options:)`
- `uploadAndCreateJob(fileURL:options:)`

Job lifecycle:

- `job(id:)`
- `history()`
- `retry(jobID:)`
- `cancel(jobID:)`
- `links(jobID:)`

Service checks:

- `health()`
- `verifyConfiguration()`

### `SigningProject`
Safe project metadata returned to an authorized principal: stable ID/name, bundle ID, version scheme, project default profile, and sync state.

### `ProjectVersion`
An immutable Worker-managed source release. Important fields include `versionID`, `version`, GitHub release/asset identity, digest state, and lifecycle state. It intentionally has no unsigned IPA URL.

### `ProfileCapability`
Safe client view of a signing profile set: ID, display name, expiry, short-lived flag, signable flag, and project-default flag. Raw mobileprovision data, UDIDs, and private certificate material are never exposed here.

### `ProjectUpdate`
The Worker's authoritative update decision: project, current-known state, `updateAvailable`, optional target version, and the project's usable profile capabilities.

### `ProjectSigningOptions`
Options a client may choose for a Worker-managed ProjectVersion:

- signing mode
- target bundle identifier
- profile ID
- keychain access groups
- embedded-bundle compatibility policy
- entitlement compatibility policy

It intentionally cannot express `source_url`, expected source digest, expected version, or expected build.

### `SigningOptions`
Options for generic URL/upload signing. It retains expected source digest/version/build assertions because the client is supplying that generic source.

### `SigningJob`
Represents asynchronous signing status. Poll active jobs until completed/failed/cancelled, then mint `DeliveryLinks` for completed jobs.

### `DeliveryLinks`
Short-lived manifest/export/install URLs minted by the Worker.

## PrivateSignerSelfUpdate

### `SelfUpdateCoordinator`
Construct with:

```swift
SelfUpdateCoordinator(
    store: store,
    projectID: "my-app",
    currentVersion: currentVersion,
    userAgent: "MyApp/\(currentVersion)"
)
```

Key operations:

- `updateStatus()` — full Worker update decision and profiles.
- `checkForUpdate()` — returns the target `ProjectVersion` or `nil`.
- `availableProfiles()` — Worker-discovered capabilities for the project.
- `requestSignedBuild(of:target:profileID:)` — signs an immutable ProjectVersion.
- `refresh(jobID:target:)` — polls an existing job and obtains links when ready.
- `installedSignature()` / `needsRenewal(within:)` — inspect current embedded profile.
- `requestRenewal(target:profileID:)` — re-sign the exact installed ProjectVersion.

`SelfUpdateCandidate` is a typealias of `ProjectVersion`. There is no `ReleaseSource` or `GitHubReleaseSource` in v3.

## PrivateSignerUI

### `SignerUIContext`
Contains Keychain configuration, environments, and user agent. It has no profile ID field.

### `SelfUpdateView`
Worker-driven project update UI:

```swift
SelfUpdateView(
    context: context,
    projectID: "my-app",
    currentVersion: currentVersion
)
```

Profiles are discovered and rendered as a Picker.

### `SigningJobsView`
Optional general-purpose URL/upload signing UI. It discovers the profiles visible to the current principal and requires a selection before submission. A project-scoped principal without generic scopes will be rejected by the Worker for generic operations.

## Contract compatibility

This package supports Worker contract `v3` only. `/v2`, host-supplied profile defaults, client-side GitHub release discovery, and the special `personal-main` identifier are intentionally unsupported.

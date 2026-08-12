# PrivateSigner iOS v2 API reference

## PrivateSignerKit

### `SignerConfiguration`
Stores the HTTPS Worker URL and the existing v2 `SIGNING_REQUEST_TOKEN` value.

### `SignerConfigurationStore`
Persists configuration in the configured Keychain access group. Use a stable access group when the app is re-signed repeatedly.

### `SigningClient`
The single v2 HTTP client.

Project catalog:

- `projects() -> [SigningProject]`
- `project(id:) -> ProjectDetail`
- `projectVersions(projectID:) -> [ProjectVersion]`
- `projectUpdate(projectID:currentVersion:) -> ProjectUpdate`
- `profiles(projectID:) -> [ProfileCapability]`

Project signing:

- `createProjectJob(projectID:versionID:options:) -> SigningJob`

Generic signing:

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

Every authenticated operation above uses the same configured Bearer token.

### `SigningProject`
Safe project metadata: stable ID/name, bundle ID, version scheme, project default Profile, and sync state.

### `ProjectVersion`
A Worker-managed source release. Important fields include `versionID`, `version`, GitHub release/asset identity, digest state, and lifecycle state. It intentionally has no unsigned IPA URL.

### `ProfileCapability`
Safe client view of a signing Profile Set: ID, display name, expiry, short-lived flag, signable flag, and project-default flag. Raw provisioning data, UDIDs, and private certificate material are not exposed.

### `ProjectUpdate`
The Worker's update decision: project, whether the current version is known, `updateAvailable`, optional target version, and usable Profile capabilities.

### `ProjectSigningOptions`
Options a client may choose for a Worker-managed ProjectVersion:

- signing mode
- target bundle identifier
- Profile ID
- Keychain access groups
- embedded-bundle compatibility policy
- entitlement compatibility policy

It cannot express source URL, source digest, expected source version, or expected source build; those are server-managed for project jobs.

### `SigningOptions`
Options for generic URL/upload signing. Generic sources may retain expected digest/version/build assertions because the client supplies the source.

### `SigningJob`
Represents asynchronous signing status. Poll active jobs, then mint `DeliveryLinks` for completed jobs.

### `DeliveryLinks`
Short-lived manifest/export/install URLs minted by the Worker.

## PrivateSignerSelfUpdate

### `SelfUpdateCoordinator`

```swift
SelfUpdateCoordinator(
    store: store,
    projectID: "my-app",
    currentVersion: currentVersion,
    userAgent: "MyApp/\(currentVersion)"
)
```

Key operations:

- `updateStatus()` — Worker update decision and Profiles.
- `checkForUpdate()` — target `ProjectVersion` or `nil`.
- `availableProfiles()` — Worker-discovered Profiles for the project.
- `requestSignedBuild(of:target:profileID:)` — signs a selected ProjectVersion.
- `refresh(jobID:target:)` — polls a job and obtains links when ready.
- `installedSignature()` / `needsRenewal(within:)` — inspect the current embedded profile.
- `requestRenewal(target:profileID:)` — re-sign the exact installed ProjectVersion when it exists in the Worker catalog.

`SelfUpdateCandidate` is a typealias of `ProjectVersion`. Client-side GitHub Release discovery is not part of project self-update.

## PrivateSignerUI

### `SignerUIContext`
Contains Keychain configuration, environments, and user agent. It does not contain a hard-coded Profile ID.

### `SelfUpdateView`

```swift
SelfUpdateView(
    context: context,
    projectID: "my-app",
    currentVersion: currentVersion
)
```

Profiles are discovered from the Worker and rendered as a Picker.

### `SigningJobsView`
Optional general-purpose URL/upload signing UI. It discovers available Profiles and requires an explicit selection before generic signing.

## Contract compatibility

This package supports Worker contract `v2` only. Host-supplied magic Profile defaults, client-side GitHub release discovery, and special handling for historical Profile names are unsupported.

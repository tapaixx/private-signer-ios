# Private IPA Signer — Client Integration Guide

This guide adds private IPA signing, OTA delivery, and optional self-updating to an iOS/iPadOS
project. It is written to be followed step by step by an AI coding agent, and it ends with
assertions you can run.

Normative source. The Chinese translation is [client-integration-guide.zh-CN.md](client-integration-guide.zh-CN.md);
where the two disagree, this file wins.

**Stop rules for an agent following this guide:**

- Stop and ask the human if you cannot obtain a value from [§1](#1-collect-these-values-first). Do
  not invent a Team ID, Bundle ID, Worker URL, or token.
- Never write a Signing Request Token into source, a build setting, a plist, a test fixture, a log
  line, or a commit message.
- Do not report the integration as working. You cannot verify it. [§7](#7-acceptance) says what
  you can verify and what only a human with a device can.

---

## 1. Collect these values first

| Value | Example | Where it comes from |
| --- | --- | --- |
| Apple Team ID | `4JJ849C5Q2` | Apple Developer account; also the prefix of any existing access group |
| Installed Bundle ID | `com.example.app` | The host app's `PRODUCT_BUNDLE_IDENTIFIER` |
| Stable Configuration Group | `4JJ849C5Q2.com.example.app` | Chosen by you — see [§3](#3-decide-the-stable-configuration-group) |
| Legacy access groups | `4JJ849C5Q2.old.identifier` | Only if a shipped build already stored configuration elsewhere |
| Worker URL | `https://signer.example.workers.dev` | The Private IPA Signer deployment. Entered by the user at runtime — never compiled in |
| Signing Request Token | *(secret)* | Same. Entered by the user at runtime |
| Profile ID | `personal-main` | The signing service's configured profile set; `nil` selects its default |
| Release repository | `owner/name` | Only for self-update via GitHub Releases |
| Release asset name | `MyApp-{tag}-unsigned.ipa` | The exact asset filename your release workflow publishes |
| Version string | `1.0.5-0006` | How the app knows its own version at runtime |

The Worker URL and token are **user configuration, not build configuration**. A public repository
that compiles them in has leaked full signing authority.

---

## 2. Add the dependency

Swift Package Manager:

```swift
.package(url: "https://github.com/nnnmdzz/private-signer-ios.git", exact: "0.1.1")
```

Pin with `exact:`, not `from:`. If self-update is the only way you ship builds, a dependency that
drifts on its own can break the one mechanism that would otherwise let you fix it.

For **XcodeGen** projects, add to `project.yml`:

```yaml
packages:
  PrivateSigner:
    url: https://github.com/nnnmdzz/private-signer-ios.git
    exactVersion: 0.1.1

targets:
  YourApp:
    dependencies:
      - package: PrivateSigner
        product: PrivateSignerKit
      - package: PrivateSigner
        product: PrivateSignerSelfUpdate
      - package: PrivateSigner
        product: PrivateSignerUI      # optional
```

Take only `PrivateSignerKit` if you are building your own UI and your own update discovery.

Minimum platforms: iOS 15, Swift 5.9.

---

## 3. Decide the Stable Configuration Group

**This is the step integrations get wrong, and the failure is delayed.**

The Worker URL and token live in the Keychain. Under `split` signing, the signed
`application-identifier` comes from the provisioning profile, not from your Bundle ID — so the
*default* Keychain access group changes whenever the profile changes. An app that relies on the
default loses its configuration the first time it re-signs itself, and the user has to re-enter a
high-entropy token they cannot see.

Naming a group explicitly and asking the signer to materialize it is what prevents this:

```swift
let store = SignerConfigurationStore(
    keychain: SignerKeychainConfiguration(
        service: "com.example.app.private-signer",
        configurationAccessGroup: "4JJ849C5Q2.com.example.app",
        legacyAccessGroups: []      // groups a shipped build already wrote to
    )
)
```

Rules:

1. The group must be **authorized by the provisioning profile** the signer uses. The signer will
   not fabricate a group outside the profile's allowance — a request for an unauthorized group
   fails.
2. Every Signing Request this app makes must carry the group. `SelfUpdateCoordinator` does this
   automatically by sending `store.authorizedAccessGroups`. If you call `SigningClient` directly,
   pass them yourself.
3. The **unsigned** build does not need `keychain-access-groups` in its `.entitlements`. The group
   is materialized at signing time from the request. Adding it to the source entitlements is
   allowed but not required.
4. Changing the group later strands every already-installed client's configuration. Add the old
   value to `legacyAccessGroups` instead — reads fall back to it and migrate the item on the spot.

### Migrating an app that already stores configuration

If a shipped build wrote its configuration under a different service, account, or access group,
keep the old values readable:

```swift
SignerKeychainConfiguration(
    service: "com.example.app.private-update",   // whatever the shipped build used
    account: "worker-configuration",             // default; change only if yours differs
    configurationAccessGroup: "4JJ849C5Q2.com.example.app",
    legacyAccessGroups: ["4JJ849C5Q2.previous.identifier"]
)
```

The stored JSON's token key is pinned to `personalToken` for exactly this reason. Do not "fix" it.

---

## 4. Write the Integration Adapter

One file. Everything application-specific goes here and nowhere else — that is what keeps the rest
of the integration upgradeable.

```swift
import Foundation
import PrivateSignerKit
import PrivateSignerSelfUpdate

enum PrivateSigning {
    static let teamID = "4JJ849C5Q2"
    static let bundleID = Bundle.main.bundleIdentifier ?? "com.example.app"

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    static var userAgent: String { "MyApp/\(currentVersion)" }

    static let store = SignerConfigurationStore(
        keychain: SignerKeychainConfiguration(
            service: "com.example.app.private-signer",
            configurationAccessGroup: "\(teamID).com.example.app"
        )
    )

    static let releaseSource = GitHubReleaseSource(
        repository: "owner/name",
        assetNameTemplate: "MyApp-{tag}-unsigned.ipa",
        userAgent: userAgent
    )

    static var coordinator: SelfUpdateCoordinator {
        SelfUpdateCoordinator(
            store: store,
            releaseSource: releaseSource,
            currentVersion: currentVersion,
            userAgent: userAgent,
            installedBundleIdentifier: bundleID,
            profileID: "personal-main"
        )
    }

    static var uiContext: SignerUIContext {
        SignerUIContext(
            keychain: store.keychain,
            environments: [.default],
            userAgent: userAgent,
            defaultProfileID: "personal-main"
        )
    }
}
```

**Version format.** `GitHubReleaseSource` defaults to `BuildTaggedVersionOrdering`, which
understands `vX.Y.Z-NNNN` (e.g. `v1.0.5-0006`). If your tags are plain semantic versions, pass
`ordering: DottedVersionOrdering()`. If they are something else, implement `VersionOrdering`
yourself — do not change your tag scheme to satisfy this package.

**Asset name.** `{tag}` is the published tag verbatim (`v1.0.5-0006`); `{version}` is the same
without a leading `v`. If a release exists but the asset name does not match, the call fails with
`missingAsset` naming the tag — that error means the template is wrong, not that the release is.

---

## 5. Wire the UI

### Option A — use the shipped screens

```swift
import PrivateSignerUI

NavigationLink("Signed update") {
    SelfUpdateView(
        context: PrivateSigning.uiContext,
        releaseSource: PrivateSigning.releaseSource,
        currentVersion: PrivateSigning.currentVersion,
        installedBundleIdentifier: PrivateSigning.bundleID
    )
}

NavigationLink("Private IPA signing") {
    SigningJobsView(context: PrivateSigning.uiContext)
}
```

They ship zh-Hans and en. "Install as a side-by-side clone" sits behind the advanced disclosure
and renames the primary button when enabled.

### Option B — build your own on Kit

Do this if you need different wording or layout. The whole contract is in `PrivateSignerKit`; the
UI product has no privileged access to anything.

---

## 6. Self-update, in-place versus side-by-side

```swift
guard let candidate = try await PrivateSigning.coordinator.checkForUpdate() else {
    return   // already current
}

var result = try await PrivateSigning.coordinator.requestSignedBuild(
    of: candidate,
    target: .installedApp                              // replaces the running app
    // target: .sideBySideClone(bundleID: "com.example.app.clone2")   // adds a second app
)

while result.job.isActive {
    try await Task.sleep(nanoseconds: 5_000_000_000)
    result = try await PrivateSigning.coordinator.refresh(jobID: result.job.jobID, target: target)
}

if let installURL = result.installationURL {
    await UIApplication.shared.open(installURL)
}
```

`SelfUpdateTarget` has two cases instead of an optional Bundle ID because the outcomes are visibly
different and a caller must not be able to pick the wrong one by accident. Check
`result.willReplaceInstalledApp` before showing an install prompt, and say which one is about to
happen.

Facts worth surfacing in your UI:

- Each distinct `target_bundle_id` is a distinct request fingerprint, so **N clones cost N real
  signing jobs**. They are not deduplicated against each other.
- A clone inherits the Stable Configuration Group automatically, so the token is not re-entered.
- **Known limitation:** iOS may remove Keychain items when the last app owning their access group
  is uninstalled. If the main app is removed and only clones remain, the stored configuration may
  or may not survive. This is untested; treat it as a risk, not a guarantee.

### Polling

Poll no faster than every 5 seconds, only while the app is in the foreground, and only while
`job.isActive`. Signing runs on a real macOS runner; a tight loop buys nothing and burns rate
limit.

---

## 7. Acceptance

### What CI can verify

Add this to your test suite. It fails on the mistakes that are cheap to make and expensive to
discover later:

```bash
#!/usr/bin/env bash
set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }

# 1. No signing credential is compiled in.
grep -rniE '(signing[_-]?request[_-]?token|personal[_-]?update[_-]?token)[[:space:]]*[=:][[:space:]]*"[^"]+"' \
  --include='*.swift' --include='*.plist' --include='*.xcconfig' --include='*.yml' . \
  && fail "a signing token appears to be hard-coded"

# 2. No default Worker URL is compiled in.
grep -rniE 'https://[a-z0-9.-]*workers\.dev' --include='*.swift' . \
  && fail "a Worker URL is hard-coded"

# 3. Application-specific values live only in the adapter.
for symbol in GitHubReleaseSource SignerKeychainConfiguration; do
  hits=$(grep -rl "$symbol" --include='*.swift' Sources App Shared 2>/dev/null | grep -v 'PrivateSigningAdapter.swift' || true)
  [ -z "$hits" ] || fail "$symbol is constructed outside the adapter: $hits"
done

# 4. The self-update path names its target explicitly.
grep -rn 'requestSignedBuild' --include='*.swift' . | grep -qv 'target:' \
  && fail "requestSignedBuild called without an explicit target"

echo "OK"
```

Adjust the paths in check 3 to your project layout, and the adapter filename to whatever you named
it in [§4](#4-write-the-integration-adapter).

### What only a human with a device can verify

macOS `codesign --verify` passing does **not** prove iOS will install or upgrade the build. Every
one of these needs a real phone:

- [ ] Clean install of a signed IPA succeeds and the app launches.
- [ ] **Upgrade over the currently installed build** succeeds — not only clean install.
- [ ] The Worker URL and token survive that upgrade without re-entry.
- [ ] Entitlement-dependent features still work after signing (some entitlements are stripped by
      policy — read the signing report).
- [ ] A side-by-side clone installs as a *second* app and the original still runs.
- [ ] The clone can read the configuration without the token being typed again.
- [ ] A wrong Worker URL and a wrong token produce different, actionable messages.

Do not ship on CI green alone.

---

## 8. Failure handling

`ConfigurationVerification` exists so the two things a hand-entered configuration gets wrong are
distinguishable:

| Result | Means | What to tell the user |
| --- | --- | --- |
| `.usable` | Address and token both work | Proceed |
| `.usableWithUndeclaredContract` | Works, but the Worker predates the contract field | Proceed; suggest updating the Worker |
| `.notASigner` | Something answered, but it is not a Private IPA Signer | Check the address |
| `.unsupportedContract(v)` | Version mismatch | Upgrade the app or the Worker |
| `.invalidToken` | Address is right, token is rejected | Re-enter the token only |
| `.unreachable(detail)` | Network or DNS | Show the detail |

Every error type in this package carries a stable `code` alongside a localized
`errorDescription`. **Branch on `code`; display `errorDescription`.** Never parse the message.

Preserve for diagnostics: HTTP status, `error_code`, `message`, `job_id`, `attempt`, and the job
status. Never log the `Authorization` header or a delivery-link URL — delivery links are bearer
credentials in query-string form.

---

## Appendix A — raw HTTP contract

For clients that are not Swift. `PrivateSignerKit` implements all of this.

Base: the Worker origin. Auth: `Authorization: Bearer <Signing Request Token>` on everything
except `/health` and the delivery endpoints (which carry their own signed token).

| Endpoint | Method | Purpose |
| --- | --- | --- |
| `/health` | GET | Unauthenticated. `{"ok":true,"contract":"v2"}` |
| `/v2/sign/jobs` | POST | Create or reuse a Signing Job |
| `/v2/sign/jobs` | GET | Paginated history, newest first, `next_cursor` |
| `/v2/sign/jobs/<id>` | GET | Poll one job |
| `/v2/sign/jobs/<id>/retry` | POST | Retry a failed job |
| `/v2/sign/jobs/<id>/cancel` | POST | Cancel an active job |
| `/v2/sign/jobs/<id>/links` | POST | Mint 15-minute delivery links |
| `/v2/uploads` | POST | Start an Upload Session |
| `/v2/uploads/<id>/parts/<n>` | PUT | Upload one part |
| `/v2/uploads/<id>/complete` | POST | Finalize the upload |
| `/v2/delivery/manifest?token=` | GET | OTA manifest |
| `/v2/delivery/artifact?token=` | GET | Signed IPA |

Job creation body — send exactly one source (`source_url` **or** `upload_id`) and always send
`signing_mode`:

```json
{
  "source_url": "https://example.com/App.ipa",
  "signing_mode": "split",
  "target_bundle_id": "com.example.clone",
  "profile_id": "personal-main",
  "keychain_access_groups": ["TEAM.com.example.app"],
  "embedded_bundle_policy": "strip_unsupported",
  "entitlement_policy": "strip_unsupported",
  "expected_sha256": "<64 hex, optional>"
}
```

Job statuses: `dispatching`, `queued`, `dispatch_failed`, `signing`, `following`, `completed`,
`failed`, `cancelled`. **Treat any unrecognized status as neither active nor failed and keep
polling** — do not crash on a server that learned a new state.

Limits: sources 100 MiB; parts 8 MiB (use the server's returned `part_size`, do not assume it);
at most 5 active upload sessions, 20 new sessions per hour, 500 MiB declared upload bytes per
hour. Job metadata is retained 30 days, signed artifacts 7 days, delivery links 15 minutes
(renewable while the artifact exists).

HTTP mapping:

| Status | Handling |
| --- | --- |
| `2xx` | Decode and continue per returned status |
| `400` | Request/options/source validation error; show the server's `error` |
| `401` | Token missing, invalid, or rotated; request credential repair |
| `404` | Job or upload is gone; stop assuming it exists |
| `409` | Lifecycle conflict (incomplete upload, non-retryable job, artifact not ready) |
| `410` | Source/upload/artifact expired; reacquire |
| `429` | Rate limited; back off, preserve the operation |
| `5xx` | Service or dispatch failure; retry only where the operation allows it |

---

## Appendix B — contract versus recommendation

- **Contract** (changes only with the service): accepted fields, statuses, limits, retention,
  endpoint behavior, the `keychain_access_groups` authorization rule.
- **Recommendation** (yours to change): poll timing, UI mapping, when to use `standard` versus
  `split`, adapter structure, logging policy.

When the `/v2` contract changes, this guide, its Chinese translation, and this package are updated
together so downstream projects never have to reverse-engineer behavior from implementation code.

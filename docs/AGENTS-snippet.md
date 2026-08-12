# AGENTS.md snippet

Paste this into the consuming project's `AGENTS.md` / `CLAUDE.md` after integrating. It is what a
future agent needs to know to avoid breaking the integration.

```markdown
## Private IPA signing

This project signs its own builds through a Private IPA Signer deployment, via the
`private-signer-ios` package. Integration guide:
https://github.com/nnnmdzz/private-signer-ios/blob/main/docs/client-integration-guide.md

- All application-specific signing values live in `<path>/PrivateSigningAdapter.swift`. Construct
  `SignerKeychainConfiguration` and `GitHubReleaseSource` there and nowhere else.
- The Worker URL and Signing Request Token are user configuration stored in the Keychain. Never
  write either into source, build settings, plists, tests, logs, or commit messages.
- `configurationAccessGroup` is the Stable Configuration Group. Changing its value strands every
  installed client's configuration. To change it, move the old value into `legacyAccessGroups`
  instead of replacing it.
- Every signing request must carry `store.authorizedAccessGroups`. `SelfUpdateCoordinator` does
  this automatically; direct `SigningClient` calls must pass them.
- `requestSignedBuild` must always be called with an explicit `target:`. `.installedApp` upgrades
  the app; `.sideBySideClone` installs a second one. Never let the choice be implicit.
- Branch on the `code` property of package errors. Display `errorDescription`. Never parse
  message text.
- Pin the package with `exact:`. Do not widen it to `from:`.
- CI cannot verify that a signed build installs on a device. Do not report signing changes as
  verified without a human running the real-device checklist in §7 of the guide.
```

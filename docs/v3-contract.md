# PrivateSigner v3 client contract

v3 is a breaking bug-fix contract. The SDK no longer discovers GitHub releases or embeds a provisioning profile identifier.

## Project self-update

A host app compiles only a stable `projectID`. The flow is:

1. `GET /v3/projects/{projectID}/update?current_version=...`
2. choose the Worker's default signable profile, or another profile returned by that response
3. `POST /v3/sign/jobs` with `project_id`, `version_id`, and signing options
4. poll `/v3/sign/jobs/{jobID}` and mint delivery links when completed

The SDK never receives or submits the unsigned IPA URL in project mode. Source URL, source digest, and expected release version are Worker-owned ProjectVersion facts.

## Generic signing

URL and local-file signing remain available through `createURLJob` and `uploadAndCreateJob`, but only for principals with `generic-url-sign` / `upload-sign` scopes. Profiles are discovered with `GET /v3/profiles`; profile IDs are not free-text configuration.

## Removed v2 assumptions

- `/v2` client routes are unsupported
- `personal-main` has no special meaning
- `GitHubReleaseSource` is removed
- `SignerUIContext.defaultProfileID` is removed
- `SelfUpdateCoordinator` and `SelfUpdateView` take `projectID`

# v2 contract

PrivateSigner maintains one Worker contract: `v2`.

## Authentication

Every authenticated SDK request uses the configured `SIGNING_REQUEST_TOKEN` as a Bearer token. Project discovery, Profile discovery, project signing and generic URL/upload signing do not use separate credentials.

## Project endpoints

```text
GET /v2/projects
GET /v2/projects/{project_id}
GET /v2/projects/{project_id}/versions
GET /v2/projects/{project_id}/update?current_version=...
GET /v2/profiles?project_id=...
```

A project signing job uses the established endpoint:

```text
POST /v2/sign/jobs
```

with `project_id`, `version_id`, optional `profile_id`, and signing options. The Worker owns the ProjectVersion source URL, digest and expected app version.

Generic URL/upload signing continues to use `/v2/sign/jobs` and `/v2/uploads`.

## Service identity

`GET /health` is unauthenticated and declares `contract: "v2"`. Newer Workers may also include an implementation `version`; clients must not confuse that release number with the API contract.

## Profile IDs

Profile IDs are ordinary Worker registry data discovered at runtime. No identifier, including historical names, has protocol-level fallback semantics.

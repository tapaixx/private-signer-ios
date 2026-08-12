# Private Signer iOS Client

**English** · [简体中文](CONTEXT.zh-CN.md)

This context describes the client half of private IPA signing: how an app asks for a signed build,
proves the result is the build it asked for, and installs it.

The service-side terms below are restated verbatim from the Private IPA Signer's own glossary
rather than linked, because that repository is private and this one is not. When a term changes on
one side, change the wording on both — the two glossaries are kept in sync by identical text, not
by a reference.

## Language

### Client concepts

**Signer Client**:
The library that submits Signing Requests and follows their Signing Jobs on behalf of one
installed application, holding no signing authority of its own.
_Avoid_: Signing SDK, API wrapper, signer

**Integration Adapter**:
The small piece of code inside a host application that supplies its application-specific values —
release repository, asset name, access group, user agent — to an otherwise application-agnostic
Signer Client.
_Avoid_: Config file, glue code, bridge

**Release Source**:
The application-specific way a client discovers builds of itself that are newer than the one
running, and the only part of self-updating that differs between projects.
_Avoid_: Update feed, release checker, version API

**Self-Update Coordinator**:
The client flow that turns a discovered Release Candidate into an installable Signed Artifact by
issuing an ordinary Signing Request.
_Avoid_: Updater, auto-update service, OTA manager

**Release Candidate**:
One discovered build that a client could install, carrying its version, its resignable IPA
location, and an optional digest that binds the request to exact bytes.
_Avoid_: Latest release, new version, update

**In-Place Update**:
A Signing Request whose Target Bundle ID equals the installed application's, so iOS replaces the
running app instead of adding another one.
_Avoid_: Normal update, self-update, upgrade

**Side-by-Side Clone**:
A Signing Request whose Target Bundle ID deliberately differs from the installed application's, so
the signed build installs as an additional app and the running one survives.
_Avoid_: Multi-instance, dual open, second copy

**Stable Configuration Group**:
The Keychain access group that owns an application's Worker URL and Signing Request Token across
every future signature, named explicitly because the default group is derived from the
provisioning profile and therefore changes when the profile does.
_Avoid_: Default Keychain group, current access group, app group

**Signing Environment**:
A named set of stored Signer credentials, letting one installed application hold a production and
a staging configuration at the same time without re-entering either.
_Avoid_: Profile, workspace, account

**Signature Renewal**:
Re-signing the version already installed because its signature is about to expire, rather than installing a newer one. Kept apart from In-Place Update because a caller reading a discovered candidate as "there is something newer" must stay right.
_Avoid_: Refresh, re-sign, update

**Installed Signature**:
What the running app's own `embedded.mobileprovision` says about the signature it carries: when it expires, which profile produced it, and whether that profile is one Apple issues with a seven-day life.
_Avoid_: Provisioning info, cert expiry, profile

**Service Contract**:
The interface version a Signer deployment declares on its unauthenticated health endpoint, used to
tell "this address is not a Signer" apart from "this token is wrong".
_Avoid_: API version, health check, ping

### Service concepts (restated from the Private IPA Signer glossary)

**Signing Request**:
An authenticated instruction to acquire one Resignable IPA and produce a device-gated signed
artifact using explicit signing options.
_Avoid_: Update request, release request, queue item

**Signing Job**:
The uniquely identified execution created from one accepted Signing Request and polled by its
caller until signing succeeds or fails.
_Avoid_: Workflow run, R2 record, build

**Signing Request Token**:
The bearer credential whose holder has full authority to submit Signing Requests from an app,
shortcut, or command-line client.
_Avoid_: Personal Update Token, admin token, app token

**Resignable IPA**:
An IPA whose executable code is not FairPlay encrypted and can therefore receive a new valid code
signature without decryption.
_Avoid_: Decrypted IPA, cracked IPA, unsigned IPA

**Source IPA**:
The resignable packaged app selected by a Signing Request as its input artifact, whether unsigned
or previously signed.
_Avoid_: Release asset, update package

**Upload Session**:
The authenticated, resumable sequence that assembles one device-selected IPA from bounded parts
before it becomes a Source Snapshot.
_Avoid_: Multipart upload, temporary object, upload job

**Source Snapshot**:
The immutable copy created from a Source IPA on its first successful download and identified by
its SHA-256 digest.
_Avoid_: Download cache, temporary IPA, source URL

**Signed Artifact**:
The device-gated IPA produced by a successful Signing Job and retained independently from its
renewable, short-lived download link.
_Avoid_: Result URL, manifest, signed update

**Delivery Link**:
A renewable, purpose-bound URL that grants repeated access to one manifest or Signed Artifact
until its short expiry.
_Avoid_: Download token, permanent link, artifact URL

**Target Bundle ID**:
The optional requested identity of the signed main app; when absent, the Source IPA's main bundle
identifier is preserved.
_Avoid_: Bundle ID override, clone ID, requested bundle ID

**Requested Keychain Groups**:
The optional set of Keychain access groups a Signing Request asks the signer to preserve or
materialize within the selected provisioning profile's authority.
_Avoid_: Split access group, Keychain entitlement override

**Profile ID**:
A stable, non-secret alias that selects one configured certificate and provisioning-profile set;
omission selects the explicit default.
_Avoid_: Profile slot, certificate name, signing identity

**Device Gate**:
The server-controlled requirement that a Profile ID's provisioning profiles cover the configured
target devices, independent of caller input.
_Avoid_: UDID list, allowed device, device filter

**Profile Set**:
The provisioning profiles that sign one root app and its embedded bundles together, selected as a unit by a Profile ID and the only scope a Device Gate is derived from.
_Avoid_: Profile group, profile bundle, certificate profiles

**Signing Mode**:
The explicit identity policy for a Signing Job: Standard keeps bundle and application identities
conventionally aligned, while Split keeps the final bundle identity separate from the
profile-derived application identity.
_Avoid_: Signing strategy, rewrite mode, identity mode

**Embedded Bundle Policy**:
The requested treatment of extensions, widgets, Watch apps, and other nested bundles that the
selected Profile ID cannot sign: strip and report them, or require every bundle.
_Avoid_: Plugin handling, extension cleanup, nested signing mode

**Entitlement Policy**:
The requested treatment of source capabilities that the selected provisioning profiles do not
authorize: strip and report them, or require every capability.
_Avoid_: Capability cleanup, entitlement filtering, permission mode

# Presentools 0.3.0 — release, update, and launch-at-login

Design for turning Presentools from a private local build into a publicly
installable release, and adding three user-facing integrations: automatic
update checking, login-item registration, and version/account information.

## Context

Presentools is currently an unsigned, local-only build. There is no git
remote, no README, and no release process. The hotkey-customisation work in
`2026-09-30-custom-hotkeys-design.md` is complete and uncommitted.

The app is ad-hoc signed with no Apple Developer account. This single fact
drives most of the decisions below, so it is stated once and referred to as
*the ad-hoc constraint*.

### Modifier decision carried over

The four effect bindings ship as `⌥0` `⌥1` `⌥2` `⌥3` and panic as `⌥Esc`.
Mode defaults to **toggle** for all four effects. Toggle suits a presenter
better than hold: a toggle survives a stumble, and it means the presenter can
let go of the keyboard mid-sentence.

## Explicitly rejected: Sparkle

Sparkle is the standard macOS updater and is the wrong choice here.

1. Sparkle's appcast requires a Developer ID signature to publish. Under the
   ad-hoc constraint there is no key to sign it with.
2. An update replaces the app with a newly-signed copy, which invalidates the
   Screen Recording TCC grant. The zoom lens would silently stop working after
   every update, and users would not connect that to the update.
3. It is an external dependency for a codebase that currently has none, and the
   app is 1.0 MB — the dependency is a large fraction of the deliverable.

A hand-rolled checker is ~200 lines, has no dependencies, and can never break
the TCC grant because it never touches the installed app.

## Architecture

Four new units, each independently testable, each with one job:

| Unit | Responsibility | Network | Main actor |
|------|----------------|---------|------------|
| `Version` | parse + compare `1.2.3` | no | no |
| `UpdateChecker` | fetch release JSON, decide if newer | yes | no |
| `LaunchAtLogin` | wrap `SMAppService`, map status | no | no |
| `About` | version + repo URL strings | no | no |

Version comparison and digest verification are **pure functions**. The
network-touching and TCC-touching code is a thin shell around them. This is
what makes the logic provable in `--selftest` without a network or a login
item, matching how `HotKeyDecision` and `HotKeyConflict` are already tested.

### `Version`

Numeric component comparison, not lexicographic. `1.10.0 > 1.9.0` is true
numerically and false as a string. Missing components read as `0`, so
`1.2` and `1.2.0` are equal. Non-numeric suffixes (`1.2.0-beta1`) parse to
`(1, 2, 0)` for comparison but are preserved verbatim for display. Ties resolve
to *not newer*, so a malformed tag never prompts the user to update to itself.

### `UpdateChecker`

`GET https://api.github.com/repos/ardith666/presentools/releases/latest`.
No auth header; the endpoint is unauthenticated and rate-limited to 60/hour per
IP, which is far above a check that runs at most once per launch.

Behaviour:

- Compare `tag_name` (stripped of a leading `v`) against `CFBundleShortVersionString`.
- Newer → panel showing new version, release notes, and **Download**.
- Same or older → nothing. No notification, no window, no sound.
- Any failure (no network, 404, rate limit, malformed JSON) → one line on the
  status line, no dialog, no log noise.

The last rule is a product requirement, not caution: **a presenter must never
see an error dialog mid-talk.** A presenter whose spotlight dies mid-talk does
not recover. Update failures are the least important thing happening on the
machine at that moment and must be invisible.

User control: a `Check for Updates Automatically` menu toggle, on by default,
persisted in `Settings`. Off means no launch-time check; the manual
**Check for Updates…** item always works.

### Download and integrity

**Download** fetches the release's `.dmg` asset, verifies its SHA-256 against a
digest published in the release body, and opens the containing folder in
Finder. The user drags the app over. The running app is never replaced.

The digest is compared against the release **body** rather than a hardcoded
constant, so publishing a new release needs no app change.

Failure modes, each silent-but-logged: digest mismatch (asset corrupted or
tampered — do **not** open it), 404 on the asset, network error, or no digest
in the body.

### `LaunchAtLogin`

`SMAppService.mainAppService` (macOS 13+; target is 27.0). Replaces the older
`LSSharedFileList` approach and needs no helper binary here.

**First launch only**, guarded by a `hasSeenLaunchAtLoginPrompt` flag, show one
`NSAlert`: "Launch Presentools at login?" with **Yes** / **Not Now**. The app
never registers silently and never re-asks. After that, a `Launch at Login`
menu item reflects live `SMAppService.status`.

The menu checkmark must be derived from live status, never from a stored
preference. A user who revokes the item in System Settings must see the tick
removed on next launch; a stale tick is a small lie that costs the user a
debugging session.

`.requiresApproval` is the case that silently breaks apps — the user has to
approve in System Settings and the app cannot know until it checks — so it
maps to a distinct menu state and an explanatory hint rather than a bare tick.

Registration failure is reported on the status line, not raised. `SMAppService`
throws when the bundle is not in a standard location, which is exactly what
happens when someone runs the build from `build/` instead of
`/Applications`.

### `About`

Non-editable menu items: `Version 0.3.0` and `ardith666/presentools` (opens
the repo in the default browser). Version reads `Bundle.main`, never a
hardcoded string, so it cannot drift from `bundle.sh`.

No credits panel and no signature-check affordance: under the ad-hoc
constraint those would be dishonest UI.

## Menu shape

```
No Effect
Spotlight
Laser Pointer
Zoom Lens
─
Shortcuts…
─
Spotlight / Zoom Lens / Laser Pointer / Edge   (existing settings)
Reset to Defaults
Launch at Login                    ✓ / off
Check for Updates Automatically    ✓ / off
Check for Updates…
─
Screen Recording: granted
─
About ▸
    Version 0.3.0
    ardith666/presentools
─
Quit Presentools
```

## Release mechanics

### Repository

Create `ardith666/presentools`, **public**, starting from **clean history**
per the decision above: the existing commits were private work-in-progress
with no README and no installable release, so they are not the public record.
The new history begins at 0.3.0.

`knowledge/` is retained — it is the project's real engineering log and the
`macos-27-overlay` notes are the only written record of the TCC quirks. It is
the most valuable thing in the repo for a future contributor.

### Version

`0.3.0`. Bump `CFBundleShortVersionString` in `bundle.sh`. `Version` reads it
at runtime; nothing else hardcodes it.

### Homebrew

**Own tap: `ardith666/homebrew-presentools`.** Upstream `homebrew-cask` audits
prefer notarized apps and would likely reject this without a paid account.

Cask keeps `quarantine` **enabled** (the default). Under the ad-hoc constraint
Gatekeeper must block a freshly-downloaded unsigned app; the cask therefore
needs `quarantine: true` and the README documents the right-click **Open**
step. Stripping quarantine would make launch smoother but would also disable a
real safety check and hide that the app is unsigned. The install is one extra
right-click either way.

```
brew install --cask ardith666/presentools
```

### Release

Tag `0.3.0`, `gh release create` with the DMG asset and a release body that
contains the asset's SHA-256 — this is the value `UpdateChecker` verifies
against, so the body is the trust anchor for the whole update path.

### README (English)

Install via Homebrew and via DMG; the Gatekeeper right-click step stated
plainly and up front; macOS 27+ requirement; the five shortcuts; the three
effects; the first-run Screen Recording grant and why zoom needs it.

## Testing

`--selftest` covers every pure unit, no network and no login item:

- `Version`: `1.10.0 > 1.9.0`, equal-with-missing-components, `v` prefix,
  suffix parse, tie-is-not-newer, garbage input.
- Update decisions: newer / same / older / malformed JSON / missing fields,
  each mapped to its outcome.
- Digest verification: match, mismatch, absent digest, case-insensitive hex.
- `LaunchAtLogin` status → menu-state mapping, for all four status cases.
- Existing: default bindings now `opt` with **toggle** mode; the shipped-table
  self-consistency check must still pass.

Not covered by `selftest`, listed in `knowledge/history.md` as requiring a
human: a real update round-trip, the first-launch prompt, and the actual
behaviour of each `SMAppService` status.

## Risks

| Risk | Mitigation |
|------|-----------|
| Ad-hoc signature + Gatekeeper blocks launch | Documented in README and cask; user right-clicks Open once |
| Update digest mismatch | Asset is not opened; one status line |
| `SMAppService` throws outside `/Applications` | Caught, reported on status line, app keeps running |
| Rate limit on the GitHub API | Once per launch at most; failure is silent |
| Clean history loses reasoning trail | `knowledge/history.md` retains the decisions and their reasons |
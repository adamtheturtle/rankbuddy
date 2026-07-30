# Dependency & CI supply-chain policy

This document records how RankBuddy keeps its GitHub Actions and Swift package
dependencies current without silently drifting the build toolchain or running
unreviewed automation. It is the human-readable counterpart to
[`.github/dependabot.yml`](../.github/dependabot.yml) and
[`.github/workflows/ci.yml`](../.github/workflows/ci.yml).

## GitHub Actions

- **Automated, grouped, weekly.** Dependabot (`package-ecosystem: github-actions`)
  opens one grouped PR per week for all action bumps, so the actions used in CI
  (`actions/checkout`, `actions/cache`, `actions/upload-artifact`, …) stay current
  — including security fixes — without one-PR-per-action churn.
- **Review transitive changes.** Action update PRs are reviewed like any other
  change before merge.

## Swift packages

- **Owner: a documented manual process, not Dependabot.** Adopting a new release
  of the shared [`buddy-kit`](https://github.com/adamtheturtle/buddy-kit)
  foundation (and its transitive packages such as `SwiftUI-Flow` and `textual`)
  is a deliberate, reviewed step, so there is intentionally no
  `package-ecosystem: swift` entry in `dependabot.yml`. To update:
  1. Pick the target `buddy-kit` release tag.
  2. Update the pin in the Xcode project's package references.
  3. Resolve packages and **commit the updated `Package.resolved`** so a fresh
     checkout resolves the exact same graph used in CI.
  4. Review the transitive dependency changes in the resulting diff.
- **Pinning discipline.**
  - `buddy-kit` itself is pinned to an **exact released version** (never a branch
    or floating range), so every build is reproducible.
  - `buddy-kit`'s own dependencies follow its `Package.swift`: `textual` is
    exact-pinned, `SwiftUI-Flow` is pinned to a major (`from:`) so everything
    resolves to one Flow version.
- **Resolution files are committed.** `Package.resolved` is tracked (it is **not**
  git-ignored) so a fresh checkout — local or CI — resolves an identical package
  graph.

### FastList usage audit

RankBuddy intentionally has one `FastList` construction point:
`Views/LoadableList.swift`. Tests, Questions, Interviews, People, Teams, and
Candidates configure that app-owned wrapper rather than building package-specific
lists themselves. The app still needs the macOS recycled `NSTableView` primitive
for large, paginated collections.

The package surface used by `LoadableList` falls into these ownership groups:

- **Retain as platform primitives:** selection binding, recycled hosted rows,
  double-click and Return activation, native row context menus and drag sessions,
  scroll-to-row, top-row reporting, and end-of-viewport reporting.
- **Already app-owned:** row height (`FastListRowMetrics`), favourite state and
  drag payloads, menu construction (`rowMenuItems`), copy/CSV transfer models,
  pagination retry/loading UI, scroll persistence, and detail activation.
- **Compatibility conveniences to migrate when FastList deprecates them:**
  `reloadID` (currently used to rebuild recycled favourite accessories) and
  `onCopyCommand` (currently supplied by RankBuddy's `RowTransfer` providers).
  Their replacements should remain in `LoadableList`, not move domain behavior
  into the package.

This boundary matches the reduced shared direction tracked in
[`FastList#4`](https://github.com/adamtheturtle/FastList/issues/4). New RankBuddy
features must be implemented in `LoadableList` or another app-owned layer unless
they are required by the recycled-table primitive itself.

## Build & lint tool versions

The validation tools are version-pinned in `ci.yml` and must be bumped in lockstep
with the local toolchain and the config files they read:

| Tool        | Pinned in                                     | Keep aligned with               |
| ----------- | --------------------------------------------- | ------------------------------- |
| SwiftLint   | `ci.yml` (`0.63.3`)                           | `.swiftlint.yml`                |
| SwiftFormat | `ci.yml` (`0.61.1`)                           | `.swiftformat`                  |
| actionlint  | `ci.yml` (`1.7.12`)                           | the workflow syntax in use      |
| Swift/Xcode | `swift:6.2` container + `Xcode_26.5` on macOS | the app target's Swift version  |

When upgrading a tool locally, bump the version in `ci.yml` in the same change so
local and CI parsing/build behavior stay identical.

## Pinning sensitive actions

For ordinary validation jobs we pin first-party actions to floating **major** tags
(`actions/checkout@v7`) and let Dependabot advance them; this is low-risk because
the jobs only read the checkout (see workflow permissions below).

The third-party `actionlint` downloader is fetched at an **exact version tag**
(not `main`) so its script can't change underneath us.

When release/signing workflows are added (Developer ID / notarization, see #11),
any **security-sensitive third-party action** — certificate/keychain import,
release publishing — must be pinned to an **immutable commit SHA**, not a mutable
tag, so a compromised tag can't inject code into a signing step.

## Workflow permissions

CI follows least privilege. `ci.yml` declares a top-level read-only token:

```yaml
permissions:
  contents: read
```

No validation job writes to the repository, comments, or publishes artifacts to
external services, so none needs more than read access. Workflows added later
(release, website deploy) must declare the **minimum** additional permissions they
require at the job level rather than widening the default for the whole file.

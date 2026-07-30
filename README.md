# RankBuddy for macOS

A native macOS app for browsing your [HackerRank for Work](https://www.hackerrank.com/work/)
data — tests, candidates, questions, and interviews — built on the shared `buddy-kit`
foundation. Pre-release; the read-only MVP is the current focus.

## Requirements

- macOS 15 or later.
- A HackerRank for Work personal access token (added in Settings). Tokens are stored in
  the login Keychain and never leave your machine except to call the HackerRank API.

## Features

- Read-only **Tests**, **Candidates** (per test), **Questions**, and **Interviews** lists
  with detail panes.
- Per-list **search**, **sorting** (remembered across launches), pull-to-refresh, and
  loading / empty / error states.
- Right-click **context menus** to copy a row's primary text or open/copy its web link.
- A ⌘K **command palette** with fuzzy ranking and full keyboard navigation.
- A **menu bar extra** for quick section switching.

### Keyboard shortcuts

| Shortcut | Action |
| -------- | ------ |
| ⌘1 / ⌘2 / ⌘3 | Jump to Tests / Questions / Interviews |
| ⌘K | Open the command palette |
| ⌘R | Refresh the current list |

## Demo mode

RankBuddy ships a deterministic, sanitized mock of the HackerRank API so the UI can be
explored and screenshotted without a token. Set environment variables in the run scheme:

- `RANKBUDDY_DEMO=1` — seed a demo account and serve bundled fixtures (populated lists,
  including a multi-page tests collection).
- `RANKBUDDY_DEMO_SCENARIO=<scenario>` — choose what the mock returns, to exercise
  non-happy paths:
  - `success` (default) — populated, paginated data.
  - `empty` — every collection is empty (empty states).
  - `unauthorized` — a `401` (authentication-failure state).
  - `malformed` — invalid JSON (decode-failure state).

The demo mock is installed only on a dedicated `URLSession`, so it never intercepts real
network traffic.

## Development

- **Build:** open `rankbuddy-macos.xcodeproj` in Xcode and build the `rankbuddy-macos`
  scheme, or run the project's build via the Xcode tooling.
- **Lint** (matching CI):

  ```sh
  swiftformat . --lint     # formatting (SwiftFormat owns formatting)
  swiftlint --strict       # correctness (SwiftLint owns correctness)
  ```

  Configuration lives in `.swiftformat`, `.swiftlint.yml`, and `.periphery.yml`.

- **Release type-check budget:** Release builds pass
  `-warn-long-expression-type-checking=250` and
  `-warn-long-function-bodies=500` to the Swift compiler. Because Release treats warnings
  as errors, expressions taking more than 250 ms or function bodies taking more than
  500 ms to type-check fail the build. Keep these thresholds in the project-level Release
  configuration so they cover every Swift target and the scheduled CI Release build.

The HackerRank API contract RankBuddy relies on is documented in
[`docs/hackerrank-api.md`](docs/hackerrank-api.md); dependency notes are in
[`docs/dependencies.md`](docs/dependencies.md).

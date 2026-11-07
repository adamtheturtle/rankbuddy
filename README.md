# RankBuddy for macOS

A native macOS app for working with [HackerRank for Work](https://www.hackerrank.com/work/), built on the shared `buddy-kit` foundation.
Browse and edit interview resources through native screens, or use the API Explorer and embedded MCP server for the complete documented API.

## Requirements

- macOS 15 or later.
- A HackerRank for Work personal access token (added in Settings).
  Tokens are stored in the login Keychain and never leave your machine except to call the HackerRank API.

## Features

- **Tests**, **Candidates** (per test), **Questions**, **Interviews**, **People** and **Teams**, with detail panes and editing flows.
- An **API Explorer** covering all 76 documented v3, ATS and SCIM operations, with request schemas and complete responses.
- An embedded **MCP server**, with read tools by default and explicit write access in Settings.
- Cursor-based **Account Activity**, with object and date filters.
- Per-list **search**, **sorting** (remembered across launches), pull-to-refresh, and loading / empty / error states.
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

RankBuddy ships a deterministic, sanitized mock of the HackerRank API so the UI can be explored and screenshotted without a token.
Set environment variables in the run scheme:

- `RANKBUDDY_DEMO=1` — seed a demo account and serve bundled fixtures (populated lists, including a multi-page tests collection).
- `RANKBUDDY_DEMO_SCENARIO=<scenario>` — choose what the mock returns, to exercise non-happy paths:
  - `success` (default) — populated, paginated data.
  - `empty` — every collection is empty (empty states).
  - `unauthorized` — a `401` (authentication-failure state).
  - `malformed` — invalid JSON (decode-failure state).

The demo mock is installed only on a dedicated `URLSession`, so it never intercepts real network traffic.

For deterministic failure-state work, launch RankBuddy with `RANKBUDDY_DEMO_SCENARIO` set to `empty`, `validation`, `throttled`, `malformed`, or `server-error`, then use the demo account.
The override applies only to demo requests; configured live accounts continue using their authenticated network sessions.

## Development

- **Preflight:** run `./scripts/preflight.sh` before pushing.
  It resolves the committed package graph, lints, checks formatting, builds the macOS app, runs the parallel Fast test plan, and checks staged and unstaged patches for whitespace errors.
  Full logs and result bundles are retained under `.context/`.

- **Build:** open `rankbuddy-macos.xcodeproj` in Xcode and build the `rankbuddy-macos` scheme, or run the project's build via the Xcode tooling.
- **Lint** (matching CI):

  ```sh
  swiftformat . --lint --config .swiftformat  # formatting; ignore parent configs
  swiftlint lint --strict  # fast correctness rules
  periphery scan --strict  # unused code (nightly/manual CI)
  ```

  Configuration lives in `.swiftformat`, `.swiftlint.yml`, and `.periphery.yml`.
  Analyzer-only SwiftLint rules run in CI against the compiler log captured from a clean macOS build; listing them in `.swiftlint.yml` alone does not enforce them.

- **Release type-check budget:** Release builds pass `-warn-long-expression-type-checking=250` and `-warn-long-function-bodies=500` to the Swift compiler.
  Because Release treats warnings as errors, expressions taking more than 250 ms or function bodies taking more than 500 ms to type-check fail the build.
  Keep these thresholds in the project-level Release configuration so they cover every Swift target and the scheduled CI Release build.

The HackerRank API contract RankBuddy relies on is documented in [`docs/hackerrank-api.md`](docs/hackerrank-api.md); dependency notes are in [`docs/dependencies.md`](docs/dependencies.md), and the tagged Developer ID release process is in [`docs/releasing.md`](docs/releasing.md).

## Complete API access

Open **API Explorer** from the main window toolbar, select an account and operation, then fill its path parameters, query fields and JSON body.
**Request format** shows the operation's complete schema.
The response includes its HTTP status and headers, so empty responses and pending interview artifacts remain distinguishable.
SCIM operations use a separate provisioning token, saved in the selected account's Keychain item.
ATS invite workflows are available in the Explorer as well as MCP.

The MCP `api_` catalogue exposes the same operations and request schemas.
Write tools require **Allow the MCP server to make changes** in Settings.
SCIM tools use the account's saved provisioning credential.
The demo account supports the complete catalogue without live credentials.

This branch temporarily pins the tested commit from [HackerRankKit #224](https://github.com/adamtheturtle/HackerRankKit/pull/224).
Replace that revision with a released version after the SDK is released.

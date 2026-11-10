# HackerRank API coverage

RankBuddy uses the [official HackerRank for Work contract](https://www.hackerrank.com/work/apidocs), packaged by [HackerRankKit](https://github.com/adamtheturtle/HackerRankKit).
The SDK catalogue contains all 76 documented operations: 65 v3 operations and 11 SCIM operations.
It includes path/query parameters, request-body schemas and referenced definitions.

## Desktop and MCP

The native screens cover the published operations and request options:

- Tests, candidates, questions, interviews, people, and teams expose resource actions and settings in their detail toolbar.
- Templates have a **New Template** action, initial question selection, settings, deletion, and explicit sharing controls.
  Invitation-email templates are a separate read-only API resource.
- **Candidates** searches across tests; per-test search remains available in each assessment’s candidate list.
- **Audit Logs** supports offset and cursor pagination, with all published filters.
- **ATS Invitations** has separate assessment and interview workflows.
- **Provisioning** manages SCIM users and groups with the account’s separate provisioning credential.

Forms use native controls for booleans, enumerated choices, dates, arrays, and nested settings.
Optional values distinguish keeping defaults from sending false, zero, empty text, or an empty list.
Resource editors retrieve current settings and omit unchanged fields on partial updates.
No operation picker, path/query JSON editor, or request console is needed.

The embedded MCP server uses [HackerRankMCP](https://github.com/adamtheturtle/HackerRankMCP) for its tool catalogue and request handling.
RankBuddy adapts its Keychain accounts and demo backend, and keeps activity logging, the account resource and triage prompt in the app.
The shared provider preserves the existing friendly tools and exposes the complete contract as `api_` tools.
Each tool accepts nested `path`, `query` and `body` objects, with the account selected separately.
Read tools are available by default.
Write tools require the existing Settings opt-in and remain blocked when invoked by name without it.
The `api_` catalogue covers resource details, global candidate search, membership reads, transcripts, template sharing, code-stub operations and testcase add/update alongside the existing friendly tools.

## Authentication and namespaces

Ordinary operations use the account's v3 personal token and configured HTTPS origin under `/x/api/v3`.
SCIM uses `https://services.hackerrank.com/scim/v2` with a separate provisioning credential.
Enter that credential in the account editor’s **Provisioning token** field in Settings.
It is stored in the account's Keychain item, independently of the ordinary token.
MCP never accepts provisioning tokens as tool arguments or returns stored credentials.
The demo account uses the in-process mock for both namespaces.

## Interview artifacts and notes

Interviews V2 exposes artifact metadata through `GET /interviews/{interview_id}/artifacts`.
Eligible ended interviews can provide submitted-code, execution-history, AI-chat, whiteboard and transcript download descriptors.
Availability varies by question and enabled features.
A successful result can contain unavailable artifacts or empty arrays.
The endpoint retrieves existing artifacts and does not trigger generation.

During the documented post-interview generation window, HTTP 202 carries a message and `Retry-After`.
Signed download URLs expire after 3,600 seconds, so obtain fresh metadata when needed.
Interviewer note references do not contain note text.
Use the notes read operation to retrieve permitted notes and the PATCH operation to replace the current user's note.
An empty content string clears it.

## Audit logs

Account Activity uses the cursor audit endpoint, allowing traversal beyond the offset API's 10,000-record window.
Initial requests support user, source type/ID, timestamp range, sort and expansion filters.
Later requests send only the opaque cursor from the preceding page.
Cursors expire after inactivity, and refreshing starts a new traversal.
Object and date filters remain available in Account Activity.
The **Audit Logs** destination uses cursor pagination automatically behind **Load More**.
Its Filters sheet retains the audit filters and hides the continuation cursor, which the app manages.
The documented actor filter is `user`.

## Pagination and contract details

Ordinary collections use offset/limit pagination with absolute `next` URLs. HackerRankKit validates continuation origins before authenticating them. Global candidate search is separate from per-test candidate search. Interview templates and invite-email templates are distinct resources. The API offers adding/removing template questions without an ordering guarantee.

The generated catalogue normalizes query parameters that Swagger incorrectly marks as path parameters.
It preserves the PDF endpoint's fixed `format=url` query.
Request bodies retain additional JSON fields, including the support-confirmed project `custom_system_prompt` field.
Project AI prompts preserve whitespace and may contain up to 15,000 characters.

## SCIM request shapes

The native forms retain the service’s documented `diplayName` group-name key.
SCIM emails use address objects with `value` and optional `primary` fields, matching the SDK’s typed requests and the service.
SCIM patch requests use capitalized `Operations` and the PatchOp schema identifier.
Each change supports an operation, an optional path, and a structured value.
These wire details differ from parts of the legacy Swagger schema and have explicit request tests.

## Verification

Unit and integration tests use synthetic data and the SDK's mock server.
Native coverage is recorded in [native-api-coverage.json](native-api-coverage.json).
Tests verify the 76 source entry points, 319 documented nested body-field paths, path/query parameters, and enumerated choices against the pinned SDK catalogue.
Request tests submit every operation from native form state through the SDK with a synthetic URL protocol, checking authentication, queries, and encoded bodies.
Separate MCP tests compare advertised `api_` tool names with the SDK catalogue.
These checks establish request routing and response handling, not live account permissions or the success of particular production mutations.

## Package adoption

Release HackerRankKit first, then HackerRankMCP, then RankBuddy.
The app still uses HackerRankKit directly for desktop API calls.
The app uses released HackerRankKit 0.11.1 and HackerRankMCP 0.4.1 packages.
Tool contract tests run in HackerRankMCP against mock clients.
RankBuddy retains tests for its host adapter and app-owned resources and prompts.

# HackerRank API coverage

RankBuddy uses the [official HackerRank for Work contract](https://www.hackerrank.com/work/apidocs), packaged by [HackerRankKit](https://github.com/adamtheturtle/HackerRankKit).
The SDK catalogue contains all 76 documented operations: 65 v3 operations and 11 SCIM operations.
It includes path/query parameters, request-body schemas and referenced definitions.

## Desktop and MCP

The native screens provide common test, candidate, question, interview, user and team workflows.
**API Explorer**, available from the main toolbar, exposes every documented operation, including interview-template management and sharing, question membership, ATS invites and SCIM provisioning.
Choose an account and operation, review its request format, enter path/query/body JSON, and run it.
Complete response status, headers and JSON are retained, including empty responses and HTTP 202 results.

The embedded MCP server exposes the same contract as `api_` tools.
Each tool accepts nested `path`, `query` and `body` objects, with the account selected separately.
Read tools are available by default.
Write tools require the existing Settings opt-in and remain blocked when invoked by name without it.
The `api_` catalogue covers resource details, global candidate search, membership reads, transcripts, template sharing, code-stub operations and testcase add/update alongside the existing friendly tools.

## Authentication and namespaces

Ordinary operations use the account's v3 personal token and configured HTTPS origin under `/x/api/v3`.
SCIM uses `https://services.hackerrank.com/scim/v2` with a separate provisioning credential.
Enter that credential in API Explorer while selecting a SCIM operation and choose **Save Token**.
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
Object and date filters are available in Account Activity; the Explorer exposes all documented audit filters and both pagination APIs.
The documented actor filter is `user`.

## Pagination and contract details

Ordinary collections use offset/limit pagination with absolute `next` URLs.
HackerRankKit validates continuation origins before authenticating them.
Global candidate search is separate from per-test candidate search.
Interview templates and invite-email templates are distinct resources.
The API offers adding/removing template questions without an ordering guarantee.

The generated catalogue normalizes query parameters that Swagger incorrectly marks as path parameters.
It preserves the PDF endpoint's fixed `format=url` query.
Request bodies retain additional JSON fields, including the support-confirmed project `custom_system_prompt` field.
Project AI prompts preserve whitespace and may contain up to 15,000 characters.

## Verification

Unit and integration tests use synthetic data and the SDK's mock server.
Coverage checks compare advertised `api_` tool names with the complete SDK catalogue and invoke every documented route without live credentials.
These checks establish request routing and response handling, not live account permissions or the success of particular production mutations.

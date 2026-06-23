# HackerRank for Work API contract

What RankBuddy relies on from the HackerRank for Work API, recorded here (without
secrets) so the transport and models can be reasoned about and the mock fixtures can
match. Derived from the public [`adamtheturtle/hackerrank`](https://github.com/adamtheturtle/hackerrank)
Python client; **the exact contract should still be confirmed against a live account**
(see #3) before the endpoint-specific UI is considered fully verified.

## Base URL and versioning

- Default base URL: `https://www.hackerrank.com` (overridable per account for regional
  deployments).
- All endpoints are under the `/x/api/v3` prefix.

## Authentication

- Bearer token: `Authorization: Bearer <personal access token>`.
- `Accept: application/json`.
- An invalid/expired token returns `401`/`403`.

## Pagination

List endpoints use **offset/limit** pagination and return a top-level envelope:

```json
{
  "data": [ /* items */ ],
  "page_total": 50,
  "offset": 0,
  "previous": "<url|null>",
  "next": "<absolute url|null>",
  "first": "<url>",
  "last": "<url>",
  "total": 1234
}
```

- Items are under `data`.
- `next` is an **absolute URL** for the following page (or `null` on the last page).
- RankBuddy follows `next` sequentially. It deliberately does **not** use the generic
  transport's page-number fast path, which assumes `?page=N` URLs that HackerRank does
  not honour (it pages by `offset`/`limit`).

## Endpoints used (read-only MVP)

| Resource    | Path                                        |
| ----------- | ------------------------------------------- |
| Tests       | `GET /x/api/v3/tests`                        |
| Candidates  | `GET /x/api/v3/tests/{test_id}/candidates`  |
| Questions   | `GET /x/api/v3/questions`                    |
| Interviews  | `GET /x/api/v3/interviews`                   |

Candidates exist only in the context of a test, so RankBuddy nests them under a test
rather than offering a global candidates list.

Token validation uses a lightweight `GET /x/api/v3/tests?limit=1`.

## Rate limiting and errors

- `429` indicates rate limiting; RankBuddy retries with bounded exponential backoff.
- `5xx` and recoverable transport errors (timeout, connection lost, offline, DNS) are
  also retried; `4xx` (auth/validation) and decode failures surface immediately.

## Model fields

The decoded model fields mirror the documented response shapes; see
`rankbuddy-macos/Models/`. Unmodelled keys are ignored, so responses with extra fields
decode without failure.

# HackerRank for Work API contract

What RankBuddy relies on from the HackerRank for Work API, recorded here (without
secrets) so the transport and models can be reasoned about and the mock fixtures can
match. Derived from the public [`adamtheturtle/hackerrank`](https://github.com/adamtheturtle/hackerrank)
Python client and **confirmed against a live HackerRank for Work account on 2026-06-24**
(#3) for the read-only endpoints below.

## Re-confirmed against a live account (2026-06-27)

- **Auth + paginated fetch still hold** end-to-end: `GET /x/api/v3/tests?limit=1` returns
  the envelope below; a valid token authenticates and an invalid token is rejected with a
  mapped `HackerRankError` (clear message), exercising both the success and auth-failure paths.
- **`GET /x/api/v3/users/me`** returns the **single signed-in user object** (not a paged
  envelope) in the same shape as a People-list entry — `id`, `email`, `firstname`, `lastname`,
  `role`, `company_admin`, team/permission fields. RankBuddy uses it to auto-discover an
  account's identity in the editor (#72); it decodes straight into the `User` model.

## Confirmed against a live account (2026-06-24)

- **Auth/pagination:** `GET /x/api/v3/tests|questions|interviews` return `200` with the
  envelope below (`data`, `total`, `page_total`, `offset`, absolute `next`/`previous`/
  `first`/`last`). Pagination is offset/limit and `next` is absolute — as modelled.
- **Ids are JSON strings** (e.g. `"2360707"`), so the models' `String` ids are correct.
- **Dates** are ISO-8601 with a `+0000` zero-offset and no fractional seconds
  (e.g. `2026-06-22T04:10:51+0000`); `DisplayFormat` parses this.
- **Field-name correction:** tests expose **`start_time` / `end_time`** (not
  `starttime` / `endtime` as the Python schema implied). The `Test` model was corrected.
- **Unmodelled fields** are present and safely ignored (tests: `sections`, `permission`,
  `test_type`; questions: `skills`, `test_case_count`, `leaked_data`; candidates: many).
- **`integrity_status`** uses human strings like `"No Issues Detected"` live, not the
  `clean`/`review` tokens the badge currently keys on (relevant to #14).
- **Collection sizes are large** on a real account (this one: ~241 tests, ~9,720
  questions, ~87,345 interviews). The client currently fetches *all* pages, so the
  read-only lists must move to bounded/lazy paging before live use — tracked separately.

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
| Users       | `GET /x/api/v3/users`                        |
| Current user| `GET /x/api/v3/users/me`                     |
| Teams       | `GET /x/api/v3/teams`                        |
| Team members| `GET /x/api/v3/teams/{team_id}/users`       |

Candidates exist only in the context of a test, so RankBuddy nests them under a test
rather than offering a global candidates list. `users/me` returns a single user object
(not a paged envelope) and is used to auto-discover the account's identity (#72).

Token validation uses a lightweight `GET /x/api/v3/tests?limit=1`.

## Sorting (interviews)

The collections default to **oldest-first**, which on a real account (≈87k interviews)
means the recent records never appear in the first pages. `GET /x/api/v3/interviews`
accepts two sort parameters (from the official OpenAPI spec — *not* a generic `ordering`
key, which the server ignores):

- `order_by` ∈ `title`, `id`, `created_at`, `ended_at`, `current_status`, `user`.
- `order_dir` ∈ `asc`, `desc`. **Required whenever `order_by` is set.**

RankBuddy requests `order_by=created_at&order_dir=desc` so the newest interviews — and
anything created today — load first; the server carries the parameters into the `next`
URLs. `GET /x/api/v3/questions` exposes no sort parameter, and the spec documents none
for tests/users/teams.

## Date filtering (interviews)

`GET /x/api/v3/interviews` accepts a `created_at=<from>..<to>` range filter. RankBuddy uses
it for the Interviews date chip (#86) so the filter spans the whole collection rather than
only the rows already loaded — on a real account "last 90 days" matched ~6.9k of ~87.6k
interviews, far more than the client ever pages in. Both bounds are ISO-8601; the API
accepts UTC `…Z` form (e.g. `2026-03-30T00:00:00Z..2026-06-27T23:59:59Z`), which is what
`ISO8601DateFormatter` emits, and the named ranges map to it via `DateRangeFilter`.

## Rate limiting and errors

- `429` indicates rate limiting; RankBuddy retries with bounded exponential backoff.
- `5xx` and recoverable transport errors (timeout, connection lost, offline, DNS) are
  also retried; `4xx` (auth/validation) and decode failures surface immediately.

## Model fields

The decoded model fields mirror the documented response shapes; see
`rankbuddy-macos/Models/`. Unmodelled keys are ignored, so responses with extra fields
decode without failure.

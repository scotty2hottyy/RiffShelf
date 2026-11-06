# RiffShelf backend

This independent FastAPI service exposes Songsterr search and optional MusicBrainz metadata. `GET /health` returns `{"status":"ok"}` when the process responds; it is not a check of external providers. No tab bodies or personal files are stored.

## Install, run, and test on macOS or Linux

Install Python 3.14 (including its `venv` module; on Ubuntu install the matching Python venv package if needed). From the repository root:

```sh
cd server
python3.14 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
python -m compileall -q app tests
python -m ruff check app tests
python -m pytest
python -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

These commands use a project-local virtual environment and pinned direct and transitive dependencies. Port 8000 is only a local development example; choose another if occupied. In another terminal, verify:

```sh
curl -fsS http://127.0.0.1:8000/health
curl -fsS http://127.0.0.1:8000/docs
curl -fsS http://127.0.0.1:8000/openapi.json
curl -G --data-urlencode 'q=Come As You Are' http://127.0.0.1:8000/api/v1/search/tabs
curl -G --data-urlencode 'artist=Nirvana' --data-urlencode 'title=Come As You Are' http://127.0.0.1:8000/api/v1/metadata/recordings
```

Open `http://127.0.0.1:8000/docs` in a browser for the interactive Swagger UI (its assets require network access). Stop the server with Ctrl-C and leave the virtual environment with `deactivate`.

## Search contract

`GET /api/v1/search/tabs?q=<song title or artist>` returns `200` with `{"results":[...]}`. Each result represents one Songsterr song and one identified instrument (`guitar` or `bass`). The response contains `artist`, `title`, `source` (`Songsterr`), `source_id`, `source_url`, `instrument`, `available_arrangements` (track `name` and `tuning`), and song/instrument `tuning`. Tuning is an array of pitch names from lowest to highest string; unknown names or tunings are `null`. The top-level tuning is `null` if the arrangements disagree or any arrangement lacks tuning. Songs without identified guitar or bass tracks are omitted. An empty search is `{"results":[]}`.

Example response excerpt for the request above (live Songsterr result on 2026-11-03):

```json
{"results":[{"artist":"Nirvana","title":"Come As You Are","source":"Songsterr","source_id":"14","source_url":"https://www.songsterr.com/a/wsa/song?id=14","instrument":"bass","available_arrangements":[{"name":"Krist Novoselic | Gibson Ripper | Bass","tuning":["D1","G1","C2","F2"]}],"tuning":["D1","G1","C2","F2"]}]}
```

The example shows one result from a larger response. Query validation returns `422` for missing, duplicate, blank, control-character, or over-120-character `q`. The process-local per-client-address limit returns `429` after 30 valid requests per rolling minute by default. Songsterr HTTP/network failures and malformed responses return `502`; upstream timeouts return `504`. All errors use `{"error":{"code":"...","message":"..."}}`, with codes `invalid_query`, `rate_limited`, `provider_failure`, `provider_timeout`, or `malformed_provider_response`. Rate limits are per process and reset on restart; this service does not trust proxy forwarding headers by default.

Example error response (HTTP 429):

```json
{"error":{"code":"rate_limited","message":"Search rate limit exceeded. Try again in one minute."}}
```

The backend test suite uses mocked Songsterr HTTP responses and needs no live internet. GitHub Actions runs Python 3.14, pinned dependencies, syntax checks, Ruff, and pytest as a separate required-to-pass job alongside the existing Flutter validation and builds.

## Optional MusicBrainz metadata contract

`GET /api/v1/metadata/recordings?artist=<artist>&title=<song title>` returns `200` with `{"recordings":[...]}`. Each candidate has `recording_id` (MusicBrainz ID), `artist` (credited name), `artist_ids` (MusicBrainz artist IDs), `title`, `provider_confidence` (MusicBrainz search score from 0 to 100, or `null`), and `releases`. Each release has `release_id` (MusicBrainz ID), `title`, and `date` (year, year-month, full date, or `null`). A recording may have zero or several releases. Results preserve MusicBrainz's order and score; no release is selected or treated as the album automatically. `{"recordings":[]}` means no match. Results are limited to the first 25 recordings returned by MusicBrainz.

Example response shape:

```json
{"recordings":[{"recording_id":"c7c16d8f-6b67-4e60-a5ea-d201a12c00a6","artist":"Nirvana","artist_ids":["5b11f4ce-a62d-471e-81fc-a69a8278c7da"],"title":"Come As You Are","provider_confidence":100,"releases":[{"release_id":"a1ed26f7-3f11-4633-a3c7-4a4abfa3271f","title":"Nevermind","date":"1991-09-24"}]}]}
```

The IDs and score above illustrate the response format; they are not a verified live lookup. Artist and title are required once each, trimmed, and limited to 120 characters without control characters. Invalid values return `422`. The process allows at most one MusicBrainz request per second and returns `429` with `rate_limited` if another lookup arrives sooner. MusicBrainz rate limiting returns `503` with `provider_rate_limited`; other upstream HTTP/network failures and malformed responses return `502`; timeouts return `504`. Errors use the same `{"error":{"code":"...","message":"..."}}` envelope as search. Metadata failures affect only this endpoint: Songsterr search, tab downloads, and saved tabs do not require MusicBrainz. No artwork is fetched.

The adapter sends `RiffShelf/0.1.0 (https://github.com/scotty2hottyy/RiffShelf)` as its identifying User-Agent, uses HTTPS, makes one recording search per accepted call, and has a five-second timeout by default. `RIFFSHELF_MUSICBRAINZ_TIMEOUT_SECONDS` configures a positive timeout up to 30 seconds. The one-request-per-second pacer is per process; deployments using multiple worker processes or sharing an outbound IP with other clients need a shared throttle to satisfy [MusicBrainz's rate guidance](https://musicbrainz.org/doc/MusicBrainz_API/Rate_Limiting). The query uses [MusicBrainz recording search fields](https://musicbrainz.org/doc/MusicBrainz_API/Search) for artist and title. The mock-based backend tests make no live MusicBrainz requests.

## Configuration

`RIFFSHELF_DOCS_ENABLED` defaults to `true` for local development. Set it to `false` before starting the service to disable `/docs` and `/openapi.json`. Values are case-insensitive `true` or `false`; invalid values fail startup. For example:

```sh
export RIFFSHELF_DOCS_ENABLED=false
python -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

No credentials are required. The host and port are Uvicorn command-line options, not assumed deployment settings. Do not commit secrets or local environment files.

`RIFFSHELF_SONGSTERR_TIMEOUT_SECONDS` defaults to `8` (positive, at most `60`) for each upstream request. `RIFFSHELF_SEARCH_RATE_LIMIT_PER_MINUTE` defaults to `30` (positive integer). Invalid values fail startup. The search adapter first tries the legacy Songsterr URL and falls back to `/api/songs` after a non-success status. These unofficial endpoints may change.

## Local Flutter integration demonstration

On a Mac with the iOS simulator booted, start the backend in one terminal using the setup above. From the repository root in another terminal, run:

```sh
flutter pub get
flutter test integration_test/live_backend_search_test.dart -d <simulator-device-id> --dart-define=RIFFSHELF_API_BASE_URL=http://127.0.0.1:8000
```

The optional integration test enters “Come As You Are” in Discover, taps Search, and checks that Nirvana/Songsterr results appear. It uses real Songsterr access, so it is separate from CI and requires a reachable provider. A local iOS simulator run on 2026-11-03 passed, and the FastAPI log recorded its `GET /api/v1/search/tabs` request with HTTP 200. Local HTTP is accepted by the debug app; release builds require an HTTPS backend URL. For Android or a physical device, use a reachable host address or HTTPS endpoint rather than assuming that the device's loopback address is the Mac. The simulator demonstration does not verify deployed network access or a physical device.

The backend returns search metadata only. Songsterr's unofficial endpoints and content availability can change. A TestFlight build without `RIFFSHELF_API_BASE_URL` continues to search Songsterr directly; a configured backend failure is shown in Discover with Retry. Saved SQLite tabs remain available offline.

## Before any SkyNet deployment

The authoritative `SkyNet_Server_Context.md` in the ChatGPT Library was not available to this implementation session. Read it and confirm it is current before making deployment decisions. On the Ubuntu server, first verify:

- The intended host, access method, operator permissions, and existing services and policies.
- A free, approved listening address and port, using the server's existing network and firewall configuration; check current listeners before choosing one.
- An approved deployment directory, service account, Python 3.14 and venv availability, disk space, and dependency installation method.
- Existing reverse proxy, TLS, DNS, firewall, service manager, logging, restart, update, and rollback conventions before selecting any configuration.
- Whether API documentation should be disabled and how future secrets and provider access will be handled.

No SkyNet installation or deployment is performed by these instructions.

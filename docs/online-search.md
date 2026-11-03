# Online tab search

Discover uses a provider interface and search service, separate from Flutter presentation. Songsterr is the enabled provider. Its public search, metadata and structured-track endpoints are unofficial and can change or become unavailable; network errors and incompatible responses are reported to the user. Search results identify guitar and bass where Songsterr provides track metadata. Selecting a result retrieves the current revision and lets the user choose a matching track. Only actual downloaded notes can be saved; the existing SQLite library stores the tab for offline viewing.

Ultimate Guitar is not enabled: Tab-Star's adapter requires a separate proxy, and no running or verified service is assumed. The independent backend in `server/` provides `GET /api/v1/search/tabs?q=...` for Songsterr metadata search. Flutter Discover uses it when `RIFFSHELF_API_BASE_URL` is configured. Without a URL, Discover continues to search Songsterr directly until deployment. A configured backend failure is shown with Retry; Discover does not silently switch to direct search. Songsterr still supplies track selection and tablature downloads. The backend supplies search metadata only.

Configure an HTTPS API origin at build/run time for Android or iOS; do not append `/api/v1/search/tabs` to the URL:

```sh
flutter run --dart-define=RIFFSHELF_API_BASE_URL=https://your-api.example
flutter build apk --release --dart-define=RIFFSHELF_API_BASE_URL=https://your-api.example
flutter build ios --release --dart-define=RIFFSHELF_API_BASE_URL=https://your-api.example
```

The client appends `/api/v1/search/tabs?q=...` and requires HTTPS in release builds. Development builds may use an HTTP origin for local testing. The URL must be reachable by the device; a simulator or device does not automatically share the development machine's loopback address. No URL is committed to the app. The SQLite Library and previously saved tabs remain available offline.

The backend accepts a song title or artist and returns `{"results":[...]}`. Each result has `artist`, `title`, `source`, `source_id`, `source_url`, `instrument` (`guitar` or `bass`), `available_arrangements` (track names and tunings), and `tuning`. Unknown arrangement names and tunings are `null`; a result's tuning is `null` unless all its arrangements report the same tuning. Empty matches return `200` and an empty array. Missing, blank, duplicate, control-character, or over-120-character queries return `422`; rate limiting returns `429`; provider failures and malformed data return `502`; timeouts return `504`. Errors have `{"error":{"code":"provider_timeout","message":"Songsterr search timed out."}}` shape. See [server/README.md](../server/README.md) for all codes and settings.

Example: `curl -G --data-urlencode 'q=Come As You Are' http://127.0.0.1:8000/api/v1/search/tabs`. A live request through the running FastAPI service on 2026-11-03 returned HTTP 200 with 82 guitar/bass results. It included Nirvana's "Come As You Are" (Songsterr ID `14`) for both guitar (four named arrangements, D standard) and bass (one named arrangement, D standard). The bass result included `"tuning":["D1","G1","C2","F2"]` and source URL `https://www.songsterr.com/a/wsa/song?id=14`. This verifies local end-to-end provider access, not access from a Flutter device or deployed network. Issue #14 remains open until that acceptance criterion can be checked.

Run deterministic backend tests with `cd server && .venv/bin/python -m pytest`; run Flutter tests from the repository root with `flutter test`. The server stores no tab bodies or personal files. Issue #15 remains open until a physical device searches the deployed backend and saved tabs are checked offline.

The Songsterr adapter is adapted from the local Tab-Star project. Songsterr content and endpoint access remain subject to Songsterr's applicable terms and rights; this integration does not grant a license to redistribute tablature. Verify provider terms and content permissions before distribution or production use.

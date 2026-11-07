# Online tab search

Discover uses a provider interface and search service, separate from Flutter presentation. Songsterr is the enabled provider. Its public search, metadata and structured-track endpoints are unofficial and can change or become unavailable; network errors and incompatible responses are reported to the user. Search results identify guitar and bass where Songsterr provides track metadata. Selecting a result retrieves the current revision and lets the user choose a matching track. Only actual downloaded notes can be saved; the existing SQLite library stores the tab for offline viewing.

Ultimate Guitar is not enabled: its adapter requires a separate proxy, and no running or verified service is assumed. The independent backend in `server/` provides `GET /api/v1/search/tabs?q=...` for Songsterr metadata search. Flutter Discover uses it when `RIFFSHELF_API_BASE_URL` is configured. Without a URL, Discover continues to search Songsterr directly until deployment. A configured backend failure is shown with Retry; Discover does not silently switch to direct search. Songsterr still supplies track selection and tablature downloads. The backend supplies search metadata only.

Configure an HTTPS API origin at build/run time for Android or iOS; do not append `/api/v1/search/tabs` to the URL:

```sh
flutter run --dart-define=RIFFSHELF_API_BASE_URL=https://your-api.example
flutter build apk --release --dart-define=RIFFSHELF_API_BASE_URL=https://your-api.example
flutter build ios --release --dart-define=RIFFSHELF_API_BASE_URL=https://your-api.example
```

The client appends `/api/v1/search/tabs?q=...` and requires HTTPS in release builds. Development builds may use an HTTP origin for local testing. The URL must be reachable by the device; a simulator or device does not automatically share the development machine's loopback address. No URL is committed to the app. The SQLite Library and previously saved tabs remain available offline.

TestFlight builds without a configured backend URL continue using direct Songsterr search. To use the backend in TestFlight, pass the HTTPS origin with `--dart-define=RIFFSHELF_API_BASE_URL=...` when building that artifact. A configured backend error is shown with Retry and does not silently fall back.

The backend accepts a song title or artist and returns `{"results":[...]}`. Each result has `artist`, `title`, `source`, `source_id`, `source_url`, `instrument` (`guitar` or `bass`), `available_arrangements` (track names and tunings), and `tuning`. Unknown arrangement names and tunings are `null`; a result's tuning is `null` unless all its arrangements report the same tuning. Empty matches return `200` and an empty array. Missing, blank, duplicate, control-character, or over-120-character queries return `422`; rate limiting returns `429`; provider failures and malformed data return `502`; timeouts return `504`. Errors have `{"error":{"code":"provider_timeout","message":"Songsterr search timed out."}}` shape. See [server/README.md](../server/README.md) for all codes and settings.

Example: `curl -G --data-urlencode 'q=Come As You Are' http://127.0.0.1:8000/api/v1/search/tabs`. A live request through the running FastAPI service on 2026-11-03 returned HTTP 200 with 82 guitar/bass results. It included Nirvana's "Come As You Are" (Songsterr ID `14`) for both guitar (four named arrangements, D standard) and bass (one named arrangement, D standard). The bass result included `"tuning":["D1","G1","C2","F2"]` and source URL `https://www.songsterr.com/a/wsa/song?id=14`. This verifies local end-to-end provider access, not access from a Flutter device or deployed network. Issue #14 remains open until that acceptance criterion can be checked.

Run deterministic backend checks with `cd server && .venv/bin/python -m compileall -q app tests && .venv/bin/python -m ruff check app tests && .venv/bin/python -m pytest -q`; run Flutter checks from the repository root with `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, and `flutter test`. CI also builds a debug Android APK and iOS simulator app. Backend tests mock all Songsterr calls and do not require internet. The server stores no tab bodies or personal files.

For a live app-to-backend demonstration, start the backend with `cd server && .venv/bin/python -m uvicorn app.main:app --host 127.0.0.1 --port 8000`, then run `flutter test integration_test/live_backend_search_test.dart -d <simulator-device-id> --dart-define=RIFFSHELF_API_BASE_URL=http://127.0.0.1:8000` from the repository root on a Mac with a booted iOS simulator. This optional test enters a query in Discover, sends it through FastAPI to real Songsterr, and asserts visible Flutter results. It passed locally on 2026-11-03 for “Come As You Are”; FastAPI logged the simulator's request as HTTP 200. The test is excluded from CI because it requires live provider access. A physical device reaching a deployed HTTPS backend and offline use after that search remain unverified; Issue #15 remains open for those checks.

The Songsterr adapter is adapted from the local Tab-Star project. Songsterr content and endpoint access remain subject to Songsterr's applicable terms and rights; this integration does not grant a license to redistribute tablature. Verify provider terms and content permissions before distribution or production use.


Saved-tab album lookup uses the same `RIFFSHELF_API_BASE_URL` setting. Select a release explicitly on the tab detail screen; downloaded thumbnails remain available offline. Configure a reachable backend before testing on a physical device: its `localhost` refers to the device, not the development computer. Use an accessible HTTPS backend origin for release builds and ensure the device can also reach Cover Art Archive/Internet Archive for the image download. The backend is optional for viewing and practicing saved tabs.

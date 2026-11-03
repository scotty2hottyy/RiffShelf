import httpx
from fastapi.testclient import TestClient

from app.api.v1.search import RateLimiter
from app.config import Settings
from app.main import create_app
from app.songsterr import ProviderError, SongsterrSearchProvider, normalize


SONGS = [{
    "songId": 14, "title": "Come As You Are", "artist": "Nirvana",
    "defaultTrack": 0,
    "tracks": [
        {"instrumentId": 30, "instrument": "Distortion Guitar", "name": "Rhythm", "tuning": [64, 59, 55, 50, 45, 40]},
        {"instrumentId": 34, "instrument": "Electric Bass", "name": "Bass", "tuning": [43, 38, 33, 28]},
        {"instrumentId": 1024, "instrument": "Drums", "name": "Drums"},
    ],
}]


def client_with_provider(provider, limit=30):
    app = create_app(Settings(search_rate_limit_per_minute=limit))
    app.state.songsterr_provider = provider
    return TestClient(app)


class FakeProvider:
    def __init__(self, result=None, error=None):
        self.result = result if result is not None else []
        self.error = error
        self.queries = []

    def search(self, query):
        self.queries.append(query)
        if self.error:
            raise self.error
        return self.result


def test_valid_search_and_instruments():
    provider = FakeProvider(normalize(SONGS))
    with client_with_provider(provider) as client:
        response = client.get("/api/v1/search/tabs", params={"q": "  Nirvana  "})
    assert response.status_code == 200
    assert provider.queries == ["Nirvana"]
    guitar, bass = response.json()["results"]
    assert guitar == {
        "artist": "Nirvana", "title": "Come As You Are", "source": "Songsterr",
        "source_id": "14", "source_url": "https://www.songsterr.com/a/wsa/song?id=14",
        "instrument": "guitar", "available_arrangements": [{"name": "Rhythm", "tuning": ["E2", "A2", "D3", "G3", "B3", "E4"]}],
        "tuning": ["E2", "A2", "D3", "G3", "B3", "E4"],
    }
    assert bass["instrument"] == "bass"
    assert bass["available_arrangements"] == [{"name": "Bass", "tuning": ["E1", "A1", "D2", "G2"]}]


def test_unknown_metadata_and_empty_results():
    result = normalize([{"id": 9, "title": "Song", "artist": {"name": "Artist"},
                         "tracks": [{"instrument": "Guitar"}, {"instrument": "Guitar", "name": "Lead", "tuning": [64, 59, 55, 50, 45, 40]}]}])
    assert result[0]["tuning"] is None
    assert result[0]["available_arrangements"][0] == {"name": None, "tuning": None}
    assert normalize([]) == []
    assert normalize([{"id": 9, "title": "Song", "artist": "Artist", "tracks": []}]) == []
    with client_with_provider(FakeProvider()) as client:
        assert client.get("/api/v1/search/tabs?q=nothing").json() == {"results": []}


def test_invalid_queries_do_not_call_provider():
    provider = FakeProvider()
    with client_with_provider(provider) as client:
        for path in ("/api/v1/search/tabs", "/api/v1/search/tabs?q=%20%20",
                     "/api/v1/search/tabs?q=a&q=b", "/api/v1/search/tabs?q=a%0Ab",
                     "/api/v1/search/tabs?q=" + "x" * 121):
            response = client.get(path)
            assert response.status_code == 422
            assert response.json()["error"]["code"] == "invalid_query"
    assert provider.queries == []


def test_provider_errors_and_timeouts():
    for error, status in ((ProviderError("provider_failure", "unavailable"), 502),
                          (ProviderError("provider_timeout", "timed out"), 504),
                          (ProviderError("malformed_provider_response", "malformed"), 502)):
        with client_with_provider(FakeProvider(error=error)) as client:
            response = client.get("/api/v1/search/tabs?q=song")
        assert response.status_code == status
        assert response.json() == {"error": {"code": error.code, "message": error.message}}


def test_malformed_songsterr_responses():
    for payload in ({}, [42], [{"songId": 1, "title": "Song"}],
                    [{"songId": 1, "title": "Song", "artist": "A", "tracks": {}}]):
        try:
            normalize(payload)
        except ProviderError as error:
            assert error.code == "malformed_provider_response"
        else:
            raise AssertionError("Malformed payload accepted")


def test_songsterr_fallback_and_upstream_failures(monkeypatch):
    real_client = httpx.Client

    def run(handler):
        monkeypatch.setattr(httpx, "Client", lambda **kwargs: real_client(transport=httpx.MockTransport(handler), **kwargs))
        return SongsterrSearchProvider(0.5).search("Song")

    paths = []

    def fallback(request):
        paths.append(request.url.path)
        return httpx.Response(404) if request.url.path.endswith("songs.json") else httpx.Response(200, json=SONGS)

    assert len(run(fallback)) == 2
    assert paths == ["/a/ra/songs.json", "/api/songs"]
    for handler, code in (
        (lambda _: httpx.Response(503), "provider_failure"),
        (lambda _: httpx.Response(200, text="not json"), "malformed_provider_response"),
        (lambda request: (_ for _ in ()).throw(httpx.ReadTimeout("slow", request=request)), "provider_timeout"),
        (lambda request: (_ for _ in ()).throw(httpx.ConnectError("offline", request=request)), "provider_failure"),
    ):
        try:
            run(handler)
        except ProviderError as error:
            assert error.code == code
        else:
            raise AssertionError("Upstream failure accepted")


def test_rate_limit_and_window():
    now = [0.0]
    limiter = RateLimiter(2, clock=lambda: now[0])
    assert limiter.allow("first")
    assert limiter.allow("first")
    assert not limiter.allow("first")
    assert limiter.allow("second")
    now[0] = 60.0
    assert limiter.allow("first")
    provider = FakeProvider()
    with client_with_provider(provider, limit=1) as client:
        assert client.get("/api/v1/search/tabs?q=a").status_code == 200
        response = client.get("/api/v1/search/tabs?q=b")
        assert response.status_code == 429
        assert response.json()["error"]["code"] == "rate_limited"
    assert provider.queries == ["a"]

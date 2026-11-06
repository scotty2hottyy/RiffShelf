import httpx
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app
from app.musicbrainz import MusicBrainzProvider, RequestPacer, USER_AGENT, normalize


REAL_CLIENT = httpx.Client
ARTIST_ID = "5b11f4ce-a62d-471e-81fc-a69a8278c7da"
RECORDING_ID = "c7c16d8f-6b67-4e60-a5ea-d201a12c00a6"
RELEASE_ID = "a1ed26f7-3f11-4633-a3c7-4a4abfa3271f"
SECOND_RELEASE_ID = "cb3d57ed-69d6-4f7d-b1bd-1b4975ba6b90"
SECOND_RECORDING_ID = "0bac4cad-3b39-4788-a3dc-bef8eb1e89e1"


def recording(recording_id=RECORDING_ID, releases=None, score=100):
    return {
        "id": recording_id, "title": "Come As You Are", "score": score,
        "artist-credit": [{"name": "Nirvana", "artist": {"id": ARTIST_ID, "name": "Nirvana"}}],
        "releases": releases if releases is not None else [
            {"id": RELEASE_ID, "title": "Nevermind", "date": "1991-09-24"}],
    }


def client_with_upstream(monkeypatch, handler):
    monkeypatch.setattr(httpx, "Client", lambda **kwargs: REAL_CLIENT(
        transport=httpx.MockTransport(handler), **kwargs))
    return TestClient(create_app(Settings()))


def test_lookup_and_openapi(monkeypatch):
    requests = []

    def upstream(request):
        requests.append(request)
        return httpx.Response(200, json={"recordings": [recording()]})

    with client_with_upstream(monkeypatch, upstream) as client:
        response = client.get("/api/v1/metadata/recordings", params={
            "artist": " Nirvana ", "title": " Come As You Are "})
        schema = client.get("/openapi.json").json()
    assert response.status_code == 200
    assert response.json() == {"recordings": [{
        "recording_id": RECORDING_ID, "artist": "Nirvana", "artist_ids": [ARTIST_ID],
        "title": "Come As You Are", "provider_confidence": 100,
        "releases": [{"release_id": RELEASE_ID, "title": "Nevermind", "date": "1991-09-24"}],
    }]}
    assert len(requests) == 1
    assert requests[0].url.host == "musicbrainz.org"
    assert requests[0].url.params["query"] == 'artistname:"Nirvana" AND recording:"Come As You Are"'
    assert requests[0].url.params["fmt"] == "json"
    assert requests[0].headers["User-Agent"] == USER_AGENT
    operation = schema["paths"]["/api/v1/metadata/recordings"]["get"]
    assert operation["tags"] == ["metadata"]
    assert {item["name"] for item in operation["parameters"]} == {"artist", "title"}
    assert all(item["required"] for item in operation["parameters"])
    assert operation["responses"]["200"]["content"]["application/json"]["schema"]
    assert {"422", "429", "502", "503", "504"} <= set(operation["responses"])


def test_ambiguous_recordings_and_releases():
    payload = {"recordings": [
        recording(releases=[
            {"id": RELEASE_ID, "title": "Nevermind", "date": "1991-09-24"},
            {"id": SECOND_RELEASE_ID, "title": "Greatest Hits"}], score=95),
        recording(recording_id=SECOND_RECORDING_ID, releases=[], score=87),
    ]}
    candidates = normalize(payload)
    assert len(candidates) == 2
    assert [item["title"] for item in candidates[0]["releases"]] == ["Nevermind", "Greatest Hits"]
    assert candidates[0]["releases"][1]["date"] is None
    assert candidates[1]["recording_id"] == SECOND_RECORDING_ID
    assert candidates[1]["releases"] == []
    assert candidates[1]["provider_confidence"] == 87


def test_empty_and_invalid_queries(monkeypatch):
    calls = []

    def upstream(request):
        calls.append(request)
        return httpx.Response(200, json={"recordings": []})

    with client_with_upstream(monkeypatch, upstream) as client:
        assert client.get("/api/v1/metadata/recordings?artist=A&title=B").json() == {"recordings": []}
        for path in (
            "/api/v1/metadata/recordings?artist=%20&title=B",
            "/api/v1/metadata/recordings?artist=A&artist=B&title=C",
            "/api/v1/metadata/recordings?artist=A&title=B%0AC",
            "/api/v1/metadata/recordings?artist=A&title=" + "x" * 121,
        ):
            response = client.get(path)
            assert response.status_code == 422
            assert response.json()["error"]["code"] == "invalid_query"
    assert len(calls) == 1


def test_malformed_rate_limited_and_network_errors(monkeypatch):
    cases = [
        (lambda _: httpx.Response(200, json={"recordings": [recording(releases={})]}), 502,
         "malformed_provider_response"),
        (lambda _: httpx.Response(200, text="bad json"), 502, "malformed_provider_response"),
        (lambda _: httpx.Response(503), 503, "provider_rate_limited"),
        (lambda _: httpx.Response(429), 503, "provider_rate_limited"),
        (lambda _: httpx.Response(500), 502, "provider_failure"),
        (lambda request: (_ for _ in ()).throw(httpx.ReadTimeout("slow", request=request)),
         504, "provider_timeout"),
        (lambda request: (_ for _ in ()).throw(httpx.ConnectError("offline", request=request)),
         502, "provider_failure"),
    ]
    for handler, status, code in cases:
        with client_with_upstream(monkeypatch, handler) as client:
            response = client.get("/api/v1/metadata/recordings?artist=A&title=B")
            health = client.get("/health")
        assert response.status_code == status
        assert response.json()["error"]["code"] == code
        assert health.status_code == 200


def test_pacing_and_search_independence(monkeypatch):
    now = [0.0]
    pacer = RequestPacer(clock=lambda: now[0])
    assert pacer.allow()
    assert not pacer.allow()
    now[0] = 1.0
    assert pacer.allow()

    real_client = httpx.Client

    def upstream(request):
        if request.url.host == "musicbrainz.org":
            return httpx.Response(503)
        return httpx.Response(200, json=[])

    monkeypatch.setattr(httpx, "Client", lambda **kwargs: real_client(
        transport=httpx.MockTransport(upstream), **kwargs))
    app = create_app()
    app.state.musicbrainz_provider = MusicBrainzProvider(1, RequestPacer(clock=lambda: 0.0))
    with TestClient(app) as client:
        assert client.get("/api/v1/metadata/recordings?artist=A&title=B").status_code == 503
        assert client.get("/api/v1/metadata/recordings?artist=A&title=C").status_code == 429
        assert client.get("/api/v1/search/tabs?q=A").json() == {"results": []}

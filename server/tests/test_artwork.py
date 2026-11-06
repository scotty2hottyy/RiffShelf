import httpx
import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app

REAL_CLIENT = httpx.Client
RELEASE = "a1ed26f7-3f11-4633-a3c7-4a4abfa3271f"


def client_with(monkeypatch, handler):
    monkeypatch.setattr(httpx, "Client", lambda **kwargs: REAL_CLIENT(
        transport=httpx.MockTransport(handler), **kwargs))
    return TestClient(create_app(Settings()))


def test_front_cover_and_unknown_rights(monkeypatch):
    def handler(request):
        assert request.url.host == "coverartarchive.org"
        return httpx.Response(200, json={"images": [{"front": True,
            "image": "http://archive.org/download/item/front.jpg",
            "thumbnails": {"250": "https://archive.org/a/250.jpg", "500": "https://archive.org/a/500.jpg"}}]})
    with client_with(monkeypatch, handler) as client:
        result = client.get(f"/api/v1/metadata/releases/{RELEASE}/artwork")
        assert client.get("/api/v1/metadata/releases/invalid/artwork").status_code == 422
    assert result.status_code == 200
    assert result.json()["artwork"] == {"image_url": "https://archive.org/download/item/front.jpg",
        "thumbnail_250": "https://archive.org/a/250.jpg", "thumbnail_500": "https://archive.org/a/500.jpg",
        "source": "Cover Art Archive", "attribution": None, "rights": None}


@pytest.mark.parametrize(("response", "status"), [
    (httpx.Response(404), 200), (httpx.Response(429), 503),
    (httpx.Response(302, headers={"location": "https://evil.example/"}), 502),
    (httpx.Response(200, json={"images": [{"front": True, "image": "https://evil.example/a", "thumbnails": {}}]}), 502),
    (httpx.Response(200, json={"images": "bad"}), 502),
])
def test_failures(monkeypatch, response, status):
    with client_with(monkeypatch, lambda request: response) as client:
        result = client.get(f"/api/v1/metadata/releases/{RELEASE}/artwork")
    assert result.status_code == status
    if status == 200:
        assert result.json() == {"artwork": None}


def test_timeout(monkeypatch):
    def handler(request):
        raise httpx.ReadTimeout("timeout", request=request)
    with client_with(monkeypatch, handler) as client:
        assert client.get(f"/api/v1/metadata/releases/{RELEASE}/artwork").status_code == 504

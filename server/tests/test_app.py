import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app


def test_startup_and_health():
    with TestClient(create_app()) as client:
        response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_development_docs_and_schema():
    with TestClient(create_app(Settings(docs_enabled=True))) as client:
        docs = client.get("/docs")
        schema = client.get("/openapi.json")
    assert docs.status_code == 200
    assert "Swagger UI" in docs.text
    assert schema.status_code == 200
    assert "/health" in schema.json()["paths"]


def test_configuration_defaults_and_overrides(monkeypatch):
    monkeypatch.delenv("RIFFSHELF_DOCS_ENABLED", raising=False)
    assert Settings.from_environment().docs_enabled is True
    monkeypatch.setenv("RIFFSHELF_DOCS_ENABLED", "false")
    with TestClient(create_app()) as client:
        assert client.get("/health").status_code == 200
        assert client.get("/docs").status_code == 404
        assert client.get("/openapi.json").status_code == 404
    monkeypatch.setenv("RIFFSHELF_DOCS_ENABLED", "TRUE")
    assert Settings.from_environment().docs_enabled is True
    monkeypatch.setenv("RIFFSHELF_DOCS_ENABLED", "invalid")
    with pytest.raises(ValueError, match="RIFFSHELF_DOCS_ENABLED"):
        Settings.from_environment()


def test_search_configuration(monkeypatch):
    monkeypatch.setenv("RIFFSHELF_SONGSTERR_TIMEOUT_SECONDS", "2.5")
    monkeypatch.setenv("RIFFSHELF_SEARCH_RATE_LIMIT_PER_MINUTE", "4")
    settings = Settings.from_environment()
    assert settings.songsterr_timeout_seconds == 2.5
    assert settings.search_rate_limit_per_minute == 4
    monkeypatch.setenv("RIFFSHELF_SONGSTERR_TIMEOUT_SECONDS", "0")
    with pytest.raises(ValueError, match="RIFFSHELF_SONGSTERR_TIMEOUT_SECONDS"):
        Settings.from_environment()
    monkeypatch.setenv("RIFFSHELF_SONGSTERR_TIMEOUT_SECONDS", "2")
    monkeypatch.setenv("RIFFSHELF_SEARCH_RATE_LIMIT_PER_MINUTE", "0")
    with pytest.raises(ValueError, match="RIFFSHELF_SEARCH_RATE_LIMIT_PER_MINUTE"):
        Settings.from_environment()

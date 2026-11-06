"""FastAPI entry point."""

from fastapi import FastAPI
from pydantic import BaseModel

from app.api.v1 import router as v1_router
from app.config import Settings
from app.api.v1.search import RateLimiter
from app.songsterr import SongsterrSearchProvider
from app.musicbrainz import MusicBrainzProvider, RequestPacer


class HealthResponse(BaseModel):
    status: str


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or Settings.from_environment()
    app = FastAPI(
        title="RiffShelf Search and Metadata API",
        version="0.1.0",
        docs_url="/docs" if settings.docs_enabled else None,
        redoc_url=None,
        openapi_url="/openapi.json" if settings.docs_enabled else None,
    )
    app.state.songsterr_provider = SongsterrSearchProvider(settings.songsterr_timeout_seconds)
    app.state.musicbrainz_provider = MusicBrainzProvider(settings.musicbrainz_timeout_seconds, RequestPacer())
    app.state.search_rate_limiter = RateLimiter(settings.search_rate_limit_per_minute)

    @app.get("/health", response_model=HealthResponse, tags=["health"])
    def health() -> HealthResponse:
        """Report whether the service is responding."""
        return HealthResponse(status="ok")

    app.include_router(v1_router)
    return app


app = create_app()

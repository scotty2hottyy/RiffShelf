"""Optional MusicBrainz recording and release candidate lookup."""

import re
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Query, Request
from pydantic import BaseModel

from app.api.v1.search import error_response
from app.musicbrainz import MusicBrainzError


router = APIRouter()


class ReleaseCandidate(BaseModel):
    release_id: str
    title: str
    date: str | None


class RecordingCandidate(BaseModel):
    recording_id: str
    artist: str
    artist_ids: list[str]
    title: str
    provider_confidence: int | None
    releases: list[ReleaseCandidate]


class MetadataResponse(BaseModel):
    recordings: list[RecordingCandidate]


@router.get(
    "/metadata/recordings", response_model=MetadataResponse, tags=["metadata"],
    summary="Find MusicBrainz recording and release candidates",
    responses={
        422: {"description": "Invalid artist or title"},
        429: {"description": "Local MusicBrainz request limit reached"},
        502: {"description": "MusicBrainz failed or returned malformed data"},
        503: {"description": "MusicBrainz rate limited the request"},
        504: {"description": "MusicBrainz timed out"},
    },
)
def lookup_recordings(
    request: Request,
    artist: Annotated[str, Query(description="Artist name to search")],
    title: Annotated[str, Query(description="Song title to search")],
):
    """Search by artist and song title; return all candidates without choosing a release."""
    values = [request.query_params.getlist(name) for name in ("artist", "title")]
    if any(len(items) != 1 or not items[0].strip() or len(items[0].strip()) > 120
           or re.search(r"[\x00-\x1f\x7f]", items[0]) for items in values):
        return error_response(422, "invalid_query", "Provide one nonempty artist and title, each at most 120 characters without control characters.")
    try:
        return {"recordings": request.app.state.musicbrainz_provider.lookup(
            artist.strip(), title.strip())}
    except MusicBrainzError as error:
        status = {"rate_limited": 429, "provider_rate_limited": 503,
                  "provider_timeout": 504}.get(error.code, 502)
        return error_response(status, error.code, error.message)


@router.get("/metadata/releases/{release_id}/artwork", tags=["metadata"],
            summary="Find front-cover artwork for a MusicBrainz release")
def lookup_artwork(request: Request, release_id: UUID):
    """Return artwork metadata or null when no front cover is available."""
    try:
        return request.app.state.artwork_provider.lookup(str(release_id))
    except MusicBrainzError as error:
        status = {"provider_rate_limited": 503, "provider_timeout": 504}.get(error.code, 502)
        return error_response(status, error.code, error.message)

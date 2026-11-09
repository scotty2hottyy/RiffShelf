"""MusicBrainz recording search and release candidate normalization."""

import re
import threading
import time
from uuid import UUID

import httpx


BASE_URL = "https://musicbrainz.org/ws/2/recording/"
USER_AGENT = "RiffShelf/0.1.0 (https://github.com/scotty2hottyy/RiffShelf)"
_LUCENE_SPECIAL = re.compile(r'([+\-!(){}\[\]^"~*?:\\/\\])')


class MusicBrainzError(Exception):
    def __init__(self, code: str, message: str):
        self.code = code
        self.message = message
        super().__init__(message)


class RequestPacer:
    """Allow at most one outbound request per second per process."""

    def __init__(self, clock=time.monotonic):
        self.clock = clock
        self.next_request = 0.0
        self.lock = threading.Lock()

    def allow(self) -> bool:
        with self.lock:
            now = self.clock()
            if now < self.next_request:
                return False
            self.next_request = now + 1.0
            return True


def _mbid(value: object) -> str:
    if not isinstance(value, str):
        raise ValueError("Missing MusicBrainz ID")
    return str(UUID(value))


def _name(value: object) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError("Missing name")
    return value.strip()


def _escape_query(value: str) -> str:
    return _LUCENE_SPECIAL.sub(r"\\\1", value)


def _artist_credit(value: object) -> tuple[str, list[str]]:
    if not isinstance(value, list) or not value:
        raise ValueError("Missing artist credit")
    parts = []
    artist_ids = []
    for part in value:
        if isinstance(part, str):
            parts.append(part)
        elif isinstance(part, dict):
            parts.append(_name(part.get("name")))
            artist = part.get("artist")
            if not isinstance(artist, dict):
                raise ValueError("Missing artist")
            artist_ids.append(_mbid(artist.get("id")))
        else:
            raise ValueError("Invalid artist credit")
    return _name("".join(parts)), artist_ids


def normalize(payload: object) -> list[dict]:
    try:
        if not isinstance(payload, dict) or not isinstance(payload.get("recordings"), list):
            raise ValueError("Missing recordings")
        results = []
        for recording in payload["recordings"]:
            if not isinstance(recording, dict):
                raise ValueError("Invalid recording")
            artist, artist_ids = _artist_credit(recording.get("artist-credit"))
            score = recording.get("score")
            if score is not None:
                score = int(score)
                if not 0 <= score <= 100:
                    raise ValueError("Invalid score")
            releases = recording.get("releases", [])
            if not isinstance(releases, list):
                raise ValueError("Invalid releases")
            normalized_releases = []
            for release in releases:
                if not isinstance(release, dict):
                    raise ValueError("Invalid release")
                date = release.get("date")
                if date is not None and (not isinstance(date, str) or not re.fullmatch(
                    r"\d{4}(?:-\d{2})?(?:-\d{2})?", date
                )):
                    raise ValueError("Invalid release date")
                normalized_releases.append({
                    "release_id": _mbid(release.get("id")),
                    "title": _name(release.get("title")),
                    "date": date,
                })
            results.append({
                "recording_id": _mbid(recording.get("id")),
                "artist": artist,
                "artist_ids": artist_ids,
                "title": _name(recording.get("title")),
                "provider_confidence": score,
                "releases": normalized_releases,
            })
        return results
    except (TypeError, ValueError) as error:
        raise MusicBrainzError("malformed_provider_response", "MusicBrainz returned malformed metadata.") from error


class MusicBrainzProvider:
    def __init__(self, timeout_seconds: float, pacer: RequestPacer):
        self.timeout_seconds = timeout_seconds
        self.pacer = pacer

    def lookup(self, artist: str, title: str) -> list[dict]:
        if not self.pacer.allow():
            raise MusicBrainzError("rate_limited", "MusicBrainz request rate exceeded. Try again shortly.")
        query = f'artistname:"{_escape_query(artist)}" AND recording:"{_escape_query(title)}"'
        try:
            with httpx.Client(timeout=self.timeout_seconds, follow_redirects=False,
                              headers={"User-Agent": USER_AGENT, "Accept": "application/json"}) as client:
                response = client.get(BASE_URL, params={"query": query, "fmt": "json", "limit": 25})
            if response.status_code in (429, 503):
                raise MusicBrainzError("provider_rate_limited", "MusicBrainz is busy. Try again shortly.")
            if not response.is_success:
                raise MusicBrainzError("provider_failure", "MusicBrainz metadata is unavailable.")
            try:
                return normalize(response.json())
            except ValueError as error:
                raise MusicBrainzError("malformed_provider_response", "MusicBrainz returned malformed metadata.") from error
        except httpx.TimeoutException as error:
            raise MusicBrainzError("provider_timeout", "MusicBrainz metadata timed out.") from error
        except httpx.RequestError as error:
            raise MusicBrainzError("provider_failure", "MusicBrainz metadata is unavailable.") from error

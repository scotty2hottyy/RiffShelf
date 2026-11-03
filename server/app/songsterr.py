"""Songsterr search adapter. Search metadata only; no tablature is downloaded."""

import re

import httpx


BASE_URL = "https://www.songsterr.com"


class ProviderError(Exception):
    def __init__(self, code: str, message: str):
        self.code = code
        self.message = message
        super().__init__(message)


def _instrument(track: dict) -> str | None:
    instrument_id = track.get("instrumentId")
    if isinstance(instrument_id, int) and not isinstance(instrument_id, bool):
        if 24 <= instrument_id <= 31:
            return "guitar"
        if 32 <= instrument_id <= 39:
            return "bass"
        return None
    label = track.get("instrument") or track.get("name") or track.get("title")
    if isinstance(label, str):
        label = label.lower()
        if "guitar" in label:
            return "guitar"
        if re.search(r"\bbass\b", label):
            return "bass"
    return None


def _tuning(track: dict) -> list[str] | None:
    value = track.get("tuning")
    if not isinstance(value, list) or not value or any(
        not isinstance(note, int) or isinstance(note, bool) or not 0 <= note <= 127
        for note in value
    ):
        return None
    names = ("C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B")
    return [f"{names[note % 12]}{note // 12 - 1}" for note in reversed(value)]


def normalize(payload: object) -> list[dict]:
    if not isinstance(payload, list):
        raise ProviderError("malformed_provider_response", "Songsterr returned malformed search results.")
    results = []
    for song in payload:
        if not isinstance(song, dict):
            raise ProviderError("malformed_provider_response", "Songsterr returned malformed search results.")
        song_id = song.get("id", song.get("songId"))
        title = song.get("title")
        artist = song.get("artist")
        if isinstance(artist, dict):
            artist = artist.get("name")
        if (isinstance(song_id, bool) or not re.fullmatch(r"[0-9]+", str(song_id))
                or not isinstance(title, str) or not title.strip()
                or not isinstance(artist, str) or not artist.strip()):
            raise ProviderError("malformed_provider_response", "Songsterr returned malformed search results.")
        tracks = song.get("tracks", [])
        if not isinstance(tracks, list) or any(not isinstance(track, dict) for track in tracks):
            raise ProviderError("malformed_provider_response", "Songsterr returned malformed search results.")
        grouped = {"guitar": [], "bass": []}
        for track in tracks:
            kind = _instrument(track)
            if kind:
                name = track.get("name")
                grouped[kind].append({
                    "name": name.strip() if isinstance(name, str) and name.strip() else None,
                    "tuning": _tuning(track),
                })
        # A default track is only useful when it contains an instrument label,
        # not when it is an index into missing track metadata.
        default = song.get("defaultTrack")
        if isinstance(default, dict) and not any(grouped.values()):
            kind = _instrument(default)
            if kind:
                grouped[kind].append({"name": None, "tuning": _tuning(default)})
        for kind, arrangements in grouped.items():
            if not arrangements:
                continue
            tunings = [item["tuning"] for item in arrangements]
            tuning = tunings[0] if all(item == tunings[0] for item in tunings) else None
            results.append({
                "artist": artist.strip(), "title": title.strip(),
                "source": "Songsterr", "source_id": str(song_id),
                "source_url": f"{BASE_URL}/a/wsa/song?id={song_id}",
                "instrument": kind, "available_arrangements": arrangements,
                "tuning": tuning,
            })
    return results


class SongsterrSearchProvider:
    def __init__(self, timeout_seconds: float):
        self.timeout_seconds = timeout_seconds

    def search(self, query: str) -> list[dict]:
        try:
            with httpx.Client(timeout=self.timeout_seconds, follow_redirects=True) as client:
                response = client.get(f"{BASE_URL}/a/ra/songs.json", params={"pattern": query})
                if not response.is_success:
                    response = client.get(f"{BASE_URL}/api/songs", params={"pattern": query, "size": "50"})
            if not response.is_success:
                raise ProviderError("provider_failure", "Songsterr search is unavailable.")
            try:
                return normalize(response.json())
            except ValueError as error:
                raise ProviderError("malformed_provider_response", "Songsterr returned malformed search results.") from error
        except httpx.TimeoutException as error:
            raise ProviderError("provider_timeout", "Songsterr search timed out.") from error
        except httpx.RequestError as error:
            raise ProviderError("provider_failure", "Songsterr search is unavailable.") from error

"""Cover Art Archive front-cover metadata, with a strict URL allowlist."""
from urllib.parse import urlsplit, urlunsplit

import httpx

from app.musicbrainz import MusicBrainzError, USER_AGENT


def artwork_url(value):
    if not isinstance(value, str):
        raise ValueError("Invalid artwork URL")
    url = urlsplit(value)
    # Validate scheme
    if url.scheme not in {"http", "https"}:
        raise ValueError("Untrusted artwork URL")
    # Validate hostname against allowlist
    if url.hostname not in {"coverartarchive.org", "archive.org"} and \
            not (url.hostname or "").endswith(".archive.org"):
        raise ValueError("Untrusted artwork URL")
    # Reject URLs with authentication, non-standard ports, or fragments
    if url.username or url.password or url.port not in (None, 80, 443) or url.fragment:
        raise ValueError("Untrusted artwork URL")
    return urlunsplit(("https", url.hostname, url.path, url.query, ""))


class ArtworkProvider:
    def __init__(self, timeout_seconds):
        self.timeout_seconds = timeout_seconds

    def lookup(self, release_id):
        try:
            with httpx.Client(timeout=self.timeout_seconds, follow_redirects=False,
                              headers={"User-Agent": USER_AGENT, "Accept": "application/json"}) as client:
                response = client.get(f"https://coverartarchive.org/release/{release_id}")
            if response.status_code == 404:
                return {"artwork": None}
            if response.status_code in (429, 503):
                raise MusicBrainzError("provider_rate_limited", "Artwork provider is busy. Try again shortly.")
            if not response.is_success:
                raise MusicBrainzError("provider_failure", "Artwork is unavailable.")
            payload = response.json()
            if not isinstance(payload, dict) or not isinstance(payload.get("images"), list):
                raise ValueError("Missing images")
            for image in payload["images"]:
                if not isinstance(image, dict) or not isinstance(image.get("front"), bool):
                    raise ValueError("Invalid image")
                if not image["front"]:
                    continue
                thumbnails = image.get("thumbnails")
                if not isinstance(thumbnails, dict):
                    raise ValueError("Invalid thumbnails")
                return {"artwork": {"image_url": artwork_url(image.get("image")),
                    "thumbnail_250": artwork_url(thumbnails["250"]) if thumbnails.get("250") else None,
                    "thumbnail_500": artwork_url(thumbnails["500"]) if thumbnails.get("500") else None,
                    "source": "Cover Art Archive", "attribution": None, "rights": None}}
            return {"artwork": None}
        except (ValueError, TypeError, KeyError) as error:
            raise MusicBrainzError("malformed_provider_response", "Artwork provider returned malformed metadata.") from error
        except httpx.TimeoutException as error:
            raise MusicBrainzError("provider_timeout", "Artwork lookup timed out.") from error
        except httpx.RequestError as error:
            raise MusicBrainzError("provider_failure", "Artwork is unavailable.") from error

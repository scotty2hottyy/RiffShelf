"""Public search endpoint and a process-local per-address rate limit."""

import re
import threading
import time
from collections import defaultdict, deque

from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from app.songsterr import ProviderError


router = APIRouter()


class Arrangement(BaseModel):
    name: str | None
    tuning: list[str] | None


class TabResult(BaseModel):
    artist: str
    title: str
    source: str
    source_id: str
    source_url: str
    instrument: str
    available_arrangements: list[Arrangement]
    tuning: list[str] | None


class SearchResponse(BaseModel):
    results: list[TabResult]


class RateLimiter:
    def __init__(self, limit: int, clock=time.monotonic):
        self.limit = limit
        self.clock = clock
        self.events = defaultdict(deque)
        self.lock = threading.Lock()

    def allow(self, address: str) -> bool:
        now = self.clock()
        with self.lock:
            # Bounded by active addresses seen in the past minute.
            for key in list(self.events):
                events = self.events[key]
                while events and now - events[0] >= 60:
                    events.popleft()
                if not events:
                    del self.events[key]
            events = self.events[address]
            if len(events) >= self.limit:
                return False
            events.append(now)
            return True


def error_response(status: int, code: str, message: str) -> JSONResponse:
    return JSONResponse(status_code=status, content={"error": {"code": code, "message": message}})


@router.get("/search/tabs", response_model=SearchResponse, tags=["search"])
def search_tabs(request: Request):
    values = request.query_params.getlist("q")
    if len(values) != 1 or not values[0].strip():
        return error_response(422, "invalid_query", "Provide one nonempty q parameter.")
    query = values[0].strip()
    if len(query) > 120 or re.search(r"[\x00-\x1f\x7f]", values[0]):
        return error_response(422, "invalid_query", "q must be at most 120 characters without control characters.")
    address = request.client.host if request.client else "unknown"
    if not request.app.state.search_rate_limiter.allow(address):
        return error_response(429, "rate_limited", "Search rate limit exceeded. Try again in one minute.")
    try:
        return {"results": request.app.state.songsterr_provider.search(query)}
    except ProviderError as error:
        return error_response(504 if error.code == "provider_timeout" else 502,
                              error.code, error.message)

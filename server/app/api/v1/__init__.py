"""Version 1 API router."""

from fastapi import APIRouter
from app.api.v1.search import router as search_router

router = APIRouter(prefix="/api/v1")

router.include_router(search_router)

"""Version 1 API router."""

from fastapi import APIRouter

router = APIRouter(prefix="/api/v1")

from app.api.v1.search import router as search_router

router.include_router(search_router)

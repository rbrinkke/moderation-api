from fastapi import APIRouter, Depends, HTTPException, Query, Request
from slowapi import Limiter
from slowapi.util import get_remote_address
from typing import Optional
from datetime import datetime
import asyncpg
import json

from app.services.database import db
from app.middleware.auth import require_admin
from app.utils.errors import map_sp_error_to_http
import structlog

logger = structlog.get_logger()
router = APIRouter(prefix="", tags=["statistics"])
limiter = Limiter(key_func=get_remote_address)

@router.get("/statistics", response_model=dict)
@limiter.limit("100/minute")
async def get_moderation_statistics(
    request: Request,
    date_from: Optional[datetime] = Query(None),
    date_to: Optional[datetime] = Query(None),
    admin: dict = Depends(require_admin)
):
    """Get overall moderation statistics for admin dashboard"""
    try:
        result = await db.fetch_one(
            "SELECT activity.sp_mod_get_statistics($1, $2, $3)",
            admin["user_id"],
            date_from,
            date_to
        )

        # Parse JSON result from stored procedure
        data = json.loads(result[0])

        logger.info("statistics_fetched", admin_id=admin["user_id"])
        return data

    except asyncpg.PostgresError as e:
        status_code, message = map_sp_error_to_http(str(e))
        logger.error("get_statistics_failed", error=message, admin_id=admin["user_id"])
        raise HTTPException(status_code=status_code, detail=message)

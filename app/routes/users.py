from fastapi import APIRouter, Depends, HTTPException, Request
from slowapi import Limiter
from slowapi.util import get_remote_address
import asyncpg
import json

from app.models.requests import BanUserRequest, UnbanUserRequest
from app.models.responses import BanUserResponse, UnbanUserResponse
from app.services.database import db
from app.services.email import email_client
from app.middleware.auth import require_admin
from app.utils.errors import map_sp_error_to_http
import structlog

logger = structlog.get_logger()
router = APIRouter(prefix="", tags=["users"])
limiter = Limiter(key_func=get_remote_address)

@router.post("/users/{user_id}/ban", response_model=BanUserResponse)
@limiter.limit("50/minute")
async def ban_user(
    request: Request,
    user_id: str,
    ban_request: BanUserRequest,
    admin: dict = Depends(require_admin)
):
    """Ban or temporarily ban a user"""
    try:
        result = await db.fetch_one(
            "SELECT activity.sp_mod_ban_user($1, $2, $3, $4, $5)",
            admin["user_id"],
            user_id,
            ban_request.ban_type,
            ban_request.ban_duration_hours,
            ban_request.ban_reason
        )

        # Parse JSON result from stored procedure
        data = json.loads(result[0])

        # Send ban notification email
        user_email = data.get("email")  # Assume SP returns email
        username = data.get("username")  # Assume SP returns username

        if user_email:
            await email_client.send_email(
                to=user_email,
                template="user_banned",
                context={
                    "username": username or "User",
                    "ban_type": ban_request.ban_type,
                    "ban_expires_at": data.get("ban_expires_at"),
                    "ban_reason": ban_request.ban_reason
                }
            )

        logger.info("user_banned", user_id=user_id, ban_type=ban_request.ban_type, admin_id=admin["user_id"])
        return BanUserResponse(**data)

    except asyncpg.PostgresError as e:
        status_code, message = map_sp_error_to_http(str(e))
        logger.error("ban_user_failed", error=message, user_id=user_id, admin_id=admin["user_id"])
        raise HTTPException(status_code=status_code, detail=message)

@router.post("/users/{user_id}/unban", response_model=UnbanUserResponse)
@limiter.limit("50/minute")
async def unban_user(
    request: Request,
    user_id: str,
    unban_request: UnbanUserRequest,
    admin: dict = Depends(require_admin)
):
    """Remove ban from a user"""
    try:
        result = await db.fetch_one(
            "SELECT activity.sp_mod_unban_user($1, $2, $3)",
            admin["user_id"],
            user_id,
            unban_request.unban_reason
        )

        # Parse JSON result from stored procedure
        data = json.loads(result[0])

        # Send unban notification email
        user_email = data.get("email")  # Assume SP returns email
        username = data.get("username")  # Assume SP returns username

        if user_email:
            await email_client.send_email(
                to=user_email,
                template="user_unbanned",
                context={
                    "username": username or "User",
                    "unban_reason": unban_request.unban_reason
                }
            )

        logger.info("user_unbanned", user_id=user_id, admin_id=admin["user_id"])
        return UnbanUserResponse(**data)

    except asyncpg.PostgresError as e:
        status_code, message = map_sp_error_to_http(str(e))
        logger.error("unban_user_failed", error=message, user_id=user_id, admin_id=admin["user_id"])
        raise HTTPException(status_code=status_code, detail=message)

@router.get("/users/{user_id}/history", response_model=dict)
@limiter.limit("100/minute")
async def get_user_moderation_history(
    request: Request,
    user_id: str,
    admin: dict = Depends(require_admin)
):
    """Get complete moderation history for a user"""
    try:
        result = await db.fetch_one(
            "SELECT activity.sp_mod_get_user_moderation_history($1, $2)",
            admin["user_id"],
            user_id
        )

        # Parse JSON result from stored procedure
        data = json.loads(result[0])

        logger.info("user_history_fetched", user_id=user_id, admin_id=admin["user_id"])
        return data

    except asyncpg.PostgresError as e:
        status_code, message = map_sp_error_to_http(str(e))
        logger.error("get_user_history_failed", error=message, user_id=user_id, admin_id=admin["user_id"])
        raise HTTPException(status_code=status_code, detail=message)

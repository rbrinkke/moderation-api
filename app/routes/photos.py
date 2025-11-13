from fastapi import APIRouter, Depends, HTTPException, Query, Request
from slowapi import Limiter
from slowapi.util import get_remote_address
import asyncpg
import json

from app.models.requests import ModeratePhotoRequest
from app.models.responses import GetPendingPhotosResponse, ModeratePhotoResponse, PendingPhoto
from app.services.database import db
from app.services.email import email_client
from app.middleware.auth import require_admin
from app.utils.errors import map_sp_error_to_http
import structlog

logger = structlog.get_logger()
router = APIRouter(prefix="", tags=["photos"])
limiter = Limiter(key_func=get_remote_address)

@router.get("/photos/pending", response_model=GetPendingPhotosResponse)
@limiter.limit("100/minute")
async def get_pending_photos(
    request: Request,
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
    admin: dict = Depends(require_admin)
):
    """Get list of users with pending main photo moderation"""
    try:
        photos = await db.fetch_all(
            "SELECT * FROM activity.sp_mod_get_pending_photos($1, $2, $3)",
            admin["user_id"],
            limit,
            offset
        )

        # Convert asyncpg.Record to PendingPhoto objects
        pending_photos_list = [
            PendingPhoto(
                user_id=row["user_id"],
                username=row["username"],
                email=row["email"],
                main_photo_url=row["main_photo_url"],
                created_at=row["created_at"],
                updated_at=row["updated_at"]
            )
            for row in photos
        ]

        return GetPendingPhotosResponse(
            success=True,
            pending_photos=pending_photos_list,
            pagination={"limit": limit, "offset": offset, "total": len(pending_photos_list)}
        )

    except asyncpg.PostgresError as e:
        status_code, message = map_sp_error_to_http(str(e))
        logger.error("get_pending_photos_failed", error=message, admin_id=admin["user_id"])
        raise HTTPException(status_code=status_code, detail=message)

@router.post("/photos/moderate", response_model=ModeratePhotoResponse)
@limiter.limit("100/minute")
async def moderate_photo(
    request: Request,
    photo_request: ModeratePhotoRequest,
    admin: dict = Depends(require_admin)
):
    """Approve or reject a user's main profile photo"""
    try:
        result = await db.fetch_one(
            "SELECT activity.sp_mod_moderate_main_photo($1, $2, $3, $4)",
            admin["user_id"],
            str(photo_request.user_id),
            photo_request.moderation_status,
            photo_request.rejection_reason
        )

        # Parse JSON result from stored procedure
        data = json.loads(result[0])

        # Send email notification if rejected
        if photo_request.moderation_status == "rejected" and photo_request.rejection_reason:
            # Get user email from result
            user_email = data.get("email")  # Assume SP returns email
            username = data.get("username")  # Assume SP returns username

            if user_email:
                await email_client.send_email(
                    to=user_email,
                    template="photo_rejected",
                    context={
                        "username": username or "User",
                        "rejection_reason": photo_request.rejection_reason
                    }
                )

        logger.info("photo_moderated", user_id=str(photo_request.user_id), status=photo_request.moderation_status, admin_id=admin["user_id"])
        return ModeratePhotoResponse(**data)

    except asyncpg.PostgresError as e:
        status_code, message = map_sp_error_to_http(str(e))
        logger.error("moderate_photo_failed", error=message, user_id=str(photo_request.user_id), admin_id=admin["user_id"])
        raise HTTPException(status_code=status_code, detail=message)

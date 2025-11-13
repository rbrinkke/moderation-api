from fastapi import APIRouter, Depends, HTTPException, Request
from slowapi import Limiter
from slowapi.util import get_remote_address
import asyncpg
import json

from app.models.requests import RemoveContentRequest
from app.models.responses import RemoveContentResponse
from app.services.database import db
from app.services.email import email_client
from app.middleware.auth import require_admin
from app.utils.errors import map_sp_error_to_http
import structlog

logger = structlog.get_logger()
router = APIRouter(prefix="", tags=["content"])
limiter = Limiter(key_func=get_remote_address)

@router.post("/content/remove", response_model=RemoveContentResponse)
@limiter.limit("100/minute")
async def remove_content(
    request: Request,
    content_request: RemoveContentRequest,
    admin: dict = Depends(require_admin)
):
    """Remove or hide problematic content (posts, comments)"""
    try:
        result = await db.fetch_one(
            "SELECT activity.sp_mod_remove_content($1, $2, $3, $4)",
            admin["user_id"],
            content_request.content_type,
            str(content_request.content_id),
            content_request.removal_reason
        )

        # Parse JSON result from stored procedure
        data = json.loads(result[0])

        # Send content removal notification to author
        author_email = data.get("author_email")  # Assume SP returns author email
        author_username = data.get("author_username")  # Assume SP returns author username

        if author_email:
            await email_client.send_email(
                to=author_email,
                template="content_removed",
                context={
                    "username": author_username or "User",
                    "content_type": content_request.content_type,
                    "removal_reason": content_request.removal_reason
                }
            )

        logger.info("content_removed", content_type=content_request.content_type, content_id=str(content_request.content_id), admin_id=admin["user_id"])
        return RemoveContentResponse(**data)

    except asyncpg.PostgresError as e:
        status_code, message = map_sp_error_to_http(str(e))
        logger.error("remove_content_failed", error=message, content_id=str(content_request.content_id), admin_id=admin["user_id"])
        raise HTTPException(status_code=status_code, detail=message)

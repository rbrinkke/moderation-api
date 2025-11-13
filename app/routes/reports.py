from fastapi import APIRouter, Depends, HTTPException, Query, Request
from slowapi import Limiter
from slowapi.util import get_remote_address
from typing import Optional
import asyncpg
import json

from app.models.requests import CreateReportRequest, UpdateReportStatusRequest
from app.models.responses import CreateReportResponse, GetReportsResponse, SuccessResponse
from app.services.database import db
from app.middleware.auth import get_current_user, require_admin
from app.utils.errors import map_sp_error_to_http
import structlog

logger = structlog.get_logger()
router = APIRouter(prefix="", tags=["reports"])
limiter = Limiter(key_func=get_remote_address)

@router.post("/reports", response_model=CreateReportResponse, status_code=201)
@limiter.limit("10/minute")
async def create_report(
    request: Request,
    report_request: CreateReportRequest,
    current_user: dict = Depends(get_current_user)
):
    """Create a new report for problematic content or behavior"""
    try:
        result = await db.fetch_one(
            "SELECT * FROM activity.sp_mod_create_report($1, $2, $3, $4, $5, $6)",
            current_user["user_id"],
            None,  # reported_user_id (SP determines this)
            report_request.target_type,
            str(report_request.target_id),
            report_request.report_type,
            report_request.description
        )

        # Parse JSON result from stored procedure
        data = json.loads(result[0])

        logger.info("report_created", report_id=data["report_id"], user_id=current_user["user_id"])
        return CreateReportResponse(**data)

    except asyncpg.PostgresError as e:
        status_code, message = map_sp_error_to_http(str(e))
        logger.error("create_report_failed", error=message, user_id=current_user["user_id"])
        raise HTTPException(status_code=status_code, detail=message)

@router.get("/reports", response_model=GetReportsResponse)
@limiter.limit("100/minute")
async def get_reports(
    request: Request,
    status: Optional[str] = Query(None, pattern="^(pending|reviewing|resolved|dismissed)$"),
    target_type: Optional[str] = Query(None, pattern="^(user|post|comment|activity|community)$"),
    report_type: Optional[str] = Query(None, pattern="^(spam|harassment|inappropriate|fake|no_show|other)$"),
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
    admin: dict = Depends(require_admin)
):
    """Get reports with filtering (admin only)"""
    try:
        reports = await db.fetch_all(
            "SELECT * FROM activity.sp_mod_get_reports($1, $2, $3, $4, $5, $6)",
            admin["user_id"],
            status,
            target_type,
            report_type,
            limit,
            offset
        )

        # Convert asyncpg.Record to dict
        reports_list = []
        for r in reports:
            report_dict = dict(r)
            # Convert report to proper format with nested objects
            report_formatted = {
                "report_id": report_dict["report_id"],
                "reporter": {
                    "user_id": report_dict["reporter_user_id"],
                    "username": report_dict["reporter_username"],
                    "email": report_dict["reporter_email"]
                },
                "reported_user": {
                    "user_id": report_dict["reported_user_id"],
                    "username": report_dict["reported_username"],
                    "email": report_dict["reported_email"]
                } if report_dict.get("reported_user_id") else None,
                "target_type": report_dict["target_type"],
                "target_id": report_dict["target_id"],
                "report_type": report_dict["report_type"],
                "description": report_dict.get("description"),
                "status": report_dict["status"],
                "created_at": report_dict["created_at"],
                "updated_at": report_dict["updated_at"]
            }
            reports_list.append(report_formatted)

        return GetReportsResponse(
            success=True,
            reports=reports_list,
            pagination={"limit": limit, "offset": offset, "total": len(reports_list)}
        )

    except asyncpg.PostgresError as e:
        status_code, message = map_sp_error_to_http(str(e))
        logger.error("get_reports_failed", error=message, admin_id=admin["user_id"])
        raise HTTPException(status_code=status_code, detail=message)

@router.get("/reports/{report_id}", response_model=dict)
@limiter.limit("100/minute")
async def get_report_by_id(
    request: Request,
    report_id: str,
    admin: dict = Depends(require_admin)
):
    """Get detailed information for a specific report"""
    try:
        result = await db.fetch_one(
            "SELECT activity.sp_mod_get_report_by_id($1, $2)",
            admin["user_id"],
            report_id
        )

        # Parse JSON result from stored procedure
        data = json.loads(result[0])

        logger.info("report_fetched", report_id=report_id, admin_id=admin["user_id"])
        return data

    except asyncpg.PostgresError as e:
        status_code, message = map_sp_error_to_http(str(e))
        logger.error("get_report_failed", error=message, report_id=report_id, admin_id=admin["user_id"])
        raise HTTPException(status_code=status_code, detail=message)

@router.patch("/reports/{report_id}/status", response_model=dict)
@limiter.limit("100/minute")
async def update_report_status(
    request: Request,
    report_id: str,
    status_request: UpdateReportStatusRequest,
    admin: dict = Depends(require_admin)
):
    """Update report status and add resolution notes"""
    try:
        result = await db.fetch_one(
            "SELECT activity.sp_mod_update_report_status($1, $2, $3, $4)",
            admin["user_id"],
            report_id,
            status_request.status,
            status_request.resolution_notes
        )

        # Parse JSON result from stored procedure
        data = json.loads(result[0])

        logger.info("report_status_updated", report_id=report_id, new_status=status_request.status, admin_id=admin["user_id"])
        return data

    except asyncpg.PostgresError as e:
        status_code, message = map_sp_error_to_http(str(e))
        logger.error("update_report_status_failed", error=message, report_id=report_id, admin_id=admin["user_id"])
        raise HTTPException(status_code=status_code, detail=message)

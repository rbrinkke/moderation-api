from pydantic import BaseModel, UUID4
from typing import Optional, List, Dict, Any
from datetime import datetime

# Report responses
class CreateReportResponse(BaseModel):
    success: bool
    report_id: UUID4
    status: str
    created_at: datetime

class ReporterInfo(BaseModel):
    user_id: UUID4
    username: str
    email: str

class ReportResponse(BaseModel):
    report_id: UUID4
    reporter: ReporterInfo
    reported_user: Optional[ReporterInfo]
    target_type: str
    target_id: UUID4
    report_type: str
    description: Optional[str]
    status: str
    created_at: datetime
    updated_at: datetime

class GetReportsResponse(BaseModel):
    success: bool
    reports: List[ReportResponse]
    pagination: Dict[str, Any]

# Photo moderation responses
class PendingPhoto(BaseModel):
    user_id: UUID4
    username: str
    email: str
    main_photo_url: str
    created_at: datetime
    updated_at: datetime

class GetPendingPhotosResponse(BaseModel):
    success: bool
    pending_photos: List[PendingPhoto]
    pagination: Dict[str, Any]

class ModeratePhotoResponse(BaseModel):
    success: bool
    user_id: UUID4
    main_photo_url: str
    moderation_status: str
    moderated_at: datetime

# Ban responses
class BanUserResponse(BaseModel):
    success: bool
    user_id: UUID4
    status: str
    ban_expires_at: Optional[datetime]
    ban_reason: str
    banned_at: datetime

class UnbanUserResponse(BaseModel):
    success: bool
    user_id: UUID4
    status: str
    unbanned_at: datetime
    unbanned_by_user_id: UUID4

# Content removal response
class RemoveContentResponse(BaseModel):
    success: bool
    content_type: str
    content_id: UUID4
    status: str
    removed_at: datetime
    removed_by_user_id: UUID4

# Generic response
class SuccessResponse(BaseModel):
    success: bool
    message: Optional[str] = None

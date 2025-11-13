from pydantic import BaseModel, Field, UUID4
from typing import Optional
from datetime import datetime

# Report models
class CreateReportRequest(BaseModel):
    target_type: str = Field(..., pattern="^(user|post|comment|activity|community)$")
    target_id: UUID4
    report_type: str = Field(..., pattern="^(spam|harassment|inappropriate|fake|no_show|other)$")
    description: Optional[str] = Field(None, max_length=2000)

class UpdateReportStatusRequest(BaseModel):
    status: str = Field(..., pattern="^(reviewing|resolved|dismissed)$")
    resolution_notes: Optional[str] = Field(None, max_length=2000)

# Photo moderation models
class ModeratePhotoRequest(BaseModel):
    user_id: UUID4
    moderation_status: str = Field(..., pattern="^(approved|rejected)$")
    rejection_reason: Optional[str] = Field(None, max_length=500)

# Ban models
class BanUserRequest(BaseModel):
    ban_type: str = Field(..., pattern="^(permanent|temporary)$")
    ban_duration_hours: Optional[int] = Field(None, gt=0)
    ban_reason: str = Field(..., max_length=1000)

class UnbanUserRequest(BaseModel):
    unban_reason: str = Field(..., max_length=1000)

# Content removal models
class RemoveContentRequest(BaseModel):
    content_type: str = Field(..., pattern="^(post|comment)$")
    content_id: UUID4
    removal_reason: str = Field(..., max_length=1000)

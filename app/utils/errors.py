from fastapi import HTTPException
from typing import Dict

# Error code to HTTP status mapping
ERROR_CODE_MAPPING: Dict[str, int] = {
    # 400 Bad Request
    'INVALID_TARGET_TYPE': 400,
    'INVALID_REPORT_TYPE': 400,
    'INVALID_STATUS': 400,
    'INVALID_MODERATION_STATUS': 400,
    'INVALID_BAN_TYPE': 400,
    'INVALID_DURATION': 400,
    'INVALID_CONTENT_TYPE': 400,
    'INVALID_STATUS_TRANSITION': 400,
    'INVALID_DATE_RANGE': 400,
    'DURATION_REQUIRED': 400,
    'USER_ALREADY_BANNED': 400,
    'USER_NOT_BANNED': 400,
    'CONTENT_ALREADY_REMOVED': 400,
    'NO_MAIN_PHOTO': 400,
    'CANNOT_SELF_REPORT': 400,
    'CANNOT_SELF_BAN': 400,

    # 403 Forbidden
    'INSUFFICIENT_PERMISSIONS': 403,
    'ADMIN_INACTIVE': 403,

    # 404 Not Found
    'REPORTER_NOT_FOUND': 404,
    'ADMIN_NOT_FOUND': 404,
    'USER_NOT_FOUND': 404,
    'TARGET_NOT_FOUND': 404,
    'REPORT_NOT_FOUND': 404,
    'CONTENT_NOT_FOUND': 404,

    # 409 Conflict
    'DUPLICATE_REPORT': 409,
}

def map_sp_error_to_http(error_message: str) -> tuple[int, str]:
    """
    Map stored procedure error to HTTP status code.

    Args:
        error_message: Error message from PostgreSQL (format: "ERROR_CODE: message")

    Returns:
        Tuple of (status_code, error_message)
    """
    # Extract error code (before colon)
    error_code = error_message.split(':')[0].strip() if ':' in error_message else error_message.strip()

    # Look up status code
    status_code = ERROR_CODE_MAPPING.get(error_code, 500)

    return status_code, error_message

class AppException(HTTPException):
    """Base exception for application errors"""
    pass

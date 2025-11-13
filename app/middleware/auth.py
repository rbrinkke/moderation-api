from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import jwt, JWTError
from app.config import settings
from app.services.database import db
import structlog

logger = structlog.get_logger()
security = HTTPBearer()

async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security)
) -> dict:
    """
    Extract and validate user from JWT token.
    Fetches user details from database since auth-api JWTs contain minimal claims.

    Returns:
        dict with user_id, email, roles
    """
    try:
        # Decode JWT token
        payload = jwt.decode(
            credentials.credentials,
            settings.JWT_SECRET_KEY,
            algorithms=[settings.JWT_ALGORITHM]
        )

        # Extract user_id from 'sub' claim
        user_id: str = payload.get("sub")
        if user_id is None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid authentication credentials"
            )

        # Fetch user details from database (auth-api JWT has minimal claims)
        user_record = await db.fetch_one(
            "SELECT user_id, email, roles, is_verified, status FROM activity.users WHERE user_id = $1",
            user_id
        )

        if user_record is None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid authentication credentials"
            )

        # Check if user is verified and active
        if not user_record["is_verified"]:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Email not verified"
            )

        if user_record["status"] != "active":
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Account is {user_record['status']}"
            )

        return {
            "user_id": str(user_record["user_id"]),
            "email": user_record["email"],
            "roles": user_record["roles"] or []
        }
    except JWTError as e:
        logger.error("jwt_validation_failed", error=str(e))
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication credentials"
        )

async def require_admin(current_user: dict = Depends(get_current_user)) -> dict:
    """
    Validate user has admin or moderator role.

    Returns:
        dict with user_id, email, roles
    """
    roles = current_user.get("roles", [])

    if "admin" not in roles and "moderator" not in roles:
        logger.warning("insufficient_permissions", user_id=current_user["user_id"], roles=roles)
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="INSUFFICIENT_PERMISSIONS: Admin or moderator role required"
        )

    return current_user

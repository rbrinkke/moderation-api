from pydantic_settings import BaseSettings
from typing import Optional

class Settings(BaseSettings):
    # Environment
    ENVIRONMENT: str = "development"
    DEBUG: bool = False

    # API
    API_V1_PREFIX: str = "/moderation"
    PROJECT_NAME: str = "Activity Platform - Moderation API"

    # API Documentation (Swagger UI / OpenAPI)
    ENABLE_DOCS: bool = True
    API_VERSION: str = "1.0.0"

    # Database
    DATABASE_URL: str

    # Redis
    REDIS_URL: str

    # JWT (from auth-api)
    JWT_SECRET_KEY: str
    JWT_ALGORITHM: str = "HS256"

    # External APIs
    EMAIL_API_URL: str
    AUTH_API_URL: str

    # Rate Limiting
    RATE_LIMIT_ENABLED: bool = True

    # Logging
    LOG_LEVEL: str = "INFO"

    class Config:
        env_file = ".env"
        case_sensitive = True

settings = Settings()

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
import structlog

from app.config import settings
from app.services.database import db
from app.services.email import email_client
from app.middleware.correlation import CorrelationMiddleware

# Import all routers
from app.routes import reports, photos, users, content, statistics

# Configure structured logging
structlog.configure(
    processors=[
        structlog.contextvars.merge_contextvars,
        structlog.stdlib.add_log_level,
        structlog.stdlib.add_logger_name,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.JSONRenderer() if settings.ENVIRONMENT == "production"
        else structlog.dev.ConsoleRenderer(),
    ],
    wrapper_class=structlog.stdlib.BoundLogger,
    context_class=dict,
    logger_factory=structlog.stdlib.LoggerFactory(),
    cache_logger_on_first_use=True,
)

logger = structlog.get_logger()

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan events"""
    # Startup
    logger.info("application_starting", environment=settings.ENVIRONMENT)
    await db.connect()
    logger.info("application_started")

    yield

    # Shutdown
    logger.info("application_stopping")
    await db.disconnect()
    await email_client.close()
    logger.info("application_stopped")

# Create FastAPI app
app = FastAPI(
    title=settings.PROJECT_NAME,
    description="Moderation API for activities platform",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
    lifespan=lifespan
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure appropriately for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Add correlation ID middleware
app.add_middleware(CorrelationMiddleware)

# Health check endpoint
@app.get("/health")
async def health_check():
    """Health check endpoint"""
    health_status = {"status": "ok", "service": "moderation-api"}

    # Check database connection
    try:
        if db.pool:
            await db.fetch_one("SELECT 1")
            health_status["database"] = "ok"
        else:
            health_status["database"] = "not_connected"
            health_status["status"] = "degraded"
    except Exception as e:
        health_status["database"] = f"error: {str(e)}"
        health_status["status"] = "degraded"

    return health_status

# Include all routers with moderation prefix
app.include_router(reports.router, prefix=settings.API_V1_PREFIX)
app.include_router(photos.router, prefix=settings.API_V1_PREFIX)
app.include_router(users.router, prefix=settings.API_V1_PREFIX)
app.include_router(content.router, prefix=settings.API_V1_PREFIX)
app.include_router(statistics.router, prefix=settings.API_V1_PREFIX)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "app.main:app",
        host="0.0.0.0",
        port=8000,
        reload=settings.DEBUG
    )

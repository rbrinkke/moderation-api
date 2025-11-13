from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
import structlog
import uuid

class CorrelationMiddleware(BaseHTTPMiddleware):
    """Add correlation ID to all requests for tracing"""

    async def dispatch(self, request: Request, call_next):
        # Get correlation ID from header or generate new one
        correlation_id = request.headers.get("X-Trace-ID") or str(uuid.uuid4())

        # Bind to structlog context
        structlog.contextvars.bind_contextvars(correlation_id=correlation_id)

        # Process request
        response = await call_next(request)

        # Add correlation ID to response header
        response.headers["X-Trace-ID"] = correlation_id

        return response

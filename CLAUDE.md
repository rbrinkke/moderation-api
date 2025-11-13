# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

FastAPI service for content moderation, user sanctions, and trust & safety features. Part of a larger activities platform ecosystem that includes auth-api and email-api services. Uses a shared central database (`activitydb`) and shared Redis instance for rate limiting.

## Architecture Principles

### Database Access Pattern (CRITICAL)
**All database access MUST use stored procedures** - zero direct SQL queries in application code. The API exclusively calls stored procedures in the `activity` schema. This is a hard architectural constraint.

```python
# ✅ Correct pattern
result = await db.fetch_one(
    "SELECT * FROM activity.sp_mod_create_report($1, $2, $3, $4, $5, $6)",
    user_id, reported_user_id, target_type, target_id, report_type, description
)

# ❌ Never do this
result = await db.fetch_one(
    "INSERT INTO activity.reports (reporter_user_id, ...) VALUES ($1, ...)",
    user_id, ...
)
```

### Service Dependencies
- **auth-api** (port 8000): JWT token validation, user authentication
- **email-api** (port 8002): Email notifications (ban/unban, photo rejection, content removal)
- **activity-postgres-db**: Shared PostgreSQL 15+ database (activitydb)
- **auth-redis**: Shared Redis instance for rate limiting

### Authentication & Authorization
- All endpoints require JWT Bearer token (validated against `JWT_SECRET_KEY` from auth-api)
- Two authorization levels:
  - `get_current_user`: Any authenticated user (for creating reports)
  - `require_admin`: Admin/moderator role required (for all moderation actions)
- JWT structure: `{"sub": "user-uuid", "email": "...", "roles": ["admin", "moderator"], "exp": ...}`

## Development Commands

### Local Development (Docker - Recommended)
```bash
# Build and start service (ALWAYS rebuild after code changes)
docker compose build --no-cache
docker compose up -d

# Restart without rebuild (only for config changes)
docker compose restart

# View logs
docker compose logs -f moderation-api

# Stop service
docker compose down

# Health check
curl http://localhost:8002/health
```

**IMPORTANT**: Code changes don't take effect with `docker compose restart` alone. Always use `docker compose build` after modifying Python code.

### Local Development (Native Python)
```bash
# Setup
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate
pip install -r requirements.txt

# Run development server
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

# Run with specific settings
ENVIRONMENT=development DEBUG=true uvicorn app.main:app --reload
```

### Database Operations
```bash
# Apply stored procedures migration
psql postgresql://postgres:postgres_secure_password_change_in_prod@activity-postgres-db:5432/activitydb \
  -f migrations/001_moderation_stored_procedures.sql

# Test database connection
psql postgresql://postgres:postgres_secure_password_change_in_prod@activity-postgres-db:5432/activitydb \
  -c "SELECT 1"

# List stored procedures
psql postgresql://postgres:postgres_secure_password_change_in_prod@activity-postgres-db:5432/activitydb \
  -c "\df activity.sp_mod_*"
```

### Testing
```bash
# Run all tests
pytest tests/ -v

# Run specific test
pytest tests/test_reports.py -v

# Run with coverage
pytest tests/ --cov=app --cov-report=html

# Run tests with logs
pytest tests/ -v -s
```

## API Endpoints Structure

All endpoints prefixed with `/moderation` (via `API_V1_PREFIX="/moderation"`):

**Reports (4 endpoints)**
- `POST /moderation/reports` - Create report (user) → `sp_mod_create_report`
- `GET /moderation/reports` - List reports (admin) → `sp_mod_get_reports`
- `GET /moderation/reports/{report_id}` - Get report (admin) → `sp_mod_get_report_by_id`
- `PATCH /moderation/reports/{report_id}/status` - Update status (admin) → `sp_mod_update_report_status`

**Photo Moderation (2 endpoints)**
- `GET /moderation/photos/pending` - Pending queue (admin) → `sp_mod_get_pending_photos`
- `POST /moderation/photos/moderate` - Approve/reject (admin) → `sp_mod_moderate_main_photo`

**User Moderation (3 endpoints)**
- `POST /moderation/users/{user_id}/ban` - Ban user (admin) → `sp_mod_ban_user`
- `POST /moderation/users/{user_id}/unban` - Unban user (admin) → `sp_mod_unban_user`
- `GET /moderation/users/{user_id}/history` - Moderation history (admin) → `sp_mod_get_user_moderation_history`

**Content Removal (1 endpoint)**
- `POST /moderation/content/remove` - Remove post/comment (admin) → `sp_mod_remove_content`

**Statistics (1 endpoint)**
- `GET /moderation/statistics` - Metrics (admin) → `sp_mod_get_statistics`

## Code Architecture

### Request Flow
```
Request → CorrelationMiddleware (X-Trace-ID)
        → RateLimiter (slowapi + Redis)
        → Router (app/routes/*.py)
        → Auth Middleware (get_current_user or require_admin)
        → Database Service (db.fetch_one/fetch_all)
        → Stored Procedure (activity.sp_mod_*)
        → Response Mapping (Pydantic models)
```

### Directory Structure
```
app/
├── main.py               # FastAPI app, lifespan, middleware, global handlers
├── config.py             # Settings via pydantic-settings (12-factor config)
├── routes/               # Endpoint handlers (reports, photos, users, content, statistics)
├── models/
│   ├── requests.py       # Pydantic request schemas
│   └── responses.py      # Pydantic response schemas
├── services/
│   ├── database.py       # asyncpg connection pool (db singleton)
│   └── email.py          # httpx client for email-api (non-blocking)
├── middleware/
│   ├── auth.py           # JWT validation, role checking
│   └── correlation.py    # X-Trace-ID for request tracing
└── utils/
    └── errors.py         # PostgreSQL error → HTTP status mapping

migrations/               # SQL stored procedures (apply before deployment)
tests/                    # pytest suite with asyncio support
```

### Stored Procedures (11 total)
All stored procedures:
1. Return JSON via `jsonb_build_object()` for single results or `jsonb_agg()` for collections
2. Handle business logic validation (duplicate reports, invalid user states, etc.)
3. Use custom exception codes (e.g., `REPORT_ALREADY_EXISTS`, `USER_ALREADY_BANNED`)
4. Are located in the `activity` schema

When modifying stored procedures: update `migrations/001_moderation_stored_procedures.sql`, then reapply migration.

### Error Handling Pattern
Stored procedures raise exceptions with custom codes that are mapped to HTTP status codes:

```python
# utils/errors.py maps exceptions like:
"REPORT_ALREADY_EXISTS" → 409 Conflict
"USER_NOT_FOUND" → 404 Not Found
"INVALID_TARGET_TYPE" → 400 Bad Request
"INSUFFICIENT_PERMISSIONS" → 403 Forbidden
```

Routes catch `asyncpg.PostgresError` and use `map_sp_error_to_http()` for consistent error responses.

### Logging Strategy
- Uses `structlog` for structured JSON logging in production, console in development
- Every operation logs with context: `user_id`, `report_id`, `correlation_id`
- Log levels: DEBUG (development), INFO (production)
- Email failures are logged but don't break API responses (non-blocking)

### Rate Limiting
- Implemented via `slowapi` with Redis backend
- User endpoints: `@limiter.limit("10/minute")`
- Admin endpoints: `@limiter.limit("50/minute")` to `@limiter.limit("100/minute")`
- Rate limits enforced per IP address (`get_remote_address`)

## Environment Configuration

Required environment variables (see `.env.example`):

```bash
# Database (shared central database)
DATABASE_URL=postgresql://postgres:postgres_secure_password_change_in_prod@activity-postgres-db:5432/activitydb

# Redis (shared with auth-api)
REDIS_URL=redis://auth-redis:6379/0

# JWT (MUST match auth-api secret exactly)
JWT_SECRET_KEY=dev-secret-key-change-in-production
JWT_ALGORITHM=HS256

# External service URLs
EMAIL_API_URL=http://email-api:8002
AUTH_API_URL=http://auth-api:8000

# Environment
ENVIRONMENT=development  # or "production"
DEBUG=true               # false in production
```

## Common Development Patterns

### Adding a New Endpoint
1. **Create stored procedure** in `migrations/001_moderation_stored_procedures.sql`
2. **Add request/response models** in `app/models/requests.py` and `app/models/responses.py`
3. **Create route handler** in appropriate file under `app/routes/`
4. **Include router** in `app/main.py` (if new route file)
5. **Write tests** in `tests/`
6. **Apply migration** to database
7. **Rebuild container** to test

### Database Service Usage
```python
# Single row (returns asyncpg.Record or None)
result = await db.fetch_one(
    "SELECT * FROM activity.sp_mod_get_report_by_id($1)",
    report_id
)

# Multiple rows (returns list of asyncpg.Record)
results = await db.fetch_all(
    "SELECT * FROM activity.sp_mod_get_reports($1, $2, $3, $4)",
    status_filter, limit, offset, sort_by
)

# Parse JSON from stored procedure
data = json.loads(result[0])  # Stored proc returns JSON as string
```

### Email Notification Pattern
```python
# Email sending is non-blocking, failures don't break API
try:
    await email_client.send_email(
        recipient_email=user_email,
        subject="...",
        body="...",
        template="moderation_action"
    )
except Exception as e:
    logger.warning("email_send_failed", error=str(e))
    # Continue with API response
```

## Security Considerations

- **SQL Injection**: Protected via stored procedures (no dynamic SQL in app)
- **JWT Validation**: All endpoints require valid tokens, secrets must match auth-api
- **Role-Based Access**: Admin-only endpoints use `require_admin` dependency
- **Rate Limiting**: Prevents brute-force attacks via Redis-backed rate limiter
- **CORS**: Currently `allow_origins=["*"]` - MUST be restricted in production
- **Non-root Container**: Docker runs as user `appuser` (UID 1000)
- **Input Validation**: Pydantic schemas validate all request payloads
- **Error Sanitization**: `utils/errors.py` prevents sensitive data leaks

## Troubleshooting

**Database connection fails**
- Verify `activity_default` network exists: `docker network ls`
- Check database is running: `docker ps | grep activity-postgres-db`
- Test connection: `psql $DATABASE_URL -c "SELECT 1"`

**JWT authentication errors**
- Ensure `JWT_SECRET_KEY` matches auth-api exactly
- Check token hasn't expired (`exp` claim)
- Verify `roles` claim exists in token payload

**Stored procedure not found**
- Apply migration: `psql $DATABASE_URL -f migrations/001_moderation_stored_procedures.sql`
- Verify: `psql $DATABASE_URL -c "\df activity.sp_mod_*"`

**Rate limiting not working**
- Check Redis connection: `docker exec -it auth-redis redis-cli ping`
- Verify `REDIS_URL` in environment
- Check `RATE_LIMIT_ENABLED=true` in config

**Code changes not taking effect**
- Rebuild container: `docker compose build --no-cache`
- Don't use `docker compose restart` alone - it uses old image

**Health check fails**
- Check logs: `docker compose logs moderation-api`
- Verify database pool: `/health` endpoint shows database status
- Ensure all dependencies are running

## Production Deployment Checklist

Before production deployment:
- [ ] Set `ENVIRONMENT=production` and `DEBUG=false`
- [ ] Configure CORS with specific origins (not `["*"]`)
- [ ] Use strong `JWT_SECRET_KEY` (minimum 32 characters)
- [ ] Apply all database migrations to production database
- [ ] Set secure database credentials (not default passwords)
- [ ] Enable Redis authentication
- [ ] Set `LOG_LEVEL=INFO` or `WARNING`
- [ ] Configure monitoring for `/health` endpoint
- [ ] Test all 11 endpoints with production-like data
- [ ] Verify JWT secret matches auth-api production secret
- [ ] Review rate limits for production traffic expectations
- [ ] Set up database backups and disaster recovery

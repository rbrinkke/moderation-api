# Moderation API

A production-ready FastAPI service for content moderation, user sanctions, and trust & safety features for an activities platform.

## Features

- **Report Management**: Users can report problematic content/behavior
- **Photo Moderation**: Admin queue for approving/rejecting profile photos
- **User Sanctions**: Ban/unban users with reason tracking
- **Content Removal**: Remove or hide flagged posts and comments
- **Moderation Queue**: Admin dashboard for pending reports
- **Statistics**: Trust & safety metrics for monitoring

## Tech Stack

- **Framework**: FastAPI 0.109.0
- **Database**: PostgreSQL 15+ with asyncpg
- **Cache**: Redis 7+ for rate limiting
- **Authentication**: JWT Bearer tokens (from auth-api)
- **Database Access**: 100% Stored Procedures (zero direct queries)
- **Logging**: Structured logging with structlog
- **Containerization**: Docker + Docker Compose

## Prerequisites

- Python 3.11+
- PostgreSQL 15+
- Redis 7+
- Docker & Docker Compose (optional)

## Installation

### 1. Clone Repository

```bash
git clone <repository-url>
cd moderation-api
```

### 2. Create Virtual Environment

```bash
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
```

### 3. Install Dependencies

```bash
pip install -r requirements.txt
```

### 4. Configure Environment

```bash
cp .env.example .env
# Edit .env with your actual values
```

Required environment variables:

```bash
# Database
DATABASE_URL=postgresql://user:password@localhost:5432/activities_db

# Redis
REDIS_URL=redis://localhost:6379/0

# JWT (must match auth-api secret)
JWT_SECRET_KEY=your-secret-key-here
JWT_ALGORITHM=HS256

# External APIs
EMAIL_API_URL=http://email-api:8002
AUTH_API_URL=http://auth-api:8000

# Environment
ENVIRONMENT=development
DEBUG=true
```

### 5. Setup Database

Run the stored procedures migration:

```bash
psql -U postgres -d activities_db -f migrations/001_moderation_stored_procedures.sql
```

## Running the Application

### Local Development

```bash
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

### Docker Compose (Recommended)

```bash
docker-compose up -d
```

This will start:
- **moderation-api** on port 8000
- **PostgreSQL** on port 5432
- **Redis** on port 6379

## API Documentation

Once running, access the interactive API documentation at:

- **Swagger UI**: http://localhost:8000/docs
- **ReDoc**: http://localhost:8000/redoc
- **Health Check**: http://localhost:8000/health

## API Endpoints

### Reports (4 endpoints)

- `POST /moderation/reports` - Create new report (user)
- `GET /moderation/reports` - Get reports with filtering (admin)
- `GET /moderation/reports/{report_id}` - Get single report details (admin)
- `PATCH /moderation/reports/{report_id}/status` - Update report status (admin)

### Photo Moderation (2 endpoints)

- `GET /moderation/photos/pending` - Get pending photo queue (admin)
- `POST /moderation/photos/moderate` - Approve/reject photo (admin)

### User Moderation (3 endpoints)

- `POST /moderation/users/{user_id}/ban` - Ban user (admin)
- `POST /moderation/users/{user_id}/unban` - Unban user (admin)
- `GET /moderation/users/{user_id}/history` - Get moderation history (admin)

### Content Removal (1 endpoint)

- `POST /moderation/content/remove` - Remove post or comment (admin)

### Statistics (1 endpoint)

- `GET /moderation/statistics` - Get moderation metrics (admin)

## Authentication

All endpoints require JWT Bearer token in Authorization header:

```bash
Authorization: Bearer <your-jwt-token>
```

### JWT Structure

```json
{
  "sub": "user-uuid",
  "email": "user@example.com",
  "roles": ["admin", "moderator"],
  "exp": 1234567890
}
```

- **Regular users**: Can create reports
- **Admins/Moderators**: Access to all moderation endpoints

## Rate Limiting

Endpoints are rate-limited using Redis:

- User endpoints: 10 requests/minute
- Admin endpoints: 50-100 requests/minute

## Database Architecture

All database access uses stored procedures in the `activity` schema:

1. `sp_mod_create_report` - Create report
2. `sp_mod_get_reports` - Get reports (filtered)
3. `sp_mod_get_report_by_id` - Get single report
4. `sp_mod_update_report_status` - Update report
5. `sp_mod_moderate_main_photo` - Moderate photo
6. `sp_mod_get_pending_photos` - Get pending photos
7. `sp_mod_ban_user` - Ban user
8. `sp_mod_unban_user` - Unban user
9. `sp_mod_remove_content` - Remove content
10. `sp_mod_get_user_moderation_history` - User history
11. `sp_mod_get_statistics` - Statistics

## Testing

Run tests with pytest:

```bash
pytest tests/ -v
```

Run with coverage:

```bash
pytest tests/ --cov=app --cov-report=html
```

## Project Structure

```
moderation-api/
├── app/
│   ├── main.py                # FastAPI app + startup/shutdown
│   ├── config.py              # Settings via pydantic-settings
│   ├── routes/                # API endpoints
│   │   ├── reports.py         # Report endpoints
│   │   ├── photos.py          # Photo moderation
│   │   ├── users.py           # Ban/unban
│   │   ├── content.py         # Content removal
│   │   └── statistics.py      # Statistics
│   ├── models/                # Pydantic schemas
│   │   ├── requests.py        # Request models
│   │   └── responses.py       # Response models
│   ├── services/              # Business logic
│   │   ├── database.py        # DB connection pool
│   │   └── email.py           # Email API client
│   ├── middleware/            # Request interceptors
│   │   ├── auth.py            # JWT validation
│   │   └── correlation.py     # Correlation ID
│   └── utils/
│       └── errors.py          # Error mapping
├── tests/                     # Pytest test suite
├── migrations/                # SQL migrations
├── requirements.txt           # Python dependencies
├── Dockerfile                 # Container image
├── docker-compose.yml         # Multi-container setup
└── README.md                  # This file
```

## Error Handling

The API returns structured error responses:

```json
{
  "detail": "ERROR_CODE: Human-readable message"
}
```

HTTP status codes:
- `200` - Success (GET/PATCH)
- `201` - Created (POST)
- `400` - Bad Request (validation/business logic)
- `401` - Unauthorized (missing/invalid token)
- `403` - Forbidden (insufficient permissions)
- `404` - Not Found (resource doesn't exist)
- `409` - Conflict (duplicate report)
- `422` - Unprocessable Entity (Pydantic validation)
- `429` - Too Many Requests (rate limit)
- `500` - Internal Server Error

## Email Notifications

The API sends email notifications via email-api for:
- Photo rejections
- User bans/unbans
- Content removals

Email sending is non-blocking and failures don't break the API response.

## Monitoring & Observability

- **Health Check**: `/health` endpoint with database status
- **Structured Logging**: JSON logs in production, console in dev
- **Correlation IDs**: X-Trace-ID header for request tracing
- **Logs**: All operations logged with context (user_id, report_id, etc.)

## Security Features

- JWT authentication via auth-api
- Role-based access control (admin/moderator)
- Rate limiting (brute-force protection)
- Input validation (Pydantic schemas)
- SQL injection prevention (stored procedures only)
- Error message sanitization (no sensitive data leaks)
- Non-root Docker container
- CORS configuration

## Deployment

### Environment-Specific Configuration

**Development:**
```bash
ENVIRONMENT=development
DEBUG=true
LOG_LEVEL=DEBUG
```

**Production:**
```bash
ENVIRONMENT=production
DEBUG=false
LOG_LEVEL=INFO
```

### Docker Build

```bash
docker build -t moderation-api:latest .
```

### Health Check

Container includes health check:
```bash
docker ps  # Check STATUS column for (healthy)
```

## Troubleshooting

### Database Connection Issues

```bash
# Check DATABASE_URL format
DATABASE_URL=postgresql://user:password@host:5432/dbname

# Test connection
psql $DATABASE_URL -c "SELECT 1"
```

### Missing Stored Procedures

```bash
# Re-run migration
psql $DATABASE_URL -f migrations/001_moderation_stored_procedures.sql
```

### JWT Authentication Errors

- Verify JWT_SECRET_KEY matches auth-api
- Check token expiry
- Ensure "roles" claim exists in JWT

### Rate Limiting Issues

- Check Redis connection: `redis-cli ping`
- Verify REDIS_URL in .env

## Development

### Adding New Endpoints

1. Create Pydantic request/response models in `app/models/`
2. Implement stored procedure in `migrations/`
3. Create route handler in `app/routes/`
4. Add route to `app/main.py`
5. Write tests in `tests/`

### Code Style

- Use `black` for formatting
- Use `isort` for import sorting
- Follow FastAPI best practices

## License

[Your License Here]

## Support

For issues and questions:
- Create an issue on GitHub
- Contact: [your-email@example.com]

## Credits

Built with FastAPI, PostgreSQL, and Redis.

---

## Production Checklist

Before deploying to production, ensure you complete these critical steps:

### ⚠️ CRITICAL - Security Configuration

1. **CORS Configuration** - Currently set to `allow_origins=["*"]`
   ```python
   # In app/main.py, change:
   app.add_middleware(
       CORSMiddleware,
       allow_origins=["https://your-frontend.com"],  # Specify your actual domains
       allow_credentials=True,
       allow_methods=["GET", "POST", "PATCH"],
       allow_headers=["Authorization", "Content-Type"],
   )
   ```

2. **JWT Secret** - Use strong, unique secret
   ```bash
   # Generate strong secret:
   openssl rand -hex 32
   # Add to .env:
   JWT_SECRET_KEY=<generated-secret>
   ```

3. **Database Credentials** - Use secure credentials
   ```bash
   # Never use default passwords in production!
   DATABASE_URL=postgresql://secure_user:strong_password@db:5432/activities_db
   ```

4. **Redis Password** - Enable Redis authentication
   ```bash
   REDIS_URL=redis://:strong_password@redis:6379/0
   ```

### ✅ Configuration Checklist

- [ ] Change `ENVIRONMENT=production` in .env
- [ ] Set `DEBUG=false` in .env
- [ ] Configure CORS with specific origins
- [ ] Set strong JWT_SECRET_KEY
- [ ] Use secure database credentials
- [ ] Enable Redis authentication
- [ ] Configure EMAIL_API_URL with production URL
- [ ] Set LOG_LEVEL=INFO or WARNING
- [ ] Review rate limits for your use case
- [ ] Set up SSL/TLS certificates
- [ ] Configure firewall rules
- [ ] Set up monitoring and alerting
- [ ] Create database backups
- [ ] Test all endpoints with production data

### 🔍 Pre-Deployment Testing

1. **Load Testing**
   ```bash
   # Test rate limiting
   ab -n 1000 -c 10 http://localhost:8000/health
   ```

2. **Security Scanning**
   ```bash
   # Install safety
   pip install safety
   # Check for vulnerabilities
   safety check -r requirements.txt
   ```

3. **Database Migration**
   ```bash
   # Test stored procedures
   psql $DATABASE_URL -f migrations/001_moderation_stored_procedures.sql
   ```

4. **Integration Testing**
   - Test JWT authentication with actual auth-api
   - Test email notifications with actual email-api
   - Test all 11 endpoints with production-like data

### 📊 Monitoring Setup

Recommended monitoring:
- Application health: `/health` endpoint
- Database connection pool status
- Redis connection status
- Rate limit hit rate
- API response times
- Error rates per endpoint
- Email delivery success rate

### 🚨 Known Production Considerations

1. **Rate Limiting**: Currently configured for single-instance deployment. For multi-instance, ensure all instances share the same Redis.

2. **Database Connections**: Connection pool sized for 5-20 connections. Adjust based on your load.

3. **Email Failures**: Email sending is non-blocking. Failed emails are logged but don't break API responses.

4. **Stored Procedures**: All 11 SPs must be deployed before starting the API.

5. **JWT Validation**: Ensure JWT_SECRET_KEY exactly matches your auth-api configuration.

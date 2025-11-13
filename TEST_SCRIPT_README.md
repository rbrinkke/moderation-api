# Moderation API Test Script - Gebruikershandleiding

## Overzicht

Het `test_moderation_api.sh` script test **100% van de moderation-api functionaliteit** met volledige database verificatie.

## Features

✅ **Complete Coverage**: Test alle 11 endpoints
✅ **Database Verificatie**: Elke API call wordt geverifieerd in de database
✅ **Authenticatie**: Test met zowel admin als regular user tokens
✅ **Automatische Setup**: Maakt test data automatisch aan
✅ **Cleanup**: Verwijdert test data na afloop
✅ **Colored Output**: Duidelijke visuele feedback

## Wat Wordt Getest

### Reports (4 endpoints)
1. `POST /moderation/reports` - Maak nieuwe report
2. `GET /moderation/reports` - Haal alle reports op met filtering
3. `GET /moderation/reports/{id}` - Haal specifieke report op
4. `PATCH /moderation/reports/{id}/status` - Update report status

### Photo Moderation (2 endpoints)
5. `GET /moderation/photos/pending` - Haal pending photos op
6. `POST /moderation/photos/moderate` - Approve/reject photo

### User Moderation (3 endpoints)
7. `POST /moderation/users/{id}/ban` - Ban user (permanent en temporary)
8. `GET /moderation/users/{id}/history` - Haal moderation history op
9. `POST /moderation/users/{id}/unban` - Unban user

### Content Removal (1 endpoint)
10. `POST /moderation/content/remove` - Verwijder post/comment

### Statistics (1 endpoint)
11. `GET /moderation/statistics` - Haal moderation statistieken op

## Vereisten

- **Moderation API**: Draait op `http://localhost:8002`
- **Auth API**: Draait op `http://localhost:8000`
- **PostgreSQL**: Toegankelijk via `activity-postgres-db` container
- **Tools**: `curl`, `jq`, `docker`

## Installatie

```bash
# Installeer jq als het nog niet geïnstalleerd is
# Ubuntu/Debian:
sudo apt-get install jq

# macOS:
brew install jq

# Windows (WSL):
sudo apt-get install jq
```

## Gebruik

### Basis Gebruik

```bash
# Voer alle tests uit
./test_moderation_api.sh
```

### Met Custom URLs

```bash
# Custom API URLs
API_URL=http://localhost:8002 \
AUTH_API_URL=http://localhost:8000 \
./test_moderation_api.sh
```

### Database Configuratie

```bash
# Custom database settings
DB_HOST=activity-postgres-db \
DB_NAME=activitydb \
DB_USER=postgres \
DB_PASS=postgres_secure_password_change_in_prod \
./test_moderation_api.sh
```

## Output Voorbeeld

```
========================================
MODERATION API - COMPREHENSIVE TEST SUITE
========================================

API URL: http://localhost:8002
Auth API: http://localhost:8000
Database: activitydb@activity-postgres-db

✓ API is running

========================================
SETUP: Authentication
========================================

→ Creating test admin user...
→ Logging in as admin...
→ Granting admin role...
✓ Admin authenticated: 550e8400-e29b-41d4-a716-446655440000

→ Creating test regular user...
✓ Regular user authenticated: 660e8400-e29b-41d4-a716-446655440001

========================================
SETUP: Test Data Preparation
========================================

→ Creating reported user...
✓ Reported user created: 770e8400-e29b-41d4-a716-446655440002
→ Creating user for ban tests...
✓ Ban test user created: 880e8400-e29b-41d4-a716-446655440003
→ Creating user for photo moderation...
✓ Photo test user created: 990e8400-e29b-41d4-a716-446655440004
→ Creating test post...
✓ Test post created: aa0e8400-e29b-41d4-a716-446655440005
→ Creating test comment...
✓ Test comment created: bb0e8400-e29b-41d4-a716-446655440006

========================================
RUNNING TESTS
========================================

[TEST 1] POST /moderation/reports (Create Report)
✓ Report created: cc0e8400-e29b-41d4-a716-446655440007
→ Verifying report in database...
✓ Database verification passed

[TEST 2] GET /moderation/reports (List Reports)
✓ Retrieved 5 reports
✓ Test report found in list

[TEST 3] GET /moderation/reports/{id} (Get Report Details)
✓ Retrieved report: cc0e8400-e29b-41d4-a716-446655440007
✓ Report details match database

[TEST 4] PATCH /moderation/reports/{id}/status (Update Status)
✓ Report status updated
→ Verifying status update in database...
✓ Database verification passed: status = resolved
✓ Reviewed by admin: 550e8400-e29b-41d4-a716-446655440000

[TEST 5] GET /moderation/photos/pending (Get Pending Photos)
✓ Retrieved 1 pending photos
→ Database count: 1, API count: 1
✓ Pending photos verification passed

[TEST 6] POST /moderation/photos/moderate (Moderate Photo)
✓ Photo moderated (approved)
✓ Database verification passed: photo approved
✓ Photo moderated (rejected)
✓ Database verification passed: photo rejected

[TEST 7] POST /moderation/users/{id}/ban (Ban User)
✓ User permanently banned
✓ Database verification passed: status = banned
✓ Permanent ban verified (no expiry)
✓ User temporarily banned (24h)
✓ Database verification passed: status = temporary_ban
✓ Temporary ban has expiry: 2025-11-14 14:30:00+01

[TEST 8] GET /moderation/users/{id}/history (Get User History)
✓ Retrieved user moderation history
✓ Ban action found in history (count: 2)

[TEST 9] POST /moderation/users/{id}/unban (Unban User)
✓ User unbanned
✓ Database verification passed: status = active
✓ Ban expiry cleared

[TEST 10] POST /moderation/content/remove (Remove Content)
✓ Post removed
✓ Database verification passed: post status = removed
✓ Comment removed
✓ Database verification passed: comment status = removed

[TEST 11] GET /moderation/statistics (Get Statistics)
✓ Retrieved statistics: 8 total reports
→ Database count: 8, API count: 8
→ Pending reports: 3
→ Banned users: 0
✓ Statistics verification passed

========================================
CLEANUP: Removing Test Data
========================================

→ Cleaning up test data...
✓ Deleted test report
✓ Deleted test comment
✓ Deleted test post
✓ Reset ban test user
✓ Reset photo test user
✓ Cleanup completed

========================================
TEST RESULTS SUMMARY
========================================

Total Tests: 11
Passed: 35
Failed: 0

========================================
ALL TESTS PASSED (100% COVERAGE)
========================================
```

## Exit Codes

- **0**: Alle tests geslaagd
- **1**: Één of meer tests gefaald
- **1**: API niet bereikbaar

## Troubleshooting

### API Niet Bereikbaar

```bash
# Check of moderation-api draait
docker ps | grep moderation-api

# Check logs
docker logs moderation-api

# Restart API
docker compose restart
```

### Database Connectie Problemen

```bash
# Test database connectie
docker exec activity-postgres-db psql -U postgres -d activitydb -c "SELECT 1"

# Check netwerk
docker network inspect activity-network
```

### Auth API Problemen

```bash
# Check of auth-api draait
curl http://localhost:8000/health

# Start auth-api als nodig
cd /path/to/auth-api
docker compose up -d
```

### jq Niet Gevonden

```bash
# Installeer jq
sudo apt-get update && sudo apt-get install -y jq
```

## Database Verificatie Details

Voor elke API operatie voert het script database queries uit om te verifiëren dat:

1. **Reports**: Correct aangemaakt met juiste status, reporter, en target
2. **Photo Moderation**: Status correct updated (approved/rejected)
3. **User Bans**: Status correct (banned/temporary_ban/active), expiry correct ingesteld
4. **Content Removal**: Post/comment status = "removed"
5. **Statistics**: Counts matchen database queries

## Test Data

Het script maakt automatisch de volgende test data aan:

- **5 test users**: admin, regular user, reported user, ban test user, photo test user
- **1 test post**: Voor content removal
- **1 test comment**: Voor content removal
- **1 test report**: Voor report flow
- **Pending photo**: Voor photo moderation

Alle test data wordt automatisch verwijderd na de tests (cleanup fase).

## Customization

Je kunt het script aanpassen door environment variables te gebruiken:

```bash
# Voorbeeld: Test tegen productie API
API_URL=https://api.example.com \
AUTH_API_URL=https://auth.example.com \
DB_HOST=prod-postgres \
./test_moderation_api.sh
```

## Continuous Integration

Het script kan gebruikt worden in CI/CD pipelines:

```yaml
# GitHub Actions voorbeeld
- name: Test Moderation API
  run: |
    ./test_moderation_api.sh
```

```yaml
# GitLab CI voorbeeld
test:moderation-api:
  script:
    - chmod +x test_moderation_api.sh
    - ./test_moderation_api.sh
```

## Onderhoud

Bij het toevoegen van nieuwe endpoints:

1. Voeg test functie toe (bijv. `test_new_endpoint()`)
2. Voeg database verificatie queries toe
3. Roep de functie aan in `main()`
4. Update deze README met het nieuwe endpoint

## Support

Voor vragen of problemen:
1. Check de logs: `docker logs moderation-api`
2. Verify database: `docker exec activity-postgres-db psql ...`
3. Test handmatig met curl
4. Check TEST_PLAN.md voor details

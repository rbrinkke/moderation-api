# Moderation API - Comprehensive Test Plan

## Overview
Complete test coverage voor alle 11 moderation-api endpoints met database verificatie.

## Test Strategy

### 1. Authentication Setup
- **Regular User Token**: Voor create report endpoint
- **Admin User Token**: Voor alle moderation endpoints
- Tokens verkrijgen via auth-api (port 8000)

### 2. Test Data Requirements

#### Users (moeten bestaan in database)
- **Admin User**: UUID met admin/moderator role
- **Regular User 1**: Voor reporter
- **Regular User 2**: Voor reported user
- **Regular User 3**: Voor ban/unban tests
- **Regular User 4**: Voor photo moderation

#### Content (moeten bestaan in database)
- **Post**: Voor content removal test
- **Comment**: Voor content removal test
- **Activity**: Voor report target
- **Community**: Voor report target

### 3. Test Flows

#### Flow 1: Report Lifecycle (4 endpoints)
1. **CREATE REPORT** (Regular User)
   - POST /moderation/reports
   - Verify: report in DB met status "pending"

2. **GET ALL REPORTS** (Admin)
   - GET /moderation/reports
   - Verify: nieuwe report zichtbaar in lijst

3. **GET REPORT BY ID** (Admin)
   - GET /moderation/reports/{report_id}
   - Verify: volledige report details match DB

4. **UPDATE REPORT STATUS** (Admin)
   - PATCH /moderation/reports/{report_id}/status
   - Verify: status changed in DB, reviewed_by set

#### Flow 2: Photo Moderation (2 endpoints)
1. **GET PENDING PHOTOS** (Admin)
   - GET /moderation/photos/pending
   - Verify: users met pending photos listed

2. **MODERATE PHOTO** (Admin)
   - POST /moderation/photos/moderate (approved)
   - Verify: main_photo_moderation_status = "approved"
   - POST /moderation/photos/moderate (rejected)
   - Verify: main_photo_moderation_status = "rejected"

#### Flow 3: User Moderation (3 endpoints)
1. **BAN USER** (Admin)
   - POST /moderation/users/{user_id}/ban (permanent)
   - Verify: status = "banned", ban_expires_at NULL
   - POST /moderation/users/{user_id}/ban (temporary, 24h)
   - Verify: status = "temporary_ban", ban_expires_at set

2. **GET USER HISTORY** (Admin)
   - GET /moderation/users/{user_id}/history
   - Verify: ban actions in history

3. **UNBAN USER** (Admin)
   - POST /moderation/users/{user_id}/unban
   - Verify: status = "active", ban_expires_at NULL

#### Flow 4: Content Removal (1 endpoint)
1. **REMOVE CONTENT** (Admin)
   - POST /moderation/content/remove (post)
   - Verify: post status = "removed"
   - POST /moderation/content/remove (comment)
   - Verify: comment status = "removed"

#### Flow 5: Statistics (1 endpoint)
1. **GET STATISTICS** (Admin)
   - GET /moderation/statistics
   - Verify: counts match DB queries
   - GET /moderation/statistics?date_from=X&date_to=Y
   - Verify: filtered counts correct

### 4. Error Scenarios

#### Reports
- Duplicate report → 409 Conflict
- Invalid target_type → 400 Bad Request
- Report non-existent target → 404 Not Found
- Non-admin tries to get reports → 403 Forbidden

#### Photo Moderation
- Moderate non-existent user → 404 Not Found
- Invalid moderation_status → 400 Bad Request

#### User Bans
- Ban already banned user → 409 Conflict
- Self-ban → 400 Bad Request
- Temporary ban without duration → 400 Bad Request
- Unban active user → 400 Bad Request

#### Content Removal
- Remove non-existent content → 404 Not Found
- Invalid content_type → 400 Bad Request

### 5. Database Verification Queries

```sql
-- Verify report created
SELECT report_id, reporter_user_id, target_type, target_id, report_type, status
FROM activity.reports WHERE report_id = $1;

-- Verify report status updated
SELECT status, reviewed_by_user_id, reviewed_at, resolution_notes
FROM activity.reports WHERE report_id = $1;

-- Verify user banned
SELECT user_id, status, ban_expires_at, banned_at, banned_by_user_id
FROM activity.users WHERE user_id = $1;

-- Verify photo moderation
SELECT user_id, main_photo_moderation_status, main_photo_moderated_at, main_photo_moderated_by
FROM activity.users WHERE user_id = $1;

-- Verify content removed
SELECT post_id, status, content_moderated_at, content_moderated_by
FROM activity.posts WHERE post_id = $1;

SELECT comment_id, status, content_moderated_at, content_moderated_by
FROM activity.comments WHERE comment_id = $1;

-- Verify statistics
SELECT COUNT(*) FROM activity.reports WHERE status = 'pending';
SELECT COUNT(*) FROM activity.users WHERE status IN ('banned', 'temporary_ban');
```

### 6. Test Script Structure

```bash
#!/bin/bash

# 1. Setup
#    - Colors en helper functies
#    - Test counters
#    - API base URL

# 2. Authentication
#    - Get admin JWT token
#    - Get regular user JWT token

# 3. Test Data Preparation
#    - Create test users (if not exist)
#    - Create test content (posts, comments)
#    - Create test activity/community

# 4. Execute Tests
#    - Each endpoint test function
#    - Database verification after each
#    - Track pass/fail

# 5. Cleanup
#    - Optional: remove test data
#    - Print summary report

# 6. Exit
#    - Exit code 0 if all pass
#    - Exit code 1 if any fail
```

### 7. Success Criteria

✅ **100% Endpoint Coverage**
- Alle 11 endpoints getest

✅ **Database Verification**
- Elke wijziging geverifieerd in DB

✅ **Error Handling**
- Alle error scenarios getest

✅ **Authentication**
- Regular user vs admin permissions

✅ **Data Integrity**
- Alle foreign keys valid
- Alle constraints respected

✅ **Complete Flows**
- End-to-end scenarios werken

## Test Execution

```bash
# Run full test suite
./test_moderation_api.sh

# Run with verbose output
./test_moderation_api.sh --verbose

# Run specific test
./test_moderation_api.sh --test=reports

# Skip cleanup
./test_moderation_api.sh --no-cleanup
```

## Expected Output

```
=== MODERATION API TEST SUITE ===
API URL: http://localhost:8002
Database: activitydb@activity-postgres-db

[SETUP] Getting authentication tokens... ✓
[SETUP] Preparing test data... ✓

[TEST 1/11] POST /moderation/reports... ✓
  → DB Verification: Report created with correct data ✓

[TEST 2/11] GET /moderation/reports... ✓
  → DB Verification: Report appears in list ✓

[TEST 3/11] GET /moderation/reports/{id}... ✓
  → DB Verification: Details match database ✓

[TEST 4/11] PATCH /moderation/reports/{id}/status... ✓
  → DB Verification: Status updated, reviewer set ✓

[TEST 5/11] GET /moderation/photos/pending... ✓
  → DB Verification: Pending photos count matches ✓

[TEST 6/11] POST /moderation/photos/moderate... ✓
  → DB Verification: Photo status updated ✓

[TEST 7/11] POST /moderation/users/{id}/ban... ✓
  → DB Verification: User banned with correct expiry ✓

[TEST 8/11] GET /moderation/users/{id}/history... ✓
  → DB Verification: History shows ban action ✓

[TEST 9/11] POST /moderation/users/{id}/unban... ✓
  → DB Verification: User status restored ✓

[TEST 10/11] POST /moderation/content/remove... ✓
  → DB Verification: Content marked as removed ✓

[TEST 11/11] GET /moderation/statistics... ✓
  → DB Verification: Counts match queries ✓

[CLEANUP] Removing test data... ✓

=================================
RESULTS: 11/11 PASSED (100%)
=================================
```

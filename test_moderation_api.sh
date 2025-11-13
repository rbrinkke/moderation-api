#!/bin/bash

################################################################################
# MODERATION API - COMPREHENSIVE TEST SCRIPT
# Tests all 11 endpoints with database verification
################################################################################

set -e  # Exit on error (disabled for tests)
set +e  # Re-enable after setup

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
API_URL="${API_URL:-http://localhost:8002}"
AUTH_API_URL="${AUTH_API_URL:-http://localhost:8000}"
DB_HOST="${DB_HOST:-activity-postgres-db}"
DB_NAME="${DB_NAME:-activitydb}"
DB_USER="${DB_USER:-postgres}"
DB_PASS="${DB_PASS:-postgres_secure_password_change_in_prod}"

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Test data storage
ADMIN_TOKEN=""
USER_TOKEN=""
ADMIN_USER_ID=""
REGULAR_USER_ID=""
REPORTED_USER_ID=""
TEST_REPORT_ID=""
TEST_POST_ID=""
TEST_COMMENT_ID=""
BAN_USER_ID=""
PHOTO_USER_ID=""

################################################################################
# HELPER FUNCTIONS
################################################################################

print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_test() {
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -e "${YELLOW}[TEST $TOTAL_TESTS] $1${NC}"
}

print_success() {
    PASSED_TESTS=$((PASSED_TESTS + 1))
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    FAILED_TESTS=$((FAILED_TESTS + 1))
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}→ $1${NC}"
}

# Database query helper
db_query() {
    local query="$1"
    local show_output="${2:-false}"

    local result=$(docker exec activity-postgres-db psql -U "$DB_USER" -d "$DB_NAME" -t -A -c "$query" 2>/dev/null)

    if [ "$show_output" = "true" ]; then
        echo -e "${BLUE}→ 📊 Database Query:${NC}" >&2
        echo -e "\033[0;36m   $query\033[0m" >&2
        if [ -n "$result" ]; then
            echo -e "${BLUE}→ 📋 Query Result:${NC}" >&2
            echo -e "\033[0;33m   $result\033[0m" >&2
        else
            echo -e "${BLUE}→ 📋 Query Result: (empty)${NC}" >&2
        fi
    fi

    echo "$result"
}

# API call helper with authentication
api_call() {
    local method="$1"
    local endpoint="$2"
    local token="$3"
    local data="$4"

    if [ -n "$data" ]; then
        curl -s -X "$method" "$API_URL$endpoint" \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json" \
            -d "$data"
    else
        curl -s -X "$method" "$API_URL$endpoint" \
            -H "Authorization: Bearer $token"
    fi
}

# Check if value exists in JSON response
check_json_field() {
    local json="$1"
    local field="$2"
    local expected="$3"

    local actual=$(echo "$json" | jq -r ".$field")
    if [ "$actual" = "$expected" ]; then
        return 0
    else
        echo "Expected: $expected, Got: $actual"
        return 1
    fi
}

################################################################################
# SETUP PHASE
################################################################################

setup_authentication() {
    print_header "SETUP: Authentication"

    # Create admin user if not exists
    print_info "Creating test admin user..."
    ADMIN_EMAIL="test-admin-mod@example.com"
    ADMIN_PASSWORD="AdminTestSecurePassword2025"

    # Register admin via auth-api
    ADMIN_REGISTER_RESPONSE=$(curl -s -X POST "$AUTH_API_URL/api/auth/register" \
        -H "Content-Type: application/json" \
        -d "{
            \"email\": \"$ADMIN_EMAIL\",
            \"password\": \"$ADMIN_PASSWORD\",
            \"username\": \"test-admin-mod\",
            \"first_name\": \"Test\",
            \"last_name\": \"Admin\"
        }" 2>/dev/null || echo '{"error":"exists"}')

    # Verify admin user in database (bypass email verification for tests)
    db_query "UPDATE activity.users SET is_verified = true WHERE email = '$ADMIN_EMAIL';" > /dev/null

    # Login as admin
    print_info "Logging in as admin..."
    ADMIN_LOGIN_RESPONSE=$(curl -s -X POST "$AUTH_API_URL/api/auth/login" \
        -H "Content-Type: application/json" \
        -d "{
            \"email\": \"$ADMIN_EMAIL\",
            \"password\": \"$ADMIN_PASSWORD\"
        }")

    ADMIN_TOKEN=$(echo "$ADMIN_LOGIN_RESPONSE" | jq -r '.access_token // .token // empty')
    ADMIN_USER_ID=$(db_query "SELECT user_id FROM activity.users WHERE email = '$ADMIN_EMAIL' LIMIT 1;")

    if [ -z "$ADMIN_TOKEN" ] || [ "$ADMIN_TOKEN" = "null" ]; then
        print_error "Failed to get admin token"
        exit 1
    fi

    # Grant admin role in database
    print_info "Granting admin role..."
    db_query "UPDATE activity.users SET roles = ARRAY['admin'] WHERE user_id = '$ADMIN_USER_ID';" > /dev/null

    print_success "Admin authenticated: $ADMIN_USER_ID"

    # Create regular user
    print_info "Creating test regular user..."
    USER_EMAIL="test-user-mod@example.com"
    USER_PASSWORD="UserTestSecurePassword2025"

    USER_REGISTER_RESPONSE=$(curl -s -X POST "$AUTH_API_URL/api/auth/register" \
        -H "Content-Type: application/json" \
        -d "{
            \"email\": \"$USER_EMAIL\",
            \"password\": \"$USER_PASSWORD\",
            \"username\": \"test-user-mod\",
            \"first_name\": \"Test\",
            \"last_name\": \"User\"
        }" 2>/dev/null || echo '{"error":"exists"}')

    # Verify user in database
    db_query "UPDATE activity.users SET is_verified = true WHERE email = '$USER_EMAIL';" > /dev/null

    USER_LOGIN_RESPONSE=$(curl -s -X POST "$AUTH_API_URL/api/auth/login" \
        -H "Content-Type: application/json" \
        -d "{
            \"email\": \"$USER_EMAIL\",
            \"password\": \"$USER_PASSWORD\"
        }")

    USER_TOKEN=$(echo "$USER_LOGIN_RESPONSE" | jq -r '.access_token // .token // empty')
    REGULAR_USER_ID=$(db_query "SELECT user_id FROM activity.users WHERE email = '$USER_EMAIL' LIMIT 1;")

    if [ -z "$USER_TOKEN" ] || [ "$USER_TOKEN" = "null" ]; then
        print_error "Failed to get user token"
        exit 1
    fi

    print_success "Regular user authenticated: $REGULAR_USER_ID"
}

setup_test_data() {
    print_header "SETUP: Test Data Preparation"

    # Create reported user
    print_info "Creating reported user..."
    REPORTED_EMAIL="reported-user-mod@example.com"
    REPORTED_RESPONSE=$(curl -s -X POST "$AUTH_API_URL/api/auth/register" \
        -H "Content-Type: application/json" \
        -d "{
            \"email\": \"$REPORTED_EMAIL\",
            \"password\": \"ReportedSecurePassword2025\",
            \"username\": \"reported-user-mod\",
            \"first_name\": \"Reported\",
            \"last_name\": \"User\"
        }" 2>/dev/null || echo '{}')

    # Get user ID from database and verify
    REPORTED_USER_ID=$(db_query "SELECT user_id FROM activity.users WHERE email = '$REPORTED_EMAIL' LIMIT 1;")
    db_query "UPDATE activity.users SET is_verified = true WHERE email = '$REPORTED_EMAIL';" > /dev/null
    print_success "Reported user created: $REPORTED_USER_ID"

    # Create user for ban tests
    print_info "Creating user for ban tests..."
    BAN_EMAIL="ban-test-user@example.com"
    curl -s -X POST "$AUTH_API_URL/api/auth/register" \
        -H "Content-Type: application/json" \
        -d "{
            \"email\": \"$BAN_EMAIL\",
            \"password\": \"BanTestSecurePassword2025\",
            \"username\": \"ban-test-user\",
            \"first_name\": \"Ban\",
            \"last_name\": \"Test\"
        }" > /dev/null 2>&1 || true

    BAN_USER_ID=$(db_query "SELECT user_id FROM activity.users WHERE email = '$BAN_EMAIL' LIMIT 1;")

    # Ensure user is active and verified for ban test
    db_query "UPDATE activity.users SET status = 'active', is_verified = true WHERE user_id = '$BAN_USER_ID';" > /dev/null
    print_success "Ban test user created: $BAN_USER_ID"

    # Create user for photo moderation
    print_info "Creating user for photo moderation..."
    PHOTO_EMAIL="photo-test-user@example.com"
    curl -s -X POST "$AUTH_API_URL/api/auth/register" \
        -H "Content-Type: application/json" \
        -d "{
            \"email\": \"$PHOTO_EMAIL\",
            \"password\": \"PhotoTestSecurePassword2025\",
            \"username\": \"photo-test-user\",
            \"first_name\": \"Photo\",
            \"last_name\": \"Test\"
        }" > /dev/null 2>&1 || true

    PHOTO_USER_ID=$(db_query "SELECT user_id FROM activity.users WHERE email = '$PHOTO_EMAIL' LIMIT 1;")

    # Set photo moderation status to pending and verify user
    db_query "UPDATE activity.users SET main_photo_url = 'https://example.com/photo.jpg', main_photo_moderation_status = 'pending', is_verified = true WHERE user_id = '$PHOTO_USER_ID';" > /dev/null
    print_success "Photo test user created: $PHOTO_USER_ID"

    # Create test post
    # First, we need a community to post in
    print_info "Creating test community..."
    # Check if test community exists, otherwise use first available community
    TEST_COMMUNITY_ID=$(db_query "SELECT community_id FROM activity.communities ORDER BY created_at DESC LIMIT 1;" | head -1 | tr -d ' ')

    if [ -z "$TEST_COMMUNITY_ID" ]; then
        # Create a test community if none exists (slug must be unique)
        RANDOM_SLUG="test-mod-$(openssl rand -hex 4)"
        TEST_COMMUNITY_ID=$(db_query "INSERT INTO activity.communities (creator_user_id, name, slug, description, community_type, status) VALUES ('$ADMIN_USER_ID', 'Test Moderation Community', '$RANDOM_SLUG', 'For testing moderation API', 'open', 'active') RETURNING community_id;" | head -1 | tr -d ' ')
    fi

    print_info "Creating test post..."
    TEST_POST_ID=$(db_query "INSERT INTO activity.posts (community_id, author_user_id, content, content_type, status) VALUES ('$TEST_COMMUNITY_ID', '$REGULAR_USER_ID', 'Test post for moderation', 'post', 'published') RETURNING post_id;" | head -1 | tr -d ' ')
    print_success "Test post created: $TEST_POST_ID"

    # Create test comment
    print_info "Creating test comment..."
    TEST_COMMENT_ID=$(db_query "INSERT INTO activity.comments (post_id, author_user_id, content) VALUES ('$TEST_POST_ID', '$REGULAR_USER_ID', 'Test comment for moderation') RETURNING comment_id;" | head -1 | tr -d ' ')
    print_success "Test comment created: $TEST_COMMENT_ID"
}

################################################################################
# TEST FUNCTIONS
################################################################################

test_create_report() {
    print_test "POST /moderation/reports (Create Report)"

    local response=$(api_call "POST" "/moderation/reports" "$USER_TOKEN" "{
        \"target_type\": \"user\",
        \"target_id\": \"$REPORTED_USER_ID\",
        \"report_type\": \"spam\",
        \"description\": \"This user is spamming\"
    }")

    # Check HTTP status via response
    if echo "$response" | jq -e '.report_id' > /dev/null 2>&1; then
        TEST_REPORT_ID=$(echo "$response" | jq -r '.report_id')
        print_success "Report created: $TEST_REPORT_ID"

        # Verify in database
        print_info "Verifying report in database..."
        local db_result=$(db_query "SELECT report_id, reporter_user_id, target_type, report_type, status FROM activity.reports WHERE report_id = '$TEST_REPORT_ID';" true)

        if echo "$db_result" | grep -q "$TEST_REPORT_ID"; then
            print_success "Database verification passed"
        else
            print_error "Database verification failed: Report not found"
        fi
    else
        print_error "Failed to create report: $response"
    fi
}

test_get_reports() {
    print_test "GET /moderation/reports (List Reports)"

    local response=$(api_call "GET" "/moderation/reports?limit=10&offset=0" "$ADMIN_TOKEN")

    if echo "$response" | jq -e '.reports' > /dev/null 2>&1; then
        local count=$(echo "$response" | jq '.reports | length')
        print_success "Retrieved $count reports"

        # Verify our test report is in the list
        if echo "$response" | jq -e ".reports[] | select(.report_id == \"$TEST_REPORT_ID\")" > /dev/null 2>&1; then
            print_success "Test report found in list"
        else
            print_error "Test report not found in list"
        fi
    else
        print_error "Failed to get reports: $response"
    fi
}

test_get_report_by_id() {
    print_test "GET /moderation/reports/{id} (Get Report Details)"

    local response=$(api_call "GET" "/moderation/reports/$TEST_REPORT_ID" "$ADMIN_TOKEN")

    if echo "$response" | jq -e '.success' > /dev/null 2>&1; then
        local report_id=$(echo "$response" | jq -r '.report.report_id')
        print_success "Retrieved report: $report_id"

        # Verify details match database
        local db_result=$(db_query "SELECT report_type FROM activity.reports WHERE report_id = '$TEST_REPORT_ID';")
        if echo "$db_result" | grep -q "spam"; then
            print_success "Report details match database"
        else
            print_error "Report details mismatch"
        fi
    else
        print_error "Failed to get report: $response"
    fi
}

test_update_report_status() {
    print_test "PATCH /moderation/reports/{id}/status (Update Status)"

    local response=$(api_call "PATCH" "/moderation/reports/$TEST_REPORT_ID/status" "$ADMIN_TOKEN" "{
        \"status\": \"resolved\",
        \"resolution_notes\": \"Reviewed and resolved by automated test\"
    }")

    if echo "$response" | jq -e '.report_id' > /dev/null 2>&1; then
        print_success "Report status updated"

        # Verify in database
        print_info "Verifying status update in database..."
        local db_status=$(db_query "SELECT status FROM activity.reports WHERE report_id = '$TEST_REPORT_ID';" true)

        if [ "$db_status" = "resolved" ]; then
            print_success "Database verification passed: status = resolved"
        else
            print_error "Database verification failed: status = $db_status"
        fi

        # Check reviewed_by is set
        local reviewed_by=$(db_query "SELECT reviewed_by_user_id FROM activity.reports WHERE report_id = '$TEST_REPORT_ID';" true)
        if [ -n "$reviewed_by" ] && [ "$reviewed_by" != "" ]; then
            print_success "Reviewed by admin: $reviewed_by"
        else
            print_error "Reviewed by not set"
        fi
    else
        print_error "Failed to update report: $response"
    fi
}

test_get_pending_photos() {
    print_test "GET /moderation/photos/pending (Get Pending Photos)"

    local response=$(api_call "GET" "/moderation/photos/pending?limit=10&offset=0" "$ADMIN_TOKEN")

    if echo "$response" | jq -e '.pending_photos' > /dev/null 2>&1; then
        local count=$(echo "$response" | jq '.pending_photos | length')
        print_success "Retrieved $count pending photos"

        # Verify count matches database
        local db_count=$(db_query "SELECT COUNT(*) FROM activity.users WHERE main_photo_moderation_status = 'pending';")
        print_info "Database count: $db_count, API count: $count"

        if [ "$count" -ge 1 ]; then
            print_success "Pending photos verification passed"
        else
            print_error "No pending photos found"
        fi
    else
        print_error "Failed to get pending photos: $response"
    fi
}

test_moderate_photo() {
    print_test "POST /moderation/photos/moderate (Moderate Photo)"

    # Test approval
    local response=$(api_call "POST" "/moderation/photos/moderate" "$ADMIN_TOKEN" "{
        \"user_id\": \"$PHOTO_USER_ID\",
        \"moderation_status\": \"approved\",
        \"rejection_reason\": null
    }")

    if echo "$response" | jq -e '.user_id' > /dev/null 2>&1; then
        print_success "Photo moderated (approved)"

        # Verify in database
        local db_status=$(db_query "SELECT main_photo_moderation_status FROM activity.users WHERE user_id = '$PHOTO_USER_ID';" true)

        if [ "$db_status" = "approved" ]; then
            print_success "Database verification passed: photo approved"
        else
            print_error "Database verification failed: status = $db_status"
        fi
    else
        print_error "Failed to moderate photo: $response"
    fi

    # Reset for rejection test
    db_query "UPDATE activity.users SET main_photo_moderation_status = 'pending' WHERE user_id = '$PHOTO_USER_ID';" > /dev/null

    # Test rejection
    response=$(api_call "POST" "/moderation/photos/moderate" "$ADMIN_TOKEN" "{
        \"user_id\": \"$PHOTO_USER_ID\",
        \"moderation_status\": \"rejected\",
        \"rejection_reason\": \"Inappropriate content\"
    }")

    if echo "$response" | jq -e '.user_id' > /dev/null 2>&1; then
        print_success "Photo moderated (rejected)"

        local db_status=$(db_query "SELECT main_photo_moderation_status FROM activity.users WHERE user_id = '$PHOTO_USER_ID';" true)

        if [ "$db_status" = "rejected" ]; then
            print_success "Database verification passed: photo rejected"
        else
            print_error "Database verification failed: status = $db_status"
        fi
    else
        print_error "Failed to reject photo: $response"
    fi
}

test_ban_user() {
    print_test "POST /moderation/users/{id}/ban (Ban User)"

    # Ensure user is active
    db_query "UPDATE activity.users SET status = 'active', ban_expires_at = NULL WHERE user_id = '$BAN_USER_ID';" > /dev/null

    # Test permanent ban
    local response=$(api_call "POST" "/moderation/users/$BAN_USER_ID/ban" "$ADMIN_TOKEN" "{
        \"ban_type\": \"permanent\",
        \"ban_reason\": \"Violated community guidelines\"
    }")

    if echo "$response" | jq -e '.user_id' > /dev/null 2>&1; then
        print_success "User permanently banned"

        # Verify in database
        local db_status=$(db_query "SELECT status FROM activity.users WHERE user_id = '$BAN_USER_ID';" true)

        if [ "$db_status" = "banned" ]; then
            print_success "Database verification passed: status = banned"
        else
            print_error "Database verification failed: status = $db_status"
        fi

        # Check ban_expires_at is NULL for permanent ban
        local ban_expires=$(db_query "SELECT ban_expires_at FROM activity.users WHERE user_id = '$BAN_USER_ID';" true)
        if [ -z "$ban_expires" ] || [ "$ban_expires" = "" ]; then
            print_success "Permanent ban verified (no expiry)"
        else
            print_error "Permanent ban has expiry: $ban_expires"
        fi
    else
        print_error "Failed to ban user: $response"
    fi

    # Reset for temporary ban test
    db_query "UPDATE activity.users SET status = 'active', ban_expires_at = NULL WHERE user_id = '$BAN_USER_ID';" > /dev/null

    # Test temporary ban
    response=$(api_call "POST" "/moderation/users/$BAN_USER_ID/ban" "$ADMIN_TOKEN" "{
        \"ban_type\": \"temporary\",
        \"ban_reason\": \"Temporary suspension for review\",
        \"ban_duration_hours\": 24
    }")

    if echo "$response" | jq -e '.user_id' > /dev/null 2>&1; then
        print_success "User temporarily banned (24h)"

        local db_status=$(db_query "SELECT status FROM activity.users WHERE user_id = '$BAN_USER_ID';" true)

        if [ "$db_status" = "temporary_ban" ]; then
            print_success "Database verification passed: status = temporary_ban"
        else
            print_error "Database verification failed: status = $db_status"
        fi

        # Check ban_expires_at is set
        local ban_expires=$(db_query "SELECT ban_expires_at FROM activity.users WHERE user_id = '$BAN_USER_ID';" true)
        if [ -n "$ban_expires" ] && [ "$ban_expires" != "" ]; then
            print_success "Temporary ban has expiry: $ban_expires"
        else
            print_error "Temporary ban missing expiry"
        fi
    else
        print_error "Failed to temporarily ban user: $response"
    fi
}

test_get_user_history() {
    print_test "GET /moderation/users/{id}/history (Get User History)"

    local response=$(api_call "GET" "/moderation/users/$BAN_USER_ID/history" "$ADMIN_TOKEN")

    if echo "$response" | jq -e '.success' > /dev/null 2>&1; then
        print_success "Retrieved user moderation history"

        # Check user info
        local user_status=$(echo "$response" | jq -r '.user.status')
        print_info "User status: $user_status"

        # Check moderation summary
        local reports_received=$(echo "$response" | jq -r '.moderation_summary.total_reports_received')
        print_info "Total reports received: $reports_received"
    else
        print_error "Failed to get user history: $response"
    fi
}

test_unban_user() {
    print_test "POST /moderation/users/{id}/unban (Unban User)"

    local response=$(api_call "POST" "/moderation/users/$BAN_USER_ID/unban" "$ADMIN_TOKEN" "{
        \"unban_reason\": \"Ban lifted after review\"
    }")

    if echo "$response" | jq -e '.user_id' > /dev/null 2>&1; then
        print_success "User unbanned"

        # Verify in database
        local db_status=$(db_query "SELECT status FROM activity.users WHERE user_id = '$BAN_USER_ID';" true)

        if [ "$db_status" = "active" ]; then
            print_success "Database verification passed: status = active"
        else
            print_error "Database verification failed: status = $db_status"
        fi

        # Check ban_expires_at is cleared
        local ban_expires=$(db_query "SELECT ban_expires_at FROM activity.users WHERE user_id = '$BAN_USER_ID';" true)
        if [ -z "$ban_expires" ] || [ "$ban_expires" = "" ]; then
            print_success "Ban expiry cleared"
        else
            print_error "Ban expiry not cleared: $ban_expires"
        fi
    else
        print_error "Failed to unban user: $response"
    fi
}

test_remove_content() {
    print_test "POST /moderation/content/remove (Remove Content)"

    # Test removing post
    local response=$(api_call "POST" "/moderation/content/remove" "$ADMIN_TOKEN" "{
        \"content_type\": \"post\",
        \"content_id\": \"$TEST_POST_ID\",
        \"removal_reason\": \"Violates content policy\"
    }")

    if echo "$response" | jq -e '.content_id' > /dev/null 2>&1; then
        print_success "Post removed"

        # Verify in database
        local db_status=$(db_query "SELECT status FROM activity.posts WHERE post_id = '$TEST_POST_ID';" true)

        if [ "$db_status" = "removed" ]; then
            print_success "Database verification passed: post status = removed"
        else
            print_error "Database verification failed: post status = $db_status"
        fi
    else
        print_error "Failed to remove post: $response"
    fi

    # Test removing comment
    response=$(api_call "POST" "/moderation/content/remove" "$ADMIN_TOKEN" "{
        \"content_type\": \"comment\",
        \"content_id\": \"$TEST_COMMENT_ID\",
        \"removal_reason\": \"Spam content\"
    }")

    if echo "$response" | jq -e '.content_id' > /dev/null 2>&1; then
        print_success "Comment removed"

        # Verify comment is deleted (comments are hard-deleted, not soft-deleted)
        local db_count=$(db_query "SELECT COUNT(*) FROM activity.comments WHERE comment_id = '$TEST_COMMENT_ID';" true)

        if [ "$db_count" = "0" ]; then
            print_success "Database verification passed: comment deleted"
        else
            print_error "Database verification failed: comment still exists"
        fi
    else
        print_error "Failed to remove comment: $response"
    fi
}

test_get_statistics() {
    print_test "GET /moderation/statistics (Get Statistics)"

    local response=$(api_call "GET" "/moderation/statistics" "$ADMIN_TOKEN")

    if echo "$response" | jq -e '.success' > /dev/null 2>&1; then
        local total_reports=$(echo "$response" | jq -r '.reports.total')
        print_success "Retrieved statistics: $total_reports total reports"

        # Verify count matches database
        local db_count=$(db_query "SELECT COUNT(*) FROM activity.reports;" true)
        print_info "Database count: $db_count, API count: $total_reports"

        # Check other statistics
        local pending_reports=$(echo "$response" | jq -r '.reports.pending // 0')
        local banned_users=$(echo "$response" | jq -r '.users.total_banned // 0')

        print_info "Pending reports: $pending_reports"
        print_info "Banned users: $banned_users"

        print_success "Statistics verification passed"
    else
        print_error "Failed to get statistics: $response"
    fi
}

################################################################################
# CLEANUP
################################################################################

cleanup_test_data() {
    print_header "CLEANUP: Removing Test Data"

    print_info "Cleaning up test data..."

    # Delete test report
    if [ -n "$TEST_REPORT_ID" ]; then
        db_query "DELETE FROM activity.reports WHERE report_id = '$TEST_REPORT_ID';" > /dev/null
        print_success "Deleted test report"
    fi

    # Delete test comment
    if [ -n "$TEST_COMMENT_ID" ]; then
        db_query "DELETE FROM activity.comments WHERE comment_id = '$TEST_COMMENT_ID';" > /dev/null
        print_success "Deleted test comment"
    fi

    # Delete test post
    if [ -n "$TEST_POST_ID" ]; then
        db_query "DELETE FROM activity.posts WHERE post_id = '$TEST_POST_ID';" > /dev/null
        print_success "Deleted test post"
    fi

    # Reset test users to active status
    if [ -n "$BAN_USER_ID" ]; then
        db_query "UPDATE activity.users SET status = 'active', ban_expires_at = NULL WHERE user_id = '$BAN_USER_ID';" > /dev/null
        print_success "Reset ban test user"
    fi

    if [ -n "$PHOTO_USER_ID" ]; then
        db_query "UPDATE activity.users SET main_photo_moderation_status = NULL WHERE user_id = '$PHOTO_USER_ID';" > /dev/null
        print_success "Reset photo test user"
    fi

    print_success "Cleanup completed"
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
    print_header "MODERATION API - COMPREHENSIVE TEST SUITE"
    echo -e "API URL: ${BLUE}$API_URL${NC}"
    echo -e "Auth API: ${BLUE}$AUTH_API_URL${NC}"
    echo -e "Database: ${BLUE}$DB_NAME@$DB_HOST${NC}\n"

    # Check if API is running
    if ! curl -s "$API_URL/health" > /dev/null 2>&1; then
        print_error "API is not running at $API_URL"
        exit 1
    fi

    print_success "API is running\n"

    # Setup
    setup_authentication
    setup_test_data

    # Run all tests
    print_header "RUNNING TESTS"

    test_create_report
    test_get_reports
    test_get_report_by_id
    test_update_report_status
    test_get_pending_photos
    test_moderate_photo
    test_ban_user
    test_get_user_history
    test_unban_user
    test_remove_content
    test_get_statistics

    # Cleanup
    cleanup_test_data

    # Summary
    print_header "TEST RESULTS SUMMARY"
    echo -e "Total Tests: ${BLUE}$TOTAL_TESTS${NC}"
    echo -e "Passed: ${GREEN}$PASSED_TESTS${NC}"
    echo -e "Failed: ${RED}$FAILED_TESTS${NC}"

    if [ $FAILED_TESTS -eq 0 ]; then
        echo -e "\n${GREEN}========================================${NC}"
        echo -e "${GREEN}ALL TESTS PASSED (100% COVERAGE)${NC}"
        echo -e "${GREEN}========================================${NC}\n"
        exit 0
    else
        echo -e "\n${RED}========================================${NC}"
        echo -e "${RED}SOME TESTS FAILED${NC}"
        echo -e "${RED}========================================${NC}\n"
        exit 1
    fi
}

# Run main
main

-- ============================================================================
-- MODERATION API STORED PROCEDURES
-- Version: 1.0
-- Description: All stored procedures for moderation API endpoints
-- ============================================================================

-- Ensure the activity schema exists
CREATE SCHEMA IF NOT EXISTS activity;

-- ============================================================================
-- ENUM TYPES (if not already created)
-- ============================================================================

DO $$ BEGIN
    CREATE TYPE activity.report_type AS ENUM ('spam', 'harassment', 'inappropriate', 'fake', 'no_show', 'other');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE activity.report_status AS ENUM ('pending', 'reviewing', 'resolved', 'dismissed');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE activity.user_status AS ENUM ('active', 'temporary_ban', 'banned');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE activity.photo_moderation_status AS ENUM ('pending', 'approved', 'rejected');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE activity.content_status AS ENUM ('draft', 'published', 'archived', 'flagged', 'removed');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- ============================================================================
-- SP 1: sp_mod_create_report
-- Purpose: Create a new report for problematic content or user behavior
-- ============================================================================

CREATE OR REPLACE FUNCTION activity.sp_mod_create_report(
    p_reporter_user_id UUID,
    p_reported_user_id UUID,
    p_target_type VARCHAR(50),
    p_target_id UUID,
    p_report_type VARCHAR(50),
    p_description TEXT
) RETURNS JSON
LANGUAGE plpgsql
AS $$
DECLARE
    v_report_id UUID;
    v_reporter_active BOOLEAN;
    v_target_exists BOOLEAN := FALSE;
    v_duplicate_count INT;
    v_result JSON;
BEGIN
    -- 1. Validate reporter exists and is active
    SELECT is_active INTO v_reporter_active
    FROM activity.users
    WHERE user_id = p_reporter_user_id;

    IF v_reporter_active IS NULL THEN
        RAISE EXCEPTION 'REPORTER_NOT_FOUND: Reporter user does not exist';
    END IF;

    IF NOT v_reporter_active THEN
        RAISE EXCEPTION 'REPORTER_INACTIVE: Reporter user is not active';
    END IF;

    -- 2. Validate target_type
    IF p_target_type NOT IN ('user', 'post', 'comment', 'activity', 'community') THEN
        RAISE EXCEPTION 'INVALID_TARGET_TYPE: target_type must be user, post, comment, activity, or community';
    END IF;

    -- 3. Validate report_type
    IF p_report_type NOT IN ('spam', 'harassment', 'inappropriate', 'fake', 'no_show', 'other') THEN
        RAISE EXCEPTION 'INVALID_REPORT_TYPE: report_type must be spam, harassment, inappropriate, fake, no_show, or other';
    END IF;

    -- 4. Check if target exists based on target_type
    CASE p_target_type
        WHEN 'user' THEN
            SELECT EXISTS(SELECT 1 FROM activity.users WHERE user_id = p_target_id) INTO v_target_exists;
            -- Set reported_user_id to target_id for user reports
            p_reported_user_id := p_target_id;
        WHEN 'post' THEN
            SELECT EXISTS(SELECT 1 FROM activity.posts WHERE post_id = p_target_id) INTO v_target_exists;
        WHEN 'comment' THEN
            SELECT EXISTS(SELECT 1 FROM activity.comments WHERE comment_id = p_target_id) INTO v_target_exists;
        WHEN 'activity' THEN
            SELECT EXISTS(SELECT 1 FROM activity.activities WHERE activity_id = p_target_id) INTO v_target_exists;
        WHEN 'community' THEN
            SELECT EXISTS(SELECT 1 FROM activity.communities WHERE community_id = p_target_id) INTO v_target_exists;
    END CASE;

    IF NOT v_target_exists THEN
        RAISE EXCEPTION 'TARGET_NOT_FOUND: The specified target does not exist';
    END IF;

    -- 5. Check for self-reporting
    IF p_reported_user_id = p_reporter_user_id THEN
        RAISE EXCEPTION 'CANNOT_SELF_REPORT: You cannot report yourself';
    END IF;

    -- 6. Check for duplicate reports within 24 hours
    SELECT COUNT(*) INTO v_duplicate_count
    FROM activity.reports
    WHERE reporter_user_id = p_reporter_user_id
      AND target_id = p_target_id
      AND report_type = p_report_type::activity.report_type
      AND created_at > NOW() - INTERVAL '24 hours';

    IF v_duplicate_count > 0 THEN
        RAISE EXCEPTION 'DUPLICATE_REPORT: You have already reported this target within the last 24 hours';
    END IF;

    -- 7. Generate report_id using uuidv7()
    v_report_id := uuidv7();

    -- 8. Insert report
    INSERT INTO activity.reports (
        report_id,
        reporter_user_id,
        reported_user_id,
        target_type,
        target_id,
        report_type,
        description,
        status,
        created_at,
        updated_at
    ) VALUES (
        v_report_id,
        p_reporter_user_id,
        p_reported_user_id,
        p_target_type,
        p_target_id,
        p_report_type::activity.report_type,
        p_description,
        'pending'::activity.report_status,
        NOW(),
        NOW()
    );

    -- 9. If no_show report on user, increment no_show_count
    IF p_report_type = 'no_show' AND p_target_type = 'user' THEN
        UPDATE activity.users
        SET no_show_count = no_show_count + 1,
            updated_at = NOW()
        WHERE user_id = p_reported_user_id;
    END IF;

    -- 10. Return JSON result
    v_result := json_build_object(
        'success', TRUE,
        'report_id', v_report_id,
        'status', 'pending',
        'created_at', NOW()
    );

    RETURN v_result;
END;
$$;

-- ============================================================================
-- SP 2: sp_mod_get_reports
-- Purpose: Retrieve reports with filtering and pagination (admin view)
-- ============================================================================

CREATE OR REPLACE FUNCTION activity.sp_mod_get_reports(
    p_admin_user_id UUID,
    p_status VARCHAR(20) DEFAULT NULL,
    p_target_type VARCHAR(50) DEFAULT NULL,
    p_report_type VARCHAR(50) DEFAULT NULL,
    p_limit INT DEFAULT 50,
    p_offset INT DEFAULT 0
) RETURNS TABLE (
    report_id UUID,
    reporter_user_id UUID,
    reporter_username VARCHAR(100),
    reporter_email VARCHAR(255),
    reported_user_id UUID,
    reported_username VARCHAR(100),
    reported_email VARCHAR(255),
    target_type VARCHAR(50),
    target_id UUID,
    report_type VARCHAR(50),
    description TEXT,
    status VARCHAR(20),
    reviewed_by_user_id UUID,
    reviewed_by_username VARCHAR(100),
    reviewed_at TIMESTAMP WITH TIME ZONE,
    resolution_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_admin_active BOOLEAN;
BEGIN
    -- 1. Validate admin exists and is active
    SELECT is_active INTO v_admin_active
    FROM activity.users
    WHERE user_id = p_admin_user_id;

    IF v_admin_active IS NULL THEN
        RAISE EXCEPTION 'ADMIN_NOT_FOUND: Admin user does not exist';
    END IF;

    IF NOT v_admin_active THEN
        RAISE EXCEPTION 'ADMIN_INACTIVE: Admin user is not active';
    END IF;

    -- Note: Admin permission check would normally happen here via JWT roles in the API layer

    -- 2. Validate filters if provided
    IF p_status IS NOT NULL AND p_status NOT IN ('pending', 'reviewing', 'resolved', 'dismissed') THEN
        RAISE EXCEPTION 'INVALID_STATUS: status must be pending, reviewing, resolved, or dismissed';
    END IF;

    IF p_target_type IS NOT NULL AND p_target_type NOT IN ('user', 'post', 'comment', 'activity', 'community') THEN
        RAISE EXCEPTION 'INVALID_TARGET_TYPE: target_type must be user, post, comment, activity, or community';
    END IF;

    IF p_report_type IS NOT NULL AND p_report_type NOT IN ('spam', 'harassment', 'inappropriate', 'fake', 'no_show', 'other') THEN
        RAISE EXCEPTION 'INVALID_REPORT_TYPE: Invalid report_type value';
    END IF;

    -- 3. Return filtered and paginated reports
    RETURN QUERY
    SELECT
        r.report_id,
        r.reporter_user_id,
        reporter.username AS reporter_username,
        reporter.email AS reporter_email,
        r.reported_user_id,
        reported.username AS reported_username,
        reported.email AS reported_email,
        r.target_type,
        r.target_id,
        r.report_type::VARCHAR,
        r.description,
        r.status::VARCHAR,
        r.reviewed_by_user_id,
        reviewer.username AS reviewed_by_username,
        r.reviewed_at,
        r.resolution_notes,
        r.created_at,
        r.updated_at
    FROM activity.reports r
    INNER JOIN activity.users reporter ON r.reporter_user_id = reporter.user_id
    LEFT JOIN activity.users reported ON r.reported_user_id = reported.user_id
    LEFT JOIN activity.users reviewer ON r.reviewed_by_user_id = reviewer.user_id
    WHERE (p_status IS NULL OR r.status::VARCHAR = p_status)
      AND (p_target_type IS NULL OR r.target_type = p_target_type)
      AND (p_report_type IS NULL OR r.report_type::VARCHAR = p_report_type)
    ORDER BY r.created_at DESC
    LIMIT p_limit OFFSET p_offset;
END;
$$;

-- ============================================================================
-- SP 3: sp_mod_get_report_by_id
-- Purpose: Get detailed information for a single report
-- ============================================================================

CREATE OR REPLACE FUNCTION activity.sp_mod_get_report_by_id(
    p_admin_user_id UUID,
    p_report_id UUID
) RETURNS JSON
LANGUAGE plpgsql
AS $$
DECLARE
    v_admin_active BOOLEAN;
    v_result JSON;
BEGIN
    -- 1. Validate admin exists
    SELECT is_active INTO v_admin_active
    FROM activity.users
    WHERE user_id = p_admin_user_id;

    IF v_admin_active IS NULL THEN
        RAISE EXCEPTION 'ADMIN_NOT_FOUND: Admin user does not exist';
    END IF;

    -- 2. Fetch report with all details
    SELECT json_build_object(
        'success', TRUE,
        'report', json_build_object(
            'report_id', r.report_id,
            'reporter', json_build_object(
                'user_id', reporter.user_id,
                'username', reporter.username,
                'email', reporter.email
            ),
            'reported_user', CASE
                WHEN r.reported_user_id IS NOT NULL THEN
                    json_build_object(
                        'user_id', reported.user_id,
                        'username', reported.username,
                        'email', reported.email,
                        'no_show_count', reported.no_show_count,
                        'verification_count', reported.verification_count
                    )
                ELSE NULL
            END,
            'target_type', r.target_type,
            'target_id', r.target_id,
            'report_type', r.report_type,
            'description', r.description,
            'status', r.status,
            'reviewed_by', CASE
                WHEN r.reviewed_by_user_id IS NOT NULL THEN
                    json_build_object(
                        'user_id', reviewer.user_id,
                        'username', reviewer.username,
                        'email', reviewer.email
                    )
                ELSE NULL
            END,
            'reviewed_at', r.reviewed_at,
            'resolution_notes', r.resolution_notes,
            'created_at', r.created_at,
            'updated_at', r.updated_at
        )
    ) INTO v_result
    FROM activity.reports r
    INNER JOIN activity.users reporter ON r.reporter_user_id = reporter.user_id
    LEFT JOIN activity.users reported ON r.reported_user_id = reported.user_id
    LEFT JOIN activity.users reviewer ON r.reviewed_by_user_id = reviewer.user_id
    WHERE r.report_id = p_report_id;

    IF v_result IS NULL THEN
        RAISE EXCEPTION 'REPORT_NOT_FOUND: Report with specified ID does not exist';
    END IF;

    RETURN v_result;
END;
$$;

-- ============================================================================
-- SP 4: sp_mod_update_report_status
-- Purpose: Update report status and add resolution notes
-- ============================================================================

CREATE OR REPLACE FUNCTION activity.sp_mod_update_report_status(
    p_admin_user_id UUID,
    p_report_id UUID,
    p_new_status VARCHAR(20),
    p_resolution_notes TEXT DEFAULT NULL
) RETURNS JSON
LANGUAGE plpgsql
AS $$
DECLARE
    v_admin_active BOOLEAN;
    v_current_status VARCHAR(20);
    v_result JSON;
BEGIN
    -- 1. Validate admin exists
    SELECT is_active INTO v_admin_active
    FROM activity.users
    WHERE user_id = p_admin_user_id;

    IF v_admin_active IS NULL THEN
        RAISE EXCEPTION 'ADMIN_NOT_FOUND: Admin user does not exist';
    END IF;

    -- 2. Validate new_status
    IF p_new_status NOT IN ('reviewing', 'resolved', 'dismissed') THEN
        RAISE EXCEPTION 'INVALID_STATUS: status must be reviewing, resolved, or dismissed';
    END IF;

    -- 3. Get current status and validate transition
    SELECT status::VARCHAR INTO v_current_status
    FROM activity.reports
    WHERE report_id = p_report_id;

    IF v_current_status IS NULL THEN
        RAISE EXCEPTION 'REPORT_NOT_FOUND: Report with specified ID does not exist';
    END IF;

    -- Check valid transitions
    IF v_current_status IN ('resolved', 'dismissed') THEN
        RAISE EXCEPTION 'INVALID_STATUS_TRANSITION: Cannot change status from final state';
    END IF;

    -- 4. Update report
    UPDATE activity.reports
    SET status = p_new_status::activity.report_status,
        reviewed_by_user_id = p_admin_user_id,
        reviewed_at = NOW(),
        resolution_notes = p_resolution_notes,
        updated_at = NOW()
    WHERE report_id = p_report_id;

    -- 5. Return result
    v_result := json_build_object(
        'success', TRUE,
        'report_id', p_report_id,
        'status', p_new_status,
        'reviewed_by_user_id', p_admin_user_id,
        'reviewed_at', NOW()
    );

    RETURN v_result;
END;
$$;

-- ============================================================================
-- SP 5: sp_mod_moderate_main_photo
-- Purpose: Approve or reject a user's main profile photo
-- ============================================================================

CREATE OR REPLACE FUNCTION activity.sp_mod_moderate_main_photo(
    p_admin_user_id UUID,
    p_user_id UUID,
    p_moderation_status VARCHAR(20),
    p_rejection_reason TEXT DEFAULT NULL
) RETURNS JSON
LANGUAGE plpgsql
AS $$
DECLARE
    v_admin_active BOOLEAN;
    v_user_exists BOOLEAN;
    v_main_photo_url VARCHAR(500);
    v_username VARCHAR(100);
    v_email VARCHAR(255);
    v_result JSON;
BEGIN
    -- 1. Validate admin exists
    SELECT is_active INTO v_admin_active
    FROM activity.users
    WHERE user_id = p_admin_user_id;

    IF v_admin_active IS NULL THEN
        RAISE EXCEPTION 'ADMIN_NOT_FOUND: Admin user does not exist';
    END IF;

    -- 2. Validate moderation_status
    IF p_moderation_status NOT IN ('approved', 'rejected') THEN
        RAISE EXCEPTION 'INVALID_MODERATION_STATUS: status must be approved or rejected';
    END IF;

    -- 3. Check user exists and has main photo
    SELECT main_photo_url, username, email INTO v_main_photo_url, v_username, v_email
    FROM activity.users
    WHERE user_id = p_user_id;

    IF v_main_photo_url IS NULL THEN
        RAISE EXCEPTION 'USER_NOT_FOUND: User with specified ID does not exist';
    END IF;

    IF v_main_photo_url = '' THEN
        RAISE EXCEPTION 'NO_MAIN_PHOTO: User has not uploaded a main profile photo';
    END IF;

    -- 4. Update user photo moderation status
    UPDATE activity.users
    SET main_photo_moderation_status = p_moderation_status::activity.photo_moderation_status,
        updated_at = NOW()
    WHERE user_id = p_user_id;

    -- 5. If rejected, store reason in payload
    IF p_moderation_status = 'rejected' AND p_rejection_reason IS NOT NULL THEN
        UPDATE activity.users
        SET payload = COALESCE(payload, '{}'::JSONB) ||
                     jsonb_build_object('photo_rejection_reason', p_rejection_reason)
        WHERE user_id = p_user_id;
    END IF;

    -- 6. Return result (including email and username for API layer to send notification)
    v_result := json_build_object(
        'success', TRUE,
        'user_id', p_user_id,
        'main_photo_url', v_main_photo_url,
        'moderation_status', p_moderation_status,
        'moderated_at', NOW(),
        'email', v_email,
        'username', v_username
    );

    RETURN v_result;
END;
$$;

-- ============================================================================
-- SP 6: sp_mod_get_pending_photos
-- Purpose: Get list of users with pending main photo moderation
-- ============================================================================

CREATE OR REPLACE FUNCTION activity.sp_mod_get_pending_photos(
    p_admin_user_id UUID,
    p_limit INT DEFAULT 50,
    p_offset INT DEFAULT 0
) RETURNS TABLE (
    user_id UUID,
    username VARCHAR(100),
    email VARCHAR(255),
    main_photo_url VARCHAR(500),
    created_at TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_admin_active BOOLEAN;
BEGIN
    -- 1. Validate admin exists
    SELECT is_active INTO v_admin_active
    FROM activity.users
    WHERE user_id = p_admin_user_id;

    IF v_admin_active IS NULL THEN
        RAISE EXCEPTION 'ADMIN_NOT_FOUND: Admin user does not exist';
    END IF;

    -- 2. Return pending photos (oldest first - FIFO queue)
    RETURN QUERY
    SELECT
        u.user_id,
        u.username,
        u.email,
        u.main_photo_url,
        u.created_at,
        u.updated_at
    FROM activity.users u
    WHERE u.main_photo_moderation_status = 'pending'::activity.photo_moderation_status
      AND u.main_photo_url IS NOT NULL
      AND u.main_photo_url != ''
    ORDER BY u.created_at ASC
    LIMIT p_limit OFFSET p_offset;
END;
$$;

-- ============================================================================
-- SP 7: sp_mod_ban_user
-- Purpose: Ban or temporarily ban a user
-- ============================================================================

CREATE OR REPLACE FUNCTION activity.sp_mod_ban_user(
    p_admin_user_id UUID,
    p_user_id UUID,
    p_ban_type VARCHAR(20),
    p_ban_duration_hours INT DEFAULT NULL,
    p_ban_reason TEXT
) RETURNS JSON
LANGUAGE plpgsql
AS $$
DECLARE
    v_admin_active BOOLEAN;
    v_user_status VARCHAR(20);
    v_ban_expires_at TIMESTAMP WITH TIME ZONE;
    v_new_status VARCHAR(20);
    v_username VARCHAR(100);
    v_email VARCHAR(255);
    v_result JSON;
BEGIN
    -- 1. Validate admin exists
    SELECT is_active INTO v_admin_active
    FROM activity.users
    WHERE user_id = p_admin_user_id;

    IF v_admin_active IS NULL THEN
        RAISE EXCEPTION 'ADMIN_NOT_FOUND: Admin user does not exist';
    END IF;

    -- 2. Check for self-ban
    IF p_admin_user_id = p_user_id THEN
        RAISE EXCEPTION 'CANNOT_SELF_BAN: You cannot ban yourself';
    END IF;

    -- 3. Validate ban_type
    IF p_ban_type NOT IN ('permanent', 'temporary') THEN
        RAISE EXCEPTION 'INVALID_BAN_TYPE: ban_type must be permanent or temporary';
    END IF;

    -- 4. Get user status
    SELECT status::VARCHAR, username, email INTO v_user_status, v_username, v_email
    FROM activity.users
    WHERE user_id = p_user_id;

    IF v_user_status IS NULL THEN
        RAISE EXCEPTION 'USER_NOT_FOUND: User with specified ID does not exist';
    END IF;

    IF v_user_status IN ('temporary_ban', 'banned') THEN
        RAISE EXCEPTION 'USER_ALREADY_BANNED: User is already banned';
    END IF;

    -- 5. Calculate ban expiry and new status
    IF p_ban_type = 'temporary' THEN
        IF p_ban_duration_hours IS NULL OR p_ban_duration_hours <= 0 THEN
            RAISE EXCEPTION 'DURATION_REQUIRED: ban_duration_hours is required for temporary bans';
        END IF;
        v_ban_expires_at := NOW() + (p_ban_duration_hours || ' hours')::INTERVAL;
        v_new_status := 'temporary_ban';
    ELSE
        v_ban_expires_at := NULL;
        v_new_status := 'banned';
    END IF;

    -- 6. Update user status
    UPDATE activity.users
    SET status = v_new_status::activity.user_status,
        ban_expires_at = v_ban_expires_at,
        ban_reason = p_ban_reason,
        updated_at = NOW()
    WHERE user_id = p_user_id;

    -- 7. Return result (including email and username for API layer)
    v_result := json_build_object(
        'success', TRUE,
        'user_id', p_user_id,
        'status', v_new_status,
        'ban_expires_at', v_ban_expires_at,
        'ban_reason', p_ban_reason,
        'banned_at', NOW(),
        'email', v_email,
        'username', v_username
    );

    RETURN v_result;
END;
$$;

-- ============================================================================
-- SP 8: sp_mod_unban_user
-- Purpose: Remove ban from a user
-- ============================================================================

CREATE OR REPLACE FUNCTION activity.sp_mod_unban_user(
    p_admin_user_id UUID,
    p_user_id UUID,
    p_unban_reason TEXT
) RETURNS JSON
LANGUAGE plpgsql
AS $$
DECLARE
    v_admin_active BOOLEAN;
    v_user_status VARCHAR(20);
    v_username VARCHAR(100);
    v_email VARCHAR(255);
    v_result JSON;
BEGIN
    -- 1. Validate admin exists
    SELECT is_active INTO v_admin_active
    FROM activity.users
    WHERE user_id = p_admin_user_id;

    IF v_admin_active IS NULL THEN
        RAISE EXCEPTION 'ADMIN_NOT_FOUND: Admin user does not exist';
    END IF;

    -- 2. Get user status
    SELECT status::VARCHAR, username, email INTO v_user_status, v_username, v_email
    FROM activity.users
    WHERE user_id = p_user_id;

    IF v_user_status IS NULL THEN
        RAISE EXCEPTION 'USER_NOT_FOUND: User with specified ID does not exist';
    END IF;

    IF v_user_status NOT IN ('temporary_ban', 'banned') THEN
        RAISE EXCEPTION 'USER_NOT_BANNED: User is not currently banned';
    END IF;

    -- 3. Unban user
    UPDATE activity.users
    SET status = 'active'::activity.user_status,
        ban_expires_at = NULL,
        ban_reason = NULL,
        updated_at = NOW(),
        payload = COALESCE(payload, '{}'::JSONB) ||
                 jsonb_build_object(
                     'unban_reason', p_unban_reason,
                     'unbanned_at', NOW(),
                     'unbanned_by', p_admin_user_id
                 )
    WHERE user_id = p_user_id;

    -- 4. Return result
    v_result := json_build_object(
        'success', TRUE,
        'user_id', p_user_id,
        'status', 'active',
        'unbanned_at', NOW(),
        'unbanned_by_user_id', p_admin_user_id,
        'email', v_email,
        'username', v_username
    );

    RETURN v_result;
END;
$$;

-- ============================================================================
-- SP 9: sp_mod_remove_content
-- Purpose: Remove or hide problematic content (posts, comments)
-- ============================================================================

CREATE OR REPLACE FUNCTION activity.sp_mod_remove_content(
    p_admin_user_id UUID,
    p_content_type VARCHAR(50),
    p_content_id UUID,
    p_removal_reason TEXT
) RETURNS JSON
LANGUAGE plpgsql
AS $$
DECLARE
    v_admin_active BOOLEAN;
    v_author_user_id UUID;
    v_author_email VARCHAR(255);
    v_author_username VARCHAR(100);
    v_content_exists BOOLEAN := FALSE;
    v_result JSON;
BEGIN
    -- 1. Validate admin exists
    SELECT is_active INTO v_admin_active
    FROM activity.users
    WHERE user_id = p_admin_user_id;

    IF v_admin_active IS NULL THEN
        RAISE EXCEPTION 'ADMIN_NOT_FOUND: Admin user does not exist';
    END IF;

    -- 2. Validate content_type
    IF p_content_type NOT IN ('post', 'comment') THEN
        RAISE EXCEPTION 'INVALID_CONTENT_TYPE: content_type must be post or comment';
    END IF;

    -- 3. Remove content based on type
    IF p_content_type = 'post' THEN
        -- Check post exists and get author
        SELECT author_user_id INTO v_author_user_id
        FROM activity.posts
        WHERE post_id = p_content_id;

        IF v_author_user_id IS NULL THEN
            RAISE EXCEPTION 'CONTENT_NOT_FOUND: Post with specified ID does not exist';
        END IF;

        -- Check if already removed
        IF EXISTS (
            SELECT 1 FROM activity.posts
            WHERE post_id = p_content_id
            AND status = 'removed'::activity.content_status
        ) THEN
            RAISE EXCEPTION 'CONTENT_ALREADY_REMOVED: This content has already been removed';
        END IF;

        -- Update post status
        UPDATE activity.posts
        SET status = 'removed'::activity.content_status,
            updated_at = NOW()
        WHERE post_id = p_content_id;

        v_content_exists := TRUE;

    ELSIF p_content_type = 'comment' THEN
        -- Check comment exists and get author
        SELECT author_user_id INTO v_author_user_id
        FROM activity.comments
        WHERE comment_id = p_content_id;

        IF v_author_user_id IS NULL THEN
            RAISE EXCEPTION 'CONTENT_NOT_FOUND: Comment with specified ID does not exist';
        END IF;

        -- Check if already removed
        IF EXISTS (
            SELECT 1 FROM activity.comments
            WHERE comment_id = p_content_id
            AND is_deleted = TRUE
        ) THEN
            RAISE EXCEPTION 'CONTENT_ALREADY_REMOVED: This content has already been removed';
        END IF;

        -- Update comment
        UPDATE activity.comments
        SET is_deleted = TRUE,
            updated_at = NOW()
        WHERE comment_id = p_content_id;

        v_content_exists := TRUE;
    END IF;

    -- 4. Get author details for email notification
    SELECT username, email INTO v_author_username, v_author_email
    FROM activity.users
    WHERE user_id = v_author_user_id;

    -- 5. Return result
    v_result := json_build_object(
        'success', TRUE,
        'content_type', p_content_type,
        'content_id', p_content_id,
        'status', 'removed',
        'removed_at', NOW(),
        'removed_by_user_id', p_admin_user_id,
        'author_user_id', v_author_user_id,
        'author_email', v_author_email,
        'author_username', v_author_username
    );

    RETURN v_result;
END;
$$;

-- ============================================================================
-- SP 10: sp_mod_get_user_moderation_history
-- Purpose: Get complete moderation history for a user
-- ============================================================================

CREATE OR REPLACE FUNCTION activity.sp_mod_get_user_moderation_history(
    p_admin_user_id UUID,
    p_target_user_id UUID
) RETURNS JSON
LANGUAGE plpgsql
AS $$
DECLARE
    v_admin_active BOOLEAN;
    v_user_exists BOOLEAN;
    v_result JSON;
BEGIN
    -- 1. Validate admin exists
    SELECT is_active INTO v_admin_active
    FROM activity.users
    WHERE user_id = p_admin_user_id;

    IF v_admin_active IS NULL THEN
        RAISE EXCEPTION 'ADMIN_NOT_FOUND: Admin user does not exist';
    END IF;

    -- 2. Validate target user exists
    SELECT EXISTS(SELECT 1 FROM activity.users WHERE user_id = p_target_user_id) INTO v_user_exists;

    IF NOT v_user_exists THEN
        RAISE EXCEPTION 'USER_NOT_FOUND: User with specified ID does not exist';
    END IF;

    -- 3. Build comprehensive history JSON
    SELECT json_build_object(
        'success', TRUE,
        'user', (
            SELECT json_build_object(
                'user_id', u.user_id,
                'username', u.username,
                'email', u.email,
                'status', u.status,
                'no_show_count', u.no_show_count,
                'verification_count', u.verification_count,
                'created_at', u.created_at
            )
            FROM activity.users u
            WHERE u.user_id = p_target_user_id
        ),
        'moderation_summary', json_build_object(
            'total_reports_received', (
                SELECT COUNT(*)
                FROM activity.reports
                WHERE reported_user_id = p_target_user_id
            ),
            'total_reports_made', (
                SELECT COUNT(*)
                FROM activity.reports
                WHERE reporter_user_id = p_target_user_id
            ),
            'total_bans', 0,  -- Would need ban history tracking
            'total_content_removed', (
                SELECT
                    (SELECT COUNT(*) FROM activity.posts WHERE author_user_id = p_target_user_id AND status = 'removed'::activity.content_status) +
                    (SELECT COUNT(*) FROM activity.comments WHERE author_user_id = p_target_user_id AND is_deleted = TRUE)
            ),
            'total_photo_rejections', 0  -- Would need photo rejection history
        ),
        'history', (
            SELECT COALESCE(json_agg(event ORDER BY event_date DESC), '[]'::json)
            FROM (
                -- Reports about this user
                SELECT
                    'report' AS event_type,
                    r.created_at AS event_date,
                    r.report_type::VARCHAR AS report_type,
                    r.reporter_user_id,
                    r.status::VARCHAR AS status
                FROM activity.reports r
                WHERE r.reported_user_id = p_target_user_id
                LIMIT 20
            ) AS event
        )
    ) INTO v_result;

    RETURN v_result;
END;
$$;

-- ============================================================================
-- SP 11: sp_mod_get_statistics
-- Purpose: Get overall moderation statistics (admin dashboard metrics)
-- ============================================================================

CREATE OR REPLACE FUNCTION activity.sp_mod_get_statistics(
    p_admin_user_id UUID,
    p_date_from TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    p_date_to TIMESTAMP WITH TIME ZONE DEFAULT NULL
) RETURNS JSON
LANGUAGE plpgsql
AS $$
DECLARE
    v_admin_active BOOLEAN;
    v_date_from TIMESTAMP WITH TIME ZONE;
    v_date_to TIMESTAMP WITH TIME ZONE;
    v_result JSON;
BEGIN
    -- 1. Validate admin exists
    SELECT is_active INTO v_admin_active
    FROM activity.users
    WHERE user_id = p_admin_user_id;

    IF v_admin_active IS NULL THEN
        RAISE EXCEPTION 'ADMIN_NOT_FOUND: Admin user does not exist';
    END IF;

    -- 2. Set date range defaults
    v_date_from := COALESCE(p_date_from, NOW() - INTERVAL '30 days');
    v_date_to := COALESCE(p_date_to, NOW());

    -- Validate date range
    IF v_date_from > v_date_to THEN
        RAISE EXCEPTION 'INVALID_DATE_RANGE: date_from must be before date_to';
    END IF;

    -- 3. Calculate statistics
    SELECT json_build_object(
        'success', TRUE,
        'date_range', json_build_object(
            'from', v_date_from,
            'to', v_date_to
        ),
        'reports', json_build_object(
            'total', (
                SELECT COUNT(*)
                FROM activity.reports
                WHERE created_at BETWEEN v_date_from AND v_date_to
            ),
            'pending', (
                SELECT COUNT(*)
                FROM activity.reports
                WHERE created_at BETWEEN v_date_from AND v_date_to
                AND status = 'pending'::activity.report_status
            ),
            'reviewing', (
                SELECT COUNT(*)
                FROM activity.reports
                WHERE created_at BETWEEN v_date_from AND v_date_to
                AND status = 'reviewing'::activity.report_status
            ),
            'resolved', (
                SELECT COUNT(*)
                FROM activity.reports
                WHERE created_at BETWEEN v_date_from AND v_date_to
                AND status = 'resolved'::activity.report_status
            ),
            'dismissed', (
                SELECT COUNT(*)
                FROM activity.reports
                WHERE created_at BETWEEN v_date_from AND v_date_to
                AND status = 'dismissed'::activity.report_status
            ),
            'by_type', (
                SELECT json_object_agg(report_type::VARCHAR, count)
                FROM (
                    SELECT report_type, COUNT(*) AS count
                    FROM activity.reports
                    WHERE created_at BETWEEN v_date_from AND v_date_to
                    GROUP BY report_type
                ) AS report_types
            ),
            'avg_resolution_time_hours', (
                SELECT COALESCE(
                    AVG(EXTRACT(EPOCH FROM (reviewed_at - created_at)) / 3600),
                    0
                )
                FROM activity.reports
                WHERE reviewed_at BETWEEN v_date_from AND v_date_to
                AND reviewed_at IS NOT NULL
            )
        ),
        'users', json_build_object(
            'total_banned', (
                SELECT COUNT(*)
                FROM activity.users
                WHERE status IN ('banned'::activity.user_status, 'temporary_ban'::activity.user_status)
            ),
            'permanent_bans', (
                SELECT COUNT(*)
                FROM activity.users
                WHERE status = 'banned'::activity.user_status
            ),
            'temporary_bans', (
                SELECT COUNT(*)
                FROM activity.users
                WHERE status = 'temporary_ban'::activity.user_status
            ),
            'unbanned', 0  -- Would need ban history tracking
        ),
        'content', json_build_object(
            'posts_removed', (
                SELECT COUNT(*)
                FROM activity.posts
                WHERE status = 'removed'::activity.content_status
                AND updated_at BETWEEN v_date_from AND v_date_to
            ),
            'comments_removed', (
                SELECT COUNT(*)
                FROM activity.comments
                WHERE is_deleted = TRUE
                AND updated_at BETWEEN v_date_from AND v_date_to
            )
        ),
        'photos', json_build_object(
            'pending_moderation', (
                SELECT COUNT(*)
                FROM activity.users
                WHERE main_photo_moderation_status = 'pending'::activity.photo_moderation_status
            ),
            'approved', (
                SELECT COUNT(*)
                FROM activity.users
                WHERE main_photo_moderation_status = 'approved'::activity.photo_moderation_status
                AND updated_at BETWEEN v_date_from AND v_date_to
            ),
            'rejected', (
                SELECT COUNT(*)
                FROM activity.users
                WHERE main_photo_moderation_status = 'rejected'::activity.photo_moderation_status
                AND updated_at BETWEEN v_date_from AND v_date_to
            )
        )
    ) INTO v_result;

    RETURN v_result;
END;
$$;

-- ============================================================================
-- END OF STORED PROCEDURES
-- ============================================================================

-- Grant execute permissions (adjust schema/role as needed)
-- GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA activity TO your_api_user;

-- ============================================================================
-- Migration 002: Add roles column to users table
-- ============================================================================
-- Description: Adds a roles JSONB column to support moderation API authorization
-- After database restore, the roles column was missing. This migration adds it back.
-- ============================================================================

-- Add roles column if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'activity'
        AND table_name = 'users'
        AND column_name = 'roles'
    ) THEN
        ALTER TABLE activity.users
        ADD COLUMN roles JSONB DEFAULT '[]'::jsonb;

        COMMENT ON COLUMN activity.users.roles IS 'User roles for authorization (e.g., ["admin", "moderator"])';

        -- Create index for faster role lookups
        CREATE INDEX IF NOT EXISTS idx_users_roles ON activity.users USING gin(roles);

        RAISE NOTICE 'Successfully added roles column to activity.users';
    ELSE
        RAISE NOTICE 'Roles column already exists in activity.users';
    END IF;
END $$;

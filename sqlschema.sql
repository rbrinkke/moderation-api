-- ============================================================================
-- COMPLETE ACTIVITIES PLATFORM SCHEMA V3
-- Full Meet5-compatible schema with ALL privacy, monetization, and trust features
-- Includes: Asymmetric blocking, Ghost mode, Main photo moderation, Priority participation
-- ============================================================================

-- ============================================================================
-- SCHEMA SETUP
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS activity;

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

CREATE OR REPLACE FUNCTION activity.update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION uuidv7()
RETURNS UUID AS $$
DECLARE
    unix_ts_ms BIGINT;
    uuid_bytes BYTEA;
BEGIN
    unix_ts_ms := (EXTRACT(EPOCH FROM clock_timestamp()) * 1000)::BIGINT;
    uuid_bytes := decode(
        lpad(to_hex(unix_ts_ms), 12, '0') || 
        encode(gen_random_bytes(10), 'hex'),
        'hex'
    );
    RETURN encode(
        set_byte(
            set_byte(uuid_bytes, 6, (get_byte(uuid_bytes, 6) & 15) | 112),
            8, (get_byte(uuid_bytes, 8) & 63) | 128
        ),
        'hex'
    )::UUID;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- ENUM TYPES
-- ============================================================================

-- User-related enums
CREATE TYPE activity.subscription_level AS ENUM ('free', 'club', 'premium');
CREATE TYPE activity.user_status AS ENUM ('active', 'temporary_ban', 'banned');
CREATE TYPE activity.participant_role AS ENUM ('organizer', 'co_organizer', 'member');
CREATE TYPE activity.photo_moderation_status AS ENUM ('pending', 'approved', 'rejected');

-- Activity-related enums
CREATE TYPE activity.activity_type AS ENUM ('standard', 'xxl', 'womens_only', 'mens_only');
CREATE TYPE activity.activity_privacy_level AS ENUM ('public', 'friends_only', 'invite_only');
CREATE TYPE activity.activity_status AS ENUM ('draft', 'published', 'cancelled', 'completed');
CREATE TYPE activity.participation_status AS ENUM ('registered', 'waitlisted', 'declined', 'cancelled');
CREATE TYPE activity.attendance_status AS ENUM ('registered', 'attended', 'no_show');

-- Organization enums
CREATE TYPE activity.organization_role AS ENUM ('owner', 'admin', 'moderator', 'member');
CREATE TYPE activity.organization_status AS ENUM ('active', 'suspended', 'archived');

-- Community enums
CREATE TYPE activity.community_type AS ENUM ('open', 'closed', 'secret');
CREATE TYPE activity.community_status AS ENUM ('active', 'archived', 'suspended');
CREATE TYPE activity.membership_status AS ENUM ('pending', 'active', 'banned', 'left');

-- Content enums
CREATE TYPE activity.content_type AS ENUM ('post', 'photo', 'video', 'poll', 'event_announcement');
CREATE TYPE activity.content_status AS ENUM ('draft', 'published', 'archived', 'flagged', 'removed');

-- Interaction enums
CREATE TYPE activity.reaction_type AS ENUM ('like', 'love', 'celebrate', 'support', 'insightful');
CREATE TYPE activity.invitation_status AS ENUM ('pending', 'accepted', 'declined', 'expired');

-- Notification enums
CREATE TYPE activity.notification_type AS ENUM (
    'activity_invite', 
    'activity_reminder', 
    'activity_update',
    'community_invite',
    'new_member',
    'new_post',
    'comment',
    'reaction',
    'mention',
    'profile_view',
    'new_favorite',
    'system'
);
CREATE TYPE activity.notification_status AS ENUM ('unread', 'read', 'archived');

-- Gamification enums
CREATE TYPE activity.badge_category AS ENUM ('participation', 'achievement', 'milestone', 'special', 'verification');

-- Moderation enums
CREATE TYPE activity.report_status AS ENUM ('pending', 'reviewing', 'resolved', 'dismissed');
CREATE TYPE activity.report_type AS ENUM ('spam', 'harassment', 'inappropriate', 'fake', 'no_show', 'other');

-- ============================================================================
-- CORE USER TABLES
-- ============================================================================

-- 1. users - Core user accounts with Meet5 subscription model
CREATE TABLE activity.users (
    user_id UUID PRIMARY KEY DEFAULT uuidv7(),
    email VARCHAR(255) UNIQUE NOT NULL,
    username VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    
    -- Profile fields - CRITICAL CHANGE: Separated main photo for moderation
    profile_description TEXT,
    main_photo_url VARCHAR(500),
    main_photo_moderation_status activity.photo_moderation_status DEFAULT 'pending',
    profile_photos_extra JSONB DEFAULT '[]'::JSONB,
    date_of_birth DATE,
    gender VARCHAR(50),
    
    -- Meet5 subscription & status
    subscription_level activity.subscription_level NOT NULL DEFAULT 'free',
    subscription_expires_at TIMESTAMP WITH TIME ZONE,
    status activity.user_status NOT NULL DEFAULT 'active',
    ban_expires_at TIMESTAMP WITH TIME ZONE,
    ban_reason TEXT,
    
    -- Captain program
    is_captain BOOLEAN NOT NULL DEFAULT FALSE,
    captain_since TIMESTAMP WITH TIME ZONE,
    
    -- Activity tracking
    last_seen_at TIMESTAMP WITH TIME ZONE,
    activities_created_count INT NOT NULL DEFAULT 0,
    activities_attended_count INT NOT NULL DEFAULT 0,
    
    -- Verification & trust
    is_verified BOOLEAN NOT NULL DEFAULT FALSE,
    verification_count INT NOT NULL DEFAULT 0,
    no_show_count INT NOT NULL DEFAULT 0,
    
    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    last_login_at TIMESTAMP WITH TIME ZONE,
    
    -- Flexible storage
    payload JSONB,
    hash_value VARCHAR(64),
    
    CONSTRAINT check_counts_non_negative CHECK (
        activities_created_count >= 0 AND 
        activities_attended_count >= 0 AND
        verification_count >= 0 AND
        no_show_count >= 0
    ),
    CONSTRAINT check_subscription_expiry CHECK (
        subscription_level = 'free' OR subscription_expires_at IS NOT NULL
    ),
    CONSTRAINT check_ban_expiry CHECK (
        status != 'temporary_ban' OR ban_expires_at IS NOT NULL
    )
);

CREATE TRIGGER set_users_timestamp 
    BEFORE UPDATE ON activity.users 
    FOR EACH ROW EXECUTE FUNCTION activity.update_timestamp();

CREATE INDEX idx_users_email ON activity.users(email);
CREATE INDEX idx_users_username ON activity.users(username);
CREATE INDEX idx_users_subscription ON activity.users(subscription_level, subscription_expires_at);
CREATE INDEX idx_users_status ON activity.users(status) WHERE status != 'active';
CREATE INDEX idx_users_captain ON activity.users(is_captain) WHERE is_captain = TRUE;
CREATE INDEX idx_users_verified ON activity.users(is_verified) WHERE is_verified = TRUE;
CREATE INDEX idx_users_main_photo_moderation ON activity.users(main_photo_moderation_status) 
    WHERE main_photo_moderation_status = 'pending';

COMMENT ON TABLE activity.users IS 'Core user accounts with Meet5 subscription model and verification system';
COMMENT ON COLUMN activity.users.subscription_level IS 'Subscription tier: free (basic), club (mid-tier), premium (full features)';
COMMENT ON COLUMN activity.users.is_captain IS 'Captain program members receive free Premium subscription';
COMMENT ON COLUMN activity.users.verification_count IS 'Number of successful attendance verifications by other users';
COMMENT ON COLUMN activity.users.no_show_count IS 'Number of reported no-shows (affects trust score)';
COMMENT ON COLUMN activity.users.main_photo_url IS 'Primary profile photo - MUST show clear face (functional safety requirement)';
COMMENT ON COLUMN activity.users.main_photo_moderation_status IS 'Moderation status of main photo: pending, approved, rejected';
COMMENT ON COLUMN activity.users.profile_photos_extra IS 'Additional profile photos (up to 8 total) stored as JSON array';

-- ============================================================================
-- ACTIVITY CATEGORIES
-- ============================================================================

-- 2. categories - Activity categories (single per activity, Premium filter)
CREATE TABLE activity.categories (
    category_id UUID PRIMARY KEY DEFAULT uuidv7(),
    name VARCHAR(100) UNIQUE NOT NULL,
    slug VARCHAR(100) UNIQUE NOT NULL,
    description TEXT,
    icon_url VARCHAR(500),
    display_order INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    payload JSONB,
    
    CONSTRAINT check_slug_format CHECK (slug ~ '^[a-z0-9-]+$')
);

CREATE TRIGGER set_categories_timestamp 
    BEFORE UPDATE ON activity.categories 
    FOR EACH ROW EXECUTE FUNCTION activity.update_timestamp();

CREATE INDEX idx_categories_active ON activity.categories(is_active, display_order) WHERE is_active = TRUE;

COMMENT ON TABLE activity.categories IS 'Activity categories (e.g., Outdoor, Food & Drink, Culture) - Premium users can filter by category';

-- ============================================================================
-- CORE ACTIVITY TABLES
-- ============================================================================

-- 3. activities - Main activities table with Meet5 features
CREATE TABLE activity.activities (
    activity_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organizer_user_id UUID NOT NULL REFERENCES activity.users(user_id),
    category_id UUID REFERENCES activity.categories(category_id),
    
    -- Basic information
    title VARCHAR(255) NOT NULL,
    description TEXT NOT NULL,
    activity_type activity.activity_type NOT NULL DEFAULT 'standard',
    activity_privacy_level activity.activity_privacy_level NOT NULL DEFAULT 'public',
    status activity.activity_status NOT NULL DEFAULT 'published',
    
    -- Scheduling
    scheduled_at TIMESTAMP WITH TIME ZONE NOT NULL,
    duration_minutes INT,
    
    -- CRITICAL ADDITION: Priority participation for Premium users
    -- Free users can only join after this timestamp; Premium users can join immediately
    joinable_at_free TIMESTAMP WITH TIME ZONE,
    
    -- Participants
    max_participants INT NOT NULL,
    current_participants_count INT NOT NULL DEFAULT 0,
    waitlist_count INT NOT NULL DEFAULT 0,
    
    -- Location (basic - detailed in activity_locations)
    location_name VARCHAR(255),
    city VARCHAR(100),
    
    -- Language
    language VARCHAR(5) NOT NULL DEFAULT 'en',
    
    -- External chat reference
    external_chat_id VARCHAR(255),
    
    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMP WITH TIME ZONE,
    cancelled_at TIMESTAMP WITH TIME ZONE,
    
    -- Flexible storage
    payload JSONB,
    hash_value VARCHAR(64),
    
    CONSTRAINT check_max_participants CHECK (max_participants > 0),
    CONSTRAINT check_participants_count CHECK (current_participants_count >= 0 AND current_participants_count <= max_participants),
    CONSTRAINT check_waitlist_count CHECK (waitlist_count >= 0),
    CONSTRAINT check_scheduled_time CHECK (scheduled_at > created_at),
    CONSTRAINT check_duration CHECK (duration_minutes IS NULL OR duration_minutes > 0),
    CONSTRAINT check_joinable_time CHECK (joinable_at_free IS NULL OR joinable_at_free >= created_at)
);

CREATE TRIGGER set_activities_timestamp 
    BEFORE UPDATE ON activity.activities 
    FOR EACH ROW EXECUTE FUNCTION activity.update_timestamp();

CREATE INDEX idx_activities_organizer ON activity.activities(organizer_user_id);
CREATE INDEX idx_activities_category ON activity.activities(category_id);
CREATE INDEX idx_activities_scheduled ON activity.activities(scheduled_at) WHERE status = 'published';
CREATE INDEX idx_activities_type ON activity.activities(activity_type);
CREATE INDEX idx_activities_privacy ON activity.activities(activity_privacy_level);
CREATE INDEX idx_activities_status ON activity.activities(status);
CREATE INDEX idx_activities_city ON activity.activities(city) WHERE city IS NOT NULL;
CREATE INDEX idx_activities_language ON activity.activities(language);
CREATE INDEX idx_activities_joinable_free ON activity.activities(joinable_at_free) WHERE joinable_at_free IS NOT NULL;

COMMENT ON TABLE activity.activities IS 'Main activities with Meet5 features: privacy levels, activity types, language filtering, priority participation';
COMMENT ON COLUMN activity.activities.activity_type IS 'Activity type: standard, xxl (100+ people - blocking does NOT work for XXL), womens_only, mens_only';
COMMENT ON COLUMN activity.activities.activity_privacy_level IS 'public (everyone), friends_only (accepted friends), invite_only (explicit invitations)';
COMMENT ON COLUMN activity.activities.language IS 'ISO 639-1 language code (e.g., en, nl, de) - Premium users can hide activities in other languages';
COMMENT ON COLUMN activity.activities.external_chat_id IS 'Reference to group chat in external chat service';
COMMENT ON COLUMN activity.activities.joinable_at_free IS 'Timestamp when free users can join - Premium users skip this waiting time (NULL = no wait)';

-- 4. participants - Activity participation with attendance tracking
CREATE TABLE activity.participants (
    activity_id UUID NOT NULL REFERENCES activity.activities(activity_id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES activity.users(user_id) ON DELETE CASCADE,
    role activity.participant_role NOT NULL DEFAULT 'member',
    participation_status activity.participation_status NOT NULL DEFAULT 'registered',
    attendance_status activity.attendance_status NOT NULL DEFAULT 'registered',
    joined_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    left_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    payload JSONB,
    hash_value VARCHAR(64),
    
    PRIMARY KEY (activity_id, user_id)
);

CREATE TRIGGER set_participants_timestamp 
    BEFORE UPDATE ON activity.participants 
    FOR EACH ROW EXECUTE FUNCTION activity.update_timestamp();

CREATE INDEX idx_participants_user ON activity.participants(user_id);
CREATE INDEX idx_participants_status ON activity.participants(participation_status);
CREATE INDEX idx_participants_attendance ON activity.participants(attendance_status) WHERE attendance_status != 'registered';

COMMENT ON TABLE activity.participants IS 'Activity participation with attendance tracking for verification system';
COMMENT ON COLUMN activity.participants.attendance_status IS 'Tracks actual attendance: registered, attended, no_show - used for verification and trust scoring';

-- 5. attendance_confirmations - Peer verification system
CREATE TABLE activity.attendance_confirmations (
    confirmation_id UUID PRIMARY KEY DEFAULT uuidv7(),
    activity_id UUID NOT NULL REFERENCES activity.activities(activity_id) ON DELETE CASCADE,
    confirmed_user_id UUID NOT NULL REFERENCES activity.users(user_id) ON DELETE CASCADE,
    confirmer_user_id UUID NOT NULL REFERENCES activity.users(user_id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    payload JSONB,
    
    UNIQUE (activity_id, confirmed_user_id, confirmer_user_id),
    CONSTRAINT check_not_self_confirm CHECK (confirmed_user_id != confirmer_user_id)
);

CREATE INDEX idx_attendance_confirmations_confirmed ON activity.attendance_confirmations(confirmed_user_id);
CREATE INDEX idx_attendance_confirmations_activity ON activity.attendance_confirmations(activity_id);

COMMENT ON TABLE activity.attendance_confirmations IS 'Peer verification system - users confirm each others attendance after activities';
COMMENT ON TABLE activity.attendance_confirmations IS 'Used to award verification badges and build trust scores';

-- 6. activity_locations - Detailed location data
CREATE TABLE activity.activity_locations (
    location_id UUID PRIMARY KEY DEFAULT uuidv7(),
    activity_id UUID NOT NULL UNIQUE REFERENCES activity.activities(activity_id) ON DELETE CASCADE,
    venue_name VARCHAR(255),
    address_line1 VARCHAR(255),
    address_line2 VARCHAR(255),
    city VARCHAR(100),
    state_province VARCHAR(100),
    postal_code VARCHAR(20),
    country VARCHAR(100),
    latitude DECIMAL(10, 8),
    longitude DECIMAL(11, 8),
    place_id VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    payload JSONB,
    hash_value VARCHAR(64),
    
    CONSTRAINT check_coordinates CHECK (
        (latitude IS NULL AND longitude IS NULL) OR
        (latitude IS NOT NULL AND longitude IS NOT NULL AND
         latitude >= -90 AND latitude <= 90 AND
         longitude >= -180 AND longitude <= 180)
    )
);

CREATE TRIGGER set_activity_locations_timestamp 
    BEFORE UPDATE ON activity.activity_locations 
    FOR EACH ROW EXECUTE FUNCTION activity.update_timestamp();

CREATE INDEX idx_activity_locations_coords ON activity.activity_locations(latitude, longitude) 
    WHERE latitude IS NOT NULL AND longitude IS NOT NULL;

-- 7. activity_invitations - Invitations for invite-only activities
CREATE TABLE activity.activity_invitations (
    invitation_id UUID PRIMARY KEY DEFAULT uuidv7(),
    activity_id UUID NOT NULL REFERENCES activity.activities(activity_id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES activity.users(user_id) ON DELETE CASCADE,
    invited_by_user_id UUID NOT NULL REFERENCES activity.users(user_id),
    status activity.invitation_status NOT NULL DEFAULT 'pending',
    invited_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    responded_at TIMESTAMP WITH TIME ZONE,
    expires_at TIMESTAMP WITH TIME ZONE,
    message TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    payload JSONB,
    hash_value VARCHAR(64),
    
    UNIQUE (activity_id, user_id),
    CONSTRAINT check_invitation_dates CHECK (
        expires_at IS NULL OR expires_at > invited_at
    )
);

CREATE TRIGGER set_activity_invitations_timestamp 
    BEFORE UPDATE ON activity.activity_invitations 
    FOR EACH ROW EXECUTE FUNCTION activity.update_timestamp();

CREATE INDEX idx_activity_invitations_activity ON activity.activity_invitations(activity_id, status);
CREATE INDEX idx_activity_invitations_user ON activity.activity_invitations(user_id, status);
CREATE INDEX idx_activity_invitations_invited_by ON activity.activity_invitations(invited_by_user_id);
CREATE INDEX idx_activity_invitations_expires ON activity.activity_invitations(expires_at) 
    WHERE expires_at IS NOT NULL AND status = 'pending';

-- 8. waitlist_entries - Activity waitlist management
CREATE TABLE activity.waitlist_entries (
    waitlist_id UUID PRIMARY KEY DEFAULT uuidv7(),
    activity_id UUID NOT NULL REFERENCES activity.activities(activity_id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES activity.users(user_id) ON DELETE CASCADE,
    position INT NOT NULL,
    notified_at TIMESTAMP WITH TIME ZONE,
    expires_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    payload JSONB,
    hash_value VARCHAR(64),
    
    UNIQUE (activity_id, user_id),
    CONSTRAINT check_position_positive CHECK (position > 0)
);

CREATE TRIGGER set_waitlist_entries_timestamp 
    BEFORE UPDATE ON activity.waitlist_entries 
    FOR EACH ROW EXECUTE FUNCTION activity.update_timestamp();

CREATE INDEX idx_waitlist_activity_position ON activity.waitlist_entries(activity_id, position);

-- 9. activity_tags - Multiple interest tags per activity
CREATE TABLE activity.activity_tags (
    activity_id UUID NOT NULL REFERENCES activity.activities(activity_id) ON DELETE CASCADE,
    tag VARCHAR(100) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    
    PRIMARY KEY (activity_id, tag)
);

CREATE INDEX idx_activity_tags_tag ON activity.activity_tags(tag);

COMMENT ON TABLE activity.activity_tags IS 'Interest tags for activities (up to 20) - used for matching and discovery';

-- 10. activity_reviews - Post-activity ratings
CREATE TABLE activity.activity_reviews (
    review_id UUID PRIMARY KEY DEFAULT uuidv7(),
    activity_id UUID NOT NULL REFERENCES activity.activities(activity_id),
    reviewer_user_id UUID NOT NULL REFERENCES activity.users(user_id),
    rating INT NOT NULL,
    review_text TEXT,
    is_anonymous BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    payload JSONB,
    hash_value VARCHAR(64),
    
    UNIQUE (activity_id, reviewer_user_id),
    CONSTRAINT check_rating_range CHECK (rating >= 1 AND rating <= 5)
);

CREATE TRIGGER set_activity_reviews_timestamp 
    BEFORE UPDATE ON activity.activity_reviews 
    FOR EACH ROW EXECUTE FUNCTION activity.update_timestamp();

CREATE INDEX idx_activity_reviews_activity ON activity.activity_reviews(activity_id);
CREATE INDEX idx_activity_reviews_reviewer ON activity.activity_reviews(reviewer_user_id);

-- ============================================================================
-- SOCIAL & CONNECTIONS
-- ============================================================================

-- 11. friendships - Friend connections with privacy implications
CREATE TABLE activity.friendships (
    user_id_1 UUID NOT NULL REFERENCES activity.users(user_id) ON DELETE CASCADE,
    user_id_2 UUID NOT NULL REFERENCES activity.users(user_id) ON DELETE CASCADE,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    initiated_by UUID NOT NULL REFERENCES activity.users(user_id),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    accepted_at TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    payload JSONB,
    hash_value VARCHAR(64),
    
    PRIMARY KEY (user_id_1, user_id_2),
    CONSTRAINT check_user_order CHECK (user_id_1 < user_id_2),
    CONSTRAINT check_status CHECK (status IN ('pending', 'accepted', 'blocked'))
);

CREATE TRIGGER set_friendships_timestamp 
    BEFORE UPDATE ON activity.friendships 
    FOR EACH ROW EXECUTE FUNCTION activity.update_timestamp();

CREATE INDEX idx_friendships_user1_status ON activity.friendships(user_id_1, status);
CREATE INDEX idx_friendships_user2_status ON activity.friendships(user_id_2, status);

COMMENT ON TABLE activity.friendships IS 'Friend connections - affects access to friends_only activities';

-- 12. user_blocks - CRITICAL NEW TABLE: Asymmetric blocking system
CREATE TABLE activity.user_blocks (
    blocker_user_id UUID NOT NULL REFERENCES activity.users(user_id) ON DELETE CASCADE,
    blocked_user_id UUID NOT NULL REFERENCES activity.users(user_id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    reason TEXT,
    payload JSONB,
    
    PRIMARY KEY (blocker_user_id, blocked_user_id),
    CONSTRAINT check_not_self_block CHECK (blocker_user_id != blocked_user_id)
);

CREATE INDEX idx_user_blocks_blocker ON activity.user_blocks(blocker_user_id);
CREATE INDEX idx_user_blocks_blocked ON activity.user_blocks(blocked_user_id);

COMMENT ON TABLE activity.user_blocks IS 'ASYMMETRIC blocking system - User A can block User B independently';
COMMENT ON TABLE activity.user_blocks IS 'CRITICAL: Blocking does NOT apply to XXL activities (activity_type = xxl)';
COMMENT ON TABLE activity.user_blocks IS 'When blocked: cannot see profiles, activities, posts, or send messages';

-- 13. user_favorites - User favoriting system (ego feature)
CREATE TABLE activity.user_favorites (
    favoriting_user_id UUID NOT NULL REFERENCES activity.users(user_id) ON DELETE CASCADE,
    favorited_user_id UUID NOT NULL REFERENCES activity.users(user_id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    payload JSONB,
    
    PRIMARY KEY (favoriting_user_id, favorited_user_id),
    CONSTRAINT check_not_self_favorite CHECK (favoriting_user_id != favorited_user_id)
);

CREATE INDEX idx_user_favorites_favorited ON activity.user_favorites(favorited_user_id);

COMMENT ON TABLE activity.user_favorites IS 'User favoriting - Premium feature: see who favorited you';

-- 14. profile_views - Profile view tracking (ego feature)
CREATE TABLE activity.profile_views (
    view_id UUID PRIMARY KEY DEFAULT uuidv7(),
    viewer_user_id UUID NOT NULL REFERENCES activity.users(user_id) ON DELETE CASCADE,
    viewed_user_id UUID NOT NULL REFERENCES activity.users(user_id) ON DELETE CASCADE,
    viewed_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    payload JSONB,
    
    CONSTRAINT check_not_self_view CHECK (viewer_user_id != viewed_user_id)
);

CREATE INDEX idx_profile_views_viewed ON activity.profile_views(viewed_user_id, viewed_at DESC);
CREATE INDEX idx_profile_views_viewer ON activity.profile_views(viewer_user_id);

COMMENT ON TABLE activity.profile_views IS 'Profile view tracking - Premium feature: see who viewed your profile';
COMMENT ON TABLE activity.profile_views IS 'CRITICAL: Ghost Mode (Premium) - when enabled, NO record is created in this table';

-- 15. private_chats - Private 1-on-1 chat references with paywall logic
CREATE TABLE activity.private_chats (
    private_chat_id UUID PRIMARY KEY DEFAULT uuidv7(),
    user_id_1 UUID NOT NULL REFERENCES activity.users(user_id) ON DELETE CASCADE,
    user_id_2 UUID NOT NULL REFERENCES activity.users(user_id) ON DELETE CASCADE,
    external_chat_id VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    last_message_at TIMESTAMP WITH TIME ZONE,
    payload JSONB,
    
    UNIQUE (user_id_1, user_id_2),
    CONSTRAINT check_user_order CHECK (user_id_1 < user_id_2)
);

CREATE INDEX idx_private_chats_user1 ON activity.private_chats(user_id_1);
CREATE INDEX idx_private_chats_user2 ON activity.private_chats(user_id_2);
CREATE INDEX idx_private_chats_external ON activity.private_chats(external_chat_id);

COMMENT ON TABLE activity.private_chats IS 'Private chat references - paywall logic: only Premium users can reply to messages from non-friends';

-- 16. user_interests - Interest tags for personalization (up to 20)
CREATE TABLE activity.user_interests (
    user_id UUID NOT NULL REFERENCES activity.users(user_id) ON DELETE CASCADE,
    interest_tag VARCHAR(100) NOT NULL,
    weight DECIMAL(3,2) NOT NULL DEFAULT 1.0,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    
    PRIMARY KEY (user_id, interest_tag),
    CONSTRAINT check_weight_range CHECK (weight >= 0.0 AND weight <= 1.0)
);

CREATE TRIGGER set_user_interests_timestamp 
    BEFORE UPDATE ON activity.user_interests 
    FOR EACH ROW EXECUTE FUNCTION activity.update_timestamp();

CREATE INDEX idx_user_interests_tag ON activity.user_interests(interest_tag);

COMMENT ON TABLE activity.user_interests IS 'User interest tags (up to 20) - used for activity matching and recommendations';

-- ============================================================================
-- ORGANIZATIONS & COMMUNITIES
-- ============================================================================

-- 17. organizations - Multi-tenant organizations
CREATE TABLE activity.organizations (
    organization_id UUID PRIMARY KEY DEFAULT uuidv7(),
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(100) UNIQUE NOT NULL,
    description TEXT,
    website_url VARCHAR(500),
    logo_url VARCHAR(500),
    is_verified BOOLEAN NOT NULL DEFAULT FALSE,
    status activity.organization_status NOT NULL DEFAULT 'active',
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    payload JSONB,
    hash_value VARCHAR(64),
    
    CONSTRAINT check_slug_format CHECK (slug ~ '^[a-z0-9-]+$')
);

CREATE TRIGGER set_organizations_timestamp 
    BEFORE UPDATE ON activity.organizations 
    FOR EACH ROW EXECUTE FUNCTION activity.update_timestamp();

-- 18. organization_members
CREATE TABLE activity.organization_members (
    organization_id UUID NOT NULL REFERENCES activity.organizations(organization_id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES activity.users(user_id) ON DELETE CASCADE,
    role activity.organization_role NOT NULL DEFAULT 'member',
    joined_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    payload JSONB,
    hash_value VARCHAR(64),
    
    PRIMARY KEY (organization_id, user_id)
);

CREATE TRIGGER set_organization_members_timestamp 
    BEFORE UPDATE ON activity.organization_members 
    FOR EACH ROW EXECUTE FUNCTION activity.update_timestamp();

CREATE INDEX idx_org_members_user ON activity.organization_members(user_id);

-- 19. communities - Identity-based communities
CREATE TABLE activity.communities (
    community_id UUID PRIMARY KEY DEFAULT uuidv7(),
    organization_id UUID REFERENCES activity.organizations(organization_id) ON DELETE CASCADE,
    creator_user_id UUID NOT NULL REFERENCES activity.users(user_id),
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(100) NOT NULL,
    description TEXT,
    community_type activity.community_type NOT NULL DEFAULT 'open',
    status activity.community_status NOT NULL DEFAULT 'active',
    member_count INT NOT NULL DEFAULT 0,
    max_members INT,
    is_featured BOOLEAN NOT NULL DEFAULT FALSE,
    cover_image_url VARCHAR(500),
    icon_url VARCHAR(500),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    payload JSONB,
    hash_value VARCHAR(64),
    
    UNIQUE (organization_id, slug),
    CONSTRAINT check_member_count CHECK (member_count >= 0),
    CONSTRAINT check_max_members CHECK (max_members IS NULL OR max_members > 0)
);

CREATE TRIGGER set_communities_timestamp 
    BEFORE UPDATE ON activity.communities 
    FOR EACH ROW EXECUTE FUNCTION activity.update_timestamp();

CREATE INDEX idx_communities_org ON activity.communities(organization_id);
CREATE INDEX idx_communities_status ON activity.communities(status) WHERE status = 'active';

COMMENT ON TABLE activity.communities IS 'Identity-based communities (e.g., ultra-runners, coffee enthusiasts)';

-- 20. community_members
CREATE TABLE activity.community_members (
    community_id UUID NOT NULL REFERENCES activity.communities(community_id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES activity.users(user_id) ON DELETE CASCADE,
    status activity.membership_status NOT NULL DEFAULT 'active',
    role activity.participant_role NOT NULL DEFAULT 'member',
    invited_by_user_id UUID REFERENCES activity.users(user_id),
    joined_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    left_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    payload JSONB,
    hash_value VARCHAR(64),
    
    PRIMARY KEY (community_id, user_id)
);

CREATE TRIGGER set_community_members_timestamp 
    BEFORE UPDATE ON activity.community_members 
    FOR EACH ROW EXECUTE FUNCTION activity.update_timestamp();

CREATE INDEX idx_community_members_user ON activity.community_members(user_id);
CREATE INDEX idx_community_members_status ON activity.community_members(community_id, status);

-- 21. community_activities - Link activities to communities
CREATE TABLE activity.community_activities (
    community_id UUID NOT NULL REFERENCES activity.communities(community_id) ON DELETE CASCADE,
    activity_id UUID NOT NULL REFERENCES activity.activities(activity_id) ON DELETE CASCADE,
    is_pinned BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    payload JSONB,
    hash_value VARCHAR(64),
    
    PRIMARY KEY (community_id, activity_id)
);

CREATE TRIGGER set_community_activities_timestamp 
    BEFORE UPDATE ON activity.community_activities 
    FOR EACH ROW EXECUTE FUNCTION activity.update_timestamp();

CREATE INDEX idx_community_activities_activity ON activity.community_activities(activity_id);

-- 22. community_tags - Tags for communities
CREATE TABLE activity.community_tags (
    community_id UUID NOT NULL REFERENCES activity.communities(community_id) ON DELETE CASCADE,
    tag VARCHAR(100) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    
    PRIMARY KEY (community_id, tag)
);

CREATE INDEX idx_community_tags_tag ON activity.community_tags(tag);

-- ============================================================================
-- COMMUNITY CONTENT
-- ============================================================================

-- 23. posts - Community content
CREATE TABLE activity.posts (
    post_id UUID PRIMARY KEY DEFAULT uuidv7(),
    community_id UUID NOT NULL REFERENCES activity.communities(community_id) ON DELETE CASCADE,
    author_user_id UUID NOT NULL REFERENCES activity.users(user_id),
    activity_id UUID REFERENCES activity.activities(activity_id),
    title VARCHAR(500),
    content TEXT NOT NULL,
    content_type activity.content_type NOT NULL DEFAULT 'post',
    status activity.content_status NOT NULL DEFAULT 'published',
    view_count INT NOT NULL DEFAULT 0,
    comment_count INT NOT NULL DEFAULT 0,
    reaction_count INT NOT NULL DEFAULT 0,
    is_pinned BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    published_at TIMESTAMP WITH TIME ZONE,
    payload JSONB,
    hash_value VARCHAR(64),
    
    CONSTRAINT check_counts_positive CHECK (
        view_count >= 0 AND 
        comment_count >= 0 AND 
        reaction_count >= 0
    )
);

CREATE TRIGGER set_posts_timestamp 
    BEFORE UPDATE ON activity.posts 
    FOR EACH ROW EXECUTE FUNCTION activity.update_timestamp();

CREATE INDEX idx_posts_community ON activity.posts(community_id, status, created_at DESC);
CREATE INDEX idx_posts_author ON activity.posts(author_user_id);
CREATE INDEX idx_posts_activity ON activity.posts(activity_id) WHERE activity_id IS NOT NULL;

-- 24. comments
CREATE TABLE activity.comments (
    comment_id UUID PRIMARY KEY DEFAULT uuidv7(),
    post_id UUID NOT NULL REFERENCES activity.posts(post_id) ON DELETE CASCADE,
    parent_comment_id UUID REFERENCES activity.comments(comment_id) ON DELETE CASCADE,
    author_user_id UUID NOT NULL REFERENCES activity.users(user_id),
    content TEXT NOT NULL,
    reaction_count INT NOT NULL DEFAULT 0,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    payload JSONB,
    hash_value VARCHAR(64),
    
    CONSTRAINT check_reaction_count_positive CHECK (reaction_count >= 0)
);

CREATE TRIGGER set_comments_timestamp 
    BEFORE UPDATE ON activity.comments 
    FOR EACH ROW EXECUTE FUNCTION activity.update_timestamp();

CREATE INDEX idx_comments_post ON activity.comments(post_id, created_at);
CREATE INDEX idx_comments_parent ON activity.comments(parent_comment_id) WHERE parent_comment_id IS NOT NULL;
CREATE INDEX idx_comments_author ON activity.comments(author_user_id);

-- 25. reactions
CREATE TABLE activity.reactions (
    reaction_id UUID PRIMARY KEY DEFAULT uuidv7(),
    user_id UUID NOT NULL REFERENCES activity.users(user_id) ON DELETE CASCADE,
    target_type VARCHAR(50) NOT NULL,
    target_id UUID NOT NULL,
    reaction_type activity.reaction_type NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    
    UNIQUE (user_id, target_type, target_id),
    CONSTRAINT check_target_type CHECK (target_type IN ('post', 'comment', 'memory'))
);

CREATE INDEX idx_reactions_target ON activity.reactions(target_type, target_id);
CREATE INDEX idx_reactions_user ON activity.reactions(user_id);

-- ============================================================================
-- GAMIFICATION & ACHIEVEMENTS
-- ============================================================================

-- 26. user_badges - Achievements and verification badges
CREATE TABLE activity.user_badges (
    badge_id UUID PRIMARY KEY DEFAULT uuidv7(),
    user_id UUID NOT NULL REFERENCES activity.users(user_id) ON DELETE CASCADE,
    badge_type VARCHAR(100) NOT NULL,
    badge_category activity.badge_category NOT NULL,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    icon_url VARCHAR(500),
    earned_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    payload JSONB,
    hash_value VARCHAR(64)
);

CREATE INDEX idx_user_badges_user ON activity.user_badges(user_id, earned_at DESC);
CREATE INDEX idx_user_badges_type ON activity.user_badges(badge_type);
CREATE INDEX idx_user_badges_category ON activity.user_badges(badge_category);

COMMENT ON TABLE activity.user_badges IS 'Achievements and verification badges - includes peer-verified attendance badges';

-- ============================================================================
-- NOTIFICATIONS
-- ============================================================================

-- 27. notifications
CREATE TABLE activity.notifications (
    notification_id UUID PRIMARY KEY DEFAULT uuidv7(),
    user_id UUID NOT NULL REFERENCES activity.users(user_id) ON DELETE CASCADE,
    actor_user_id UUID REFERENCES activity.users(user_id),
    notification_type activity.notification_type NOT NULL,
    target_type VARCHAR(50),
    target_id UUID,
    title VARCHAR(255) NOT NULL,
    message TEXT,
    status activity.notification_status NOT NULL DEFAULT 'unread',
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    read_at TIMESTAMP WITH TIME ZONE,
    payload JSONB,
    hash_value VARCHAR(64)
);

CREATE INDEX idx_notifications_user_status ON activity.notifications(user_id, status, created_at DESC);
CREATE INDEX idx_notifications_created ON activity.notifications(created_at) WHERE status = 'unread';

COMMENT ON TABLE activity.notifications IS 'All platform notifications including profile_view and new_favorite for Premium users';

-- 28. user_settings - User preferences including notification settings
-- CRITICAL ADDITION: ghost_mode column for Premium users
CREATE TABLE activity.user_settings (
    user_id UUID PRIMARY KEY REFERENCES activity.users(user_id) ON DELETE CASCADE,
    email_notifications BOOLEAN NOT NULL DEFAULT TRUE,
    push_notifications BOOLEAN NOT NULL DEFAULT TRUE,
    activity_reminders BOOLEAN NOT NULL DEFAULT TRUE,
    community_updates BOOLEAN NOT NULL DEFAULT TRUE,
    friend_requests BOOLEAN NOT NULL DEFAULT TRUE,
    marketing_emails BOOLEAN NOT NULL DEFAULT FALSE,
    ghost_mode BOOLEAN NOT NULL DEFAULT FALSE,
    language VARCHAR(10) NOT NULL DEFAULT 'en',
    timezone VARCHAR(50) NOT NULL DEFAULT 'UTC',
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    payload JSONB,
    hash_value VARCHAR(64)
);

CREATE TRIGGER set_user_settings_timestamp 
    BEFORE UPDATE ON activity.user_settings 
    FOR EACH ROW EXECUTE FUNCTION activity.update_timestamp();

CREATE INDEX idx_user_settings_ghost_mode ON activity.user_settings(ghost_mode) WHERE ghost_mode = TRUE;

COMMENT ON COLUMN activity.user_settings.ghost_mode IS 'Ghost Mode (Premium feature) - visit profiles invisibly, no profile_views record created';

-- ============================================================================
-- MODERATION & SAFETY
-- ============================================================================

-- 29. reports - Content and user reporting system
CREATE TABLE activity.reports (
    report_id UUID PRIMARY KEY DEFAULT uuidv7(),
    reporter_user_id UUID NOT NULL REFERENCES activity.users(user_id),
    reported_user_id UUID REFERENCES activity.users(user_id),
    target_type VARCHAR(50) NOT NULL,
    target_id UUID NOT NULL,
    report_type activity.report_type NOT NULL,
    description TEXT,
    status activity.report_status NOT NULL DEFAULT 'pending',
    reviewed_by_user_id UUID REFERENCES activity.users(user_id),
    reviewed_at TIMESTAMP WITH TIME ZONE,
    resolution_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    payload JSONB,
    hash_value VARCHAR(64),
    
    CONSTRAINT check_target_type CHECK (target_type IN ('user', 'post', 'comment', 'activity', 'community'))
);

CREATE TRIGGER set_reports_timestamp 
    BEFORE UPDATE ON activity.reports 
    FOR EACH ROW EXECUTE FUNCTION activity.update_timestamp();

CREATE INDEX idx_reports_status ON activity.reports(status, created_at);
CREATE INDEX idx_reports_target ON activity.reports(target_type, target_id);
CREATE INDEX idx_reports_reporter ON activity.reports(reporter_user_id);
CREATE INDEX idx_reports_reported_user ON activity.reports(reported_user_id) WHERE reported_user_id IS NOT NULL;

COMMENT ON TABLE activity.reports IS 'Reporting system including no_show reports for trust & safety';

-- ============================================================================
-- MEDIA MANAGEMENT
-- ============================================================================

-- 30. media_assets - Centralized media management
CREATE TABLE activity.media_assets (
    asset_id UUID PRIMARY KEY DEFAULT uuidv7(),
    user_id UUID NOT NULL REFERENCES activity.users(user_id),
    asset_type VARCHAR(50) NOT NULL,
    file_name VARCHAR(255) NOT NULL,
    file_size_bytes BIGINT NOT NULL,
    mime_type VARCHAR(100) NOT NULL,
    storage_url VARCHAR(1000) NOT NULL,
    thumbnail_url VARCHAR(1000),
    width INT,
    height INT,
    duration_seconds INT,
    is_processed BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    payload JSONB,
    hash_value VARCHAR(64),
    
    CONSTRAINT check_file_size CHECK (file_size_bytes > 0),
    CONSTRAINT check_dimensions CHECK (
        (width IS NULL AND height IS NULL) OR
        (width > 0 AND height > 0)
    ),
    CONSTRAINT check_asset_type CHECK (asset_type IN ('image', 'video', 'audio', 'document'))
);

CREATE INDEX idx_media_assets_user ON activity.media_assets(user_id, created_at DESC);
CREATE INDEX idx_media_assets_type ON activity.media_assets(asset_type);

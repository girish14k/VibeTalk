

-- Clearing existing data (I do it for testing only)
-- TRUNCATE users, user_contacts, blocked_users, messages, message_attachments, conversations, message_reports CASCADE;


-- ----------------------------------------------------------------------------
-- 1.1 Create  Users
-- ----------------------------------------------------------------------------
-- Insert test users
INSERT INTO users (email, phone, name, age, password_hash) VALUES
('alice@gmail.com', '+11234567890', 'Alice Johnson', 28, crypt('password123', gen_salt('bf'))),
('bob@gmail.com', '+11234567891', 'Bob Smith', 32, crypt('password456', gen_salt('bf'))),
('charlie@gmail.com', '+11234567892', 'Charlie Brown', 25, crypt('password789', gen_salt('bf'))),
('diana@gmail.com', '+11234567893', 'Diana Prince', 30, crypt('password111', gen_salt('bf'))),
('eve@gmail.com', '+11234567894', 'Eve Martinez', 27, crypt('password222', gen_salt('bf')));

-- Get the inserted user IDs (for reference)
SELECT id, name, email, phone FROM users ORDER BY id;

-- ----------------------------------------------------------------------------
-- 1.2 Add Contacts 
-- ----------------------------------------------------------------------------

-- Alice's contacts: Bob, Charlie, Diana
INSERT INTO user_contacts (user_id, contact_user_id, contact_name) VALUES
(1, 2, 'Bob'),
(1, 3, 'Charlie'),
(1, 4, 'Diana');

-- Bob's contacts: Alice, Charlie, Eve
INSERT INTO user_contacts (user_id, contact_user_id, contact_name) VALUES
(2, 1, 'Alice'),
(2, 3, 'Charlie'),
(2, 5, 'Eve');

-- Charlie's contacts: Alice, Bob, Diana
INSERT INTO user_contacts (user_id, contact_user_id, contact_name) VALUES
(3, 1, 'Alice'),
(3, 2, 'Bob'),
(3, 4, 'Diana');

-- Diana's contacts: Alice, Charlie
INSERT INTO user_contacts (user_id, contact_user_id, contact_name) VALUES
(4, 1, 'Alice'),
(4, 3, 'Charlie');

-- Eve's contacts: Bob
INSERT INTO user_contacts (user_id, contact_user_id, contact_name) VALUES
(5, 2, 'Bob');

-- ----------------------------------------------------------------------------
-- 1.3 Block a User
-- ----------------------------------------------------------------------------

-- Charlie blocks Diana
INSERT INTO blocked_users (blocker_id, blocked_id, reason) VALUES
(3, 4, 'Spam messages');

-- ----------------------------------------------------------------------------
-- 1.4 Send Some Messages
-- ----------------------------------------------------------------------------

-- Alice sends message to Bob
INSERT INTO messages (sender_id, receiver_id, content, message_type)
VALUES (1, 2, 'Hey Bob! How are you doing? 👋', 'text');

-- Bob replies to Alice
INSERT INTO messages (sender_id, receiver_id, content, message_type)
VALUES (2, 1, 'Hi Alice! I am doing great, thanks for asking! 😊', 'text');

-- Alice sends another message to Bob
INSERT INTO messages (sender_id, receiver_id, content, message_type)
VALUES (1, 2, 'Want to grab coffee later?', 'text');

-- Charlie sends message to Alice
INSERT INTO messages (sender_id, receiver_id, content, message_type)
VALUES (3, 1, 'Alice, did you see the game last night?', 'text');

-- Bob sends message to Eve
INSERT INTO messages (sender_id, receiver_id, content, message_type)
VALUES (2, 5, 'Eve, checking in on the project status', 'text');

-- Alice sends message with emoji
INSERT INTO messages (sender_id, receiver_id, content, message_type)
VALUES (1, 3, 'Charlie! 🎉🎊 Congratulations on your promotion! 🚀', 'text');

-- ----------------------------------------------------------------------------
-- 1.5 Simulate Message with Attachment
-- ----------------------------------------------------------------------------

-- Alice sends an image to Bob
WITH new_msg AS (
    INSERT INTO messages (sender_id, receiver_id, message_type)
    VALUES (1, 2, 'image')
    RETURNING id
)
INSERT INTO message_attachments (message_id, file_type, file_name, file_size, file_url, mime_type)
SELECT 
    id,
    'image',
    'vacation_photo.jpg',
    2048576,  -- 2MB
    'https://s3.amazonaws.com/chat-files/abc123/vacation_photo.jpg',
    'image/jpeg'
FROM new_msg;

-- Bob sends PDF to Alice
WITH new_msg AS (
    INSERT INTO messages (sender_id, receiver_id, message_type)
    VALUES (2, 1, 'pdf')
    RETURNING id
)
INSERT INTO message_attachments (message_id, file_type, file_name, file_size, file_url, mime_type)
SELECT 
    id,
    'pdf',
    'meeting_notes.pdf',
    512000,  -- 500KB
    'https://s3.amazonaws.com/chat-files/def456/meeting_notes.pdf',
    'application/pdf'
FROM new_msg;


-- ============================================================================
-- PART 2: USER MANAGEMENT QUERIES
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 2.1 User Login
-- ----------------------------------------------------------------------------

-- Login with email
SELECT id, email, phone, name, age, created_at, is_active
FROM users
WHERE email = 'alice@gmail.com' 
  AND password_hash = crypt('password123', password_hash)
  AND is_active = TRUE;

-- Login with phone
SELECT id, email, phone, name, age, created_at, is_active
FROM users
WHERE phone = '+11234567891' 
  AND password_hash = crypt('password456', password_hash)
  AND is_active = TRUE;

-- ----------------------------------------------------------------------------
-- 2.2 Get User Profile
-- ----------------------------------------------------------------------------

SELECT id, email, phone, name, age, last_seen, created_at
FROM users
WHERE id = 1 AND is_active = TRUE;

-- ----------------------------------------------------------------------------
-- 2.3 Update User Last Seen (Activity Tracking)
-- ----------------------------------------------------------------------------

UPDATE users
SET last_seen = CURRENT_TIMESTAMP
WHERE id = 1;

-- ----------------------------------------------------------------------------
-- 2.4 Search Users by Phone (for Contact Sync)
-- ----------------------------------------------------------------------------

SELECT id, name, phone, email
FROM users
WHERE phone IN ('+11234567891', '+11234567892', '+11234567899')
  AND is_active = TRUE;


-- ============================================================================
-- PART 3: CONTACT MANAGEMENT QUERIES
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 3.1 Get User's Contacts
-- ----------------------------------------------------------------------------

SELECT 
    uc.contact_user_id AS user_id,
    uc.contact_name,
    u.name AS actual_name,
    u.phone,
    u.email,
    u.last_seen,
    EXISTS(
        SELECT 1 FROM blocked_users bu 
        WHERE (bu.blocker_id = 1 AND bu.blocked_id = uc.contact_user_id)
           OR (bu.blocker_id = uc.contact_user_id AND bu.blocked_id = 1)
    ) AS is_blocked
FROM user_contacts uc
JOIN users u ON uc.contact_user_id = u.id
WHERE uc.user_id = 1  -- Alice's contacts
  AND u.is_active = TRUE
ORDER BY uc.contact_name;

-- ----------------------------------------------------------------------------
-- 3.2 Check if Two Users Can Message Each Other
-- ----------------------------------------------------------------------------

SELECT can_users_message(1, 2) AS can_alice_message_bob;
SELECT can_users_message(3, 4) AS can_charlie_message_diana;  -- Should be FALSE (blocked)

-- ----------------------------------------------------------------------------
-- 3.3 Add New Contact
-- ----------------------------------------------------------------------------

INSERT INTO user_contacts (user_id, contact_user_id, contact_name)
VALUES (1, 5, 'Eve')  -- Alice adds Eve
ON CONFLICT (user_id, contact_user_id) DO NOTHING
RETURNING id, contact_user_id, contact_name, added_at;

-- ----------------------------------------------------------------------------
-- 3.4 Remove Contact
-- ----------------------------------------------------------------------------

DELETE FROM user_contacts
WHERE user_id = 1 AND contact_user_id = 5;  -- Alice removes Eve


-- ============================================================================
-- PART 4: BLOCKING QUERIES
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 4.1 Block a User
-- ----------------------------------------------------------------------------

INSERT INTO blocked_users (blocker_id, blocked_id, reason)
VALUES (1, 5, 'Unwanted messages')
ON CONFLICT (blocker_id, blocked_id) DO NOTHING
RETURNING id, blocked_at;

-- ----------------------------------------------------------------------------
-- 4.2 Get Blocked Users List
-- ----------------------------------------------------------------------------

SELECT 
    bu.blocked_id AS user_id,
    u.name,
    u.phone,
    bu.blocked_at,
    bu.reason
FROM blocked_users bu
JOIN users u ON bu.blocked_id = u.id
WHERE bu.blocker_id = 1  -- Alice's blocked users
ORDER BY bu.blocked_at DESC;

-- ----------------------------------------------------------------------------
-- 4.3 Unblock a User
-- ----------------------------------------------------------------------------

DELETE FROM blocked_users
WHERE blocker_id = 1 AND blocked_id = 5;  -- Alice unblocks Eve

-- ----------------------------------------------------------------------------
-- 4.4 Check if User is Blocked
-- ----------------------------------------------------------------------------

SELECT EXISTS(
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = 3 AND blocked_id = 4)
       OR (blocker_id = 4 AND blocked_id = 3)
) AS is_blocked;


-- ============================================================================
-- PART 5: MESSAGING QUERIES
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 5.1 Send Text Message
-- ----------------------------------------------------------------------------

WITH new_message AS (
    INSERT INTO messages (sender_id, receiver_id, content, message_type)
    VALUES (1, 2, 'This is a new test message! 🎈', 'text')
    RETURNING *
)
SELECT 
    nm.id,
    nm.sender_id,
    nm.receiver_id,
    nm.content,
    nm.message_type,
    nm.status,
    nm.created_at,
    us.name AS sender_name,
    ur.name AS receiver_name
FROM new_message nm
JOIN users us ON nm.sender_id = us.id
JOIN users ur ON nm.receiver_id = ur.id;

-- ----------------------------------------------------------------------------
-- 5.2 Get Messages in a Conversation (Latest 50)
-- ----------------------------------------------------------------------------

SELECT 
    m.id,
    m.sender_id,
    m.receiver_id,
    m.content,
    m.message_type,
    m.status,
    m.created_at,
    m.delivered_at,
    m.read_at,
    m.expires_at,
    m.is_expired,
    CASE WHEN m.sender_id = 1 THEN TRUE ELSE FALSE END AS is_mine,
    ma.file_name,
    ma.file_type,
    ma.file_size,
    ma.file_url,
    CASE 
        WHEN m.expires_at IS NOT NULL THEN 
            GREATEST(0, EXTRACT(EPOCH FROM (m.expires_at - CURRENT_TIMESTAMP))::INTEGER)
        ELSE NULL
    END AS seconds_until_expiration
FROM messages m
LEFT JOIN message_attachments ma ON m.id = ma.message_id
WHERE ((m.sender_id = 1 AND m.receiver_id = 2)   -- Alice and Bob
   OR (m.sender_id = 2 AND m.receiver_id = 1))
  AND m.is_expired = FALSE
  AND m.deleted_by_sender = FALSE
ORDER BY m.created_at DESC
LIMIT 50;

-- ----------------------------------------------------------------------------
-- 5.3 Mark Message as Delivered
-- ----------------------------------------------------------------------------

-- Get the latest message ID from Alice to Bob
WITH latest_msg AS (
    SELECT id FROM messages 
    WHERE sender_id = 1 AND receiver_id = 2 
    ORDER BY created_at DESC 
    LIMIT 1
)
UPDATE messages m
SET status = 'delivered',
    delivered_at = CURRENT_TIMESTAMP
FROM latest_msg lm
WHERE m.id = lm.id
  AND m.status = 'sent'
RETURNING m.id, m.status, m.delivered_at;

-- ----------------------------------------------------------------------------
-- 5.4 Mark Messages as Read (Batch Update)
-- ----------------------------------------------------------------------------

-- Get message IDs to mark as read
WITH messages_to_read AS (
    SELECT ARRAY_AGG(id) AS msg_ids
    FROM messages 
    WHERE sender_id = 1 AND receiver_id = 2 
      AND status IN ('sent', 'delivered')
    LIMIT 5
)
UPDATE messages
SET status = 'read'
FROM messages_to_read
WHERE id = ANY(messages_to_read.msg_ids)
  AND receiver_id = 2
RETURNING id, status, read_at, expires_at;

-- ----------------------------------------------------------------------------
-- 5.5 Delete Message (Within 1 Minute Window)
-- ----------------------------------------------------------------------------

-- First, send a message
WITH new_msg AS (
    INSERT INTO messages (sender_id, receiver_id, content, message_type)
    VALUES (1, 2, 'This message will be deleted!', 'text')
    RETURNING id, created_at
)
SELECT id, created_at FROM new_msg;

-- Now delete it (replace {message_id} with actual ID from above)
-- UPDATE messages
-- SET deleted_by_sender = TRUE
-- WHERE id = '{message_id}'
--   AND sender_id = 1
--   AND created_at >= CURRENT_TIMESTAMP - INTERVAL '1 minute'
--   AND deleted_by_sender = FALSE
-- RETURNING id, deleted_at, status;

-- Try to delete after 1 minute (should fail)
-- This will raise exception: "Cannot delete message after 1 minute of sending"

-- ----------------------------------------------------------------------------
-- 5.6 Get Single Message Details
-- ----------------------------------------------------------------------------

SELECT 
    m.id,
    m.sender_id,
    m.receiver_id,
    m.content,
    m.message_type,
    m.status,
    m.created_at,
    m.delivered_at,
    m.read_at,
    m.expires_at,
    m.deleted_by_sender,
    m.is_expired,
    us.name AS sender_name,
    ur.name AS receiver_name,
    ma.file_name,
    ma.file_type,
    ma.file_size,
    ma.file_url
FROM messages m
JOIN users us ON m.sender_id = us.id
JOIN users ur ON m.receiver_id = ur.id
LEFT JOIN message_attachments ma ON m.id = ma.message_id
WHERE m.sender_id = 1 
  AND m.receiver_id = 2
  AND m.is_expired = FALSE
  AND m.deleted_by_sender = FALSE
ORDER BY m.created_at DESC
LIMIT 1;


-- ============================================================================
-- PART 6: CONVERSATION QUERIES
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 6.1 Get User's Conversation List
-- ----------------------------------------------------------------------------

SELECT 
    c.id AS conversation_id,
    CASE 
        WHEN c.user1_id = 1 THEN c.user2_id 
        ELSE c.user1_id 
    END AS other_user_id,
    CASE 
        WHEN c.user1_id = 1 THEN u2.name 
        ELSE u1.name 
    END AS other_user_name,
    CASE 
        WHEN c.user1_id = 1 THEN u2.phone 
        ELSE u1.phone 
    END AS other_user_phone,
    CASE 
        WHEN c.user1_id = 1 THEN u2.last_seen 
        ELSE u1.last_seen 
    END AS other_user_last_seen,
    CASE 
        WHEN c.user1_id = 1 THEN c.user1_unread_count 
        ELSE c.user2_unread_count 
    END AS unread_count,
    c.last_message_at,
    c.last_message_id,
    m.content AS last_message_preview,
    m.message_type AS last_message_type,
    m.sender_id = 1 AS last_message_is_mine
FROM conversations c
JOIN users u1 ON c.user1_id = u1.id
JOIN users u2 ON c.user2_id = u2.id
LEFT JOIN messages m ON c.last_message_id = m.id AND m.is_expired = FALSE
WHERE (c.user1_id = 1 OR c.user2_id = 1)  -- Alice's conversations
  AND u1.is_active = TRUE 
  AND u2.is_active = TRUE
ORDER BY c.last_message_at DESC NULLS LAST
LIMIT 20;

-- ----------------------------------------------------------------------------
-- 6.2 Get Total Unread Count for User
-- ----------------------------------------------------------------------------

SELECT 
    COALESCE(SUM(
        CASE 
            WHEN user1_id = 1 THEN user1_unread_count 
            WHEN user2_id = 1 THEN user2_unread_count 
            ELSE 0 
        END
    ), 0) AS total_unread
FROM conversations
WHERE user1_id = 1 OR user2_id = 1;  -- Alice's total unread

-- ----------------------------------------------------------------------------
-- 6.3 Get or Create Conversation
-- ----------------------------------------------------------------------------

WITH user_order AS (
    SELECT 
        LEAST(1, 3) AS user1_id,    -- Alice and Charlie
        GREATEST(1, 3) AS user2_id
),
upserted_conversation AS (
    INSERT INTO conversations (user1_id, user2_id)
    SELECT user1_id, user2_id FROM user_order
    ON CONFLICT (user1_id, user2_id) DO UPDATE
    SET updated_at = CURRENT_TIMESTAMP
    RETURNING *
)
SELECT * FROM upserted_conversation;

-- ----------------------------------------------------------------------------
-- 6.4 Mark Conversation as Read
-- ----------------------------------------------------------------------------

WITH user_order AS (
    SELECT 
        LEAST(1, 2) AS user1_id,    -- Alice and Bob
        GREATEST(1, 2) AS user2_id
)
UPDATE conversations c
SET 
    user1_unread_count = CASE WHEN uo.user1_id = 1 THEN 0 ELSE c.user1_unread_count END,
    user2_unread_count = CASE WHEN uo.user2_id = 1 THEN 0 ELSE c.user2_unread_count END,
    updated_at = CURRENT_TIMESTAMP
FROM user_order uo
WHERE c.user1_id = uo.user1_id 
  AND c.user2_id = uo.user2_id
RETURNING c.id, c.user1_unread_count, c.user2_unread_count;


-- ============================================================================
-- PART 7: MESSAGE REPORTING
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 7.1 Report a Message
-- ----------------------------------------------------------------------------

-- Get a message ID to report
WITH msg_to_report AS (
    SELECT id FROM messages 
    WHERE sender_id = 2 AND receiver_id = 1 
    LIMIT 1
)
INSERT INTO message_reports (message_id, reported_by, reason, description)
SELECT 
    id,
    1,  -- Alice reports
    'spam',
    'This user keeps sending promotional content'
FROM msg_to_report
ON CONFLICT (message_id, reported_by) DO NOTHING
RETURNING id, message_id, reported_at;

-- ----------------------------------------------------------------------------
-- 7.2 Get User's Reports
-- ----------------------------------------------------------------------------

SELECT 
    mr.id,
    mr.message_id,
    mr.reason,
    mr.description,
    mr.reported_at,
    mr.is_reviewed,
    mr.reviewed_at,
    mr.action_taken,
    m.content AS message_content,
    m.sender_id,
    u.name AS sender_name
FROM message_reports mr
JOIN messages m ON mr.message_id = m.id
JOIN users u ON m.sender_id = u.id
WHERE mr.reported_by = 1  -- Alice's reports
ORDER BY mr.reported_at DESC;


-- ============================================================================
-- PART 8: BACKGROUND JOB QUERIES
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 8.1 Simulate Message Expiration
-- ----------------------------------------------------------------------------

-- First, mark some messages as read (to trigger expiration timer)
UPDATE messages 
SET status = 'read'
WHERE status = 'delivered'
  AND sender_id = 1 
  AND receiver_id = 2
LIMIT 3;

-- Check messages with expiration set
SELECT 
    id,
    sender_id,
    receiver_id,
    content,
    status,
    read_at,
    expires_at,
    is_expired,
    EXTRACT(EPOCH FROM (expires_at - CURRENT_TIMESTAMP))::INTEGER AS seconds_remaining
FROM messages
WHERE expires_at IS NOT NULL
ORDER BY expires_at;

-- Run expiration job (mark expired messages)
UPDATE messages 
SET is_expired = TRUE 
WHERE expires_at IS NOT NULL 
  AND expires_at <= CURRENT_TIMESTAMP 
  AND is_expired = FALSE
RETURNING id, content, expires_at;

-- ----------------------------------------------------------------------------
-- 8.2 Get Expired Attachments for Cleanup
-- ----------------------------------------------------------------------------

SELECT 
    ma.id,
    ma.file_url,
    ma.file_name,
    m.id AS message_id,
    m.expires_at
FROM message_attachments ma
JOIN messages m ON ma.message_id = m.id
WHERE m.is_expired = TRUE 
  AND ma.is_deleted = FALSE
LIMIT 100;

-- Mark attachments as deleted (after removing from S3)
-- UPDATE message_attachments
-- SET is_deleted = TRUE
-- WHERE id IN (1, 2, 3);  -- IDs from above query

-- ----------------------------------------------------------------------------
-- 8.3 Purge Old Deleted Messages
-- ----------------------------------------------------------------------------

-- See what would be deleted (dry run)
SELECT 
    id,
    sender_id,
    receiver_id,
    content,
    created_at,
    is_expired,
    deleted_by_sender
FROM messages 
WHERE (is_expired = TRUE OR deleted_by_sender = TRUE)
  AND created_at < CURRENT_TIMESTAMP - INTERVAL '7 days';

-- Actually delete them
-- WITH deleted_messages AS (
--     DELETE FROM messages 
--     WHERE (is_expired = TRUE OR deleted_by_sender = TRUE)
--       AND created_at < CURRENT_TIMESTAMP - INTERVAL '7 days'
--     RETURNING id
-- )
-- SELECT COUNT(*) AS purged_count FROM deleted_messages;


-- ============================================================================
-- PART 9: ANALYTICS QUERIES
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 9.1 User Message Statistics
-- ----------------------------------------------------------------------------

SELECT 
    u.id,
    u.name,
    COUNT(m.id) AS total_messages_sent,
    COUNT(CASE WHEN m.status = 'read' THEN 1 END) AS messages_read,
    COUNT(CASE WHEN m.status = 'delivered' THEN 1 END) AS messages_delivered,
    COUNT(CASE WHEN m.status = 'sent' THEN 1 END) AS messages_sent,
    COUNT(CASE WHEN m.is_expired = TRUE THEN 1 END) AS messages_expired,
    COUNT(CASE WHEN m.message_type = 'image' THEN 1 END) AS images_sent,
    COUNT(CASE WHEN m.message_type = 'pdf' THEN 1 END) AS pdfs_sent
FROM users u
LEFT JOIN messages m ON u.id = m.sender_id
WHERE u.id = 1  -- Alice's statistics
GROUP BY u.id, u.name;

-- ----------------------------------------------------------------------------
-- 9.2 Platform Statistics
-- ----------------------------------------------------------------------------

SELECT 
    COUNT(DISTINCT id) AS total_users,
    COUNT(DISTINCT CASE WHEN is_active = TRUE THEN id END) AS active_users,
    COUNT(DISTINCT CASE WHEN last_seen >= CURRENT_TIMESTAMP - INTERVAL '1 day' THEN id END) AS daily_active_users,
    COUNT(DISTINCT CASE WHEN last_seen >= CURRENT_TIMESTAMP - INTERVAL '1 hour' THEN id END) AS hourly_active_users,
    COUNT(DISTINCT CASE WHEN created_at >= CURRENT_TIMESTAMP - INTERVAL '1 day' THEN id END) AS new_signups_today
FROM users;

-- ----------------------------------------------------------------------------
-- 9.3 Message Volume Statistics
-- ----------------------------------------------------------------------------

SELECT 
    DATE(created_at) AS message_date,
    COUNT(*) AS total_messages,
    COUNT(DISTINCT sender_id) AS unique_senders,
    COUNT(CASE WHEN message_type = 'text' THEN 1 END) AS text_messages,
    COUNT(CASE WHEN message_type = 'image' THEN 1 END) AS image_messages,
    COUNT(CASE WHEN message_type = 'pdf' THEN 1 END) AS pdf_messages,
    AVG(LENGTH(content)) AS avg_message_length
FROM messages
WHERE created_at >= CURRENT_TIMESTAMP - INTERVAL '7 days'
GROUP BY DATE(created_at)
ORDER BY message_date DESC;

-- ----------------------------------------------------------------------------
-- 9.4 Most Active Conversations
-- ----------------------------------------------------------------------------

SELECT 
    LEAST(sender_id, receiver_id) AS user1_id,
    GREATEST(sender_id, receiver_id) AS user2_id,
    u1.name AS user1_name,
    u2.name AS user2_name,
    COUNT(*) AS message_count,
    MAX(created_at) AS last_message_at
FROM messages m
JOIN users u1 ON LEAST(m.sender_id, m.receiver_id) = u1.id
JOIN users u2 ON GREATEST(m.sender_id, m.receiver_id) = u2.id
WHERE m.created_at >= CURRENT_TIMESTAMP - INTERVAL '7 days'
  AND m.is_expired = FALSE
GROUP BY LEAST(sender_id, receiver_id), GREATEST(sender_id, receiver_id), u1.name, u2.name
ORDER BY message_count DESC
LIMIT 10;


-- ============================================================================
-- PART 10: TESTING & VALIDATION QUERIES
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 10.1 Verify All Constraints
-- ----------------------------------------------------------------------------

-- Test: User cannot add themselves as contact
-- INSERT INTO user_contacts (user_id, contact_user_id) VALUES (1, 1);
-- Expected: ERROR - constraint "user_contacts_no_self"

-- Test: User cannot send message to themselves
-- INSERT INTO messages (sender_id, receiver_id, content) VALUES (1, 1, 'Test');
-- Expected: ERROR - constraint "messages_sender_receiver_check"

-- Test: Invalid email format
-- INSERT INTO users (email, phone, name, age, password_hash) 
-- VALUES ('invalid-email', '+11111111111', 'Test', 25, 'hash');
-- Expected: ERROR - constraint "users_email_check"

-- ----------------------------------------------------------------------------
-- 10.2 Check Trigger Functionality
-- ----------------------------------------------------------------------------

-- Test: Verify conversation auto-creation on message send
SELECT COUNT(*) AS conversations_before FROM conversations;

INSERT INTO messages (sender_id, receiver_id, content, message_type)
VALUES (4, 5, 'Testing trigger', 'text');  -- Diana to Eve (new conversation)

SELECT COUNT(*) AS conversations_after FROM conversations;
-- Should show +1 conversation

-- Test: Verify unread count increment
SELECT user1_unread_count, user2_unread_count 
FROM conversations 
WHERE (user1_id = 1 AND user2_id = 2) OR (user1_id = 2 AND user2_id = 1);

-- Test: Verify expiration timer on read
UPDATE messages 
SET status = 'read' 
WHERE sender_id = 1 AND receiver_id = 2 AND status = 'sent'
LIMIT 1
RETURNING read_at, expires_at;
-- expires_at should be read_at + 5 minutes

-- ----------------------------------------------------------------------------
-- 10.3 Performance Testing Queries
-- ----------------------------------------------------------------------------

-- Explain query plan for conversation list
EXPLAIN ANALYZE
SELECT * FROM active_conversations_view 
WHERE user1_id = 1 OR user2_id = 1
ORDER BY last_message_at DESC;

-- Explain query plan for message retrieval
EXPLAIN ANALYZE
SELECT * FROM messages 
WHERE (sender_id = 1 AND receiver_id = 2) 
   OR (sender_id = 2 AND receiver_id = 1)
ORDER BY created_at DESC 
LIMIT 50;


-- ============================================================================
-- PART 11: CLEANUP QUERIES
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 11.1 View All Data Summary
-- ----------------------------------------------------------------------------

SELECT 
    'Users' AS table_name, 
    COUNT(*) AS record_count 
FROM users
UNION ALL
SELECT 'User Contacts', COUNT(*) FROM user_contacts
UNION ALL
SELECT 'Blocked Users', COUNT(*) FROM blocked_users
UNION ALL
SELECT 'Messages', COUNT(*) FROM messages
UNION ALL
SELECT 'Message Attachments', COUNT(*) FROM message_attachments
UNION ALL
SELECT 'Conversations', COUNT(*) FROM conversations
UNION ALL
SELECT 'Message Reports', COUNT(*) FROM message_reports;

-- ----------------------------------------------------------------------------
-- 11.2 Database Size Information
-- ----------------------------------------------------------------------------

SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size,
    pg_total_relation_size(schemaname||'.'||tablename) AS size_bytes
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;



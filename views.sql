
-- 1. active_conversations_view
CREATE OR REPLACE VIEW active_conversations_view AS
SELECT 
    c.id AS conversation_id,
    c.user1_id,
    c.user2_id,
    c.last_message_id,
    c.last_message_at,
    c.user1_unread_count,
    c.user2_unread_count,
    u1.name AS user1_name,
    u1.last_seen AS user1_last_seen,
    u2.name AS user2_name,
    u2.last_seen AS user2_last_seen,
    m.content AS last_message_content,
    m.message_type AS last_message_type,
    m.sender_id AS last_message_sender_id
FROM conversations c
JOIN users u1 ON c.user1_id = u1.id
JOIN users u2 ON c.user2_id = u2.id
LEFT JOIN messages m ON c.last_message_id = m.id
WHERE u1.is_active = TRUE 
  AND u2.is_active = TRUE
  AND (m.is_expired = FALSE OR m.id IS NULL);

COMMENT ON VIEW active_conversations_view IS 
'Provides conversation list with user details and last message';

-------------------------------------------------------------------------------------

-- 2. user_conversation_list


CREATE OR REPLACE VIEW user_conversation_list AS
SELECT 
    c.id AS conversation_id,
    CASE 
        WHEN c.user1_id = {{USER_ID}} THEN c.user2_id 
        ELSE c.user1_id 
    END AS other_user_id,
    CASE 
        WHEN c.user1_id = {{USER_ID}} THEN u2.name 
        ELSE u1.name 
    END AS other_user_name,
    CASE 
        WHEN c.user1_id = {{USER_ID}} THEN u2.last_seen 
        ELSE u1.last_seen 
    END AS other_user_last_seen,
    CASE 
        WHEN c.user1_id = {{USER_ID}} THEN c.user1_unread_count 
        ELSE c.user2_unread_count 
    END AS unread_count,
    c.last_message_at,
    m.content AS last_message_preview,
    m.sender_id = {{USER_ID}} AS last_message_is_mine
FROM conversations c
JOIN users u1 ON c.user1_id = u1.id
JOIN users u2 ON c.user2_id = u2.id
LEFT JOIN messages m ON c.last_message_id = m.id
WHERE (c.user1_id = {{USER_ID}} OR c.user2_id = {{USER_ID}})
  AND u1.is_active = TRUE 
  AND u2.is_active = TRUE
ORDER BY c.last_message_at DESC NULLS LAST;

COMMENT ON VIEW user_conversation_list IS 
'Parameterized view for specific user conversation list (replace {{USER_ID}} in application)';
-------------------------------------------------------------------------------------

-- 3. message_details_view


CREATE OR REPLACE VIEW message_details_view AS
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
    ma.file_url,
    ma.mime_type,
    CASE 
        WHEN m.read_at IS NOT NULL THEN 
            EXTRACT(EPOCH FROM (m.expires_at - CURRENT_TIMESTAMP))
        ELSE NULL
    END AS seconds_until_expiration
FROM messages m
JOIN users us ON m.sender_id = us.id
JOIN users ur ON m.receiver_id = ur.id
LEFT JOIN message_attachments ma ON m.id = ma.message_id
WHERE m.is_expired = FALSE AND m.deleted_by_sender = FALSE;

COMMENT ON VIEW message_details_view IS 
'Complete message information including attachment and expiration countdown';

-------------------------------------------------------------------------------------
-- 4. user_contacts_view


CREATE OR REPLACE VIEW user_contacts_view AS
SELECT 
    uc.id,
    uc.user_id,
    uc.contact_user_id,
    uc.contact_name,
    u.name AS actual_name,
    u.email,
    u.phone,
    u.last_seen,
    u.is_active,
    EXISTS(
        SELECT 1 FROM blocked_users bu 
        WHERE (bu.blocker_id = uc.user_id AND bu.blocked_id = uc.contact_user_id)
           OR (bu.blocker_id = uc.contact_user_id AND bu.blocked_id = uc.user_id)
    ) AS is_blocked
FROM user_contacts uc
JOIN users u ON uc.contact_user_id = u.id
WHERE u.is_active = TRUE;

COMMENT ON VIEW user_contacts_view IS 
'User contacts with blocking status and user details';


---


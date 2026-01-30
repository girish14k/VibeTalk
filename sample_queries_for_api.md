# Sample SQL Queries for API Implementation

## 1. User Management

### 1.1 Create New User (Sign Up)

```sql
INSERT INTO users (email, phone, name, age, password_hash)
VALUES ($1, $2, $3, $4, $5)
RETURNING id, email, phone, name, created_at;
```

**Parameters**: 
- $1: email (varchar)
- $2: phone (varchar)
- $3: name (varchar)
- $4: age (integer)
- $5: password_hash (varchar)

**Notes**: 
- Validate email/phone format in application before insert
- Hash password before passing to query
- Handle unique constraint violations (duplicate email/phone)

---

### 1.2 User Login (Verify Credentials)

```sql
SELECT id, email, phone, name, age, created_at, is_active
FROM users
WHERE (email = $1 OR phone = $1) 
  AND password_hash = crypt($2, password_hash)
  AND is_active = TRUE;
```

**Parameters**:
- $1: email or phone (varchar)
- $2: plain password (varchar) - will be hashed by crypt()

**Returns**: User object if credentials valid, empty if invalid

---

### 1.3 Update Last Seen (User Activity)

```sql
UPDATE users
SET last_seen = CURRENT_TIMESTAMP
WHERE id = $1;
```

**Parameters**: 
- $1: user_id (bigint)

**Notes**: Call this on every API request or WebSocket heartbeat

---

### 1.4 Get User Profile

```sql
SELECT id, email, phone, name, age, last_seen, created_at
FROM users
WHERE id = $1 AND is_active = TRUE;
```

**Parameters**: 
- $1: user_id (bigint)

---

### 1.5 Update User Profile

```sql
UPDATE users
SET name = COALESCE($2, name),
    age = COALESCE($3, age),
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1
RETURNING id, email, phone, name, age;
```

**Parameters**: 
- $1: user_id (bigint)
- $2: new_name (varchar, nullable)
- $3: new_age (integer, nullable)

---

### 1.6 Deactivate Account (Soft Delete)

```sql
UPDATE users
SET is_active = FALSE,
    updated_at = CURRENT_TIMESTAMP
WHERE id = $1;
```

**Parameters**: 
- $1: user_id (bigint)

---

## 2. Contact Management

### 2.1 Add Contact

```sql
INSERT INTO user_contacts (user_id, contact_user_id, contact_name)
VALUES ($1, $2, $3)
ON CONFLICT (user_id, contact_user_id) DO NOTHING
RETURNING id, contact_user_id, contact_name, added_at;
```

**Parameters**: 
- $1: user_id (bigint)
- $2: contact_user_id (bigint)
- $3: contact_name (varchar, from device contacts)

**Notes**: 
- Validate that contact_user_id exists and is active
- Check user_id != contact_user_id in application

---

### 2.2 Get User's Contacts

```sql
SELECT 
    uc.contact_user_id AS user_id,
    uc.contact_name,
    u.name AS actual_name,
    u.phone,
    u.last_seen,
    EXISTS(
        SELECT 1 FROM blocked_users bu 
        WHERE (bu.blocker_id = $1 AND bu.blocked_id = uc.contact_user_id)
           OR (bu.blocker_id = uc.contact_user_id AND bu.blocked_id = $1)
    ) AS is_blocked
FROM user_contacts uc
JOIN users u ON uc.contact_user_id = u.id
WHERE uc.user_id = $1 
  AND u.is_active = TRUE
ORDER BY uc.contact_name, u.name;
```

**Parameters**: 
- $1: user_id (bigint)

---

### 2.3 Remove Contact

```sql
DELETE FROM user_contacts
WHERE user_id = $1 AND contact_user_id = $2;
```

**Parameters**: 
- $1: user_id (bigint)
- $2: contact_user_id (bigint)

---

### 2.4 Check If Users Are Contacts

```sql
SELECT can_users_message($1, $2) AS can_message;
```

**Parameters**: 
- $1: user1_id (bigint)
- $2: user2_id (bigint)

**Returns**: Boolean - TRUE if they can message

---

### 2.5 Sync Contacts (Bulk Insert)

```sql
INSERT INTO user_contacts (user_id, contact_user_id, contact_name)
SELECT $1, u.id, $3
FROM users u
WHERE u.phone = ANY($2::varchar[])
  AND u.is_active = TRUE
  AND u.id != $1
ON CONFLICT (user_id, contact_user_id) DO NOTHING;
```

**Parameters**: 
- $1: user_id (bigint)
- $2: array of phone numbers (varchar[])
- $3: contact_name (varchar, can be same for all or individual)

---

## 3. Blocking Management

### 3.1 Block User

```sql
INSERT INTO blocked_users (blocker_id, blocked_id, reason)
VALUES ($1, $2, $3)
ON CONFLICT (blocker_id, blocked_id) DO NOTHING
RETURNING id, blocked_at;
```

**Parameters**: 
- $1: blocker_id (bigint)
- $2: blocked_id (bigint)
- $3: reason (varchar, optional)

---

### 3.2 Unblock User

```sql
DELETE FROM blocked_users
WHERE blocker_id = $1 AND blocked_id = $2;
```

**Parameters**: 
- $1: blocker_id (bigint)
- $2: blocked_id (bigint)

---

### 3.3 Get Blocked Users List

```sql
SELECT 
    bu.blocked_id AS user_id,
    u.name,
    u.phone,
    bu.blocked_at,
    bu.reason
FROM blocked_users bu
JOIN users u ON bu.blocked_id = u.id
WHERE bu.blocker_id = $1
ORDER BY bu.blocked_at DESC;
```

**Parameters**: 
- $1: user_id (bigint)

---

### 3.4 Check If User Is Blocked

```sql
SELECT EXISTS(
    SELECT 1 FROM blocked_users
    WHERE (blocker_id = $1 AND blocked_id = $2)
       OR (blocker_id = $2 AND blocked_id = $1)
) AS is_blocked;
```

**Parameters**: 
- $1: user1_id (bigint)
- $2: user2_id (bigint)

---

## 4. Messaging

### 4.1 Send Text Message

```sql
WITH new_message AS (
    INSERT INTO messages (sender_id, receiver_id, content, message_type)
    VALUES ($1, $2, $3, 'text')
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
```

**Parameters**: 
- $1: sender_id (bigint)
- $2: receiver_id (bigint)
- $3: content (text, max 5000 chars)

**Pre-checks**: 
- Validate can_users_message($1, $2) = TRUE
- Validate content length <= 5000

---

### 4.2 Send Message with Attachment

```sql
-- First, insert the message
WITH new_message AS (
    INSERT INTO messages (sender_id, receiver_id, message_type)
    VALUES ($1, $2, $3::message_type_enum)
    RETURNING *
),
-- Then insert the attachment
new_attachment AS (
    INSERT INTO message_attachments (
        message_id, 
        file_type, 
        file_name, 
        file_size, 
        file_url, 
        mime_type
    )
    SELECT 
        nm.id,
        $4::file_type_enum,
        $5,
        $6,
        $7,
        $8
    FROM new_message nm
    RETURNING *
)
SELECT 
    nm.id AS message_id,
    nm.sender_id,
    nm.receiver_id,
    nm.message_type,
    nm.status,
    nm.created_at,
    na.file_name,
    na.file_type,
    na.file_size,
    na.file_url,
    us.name AS sender_name,
    ur.name AS receiver_name
FROM new_message nm
JOIN users us ON nm.sender_id = us.id
JOIN users ur ON nm.receiver_id = ur.id
CROSS JOIN new_attachment na;
```

**Parameters**: 
- $1: sender_id (bigint)
- $2: receiver_id (bigint)
- $3: message_type ('image' or 'pdf')
- $4: file_type ('image' or 'pdf')
- $5: file_name (varchar)
- $6: file_size (bigint, in bytes)
- $7: file_url (text, S3 URL)
- $8: mime_type (varchar)

**Pre-checks**: 
- Upload file to S3 first, get URL
- Validate file size limits
- Validate mime type

---

### 4.3 Get Messages in Conversation (with Pagination)

```sql
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
    CASE WHEN m.sender_id = $1 THEN TRUE ELSE FALSE END AS is_mine,
    ma.file_name,
    ma.file_type,
    ma.file_size,
    ma.file_url,
    ma.mime_type,
    CASE 
        WHEN m.expires_at IS NOT NULL THEN 
            GREATEST(0, EXTRACT(EPOCH FROM (m.expires_at - CURRENT_TIMESTAMP))::INTEGER)
        ELSE NULL
    END AS seconds_until_expiration
FROM messages m
LEFT JOIN message_attachments ma ON m.id = ma.message_id
WHERE ((m.sender_id = $1 AND m.receiver_id = $2) 
   OR (m.sender_id = $2 AND m.receiver_id = $1))
  AND m.is_expired = FALSE
  AND m.deleted_by_sender = FALSE
  AND m.created_at < COALESCE($3, CURRENT_TIMESTAMP)
ORDER BY m.created_at DESC
LIMIT $4;
```

**Parameters**: 
- $1: current_user_id (bigint)
- $2: other_user_id (bigint)
- $3: before_timestamp (timestamptz, for pagination, NULL for first page)
- $4: limit (integer, e.g., 50)

**Returns**: Latest messages, newest first

---

### 4.4 Mark Message as Delivered

```sql
UPDATE messages
SET status = 'delivered',
    delivered_at = CURRENT_TIMESTAMP
WHERE id = $1
  AND status = 'sent'
  AND receiver_id = $2
RETURNING id, status, delivered_at;
```

**Parameters**: 
- $1: message_id (uuid)
- $2: receiver_id (bigint, for security)

---

### 4.5 Mark Messages as Read (Batch)

```sql
UPDATE messages
SET status = 'read'
WHERE id = ANY($1::uuid[])
  AND receiver_id = $2
  AND status IN ('sent', 'delivered')
RETURNING id, status, read_at, expires_at;
```

**Parameters**: 
- $1: array of message_ids (uuid[])
- $2: receiver_id (bigint)

**Notes**: Triggers will automatically set read_at and expires_at

---

### 4.6 Delete Message (Within 1 Minute)

```sql
UPDATE messages
SET deleted_by_sender = TRUE
WHERE id = $1
  AND sender_id = $2
  AND created_at >= CURRENT_TIMESTAMP - INTERVAL '1 minute'
  AND deleted_by_sender = FALSE
RETURNING id, deleted_at, status;
```

**Parameters**: 
- $1: message_id (uuid)
- $2: sender_id (bigint)

**Error Handling**: 
- If no rows updated, message is either:
  - Not found
  - Not owned by sender
  - Already deleted
  - Outside 1-minute window (trigger will raise exception)

---

### 4.7 Get Single Message Details

```sql
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
    ma.mime_type
FROM messages m
JOIN users us ON m.sender_id = us.id
JOIN users ur ON m.receiver_id = ur.id
LEFT JOIN message_attachments ma ON m.id = ma.message_id
WHERE m.id = $1
  AND (m.sender_id = $2 OR m.receiver_id = $2)
  AND m.is_expired = FALSE
  AND m.deleted_by_sender = FALSE;
```

**Parameters**: 
- $1: message_id (uuid)
- $2: current_user_id (bigint, for access control)

---

## 5. Conversations

### 5.1 Get User's Conversation List

```sql
SELECT 
    c.id AS conversation_id,
    CASE 
        WHEN c.user1_id = $1 THEN c.user2_id 
        ELSE c.user1_id 
    END AS other_user_id,
    CASE 
        WHEN c.user1_id = $1 THEN u2.name 
        ELSE u1.name 
    END AS other_user_name,
    CASE 
        WHEN c.user1_id = $1 THEN u2.phone 
        ELSE u1.phone 
    END AS other_user_phone,
    CASE 
        WHEN c.user1_id = $1 THEN u2.last_seen 
        ELSE u1.last_seen 
    END AS other_user_last_seen,
    CASE 
        WHEN c.user1_id = $1 THEN c.user1_unread_count 
        ELSE c.user2_unread_count 
    END AS unread_count,
    c.last_message_at,
    c.last_message_id,
    m.content AS last_message_preview,
    m.message_type AS last_message_type,
    m.sender_id = $1 AS last_message_is_mine,
    EXISTS(
        SELECT 1 FROM blocked_users bu
        WHERE (bu.blocker_id = $1 AND bu.blocked_id = (CASE WHEN c.user1_id = $1 THEN c.user2_id ELSE c.user1_id END))
           OR (bu.blocker_id = (CASE WHEN c.user1_id = $1 THEN c.user2_id ELSE c.user1_id END) AND bu.blocked_id = $1)
    ) AS is_blocked
FROM conversations c
JOIN users u1 ON c.user1_id = u1.id
JOIN users u2 ON c.user2_id = u2.id
LEFT JOIN messages m ON c.last_message_id = m.id AND m.is_expired = FALSE
WHERE (c.user1_id = $1 OR c.user2_id = $1)
  AND u1.is_active = TRUE 
  AND u2.is_active = TRUE
ORDER BY c.last_message_at DESC NULLS LAST
LIMIT $2 OFFSET $3;
```

**Parameters**: 
- $1: user_id (bigint)
- $2: limit (integer, e.g., 20)
- $3: offset (integer, for pagination)

---

### 5.2 Get or Create Conversation

```sql
WITH user_order AS (
    SELECT 
        LEAST($1, $2) AS user1_id,
        GREATEST($1, $2) AS user2_id
),
upserted_conversation AS (
    INSERT INTO conversations (user1_id, user2_id)
    SELECT user1_id, user2_id FROM user_order
    ON CONFLICT (user1_id, user2_id) DO UPDATE
    SET updated_at = CURRENT_TIMESTAMP
    RETURNING *
)
SELECT * FROM upserted_conversation;
```

**Parameters**: 
- $1: user_id_1 (bigint)
- $2: user_id_2 (bigint)

---

### 5.3 Mark Conversation as Read (Reset Unread Count)

```sql
WITH user_order AS (
    SELECT 
        LEAST($1, $2) AS user1_id,
        GREATEST($1, $2) AS user2_id
)
UPDATE conversations c
SET 
    user1_unread_count = CASE WHEN uo.user1_id = $1 THEN 0 ELSE c.user1_unread_count END,
    user2_unread_count = CASE WHEN uo.user2_id = $1 THEN 0 ELSE c.user2_unread_count END,
    updated_at = CURRENT_TIMESTAMP
FROM user_order uo
WHERE c.user1_id = uo.user1_id 
  AND c.user2_id = uo.user2_id
RETURNING c.id;
```

**Parameters**: 
- $1: current_user_id (bigint)
- $2: other_user_id (bigint)

---

### 5.4 Get Total Unread Count for User

```sql
SELECT 
    COALESCE(SUM(
        CASE 
            WHEN user1_id = $1 THEN user1_unread_count 
            WHEN user2_id = $1 THEN user2_unread_count 
            ELSE 0 
        END
    ), 0) AS total_unread
FROM conversations
WHERE user1_id = $1 OR user2_id = $1;
```

**Parameters**: 
- $1: user_id (bigint)

---

## 6. Message Reporting

### 6.1 Report Message

```sql
INSERT INTO message_reports (message_id, reported_by, reason, description)
VALUES ($1, $2, $3::report_reason_enum, $4)
ON CONFLICT (message_id, reported_by) DO NOTHING
RETURNING id, reported_at;
```

**Parameters**: 
- $1: message_id (uuid)
- $2: reported_by (bigint)
- $3: reason (enum: spam, harassment, inappropriate_content, impersonation, other)
- $4: description (text, optional)

---

### 6.2 Get User's Reports

```sql
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
WHERE mr.reported_by = $1
ORDER BY mr.reported_at DESC
LIMIT $2 OFFSET $3;
```

**Parameters**: 
- $1: user_id (bigint)
- $2: limit (integer)
- $3: offset (integer)

---

## 7. Background Jobs

### 7.1 Expire Messages (Run Every 30 Seconds)

```sql
UPDATE messages 
SET is_expired = TRUE 
WHERE expires_at IS NOT NULL 
  AND expires_at <= CURRENT_TIMESTAMP 
  AND is_expired = FALSE;
```

**Returns**: Number of rows updated

---

### 7.2 Get Expired File Attachments for Cleanup (Run Every 5 Minutes)

```sql
SELECT 
    ma.id,
    ma.file_url,
    ma.file_name,
    m.id AS message_id
FROM message_attachments ma
JOIN messages m ON ma.message_id = m.id
WHERE m.is_expired = TRUE 
  AND ma.is_deleted = FALSE
LIMIT 1000;
```

**Post-processing**: 
1. Delete files from S3
2. Mark as deleted:

```sql
UPDATE message_attachments
SET is_deleted = TRUE
WHERE id = ANY($1::bigint[]);
```

---

### 7.3 Purge Old Deleted Messages (Run Daily)

```sql
WITH deleted_messages AS (
    DELETE FROM messages 
    WHERE (is_expired = TRUE OR deleted_by_sender = TRUE)
      AND created_at < CURRENT_TIMESTAMP - INTERVAL '7 days'
    RETURNING id
)
SELECT COUNT(*) AS purged_count FROM deleted_messages;
```

**Notes**: Cascades to message_attachments and message_reports

---

## 8. Analytics Queries (Optional)

### 8.1 Get User Message Statistics

```sql
SELECT 
    COUNT(*) AS total_messages_sent,
    COUNT(CASE WHEN status = 'read' THEN 1 END) AS messages_read,
    COUNT(CASE WHEN is_expired = TRUE THEN 1 END) AS messages_expired,
    AVG(EXTRACT(EPOCH FROM (read_at - created_at)))::INTEGER AS avg_time_to_read_seconds
FROM messages
WHERE sender_id = $1
  AND created_at >= $2
  AND created_at <= $3;
```

**Parameters**: 
- $1: user_id (bigint)
- $2: start_date (timestamptz)
- $3: end_date (timestamptz)

---

### 8.2 Get Platform Statistics

```sql
SELECT 
    COUNT(DISTINCT id) AS total_users,
    COUNT(DISTINCT CASE WHEN last_seen >= CURRENT_TIMESTAMP - INTERVAL '1 day' THEN id END) AS daily_active_users,
    COUNT(DISTINCT CASE WHEN created_at >= CURRENT_TIMESTAMP - INTERVAL '1 day' THEN id END) AS new_signups_today
FROM users
WHERE is_active = TRUE;
```

---

## Best Practices for API Implementation

1. **Always use parameterized queries** to prevent SQL injection
2. **Validate permissions** before executing queries (check user owns resource)
3. **Use transactions** for multi-step operations
4. **Handle unique constraint violations** gracefully
5. **Implement retry logic** for deadlock scenarios
6. **Cache frequently accessed data** (conversation lists, contacts)
7. **Use connection pooling** for database connections
8. **Log slow queries** (> 100ms) for optimization
9. **Implement rate limiting** at API layer
10. **Always filter by is_active** when querying users

---

## Error Handling Examples

### Handle Unique Constraint Violation (Duplicate Email)

```python
try:
    cursor.execute(query, params)
except psycopg2.errors.UniqueViolation as e:
    if 'users_email_key' in str(e):
        raise APIError("Email already registered", status_code=409)
    elif 'users_phone_key' in str(e):
        raise APIError("Phone number already registered", status_code=409)
```

### Handle Check Constraint Violation

```python
try:
    cursor.execute(query, params)
except psycopg2.errors.CheckViolation as e:
    if 'messages_sender_receiver_check' in str(e):
        raise APIError("Cannot send message to yourself", status_code=400)
```

### Handle Trigger Exception (Message Deletion After 1 Minute)

```python
try:
    cursor.execute(delete_message_query, params)
except psycopg2.errors.RaiseException as e:
    if 'Cannot delete message after 1 minute' in str(e):
        raise APIError("Message can only be deleted within 1 minute", status_code=403)
```



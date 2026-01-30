# Vibe Chat Application - Low Level Design

## Low-Level Design

### Table Definitions

#### 1. users

```sql
CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY,
    email VARCHAR(255) NOT NULL UNIQUE,
    phone VARCHAR(20) NOT NULL UNIQUE,
    name VARCHAR(100) NOT NULL,
    age INTEGER NOT NULL CHECK (age >= 13 AND age <= 120),
    password_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_seen TIMESTAMP WITH TIME ZONE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    
    CONSTRAINT users_email_check CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),
    CONSTRAINT users_phone_check CHECK (phone ~ '^\+?[1-9]\d{1,14}$')
);

COMMENT ON TABLE users IS 'Stores user account information';
COMMENT ON COLUMN users.password_hash IS 'Hashed password using bcrypt/argon2';
COMMENT ON COLUMN users.last_seen IS 'Last activity timestamp for online status';
COMMENT ON COLUMN users.is_active IS 'Soft delete flag - false means account deactivated';
```

#### 2. user_contacts

```sql
CREATE TABLE user_contacts (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    contact_user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    contact_name VARCHAR(100), -- Name saved in user's contact list
    added_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT user_contacts_unique UNIQUE(user_id, contact_user_id),
    CONSTRAINT user_contacts_no_self CHECK (user_id != contact_user_id)
);

CREATE INDEX idx_user_contacts_user_id ON user_contacts(user_id);
CREATE INDEX idx_user_contacts_contact_user_id ON user_contacts(contact_user_id);

COMMENT ON TABLE user_contacts IS 'Many-to-many relationship: users can message contacts only';
COMMENT ON COLUMN user_contacts.contact_name IS 'Display name from user device contacts';
```

#### 3. blocked_users

```sql
CREATE TABLE blocked_users (
    id BIGSERIAL PRIMARY KEY,
    blocker_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    blocked_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    blocked_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    reason VARCHAR(500),
    
    CONSTRAINT blocked_users_unique UNIQUE(blocker_id, blocked_id),
    CONSTRAINT blocked_users_no_self CHECK (blocker_id != blocked_id)
);

CREATE INDEX idx_blocked_users_blocker_id ON blocked_users(blocker_id);
CREATE INDEX idx_blocked_users_blocked_id ON blocked_users(blocked_id);

COMMENT ON TABLE blocked_users IS 'Stores user blocking relationships';
```

#### 4. messages

```sql
CREATE TYPE message_type_enum AS ENUM ('text', 'image', 'pdf');
CREATE TYPE message_status_enum AS ENUM ('sent', 'delivered', 'read', 'deleted');

CREATE TABLE messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sender_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    receiver_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    content TEXT CHECK (LENGTH(content) <= 5000),
    message_type message_type_enum NOT NULL DEFAULT 'text',
    status message_status_enum NOT NULL DEFAULT 'sent',
    
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    delivered_at TIMESTAMP WITH TIME ZONE,
    read_at TIMESTAMP WITH TIME ZONE,
    expires_at TIMESTAMP WITH TIME ZONE,
    
    deleted_by_sender BOOLEAN NOT NULL DEFAULT FALSE,
    deleted_at TIMESTAMP WITH TIME ZONE,
    is_expired BOOLEAN NOT NULL DEFAULT FALSE,
    
    CONSTRAINT messages_sender_receiver_check CHECK (sender_id != receiver_id),
    CONSTRAINT messages_content_check CHECK (
        (message_type = 'text' AND content IS NOT NULL) OR
        (message_type IN ('image', 'pdf') AND content IS NULL)
    ),
    CONSTRAINT messages_status_timestamps CHECK (
        (status = 'sent') OR
        (status = 'delivered' AND delivered_at IS NOT NULL) OR
        (status = 'read' AND read_at IS NOT NULL AND delivered_at IS NOT NULL) OR
        (status = 'deleted')
    )
);

-- Critical indexes for performance
CREATE INDEX idx_messages_sender_id ON messages(sender_id) WHERE is_expired = FALSE;
CREATE INDEX idx_messages_receiver_id ON messages(receiver_id) WHERE is_expired = FALSE;
CREATE INDEX idx_messages_created_at ON messages(created_at DESC);
CREATE INDEX idx_messages_expires_at ON messages(expires_at) WHERE expires_at IS NOT NULL AND is_expired = FALSE;
CREATE INDEX idx_messages_conversation ON messages(sender_id, receiver_id, created_at DESC) WHERE is_expired = FALSE;
CREATE INDEX idx_messages_status ON messages(status) WHERE is_expired = FALSE;

COMMENT ON TABLE messages IS 'Stores all chat messages with expiration tracking';
COMMENT ON COLUMN messages.content IS 'Message text content, max 5000 chars, supports UTF-8 emojis';
COMMENT ON COLUMN messages.expires_at IS 'Set to read_at + 5 minutes when message is read';
COMMENT ON COLUMN messages.deleted_by_sender IS 'Sender can delete within 1 minute of sending';
COMMENT ON COLUMN messages.is_expired IS 'True when message has passed expiration time';
```

#### 5. message_attachments

```sql
CREATE TYPE file_type_enum AS ENUM ('pdf', 'image');

CREATE TABLE message_attachments (
    id BIGSERIAL PRIMARY KEY,
    message_id UUID NOT NULL UNIQUE REFERENCES messages(id) ON DELETE CASCADE,
    file_type file_type_enum NOT NULL,
    file_name VARCHAR(255) NOT NULL,
    file_size BIGINT NOT NULL CHECK (file_size > 0),
    file_url TEXT NOT NULL,
    mime_type VARCHAR(100) NOT NULL,
    uploaded_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    
    CONSTRAINT message_attachments_size_check CHECK (
        (file_type = 'pdf' AND file_size <= 10485760) OR  -- 10MB for PDF
        (file_type = 'image' AND file_size <= 5242880)     -- 5MB for images
    )
);

CREATE INDEX idx_message_attachments_message_id ON message_attachments(message_id);
CREATE INDEX idx_message_attachments_uploaded_at ON message_attachments(uploaded_at);

COMMENT ON TABLE message_attachments IS 'Stores file metadata; actual files in object storage';
COMMENT ON COLUMN message_attachments.file_url IS 'Presigned S3 URL or object storage path';
COMMENT ON COLUMN message_attachments.is_deleted IS 'Marks file for deletion from storage';
```

#### 6. conversations

```sql
CREATE TABLE conversations (
    id BIGSERIAL PRIMARY KEY,
    user1_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    user2_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    last_message_id UUID REFERENCES messages(id) ON DELETE SET NULL,
    last_message_at TIMESTAMP WITH TIME ZONE,
    user1_unread_count INTEGER NOT NULL DEFAULT 0,
    user2_unread_count INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT conversations_unique UNIQUE(user1_id, user2_id),
    CONSTRAINT conversations_user_order CHECK (user1_id < user2_id),
    CONSTRAINT conversations_unread_count_check CHECK (
        user1_unread_count >= 0 AND user2_unread_count >= 0
    )
);

CREATE INDEX idx_conversations_user1_id ON conversations(user1_id);
CREATE INDEX idx_conversations_user2_id ON conversations(user2_id);
CREATE INDEX idx_conversations_last_message_at ON conversations(last_message_at DESC);

COMMENT ON TABLE conversations IS 'Denormalized table for conversation list performance';
COMMENT ON COLUMN conversations.user1_id IS 'Always the smaller user ID (enforced by CHECK)';
COMMENT ON COLUMN conversations.user2_id IS 'Always the larger user ID (enforced by CHECK)';
```

#### 7. message_reports 

```sql
CREATE TYPE report_reason_enum AS ENUM (
    'spam',
    'harassment',
    'inappropriate_content',
    'impersonation',
    'other'
);

CREATE TABLE message_reports (
    id BIGSERIAL PRIMARY KEY,
    message_id UUID NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    reported_by BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reason report_reason_enum NOT NULL,
    description TEXT,
    reported_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_reviewed BOOLEAN NOT NULL DEFAULT FALSE,
    reviewed_at TIMESTAMP WITH TIME ZONE,
    reviewed_by BIGINT REFERENCES users(id) ON DELETE SET NULL,
    action_taken VARCHAR(500),
    
    CONSTRAINT message_reports_unique UNIQUE(message_id, reported_by)
);

CREATE INDEX idx_message_reports_message_id ON message_reports(message_id);
CREATE INDEX idx_message_reports_reported_by ON message_reports(reported_by);
CREATE INDEX idx_message_reports_is_reviewed ON message_reports(is_reviewed) WHERE is_reviewed = FALSE;

COMMENT ON TABLE message_reports IS 'Allows users to report messages before they disappear';
```

---

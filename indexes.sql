
-- Indexes

-- Primary Indexes are defined above
-- All PRIMARY KEY constraints automatically create indexes
-- UNIQUE constraints automatically create indexes

-- Performance Indexes (These are additionali implemented)

-- Composite index for fetching conversation messages
CREATE INDEX idx_messages_conversation_composite 
ON messages(sender_id, receiver_id, created_at DESC, status) 
WHERE is_expired = FALSE AND deleted_by_sender = FALSE;

-- Index for finding messages that need expiration
CREATE INDEX idx_messages_expiration_job 
ON messages(expires_at, is_expired) 
WHERE expires_at IS NOT NULL AND is_expired = FALSE;

-- Index for sender deletion window check (1 minute rule)
CREATE INDEX idx_messages_sender_deletion 
ON messages(sender_id, created_at) 
WHERE deleted_by_sender = FALSE AND is_expired = FALSE;

-- Partial index for active users
CREATE INDEX idx_users_active ON users(id) WHERE is_active = TRUE;

-- Index for user search by phone/email
CREATE INDEX idx_users_phone ON users(phone) WHERE is_active = TRUE;
CREATE INDEX idx_users_email ON users(lower(email)) WHERE is_active = TRUE;

-- Index for checking if users can message each other
CREATE INDEX idx_user_contacts_can_message 
ON user_contacts(user_id, contact_user_id);



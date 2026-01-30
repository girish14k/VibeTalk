
-- Database-Level Constraints

-- This ensures message content aligns with message type
ALTER TABLE messages ADD CONSTRAINT messages_type_content_validation 
CHECK (
    (message_type = 'text' AND content IS NOT NULL AND LENGTH(TRIM(content)) > 0) OR
    (message_type IN ('image', 'pdf'))
);

-- This ensure expiration is set only for read messages
ALTER TABLE messages ADD CONSTRAINT messages_expiration_logic 
CHECK (
    (status != 'read' AND expires_at IS NULL) OR
    (status = 'read' AND expires_at IS NOT NULL)
);

-- This ensure file attachment mime types are valid
ALTER TABLE message_attachments ADD CONSTRAINT attachments_mime_validation 
CHECK (
    (file_type = 'pdf' AND mime_type = 'application/pdf') OR
    (file_type = 'image' AND mime_type IN (
        'image/jpeg', 'image/png', 'image/gif', 'image/webp'
    ))
);
`
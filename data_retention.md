
## Data Retention Policies

### Background Jobs (To be implemented in application layer)

#### 1. Message Expiration Job
```
Frequency: Every 30 seconds
Purpose: Mark expired messages
Query:
    UPDATE messages 
    SET is_expired = TRUE 
    WHERE expires_at IS NOT NULL 
      AND expires_at <= CURRENT_TIMESTAMP 
      AND is_expired = FALSE;
```

#### 2. File Cleanup Job
```
Frequency: Every 5 minutes
Purpose: Queue expired file attachments for deletion from object storage
Query:
    SELECT ma.id, ma.file_url 
    FROM message_attachments ma
    JOIN messages m ON ma.message_id = m.id
    WHERE m.is_expired = TRUE 
      AND ma.is_deleted = FALSE;
      
    -- Then mark as deleted:
    UPDATE message_attachments 
    SET is_deleted = TRUE 
    WHERE id IN (selected_ids);
```

#### 3. Purge Deleted Messages
```
Frequency: Daily (off-peak hours)
Purpose: Permanently remove expired and deleted messages
Query:
    DELETE FROM messages 
    WHERE (is_expired = TRUE OR deleted_by_sender = TRUE)
      AND created_at < CURRENT_TIMESTAMP - INTERVAL '7 days';
      
    -- This cascades to message_attachments due to ON DELETE CASCADE
```

### Retention Rules

1. **Active Messages**: Kept until read + 5 minutes
2. **Unread Messages**: Kept indefinitely (no expiration until read)
3. **Deleted Messages**: Soft-deleted for 7 days, then hard-deleted
4. **User Data**: Retained until account deletion
5. **Audit Logs**: Message reports kept for 90 days after resolution


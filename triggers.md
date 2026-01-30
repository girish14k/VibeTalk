
### Trigger Functions

#### 1. Auto-update timestamps

```sql
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_conversations_updated_at
    BEFORE UPDATE ON conversations
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
```

#### 2. Set expiration time on message read

```sql
CREATE OR REPLACE FUNCTION set_message_expiration()
RETURNS TRIGGER AS $$
BEGIN
    -- When message status changes to 'read', set expiration to 5 minutes from now
    IF NEW.status = 'read' AND OLD.status != 'read' THEN
        NEW.read_at = CURRENT_TIMESTAMP;
        NEW.expires_at = CURRENT_TIMESTAMP + INTERVAL '5 minutes';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_set_message_expiration
    BEFORE UPDATE ON messages
    FOR EACH ROW
    WHEN (NEW.status = 'read' AND OLD.status != 'read')
    EXECUTE FUNCTION set_message_expiration();
```

#### 3. Update conversation on new message

```sql
CREATE OR REPLACE FUNCTION update_conversation_on_message()
RETURNS TRIGGER AS $$
DECLARE
    v_user1_id BIGINT;
    v_user2_id BIGINT;
    v_receiver_id BIGINT;
BEGIN
    -- Determine user1 and user2 (user1_id < user2_id)
    IF NEW.sender_id < NEW.receiver_id THEN
        v_user1_id := NEW.sender_id;
        v_user2_id := NEW.receiver_id;
    ELSE
        v_user1_id := NEW.receiver_id;
        v_user2_id := NEW.sender_id;
    END IF;
    
    -- Insert or update conversation
    INSERT INTO conversations (user1_id, user2_id, last_message_id, last_message_at)
    VALUES (v_user1_id, v_user2_id, NEW.id, NEW.created_at)
    ON CONFLICT (user1_id, user2_id) 
    DO UPDATE SET 
        last_message_id = NEW.id,
        last_message_at = NEW.created_at,
        updated_at = CURRENT_TIMESTAMP;
    
    -- Increment unread count for receiver
    IF v_user1_id = NEW.receiver_id THEN
        UPDATE conversations 
        SET user1_unread_count = user1_unread_count + 1
        WHERE user1_id = v_user1_id AND user2_id = v_user2_id;
    ELSE
        UPDATE conversations 
        SET user2_unread_count = user2_unread_count + 1
        WHERE user1_id = v_user1_id AND user2_id = v_user2_id;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_conversation
    AFTER INSERT ON messages
    FOR EACH ROW
    EXECUTE FUNCTION update_conversation_on_message();
```

#### 4. Reset unread count on message read

```sql
CREATE OR REPLACE FUNCTION reset_unread_count()
RETURNS TRIGGER AS $$
DECLARE
    v_user1_id BIGINT;
    v_user2_id BIGINT;
BEGIN
    IF NEW.status = 'read' AND OLD.status != 'read' THEN
        -- Determine user1 and user2
        IF NEW.sender_id < NEW.receiver_id THEN
            v_user1_id := NEW.sender_id;
            v_user2_id := NEW.receiver_id;
        ELSE
            v_user1_id := NEW.receiver_id;
            v_user2_id := NEW.sender_id;
        END IF;
        
        -- Reset unread count for the reader
        IF v_user1_id = NEW.receiver_id THEN
            UPDATE conversations 
            SET user1_unread_count = GREATEST(user1_unread_count - 1, 0)
            WHERE user1_id = v_user1_id AND user2_id = v_user2_id;
        ELSE
            UPDATE conversations 
            SET user2_unread_count = GREATEST(user2_unread_count - 1, 0)
            WHERE user1_id = v_user1_id AND user2_id = v_user2_id;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_reset_unread_count
    AFTER UPDATE ON messages
    FOR EACH ROW
    WHEN (NEW.status = 'read' AND OLD.status != 'read')
    EXECUTE FUNCTION reset_unread_count();
```

#### 5. Prevent message deletion after 1 minute

```sql
CREATE OR REPLACE FUNCTION check_message_deletion_window()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.deleted_by_sender = TRUE AND OLD.deleted_by_sender = FALSE THEN
        IF CURRENT_TIMESTAMP > (OLD.created_at + INTERVAL '1 minute') THEN
            RAISE EXCEPTION 'Cannot delete message after 1 minute of sending';
        END IF;
        NEW.deleted_at = CURRENT_TIMESTAMP;
        NEW.status = 'deleted';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_check_message_deletion
    BEFORE UPDATE ON messages
    FOR EACH ROW
    WHEN (NEW.deleted_by_sender = TRUE AND OLD.deleted_by_sender = FALSE)
    EXECUTE FUNCTION check_message_deletion_window();
```
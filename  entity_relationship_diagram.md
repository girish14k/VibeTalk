## Entity Relationship Diagram

```
┌─────────────────┐         ┌──────────────────┐
│     users       │◄───────-┤   user_contacts  │
│                 │         │  (junction table)│
│ - id (PK)       │         └──────────────────┘
│ - email (UK)    │                  │
│ - phone (UK)    │◄─────────────────┘
│ - name          │
│ - age           │         ┌──────────────────┐
│ - password_hash │         │   blocked_users  │
│ - created_at    │◄───────-┤                  │
│ - updated_at    │         │ - blocker_id (FK)│
│ - last_seen     │         │ - blocked_id (FK)│
│ - is_active     │         └──────────────────┘
└─────────────────┘
        │
        │ 1:N
        │
        ▼
┌─────────────────────────────────────────────┐
│              messages                       │
│                                             │
│ - id (PK, UUID)                             │
│ - sender_id (FK → users.id)                 │
│ - receiver_id (FK → users.id)               │
│ - content (TEXT, max 5000 chars)            │
│ - message_type (ENUM: text, image, pdf)     │
│ - status (ENUM: sent, delivered, read)      │
│ - created_at (timestamp)                    │
│ - delivered_at (timestamp, nullable)        │
│ - read_at (timestamp, nullable)             │
│ - expires_at (timestamp, nullable)          │
│ - deleted_by_sender (boolean)               │
│ - deleted_at (timestamp, nullable)          │
│ - is_expired (boolean)                      │
└─────────────────────────────────────────────┘
        │
        │ 1:1 
        │
        ▼
┌─────────────────────────────────────────────┐
│           message_attachments               │
│                                             │
│ - id (PK)                                   │
│ - message_id (FK → messages.id, UNIQUE)     │
│ - file_type (ENUM: pdf, image)              │
│ - file_name (VARCHAR)                       │
│ - file_size (BIGINT, bytes)                 │
│ - file_url (TEXT, S3/storage URL)           │
│ - mime_type (VARCHAR)                       │
│ - uploaded_at (timestamp)                   │
│ - is_deleted (boolean)                      │
└─────────────────────────────────────────────┘


┌─────────────────────────────────────────────┐
│           conversations                     │
│        (denormalized for performance)       │
│                                             │
│ - id (PK)                                   │
│ - user1_id (FK → users.id)                  │
│ - user2_id (FK → users.id)                  │
│ - last_message_id (FK → messages.id)        │
│ - last_message_at (timestamp)               │
│ - user1_unread_count (integer)              │
│ - user2_unread_count (integer)              │
│ - created_at (timestamp)                    │
│ - updated_at (timestamp)                    │
│                                             │
│ CONSTRAINT: user1_id < user2_id             │
│            (to prevent duplicates)          │
└─────────────────────────────────────────────┘
```
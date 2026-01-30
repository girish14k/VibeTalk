# Vibe Chat Application - Database Design

This is  database schema design for a secure, privacy-focused messaging application where messages automatically disappear after being read.

---

## 📋 Project Overview

This project contains the complete database architecture for an messaging platform, similar to apps like Snapchat or Signal's disappearing messages feature. The database is designed to handle:

- **Automatic message expiration** (5 minutes after reading)
- **Sender message deletion** (within 1-minute window)
- **File attachments** (images and PDFs)
- **Contact-based messaging** (only message saved contacts)
- **User blocking** and privacy controls
- **Message reporting** for content moderation

**Project Details:**
- **Developer:** Girish Chandra K
- **Date:** March 2024
- **Purpose:** Academic Curriculum Project
- **Database:** PostgreSQL 14+
- **Type:** Backend Database Design

---

## 🎯 Features

### Core Functionality
✅ User registration and authentication with OTP verification  
✅ Contact-based messaging (users can only message their contacts)  
✅ Message lifecycle management (sent → delivered → read → expired)  
✅ Automatic expiration 5 minutes after reading  
✅ Sender can delete messages within 1 minute of sending  
✅ Support for text messages (max 5000 characters with emoji support)  
✅ File attachments (PDF up to 10MB, Images up to 5MB)  
✅ User blocking and unblocking  
✅ Message reporting system  
✅ Conversation management with unread counts  

### Technical Features
✅ Trigger-based automation for message expiration  
✅ Denormalized conversation table for performance  
✅ Comprehensive indexing strategy  
✅ Database views for common queries  
✅ Background job support for cleanup  
✅ Strong data integrity with constraints  
✅ Scalable architecture (supports millions of users)  

---

## 🗄️ Database Schema

### Tables (7 Core Tables)

1. **users** - User account information
2. **user_contacts** - Many-to-many contact relationships
3. **blocked_users** - User blocking relationships
4. **messages** - All chat messages with expiration tracking
5. **message_attachments** - File metadata (images, PDFs)
6. **conversations** - Denormalized conversation data for performance
7. **message_reports** - User-reported content

### Views (4 Views)

1. **active_conversations_view** - Conversation list with user details
2. **message_details_view** - Complete message information
3. **user_contacts_view** - Contacts with blocking status

### Triggers (6 Automated Triggers)

1. Auto-update timestamps
2. Set message expiration on read
3. Update conversation on new message
4. Reset unread count on read
5. Prevent deletion after 1 minute
6. Maintain conversation state

---

## 🚀 Quick Start

### Prerequisites

- PostgreSQL 14 or higher
- pgAdmin or psql command-line tool
- Basic knowledge of SQL

### Installation

1. **Create Database**
   ```sql
   CREATE DATABASE ephemeral_chat;
   ```

2. **Run Schema Script**
   ```bash
   psql -U postgres -d ephemeral_chat -f schema.sql
   ```

3. **Load Sample Data (Optional)**
   ```bash
   psql -U postgres -d ephemeral_chat -f sample_queries_executable.sql
   ```

4. **Verify Installation**
   ```sql
   -- Check tables
   \dt
   
   -- Check views
   \dv
   
   -- Verify sample data
   SELECT COUNT(*) FROM users;
   ```

---

## 💡 Usage Examples

### Send a Message
```sql
INSERT INTO messages (sender_id, receiver_id, content, message_type)
VALUES (1, 2, 'Hello! How are you? 👋', 'text');
```

### Get Conversation List
```sql
SELECT * FROM active_conversations_view 
WHERE user1_id = 1 OR user2_id = 1
ORDER BY last_message_at DESC;
```

### Mark Message as Read (Triggers Expiration)
```sql
UPDATE messages 
SET status = 'read'
WHERE id = 'message-uuid' AND receiver_id = 2;
-- Automatically sets expires_at = read_at + 5 minutes
```

### Check Messages in Conversation
```sql
SELECT * FROM messages 
WHERE (sender_id = 1 AND receiver_id = 2) 
   OR (sender_id = 2 AND receiver_id = 1)
  AND is_expired = FALSE
ORDER BY created_at DESC
LIMIT 50;
```

---

## 🏗️ Architecture Highlights

### Message Lifecycle Flow

```
1. SEND
   ├─> Insert message (status: 'sent')
   └─> Trigger: Update conversation & increment unread count

2. DELIVER
   └─> Update status to 'delivered'

3. READ
   ├─> Update status to 'read'
   ├─> Trigger: Set expires_at = NOW() + 5 minutes
   └─> Trigger: Decrement unread count

4. EXPIRE
   └─> Background job: Set is_expired = TRUE

5. CLEANUP
   └─> Background job: Delete after 7 days
```

### Key Design Decisions

- **UUID for Messages**: Enables distributed systems and prevents ID enumeration
- **Denormalized Conversations**: Optimizes conversation list queries (most frequent operation)
- **Trigger-Based Expiration**: Ensures consistency regardless of API client
- **Soft Delete**: 7-day grace period for abuse investigation
- **Extensive Indexing**: Optimizes common query patterns

---


## 🚧 Out of Scope

The following features are explicitly **not** included in this database design:

❌ Group chats (only one-on-one messaging)  
❌ Video file attachments  
❌ Message editing  
❌ Message forwarding  
❌ Database backup strategies  
❌ Voice messages  
❌ Read receipts toggle (always on)  

These can be added as future enhancements.

---

## 🔮 Future Enhancements

Potential improvements for version 2.0:

- [ ] Group chat support
- [ ] Voice message attachments
- [ ] Message reactions (emoji reactions)
- [ ] Custom expiration timers (user-configurable)
- [ ] End-to-end encryption
- [ ] Message search with Elasticsearch
- [ ] Analytics dashboard
- [ ] Push notification integration
- [ ] Typing indicators
- [ ] Message translation
- [ ] Screenshot detection

---

## 📝 Assumptions & Constraints

### Key Assumptions

1. **Expiration Timer**: Starts when message is marked as 'read', not when sent
2. **Unread Messages**: Do not expire (only expire after being read)
3. **Contact System**: Users can only message contacts in their device contact list who are also registered
4. **File Storage**: Files stored in external object storage (S3), database stores metadata only
5. **OTP Verification**: Handled at API layer, not stored in main database

### Technical Constraints

- Maximum message length: 5,000 characters
- Maximum PDF size: 10 MB
- Maximum image size: 5 MB
- Supported image formats: JPEG, PNG, GIF, WebP
- Message deletion window: 1 minute after sending
- Message expiration: 5 minutes after reading
- Minimum user age: 13 years

---

## 🛠️ Technology Stack

- **Database**: PostgreSQL 14+
- **Extensions**: uuid-ossp, pgcrypto
- **Language**: SQL (DDL, DML, PL/pgSQL)
- **Tools**: psql, pgAdmin (recommended)

### Recommended API Stack (Not Included)
- **Backend**: Node.js/Express, Python/FastAPI, or Go
- **File Storage**: AWS S3, Google Cloud Storage, or Azure Blob
- **Caching**: Redis
- **Real-time**: WebSockets (Socket.io)

---

## 🐛 Known Limitations

1. **No built-in encryption**: Implement application-layer encryption for sensitive content
2. **Single database design**: Requires additional work for multi-region deployment
3. **No real-time features**: WebSocket layer needed for instant messaging
4. **Background jobs external**: Requires separate scheduler (cron, job queue)
5. **Limited search**: Full-text search requires additional indexing

---
---

## 👤 Author

**Girish Chandra K**  
**Project Date:** March 2024  
**Course:** [Database Management Systems]
---
---

## 🙏 Acknowledgments

- PostgreSQL documentation and community
- Database design patterns from industry best practices
- Inspiration from messaging platforms like WhatsApp, Signal, and Snapchat
- Academic mentors and instructors

---

## 📚 References

- PostgreSQL Official Documentation: https://www.postgresql.org/docs/
- Database Design Best Practices
- Messaging System Architecture Patterns
- Privacy-First Application Design

---

**Last Updated:** March 2024  
**Version:** 1.0  
**Status:** Complete ✅

---


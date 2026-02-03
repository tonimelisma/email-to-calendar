---
name: email-to-calendar
version: 1.9.1
description: Extract calendar events from emails and create calendar entries. Supports two modes: (1) Direct inbox monitoring - scans all emails for events, or (2) Forwarded emails - processes emails you forward to a dedicated address. Features smart onboarding, event tracking, pending invite reminders, undo support, and silent activity logging.
---

> **CRITICAL RULES - READ BEFORE PROCESSING ANY EMAIL**
>
> 1. **ALWAYS ASK BEFORE CREATING** - Never create calendar events without explicit user confirmation in the current conversation
> 2. **CHECK IF ALREADY PROCESSED** - Before processing any email, check `processed_emails` in index.json
> 3. **READ CONFIG FIRST** - Load and apply `ignore_patterns` and `auto_create_patterns` before presenting events
> 4. **READ MEMORY.MD** - Check for user preferences stored from previous sessions
> 5. **INCLUDE ALL CONFIGURED ATTENDEES** - When creating/updating/deleting events, always include attendees from config with `--attendees` flag (and `--send-updates all` if supported)
> 6. **CHECK TRACKED EVENTS FIRST** - Use `lookup_event.sh --email-id` to find existing events before calendar search (faster, more reliable)
> 7. **TRACK ALL CREATED EVENTS** - The `create_event.sh` script automatically tracks events; use tracked IDs for updates/deletions
> 8. **SHOW DAY-OF-WEEK** - Always include the day of week when presenting events for user verification

> **Tool Flexibility:** This skill is designed for Gmail and Google Calendar.
> The `gog` CLI commands shown below are reference examples. If your agent
> has alternative tools for email/calendar access (MCP servers, other CLIs),
> use those instead - the workflow and logic remain the same.

# Email to Calendar Skill

Extract calendar events and action items from emails, present them for review, and create/update calendar events with duplicate detection and undo support.

**First-time setup:** See [SETUP.md](SETUP.md) for configuration options and smart onboarding.

## Reading Email Content

**IMPORTANT:** Before you can extract events, you must read the email body.

```bash
# Read config for Gmail account
CONFIG_FILE="$HOME/.config/email-to-calendar/config.json"
GMAIL_ACCOUNT=$(jq -r '.gmail_account' "$CONFIG_FILE")

# Get a single email by ID (PREFERRED)
gog gmail get <messageId> --account "$GMAIL_ACCOUNT"

# Search with body content included
gog gmail messages search "in:inbox is:unread" --max 20 --include-body --account "$GMAIL_ACCOUNT"
```

**Note on stale forwards:** Don't use `newer_than:1d` because it checks the email's original date header, not when it was received. Process all UNREAD emails and rely on the "already processed" check.

## Workflow

### 0. Pre-Processing Checks (MANDATORY)

```bash
SCRIPTS_DIR="$HOME/.openclaw/workspace/skills/email-to-calendar/scripts"
CONFIG_FILE="$HOME/.config/email-to-calendar/config.json"
INDEX_FILE="$HOME/.openclaw/workspace/memory/email-extractions/index.json"

# Start activity logging
"$SCRIPTS_DIR/activity_log.sh" start-session

# Check email mode
EMAIL_MODE=$(jq -r '.email_mode // "forwarded"' "$CONFIG_FILE")

# Check if email was already processed
EMAIL_ID="<the email message ID>"
if jq -e ".extractions[] | select(.email_id == \"$EMAIL_ID\")" "$INDEX_FILE" > /dev/null 2>&1; then
    "$SCRIPTS_DIR/activity_log.sh" log-skip --email-id "$EMAIL_ID" --subject "Subject" --reason "Already processed"
    exit 0
fi

# Load ignore/auto-create patterns
IGNORE_PATTERNS=$(jq -r '.event_rules.ignore_patterns[]' "$CONFIG_FILE")
AUTO_CREATE_PATTERNS=$(jq -r '.event_rules.auto_create_patterns[]' "$CONFIG_FILE")
```

### 1. Find Emails to Process

**DIRECT mode:** Scan all unread emails for event indicators (dates, times, meeting keywords).

**FORWARDED mode:** Only process emails with forwarded indicators (Fwd:, forwarded message headers).

### 2. Extract Events (Agent does this directly)

Read the email and extract events as structured data. Include for each event:
- **title**: Descriptive name (max 80 chars)
- **date**: Event date(s)
- **day_of_week**: For verification
- **time**: Start/end times (default: 9 AM - 5 PM)
- **is_multi_day**: Whether it spans multiple days
- **is_recurring**: Whether it repeats (and pattern)
- **confidence**: high/medium/low

### 3. Present Items to User and WAIT

Apply event rules, then present with numbered selection:

```
I found the following potential events:

1. ~~ELAC Meeting (Feb 2, Monday at 8:15 AM)~~ - SKIP (matches ignore pattern)
2. **Team Offsite (Feb 2-6, Sun-Thu)** - PENDING
3. **Staff Development Day (Feb 12, Wednesday)** - AUTO-CREATE

Reply with numbers to create (e.g., '2, 3'), 'all', or 'none'.
```

**STOP AND WAIT for user response.**

After presenting, record pending invites:
```bash
# Record pending invites for follow-up reminders
# (See pending_invites.json structure in File Locations)
```

### 4. Check for Duplicates (MANDATORY)

**ALWAYS check before creating any event:**

```bash
# Step 1: Check local tracking first (fast)
TRACKED=$("$SCRIPTS_DIR/lookup_event.sh" --email-id "$EMAIL_ID")
if [ "$(echo "$TRACKED" | jq 'length')" -gt 0 ]; then
    EXISTING_EVENT_ID=$(echo "$TRACKED" | jq -r '.[0].event_id')
fi

# Step 2: If not found, try summary match
if [ -z "$EXISTING_EVENT_ID" ]; then
    TRACKED=$("$SCRIPTS_DIR/lookup_event.sh" --summary "$EVENT_TITLE")
fi

# Step 3: Fall back to calendar search
if [ -z "$EXISTING_EVENT_ID" ]; then
    gog calendar events "$CALENDAR_ID" --from "${EVENT_DATE}T00:00:00" --to "${EVENT_DATE}T23:59:59" --json
fi
```

Use LLM semantic matching for fuzzy duplicates (e.g., "Team Offsite" vs "Team Offsite 5-6pm").

### 5. Create or Update Calendar Events

**Use create_event.sh (recommended)** - handles date parsing, tracking, and changelog:

```bash
# Create new event
"$SCRIPTS_DIR/create_event.sh" \
    "$CALENDAR_ID" \
    "Event Title" \
    "February 11, 2026" \
    "9:00 AM" \
    "5:00 PM" \
    "Description" \
    "$ATTENDEE_EMAILS" \
    "" \
    "$EMAIL_ID"

# Update existing event (pass event_id as 8th parameter)
"$SCRIPTS_DIR/create_event.sh" \
    "$CALENDAR_ID" \
    "Updated Title" \
    "February 11, 2026" \
    "10:00 AM" \
    "6:00 PM" \
    "Updated description" \
    "$ATTENDEE_EMAILS" \
    "$EXISTING_EVENT_ID" \
    "$EMAIL_ID"
```

For direct gog commands and advanced options, see [references/gog-commands.md](references/gog-commands.md).

### 6. Update Status and Handle Email

```bash
# Update invite status
"$SCRIPTS_DIR/update_invite_status.sh" \
    --email-id "$EMAIL_ID" \
    --event-title "Event Title" \
    --status created

# Mark email as read (per config)
gog gmail modify "$EMAIL_ID" --remove-labels UNREAD --account "$GMAIL_ACCOUNT"

# End activity session
"$SCRIPTS_DIR/activity_log.sh" end-session
```

## Event Creation Rules

### Date/Time Handling
- **Single-day events**: Default 9:00 AM - 5:00 PM
- **Multi-day events** (e.g., Feb 2-6): Use `--rrule "RRULE:FREQ=DAILY;COUNT=N"`
- **Events with specific times**: Use exact time from email

### Duplicate Detection
Consider it a duplicate if:
- Same date AND similar title (semantic matching) AND overlapping time

Always update existing events rather than creating duplicates.

## Activity Log

```bash
# Start session
"$SCRIPTS_DIR/activity_log.sh" start-session

# Log skipped emails
"$SCRIPTS_DIR/activity_log.sh" log-skip --email-id "abc" --subject "Newsletter" --reason "No events"

# Log events
"$SCRIPTS_DIR/activity_log.sh" log-event --email-id "def" --title "Meeting" --action created

# End session
"$SCRIPTS_DIR/activity_log.sh" end-session

# Show recent activity
"$SCRIPTS_DIR/activity_log.sh" show --last 3
```

## Changelog and Undo

Changes can be undone within 24 hours:

```bash
# List recent changes
"$SCRIPTS_DIR/changelog.sh" list --last 10

# List undoable changes
"$SCRIPTS_DIR/undo.sh" list

# Undo most recent change
"$SCRIPTS_DIR/undo.sh" last

# Undo specific change
"$SCRIPTS_DIR/undo.sh" --change-id "chg_20260202_143000_001"
```

## Pending Invites

Events not immediately actioned are tracked for reminders:

```bash
# List pending invites (JSON)
"$SCRIPTS_DIR/list_pending.sh"

# Human-readable summary
"$SCRIPTS_DIR/list_pending.sh" --summary

# Update reminder tracking
"$SCRIPTS_DIR/list_pending.sh" --summary --update-reminded

# Auto-dismiss after 3 ignored reminders
"$SCRIPTS_DIR/list_pending.sh" --summary --auto-dismiss
```

## Event Tracking

```bash
# Look up by email ID
"$SCRIPTS_DIR/lookup_event.sh" --email-id "19c1c86dcc389443"

# Look up by summary
"$SCRIPTS_DIR/lookup_event.sh" --summary "Staff Development"

# List all tracked events
"$SCRIPTS_DIR/lookup_event.sh" --list

# Validate events exist (removes orphans)
"$SCRIPTS_DIR/lookup_event.sh" --email-id "abc" --validate
```

## File Locations

| File | Purpose |
|------|---------|
| `~/.config/email-to-calendar/config.json` | User configuration |
| `~/.openclaw/workspace/memory/email-extractions/` | Extracted data |
| `~/.openclaw/workspace/memory/email-extractions/index.json` | Processing index |
| `~/.openclaw/workspace/memory/email-to-calendar/events.json` | Event tracking |
| `~/.openclaw/workspace/memory/email-to-calendar/pending_invites.json` | Pending invites |
| `~/.openclaw/workspace/memory/email-to-calendar/activity.json` | Activity log |
| `~/.openclaw/workspace/memory/email-to-calendar/changelog.json` | Change history |
| `~/.openclaw/workspace/skills/email-to-calendar/scripts/` | Utility scripts |
| `~/.openclaw/workspace/skills/email-to-calendar/MEMORY.md` | User preferences |

## References

- **Setup Guide**: [SETUP.md](SETUP.md) - Configuration and onboarding
- **CLI Reference**: [references/gog-commands.md](references/gog-commands.md) - Detailed gog CLI usage
- **Extraction Patterns**: [references/extraction-patterns.md](references/extraction-patterns.md) - Date/time parsing
- **Workflow Example**: [references/workflow-example.md](references/workflow-example.md) - Complete example

## Notes

### Date Parsing
Handles common formats:
- January 15, 2026, Wednesday January 15
- 01/15/2026, 15/01/2026
- Date ranges like "Feb 2-6"

### Time Zones
All times assumed local timezone. Time zone info preserved in descriptions.

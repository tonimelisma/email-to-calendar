---
name: email-to-calendar
version: 1.4.0
description: Extract calendar events from emails and create calendar entries. Supports two modes: (1) Direct inbox monitoring - scans all emails for events, or (2) Forwarded emails - processes emails you forward to a dedicated address. Features event tracking for efficient updates and deletions.
---

> **⚠️ CRITICAL RULES — READ BEFORE PROCESSING ANY EMAIL**
>
> 1. **ALWAYS ASK BEFORE CREATING** — Never create calendar events without explicit user confirmation in the current conversation
> 2. **CHECK IF ALREADY PROCESSED** — Before processing any email, check `processed_emails` in index.json
> 3. **READ CONFIG FIRST** — Load and apply `ignore_patterns` and `auto_create_patterns` before presenting events
> 4. **READ MEMORY.MD** — Check for user preferences stored from previous sessions
> 5. **INCLUDE ALL CONFIGURED ATTENDEES** — When creating/updating/deleting events, always include attendees from config with `--attendees` flag (and `--send-updates all` if supported)
> 6. **CHECK TRACKED EVENTS FIRST** — Use `lookup_event.sh --email-id` to find existing events before calendar search (faster, more reliable)
> 7. **TRACK ALL CREATED EVENTS** — The `create_event.sh` script automatically tracks events; use tracked IDs for updates/deletions

# Email to Calendar Skill

Extract calendar events and action items from emails, present them for review, and create/update calendar events with duplicate detection.

## First-Run Setup

**Before first use, check if configuration exists:**

```bash
CONFIG_FILE="$HOME/.config/email-to-calendar/config.json"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Configuration not found. Setup required."
fi
```

**If no config exists, ask the user these questions:**

1. **Email Monitoring Mode:** "How should I find emails with events?"
   - Option A: **Direct access** — "I monitor your real inbox. I'll scan emails and find ones containing events."
   - Option B: **Forwarded emails** — "I have my own email address. You forward emails with events to me."

2. **Gmail Account:** "Which Gmail account should I monitor for emails?"

3. **Calendar ID:** "Which calendar should events be created in? (default: primary)"

4. **Attendees:** "Should I add attendees to events? If yes, which email addresses? (comma-separated)"

5. **Whole-day Event Style:**
   - "For whole-day events (like school holidays), how should I create them?"
   - Option A: Timed events (e.g., 9 AM - 5 PM)
   - Option B: All-day events (no specific time)

6. **Multi-day Event Style:**
   - "For multi-day events (e.g., Feb 2-6), how should I create them?"
   - Option A: Daily recurring events (one 9-5 event each day)
   - Option B: Single spanning event (one event across all days)

7. **Ignore Patterns (optional):** "Are there event types I should always ignore? (comma-separated, e.g., fundraiser, PTA meeting)"

8. **Auto-create Patterns (optional):** "Are there event types I should always create without asking? (comma-separated, e.g., No School, holiday)"

9. **Email Handling After Processing:** "After processing an email, what should I do with it?"
   - Option A: Mark as read only
   - Option B: Mark as read and archive
   - Option C: Leave as-is (don't modify the email)

**Then create the config file:**

```bash
mkdir -p "$HOME/.config/email-to-calendar"
cat > "$CONFIG_FILE" << EOF
{
  "email_mode": "<direct/forwarded>",
  "gmail_account": "<USER_GMAIL>",
  "calendar_id": "<CALENDAR_ID>",
  "attendees": {
    "enabled": <true/false>,
    "emails": [<ATTENDEE_EMAILS>]
  },
  "whole_day_events": {
    "style": "<timed/all_day>",
    "start_time": "09:00",
    "end_time": "17:00"
  },
  "multi_day_events": {
    "style": "<daily_recurring/all_day_span>"
  },
  "event_rules": {
    "ignore_patterns": [<IGNORE_PATTERNS>],
    "auto_create_patterns": [<AUTO_CREATE_PATTERNS>]
  },
  "email_handling": {
    "mark_read": <true/false>,
    "archive": <true/false>
  }
}
EOF
```

**Read configuration for use:**

```bash
CONFIG_FILE="$HOME/.config/email-to-calendar/config.json"
EMAIL_MODE=$(jq -r '.email_mode // "forwarded"' "$CONFIG_FILE")
GMAIL_ACCOUNT=$(jq -r '.gmail_account' "$CONFIG_FILE")
CALENDAR_ID=$(jq -r '.calendar_id' "$CONFIG_FILE")
ATTENDEES_ENABLED=$(jq -r '.attendees.enabled' "$CONFIG_FILE")
ATTENDEE_EMAILS=$(jq -r '.attendees.emails | join(",")' "$CONFIG_FILE")
```

## Reading Email Content

**IMPORTANT:** Before you can extract events, you must read the email body. Use these commands:

### Get a single email by ID (PREFERRED)
```bash
# Read config for Gmail account
CONFIG_FILE="$HOME/.config/email-to-calendar/config.json"
GMAIL_ACCOUNT=$(jq -r '.gmail_account' "$CONFIG_FILE")

gog gmail get <messageId> --account "$GMAIL_ACCOUNT"
```

### Search with body content included
```bash
gog gmail messages search "in:inbox newer_than:1d" --max 5 --include-body --account "$GMAIL_ACCOUNT"
```

### Common Mistakes to Avoid
- WRONG: `gog gmail messages get <id>` - This command does not exist!
- WRONG: Using Python's google-api-python-client - Not installed on this system
- CORRECT: `gog gmail get <id>` - Use this to read a single email

## Workflow

### 0. Pre-Processing Checks (MANDATORY)

Before processing ANY email, perform these checks:

#### Determine the email mode:
```bash
CONFIG_FILE="$HOME/.config/email-to-calendar/config.json"
EMAIL_MODE=$(jq -r '.email_mode // "forwarded"' "$CONFIG_FILE")
```

#### For DIRECT mode:
- Scan ALL unread emails (or last 24 hours)
- For each email, check if it contains event indicators (dates, times, meeting keywords)
- Only process emails that have event content
- Most emails will be skipped

#### For FORWARDED mode:
- Only look for emails with forwarded indicators (Fwd:, forwarded message headers)
- Process all forwarded emails
- Skip non-forwarded emails

#### Check if email was already processed:
```bash
INDEX_FILE="$HOME/.openclaw/workspace/memory/email-extractions/index.json"
EMAIL_ID="<the email message ID>"

# Check if this email ID was already processed
if jq -e ".extractions[] | select(.email_id == \"$EMAIL_ID\")" "$INDEX_FILE" > /dev/null 2>&1; then
    echo "EMAIL ALREADY PROCESSED - SKIP"
    # Do NOT process this email again
    exit 0
fi
```

#### Load user preferences:
```bash
# Read ignore patterns
IGNORE_PATTERNS=$(jq -r '.event_rules.ignore_patterns[]' "$CONFIG_FILE")

# Read auto-create patterns
AUTO_CREATE_PATTERNS=$(jq -r '.event_rules.auto_create_patterns[]' "$CONFIG_FILE")

# Read MEMORY.md for additional preferences
MEMORY_FILE="$HOME/.openclaw/workspace/skills/email-to-calendar/MEMORY.md"
if [ -f "$MEMORY_FILE" ]; then
    cat "$MEMORY_FILE"  # Read and apply preferences
fi
```

**If the email was already processed, STOP. Do not re-process.**

### 1. Find Emails to Process

#### DIRECT mode:
```bash
gog gmail messages search "in:inbox is:unread newer_than:1d" --max 20 --include-body --account "$GMAIL_ACCOUNT"
```

Check each email for event indicators:
- Date patterns (January 15, next Tuesday, Feb 2-6)
- Time patterns (2:30 PM, 14:00)
- Event keywords (meeting, appointment, deadline, holiday)
- .ics attachments

**Only proceed for emails with event content.**

#### FORWARDED mode:
```bash
gog gmail messages search "in:inbox is:unread subject:Fwd OR subject:FW" --max 10 --include-body --account "$GMAIL_ACCOUNT"
```

Also detect forwarded patterns in body:
- "---------- Forwarded message ----------"
- "Begin forwarded message:"

**Process all forwarded emails.**

### Direct Mode: Email Filtering

In direct mode, you'll see many emails. Use these heuristics:

**Strong indicators (likely has events):**
- Multiple date references
- Time patterns with dates
- Subject contains: meeting, invite, calendar, schedule
- .ics attachment
- From event sources (Eventbrite, Meetup, school newsletters)

**Skip these:**
- Marketing/promotional
- Receipts (unless delivery dates needed)
- Social notifications
- Spam/junk
- Already-read emails

### 2. Read the Full Email Body

First, get the email content using gog:

```bash
# Get email by ID
gog gmail get <messageId> --account "$GMAIL_ACCOUNT"

# Or search with body included
gog gmail messages search "subject:Fwd" --max 5 --include-body --account "$GMAIL_ACCOUNT"
```

### 3. Extract Events and Actions (Agent does this directly)

Read the email content and extract events as structured data. **Do NOT use any extraction script** - the Agent's natural language understanding is more accurate than regex patterns for unstructured email content (e.g., "we meet next Tuesday, not this one" is trivial for an LLM but impossible for regex).

For each potential event, identify:
- **title**: Descriptive event name (max 80 chars)
- **date**: The date(s) of the event
- **time**: Start/end times if specified (default: 9 AM - 5 PM)
- **is_multi_day**: Whether it spans multiple days
- **confidence**: high/medium/low based on context clarity

Also extract any action items with optional deadlines.

### 4. Store Extracted Items

Save the extracted items to a memory file for later review:

```bash
# Create dated extraction file
EXTRACTION_FILE="$HOME/.openclaw/workspace/memory/email-extractions/$(date +%Y-%m-%d-%H%M%S).json"
mkdir -p "$(dirname "$EXTRACTION_FILE")"
# Write the extracted events as JSON (Agent constructs this from Step 3)
```

Also update a master index file with the email_id to prevent reprocessing:

```bash
# Update index with new extraction
INDEX_FILE="$HOME/.openclaw/workspace/memory/email-extractions/index.json"
echo '{"extractions": []}' > "$INDEX_FILE" 2>/dev/null || true
python3 << 'EOF'
import json
import sys
import os
from datetime import datetime

index_file = os.path.expanduser("~/.openclaw/workspace/memory/email-extractions/index.json")
extraction_file = os.environ.get('EXTRACTION_FILE', '')
email_id = os.environ.get('EMAIL_ID', '')  # IMPORTANT: Include email ID
try:
    with open(index_file, 'r') as f:
        index = json.load(f)
except:
    index = {"extractions": []}

index['extractions'].append({
    'file': extraction_file,
    'email_id': email_id,  # Prevents reprocessing the same email
    'date': datetime.now().isoformat(),
    'status': 'pending_review'
})

with open(index_file, 'w') as f:
    json.dump(index, f, indent=2)
EOF
```

### 5. Present Items to User and WAIT for Response

**⚠️ THIS STEP IS MANDATORY — NEVER SKIP**

First, apply event rules from config:
```bash
# For each extracted event:
for event in events:
    # Check ignore patterns
    if event.title matches any IGNORE_PATTERNS:
        mark as "SKIP (ignored per config)"
        continue

    # Check auto-create patterns
    if event.title matches any AUTO_CREATE_PATTERNS:
        mark as "AUTO-CREATE (per config)"
        continue

    # Everything else needs user confirmation
    mark as "PENDING"
```

Present ALL items to the user with numbered selection:

**Example presentation:**
> I found the following potential events:
>
> 1. ~~ELAC Meeting (Feb 2 at 8:15 AM)~~ - SKIP (matches ignore pattern)
> 2. ~~WCEF Fundraiser (Feb 2-6)~~ - SKIP (matches ignore pattern)
> 3. **Team Offsite (Feb 2-6)** - PENDING
> 4. **Classroom Valentine's Day (Feb 11)** - AUTO-CREATE
> 5. **Staff Development Day - No School (Feb 12)** - AUTO-CREATE
> 6. **President's Day Weekend - No School (Feb 13-16)** - AUTO-CREATE
> 7. ~~PTA Meeting (Feb 19 at 7 PM)~~ - SKIP (matches ignore pattern)
> 8. **Copyright Notice (Jan 1, 2026)** - PENDING *(likely false positive)*
>
> Reply with the numbers you want to create (e.g., '3, 4, 5, 6'), 'all', or 'none'.
> *(Items marked SKIP are excluded. AUTO-CREATE items are pre-selected.)*

**⏸️ STOP AND WAIT for user response.**

User can respond with:
- Specific numbers: `3, 4, 5, 6` → Create only those items
- `all` → Create all non-skipped items (3-6, 8)
- `none` → Cancel, create nothing
- `4, 5, 6` → Create just the auto-create items (excluding 3 and 8)

This allows users to cherry-pick events without back-and-forth clarification.

### 6. Check for Duplicates (MANDATORY)

**⚠️ THIS IS A HARD REQUIREMENT — ALWAYS DO THIS BEFORE CREATING ANY EVENT**

For EACH event to be created, first check tracked events, then fall back to calendar search:

```bash
SCRIPTS_DIR="$HOME/.openclaw/workspace/skills/email-to-calendar/scripts"
EVENT_DATE="2026-02-11"
CALENDAR_ID=$(jq -r '.calendar_id' "$CONFIG_FILE")

# Step 1: Check local tracking first (fast, reliable)
TRACKED=$("$SCRIPTS_DIR/lookup_event.sh" --email-id "$EMAIL_ID")
if [ "$(echo "$TRACKED" | jq 'length')" -gt 0 ]; then
    EXISTING_EVENT_ID=$(echo "$TRACKED" | jq -r '.[0].event_id')
    echo "Found in tracking: $EXISTING_EVENT_ID"
fi

# Step 2: If not found by email_id, try summary match
if [ -z "$EXISTING_EVENT_ID" ]; then
    TRACKED=$("$SCRIPTS_DIR/lookup_event.sh" --summary "$EVENT_TITLE")
    # Filter to matching date
    EXISTING_EVENT_ID=$(echo "$TRACKED" | jq -r --arg date "$EVENT_DATE" \
        '[.[] | select(.start | startswith($date))] | .[0].event_id // empty')
fi

# Step 3: Fall back to calendar search if not tracked
if [ -z "$EXISTING_EVENT_ID" ]; then
    gog calendar events "$CALENDAR_ID" \
        --from "${EVENT_DATE}T00:00:00" \
        --to "${EVENT_DATE}T23:59:59" \
        --json
fi
```

**Decision logic:**
1. **Found in tracking by email_id** → Use tracked event_id for update
2. **Found in tracking by summary+date** → Use tracked event_id for update
3. **Found in calendar search (similar title)** → Update and add to tracking
4. **Not found anywhere** → Create new event (automatically tracked)

**Example duplicate detection:**
```bash
# Event to create: "Staff Development Day - No School" on Feb 12
# Email ID: 19c1c86dcc389443

# Check 1: tracking by email_id
TRACKED=$("$SCRIPTS_DIR/lookup_event.sh" --email-id "19c1c86dcc389443")
# Returns: [{"event_id": "abc123", ...}] → UPDATE abc123

# OR if not found, check 2: tracking by summary
TRACKED=$("$SCRIPTS_DIR/lookup_event.sh" --summary "Staff Development")
# Returns events with similar summaries → filter by date

# OR if not tracked, check 3: calendar search (legacy fallback)
```

**Always use update when duplicate found:**
```bash
gog calendar update "$CALENDAR_ID" "$EXISTING_EVENT_ID" \
    --summary "Updated Title" \
    --description "Updated description with new info" \
    --attendees "$ATTENDEE_EMAILS" \
    --send-updates all
```

### 7. Create or Update Calendar Events

**IMPORTANT: Always include configured attendees in ALL calendar operations.**

#### Using create_event.sh (Recommended)

The `create_event.sh` script handles date parsing, time formatting, and **automatic event tracking**:

```bash
SCRIPTS_DIR="$HOME/.openclaw/workspace/skills/email-to-calendar/scripts"

# Create new event (automatically tracked)
"$SCRIPTS_DIR/create_event.sh" \
    "$CALENDAR_ID" \
    "Event Title" \
    "February 11, 2026" \
    "9:00 AM" \
    "5:00 PM" \
    "Event description" \
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

The script:
- Parses various date formats (e.g., "February 11, 2026", "02/11/2026")
- Parses time formats (e.g., "9:00 AM", "14:30")
- Outputs the event ID on success
- Automatically calls `track_event.sh` to store the event in tracking

#### Direct gog commands (for advanced use)

```bash
# Read attendees from config
CONFIG_FILE="$HOME/.config/email-to-calendar/config.json"
ATTENDEES_ENABLED=$(jq -r '.attendees.enabled' "$CONFIG_FILE")
ATTENDEE_EMAILS=$(jq -r '.attendees.emails | join(",")' "$CONFIG_FILE")
CALENDAR_ID=$(jq -r '.calendar_id' "$CONFIG_FILE")

# For EVERY calendar create/update/delete, include attendees:
gog calendar create "$CALENDAR_ID" \
    --summary "Event Title" \
    --from "2026-02-11T09:00:00" \
    --to "2026-02-11T17:00:00" \
    --description "Event description" \
    --attendees "$ATTENDEE_EMAILS" \
    --send-updates all
```

**Note:** When using direct gog commands, remember to manually track the event using `track_event.sh`.

**Never create an event without the `--attendees` and `--send-updates all` flags if attendees are configured.**

#### Creating Single-Day Events

All single-day events should be **9:00 AM to 5:00 PM** (09:00-17:00) by default:

```bash
gog calendar create "$CALENDAR_ID" \
    --summary "Event Title" \
    --from "2026-02-11T09:00:00" \
    --to "2026-02-11T17:00:00" \
    --description "Event description" \
    --attendees "$ATTENDEE_EMAILS" \
    --send-updates all
```

#### Creating Multi-Day Events (e.g., Feb 2-6)

For events spanning multiple days, create a **9:00-17:00 event on the FIRST day** with a recurrence rule for the number of days:

```bash
# Example: Feb 2-6 = 5 days
gog calendar create "$CALENDAR_ID" \
    --summary "Multi-Day Event" \
    --from "2026-02-02T09:00:00" \
    --to "2026-02-02T17:00:00" \
    --description "Event description" \
    --attendees "$ATTENDEE_EMAILS" \
    --send-updates all \
    --rrule "RRULE:FREQ=DAILY;COUNT=5"
```

#### Recurrence Patterns (--rrule flag)

Uses standard RFC 5545 RRULE syntax:

| Pattern | RRULE |
|---------|-------|
| Daily for N days | `RRULE:FREQ=DAILY;COUNT=N` |
| Daily (forever) | `RRULE:FREQ=DAILY` |
| Weekly | `RRULE:FREQ=WEEKLY` |
| Every weekday | `RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR` |
| Monthly on specific day | `RRULE:FREQ=MONTHLY;BYMONTHDAY=19` |
| Yearly | `RRULE:FREQ=YEARLY` |
| Until a date | `RRULE:FREQ=WEEKLY;UNTIL=20261231T235959Z` |

#### Example: Monthly Meeting with Reminders

```bash
gog calendar create "$CALENDAR_ID" \
    --summary "Monthly Meeting" \
    --from "2026-02-19T19:00:00" \
    --to "2026-02-19T20:00:00" \
    --rrule "RRULE:FREQ=MONTHLY;BYMONTHDAY=19" \
    --reminder "email:1d" \
    --reminder "popup:30m" \
    --attendees "$ATTENDEE_EMAILS" \
    --send-updates all
```

#### Key Flags for Calendar Events

| Flag | Description |
|------|-------------|
| `--attendees` | Comma-separated emails |
| `--send-updates` | `all`, `externalOnly`, or `none` (see note below) |
| `--rrule` | Recurrence rule (RFC 5545 format) |
| `--reminder` | Add reminder (e.g., `email:1d`, `popup:30m`) |
| `--guests-can-invite` | Allow guests to invite others |
| `--guests-can-modify` | Allow guests to modify event |
| `--guests-can-see-others` | Allow guests to see other attendees |

> **Note on `--send-updates`:** This flag is only available in tonimelisma's gogcli fork. The `create_event.sh` script auto-detects support and uses it when available. Without this flag, attendees won't receive email notifications for event changes. To enable, install gogcli from: https://github.com/tonimelisma/gogcli (feat/calendar-send-updates branch)

#### Advanced Attendee Syntax

Mark attendees as optional or add comments:
```bash
--attendees "alice@example.com,bob@example.com;optional,carol@example.com;comment=FYI only"
```

#### Updating Existing Events

```bash
# Replace all attendees
gog calendar update "$CALENDAR_ID" <eventId> --attendees "new@example.com"

# Add attendees while preserving existing ones
gog calendar update "$CALENDAR_ID" <eventId> --add-attendee "additional@example.com"

# Update event details
gog calendar update "$CALENDAR_ID" <eventId> \
    --summary "Updated Title" \
    --from "2026-01-15T09:00:00" \
    --to "2026-01-15T17:00:00"

# Clear recurrence
gog calendar update "$CALENDAR_ID" <eventId> --rrule " "
```

### 8. Handle Cancellations

If the email indicates an event is cancelled:
- Search for the event using the duplicate check
- If found, use `gog calendar delete` or update with "CANCELLED" in title

```bash
# Delete/cancel event
gog calendar delete "$CALENDAR_ID" "$EVENT_ID"
```

### 9. Handle Processed Email

After successfully creating/updating calendar events, handle the source email based on config:

```bash
CONFIG_FILE="$HOME/.config/email-to-calendar/config.json"
MARK_READ=$(jq -r '.email_handling.mark_read // true' "$CONFIG_FILE")
ARCHIVE=$(jq -r '.email_handling.archive // false' "$CONFIG_FILE")
GMAIL_ACCOUNT=$(jq -r '.gmail_account' "$CONFIG_FILE")

# Mark email as read
if [ "$MARK_READ" = "true" ]; then
    gog gmail modify "$EMAIL_ID" --remove-labels UNREAD --account "$GMAIL_ACCOUNT"
fi

# Archive email (remove from inbox)
if [ "$ARCHIVE" = "true" ]; then
    gog gmail modify "$EMAIL_ID" --remove-labels INBOX --account "$GMAIL_ACCOUNT"
fi
```

**Also update the extraction index to record the email was processed:**
```bash
# Update index.json with email_id and status
jq ".extractions |= map(if .file == \"$EXTRACTION_FILE\" then .email_id = \"$EMAIL_ID\" | .status = \"processed\" else . end)" "$INDEX_FILE" > tmp.json && mv tmp.json "$INDEX_FILE"
```

## Event Creation Rules

### Date/Time Handling

- **Single-day events**: Default 9:00 AM to 5:00 PM (09:00-17:00), configurable
- **Multi-day events** (e.g., Feb 2-6): Create 9:00-17:00 on FIRST day with `--rrule "RRULE:FREQ=DAILY;COUNT=N"` where N = number of days
- **Events with specific times**: Use the exact time from the email
- **No School days / Holidays**: Create as 9:00-17:00 single-day or multi-day as appropriate

### Event Details
- **Subject/Title**: Create descriptive, concise titles (max 80 chars)
- **Description**: Include:
  - Full context from the email
  - Any action items or preparation needed
  - Original sender information
  - Links or attachments mentioned

### Duplicate Detection
Consider it a duplicate if:
- Same date AND
- Similar title (2+ keywords match) AND
- Overlapping time (within 1 hour)

Always update existing events rather than creating duplicates.

### Attendees (if configured)
If `attendees.enabled` is true in config, add configured attendees using:
```bash
--attendees "$ATTENDEE_EMAILS" --send-updates all
```

## Review Pending Items

When the user asks to review previously extracted items:

```bash
# List pending extractions
python3 << 'EOF'
import json
import glob
import os

index_file = os.path.expanduser("~/.openclaw/workspace/memory/email-extractions/index.json")
try:
    with open(index_file, 'r') as f:
        index = json.load(f)
    pending = [e for e in index.get('extractions', []) if e.get('status') == 'pending_review']
    for p in pending:
        print(f"Extraction: {p['file']} ({p['date']})")
        try:
            with open(p['file'], 'r') as ef:
                data = json.load(ef)
                print(f"  Events: {len(data.get('events', []))}")
                print(f"  Actions: {len(data.get('actions', []))}")
        except:
            print("  (could not read)")
except Exception as e:
    print(f"No pending extractions: {e}")
EOF
```

Present the items and ask which to process.

## File Locations

- **Config**: `~/.config/email-to-calendar/config.json`
- **Extractions**: `~/.openclaw/workspace/memory/email-extractions/`
- **Index**: `~/.openclaw/workspace/memory/email-extractions/index.json`
- **Event Tracking**: `~/.openclaw/workspace/memory/email-to-calendar/events.json`
- **Scripts**: `~/.openclaw/workspace/skills/email-to-calendar/scripts/`
- **Memory**: `~/.openclaw/workspace/skills/email-to-calendar/MEMORY.md`

## Event Tracking System

Events created by this skill are automatically tracked in `events.json` for efficient updates and deletions without searching the calendar.

### Tracking File Structure

Located at `~/.openclaw/workspace/memory/email-to-calendar/events.json`:
```json
{
  "events": [
    {
      "event_id": "abc123xyz",
      "calendar_id": "primary",
      "email_id": "19c1c86dcc389443",
      "summary": "Staff Development Day",
      "start": "2026-02-12T09:00:00",
      "created_at": "2026-02-01T21:15:00",
      "updated_at": null
    }
  ]
}
```

### Tracking Scripts

#### Look up tracked events
```bash
# Find by email ID (best for duplicate detection)
./scripts/lookup_event.sh --email-id "19c1c86dcc389443"

# Find by event ID
./scripts/lookup_event.sh --event-id "abc123xyz"

# Find by summary (partial match)
./scripts/lookup_event.sh --summary "Staff Development"

# List all tracked events
./scripts/lookup_event.sh --list
```

#### Track a new event (called automatically by create_event.sh)
```bash
./scripts/track_event.sh \
    --event-id "abc123xyz" \
    --calendar-id "primary" \
    --email-id "19c1c86dcc389443" \
    --summary "Staff Development Day" \
    --start "2026-02-12T09:00:00"
```

#### Update tracked event metadata
```bash
./scripts/update_tracked_event.sh --event-id "abc123xyz" --summary "New Title"
```

#### Delete from tracking (after calendar deletion)
```bash
./scripts/delete_tracked_event.sh --event-id "abc123xyz"
```

### Using Tracking for Duplicate Detection

**IMPORTANT:** Always check tracked events BEFORE searching the calendar:

```bash
# Step 1: Check local tracking first (fast)
TRACKED=$(./scripts/lookup_event.sh --email-id "$EMAIL_ID")
if [ "$(echo "$TRACKED" | jq 'length')" -gt 0 ]; then
    EXISTING_EVENT_ID=$(echo "$TRACKED" | jq -r '.[0].event_id')
    echo "Found tracked event: $EXISTING_EVENT_ID"
    # Use this ID for updates
fi

# Step 2: Only search calendar if not found in tracking (fallback)
if [ -z "$EXISTING_EVENT_ID" ]; then
    gog calendar events "$CALENDAR_ID" --from "$DATE" --to "$DATE" --json
fi
```

### Workflow for Updates

When an email contains updates to a previously created event:

```bash
# 1. Look up by email_id
TRACKED=$(./scripts/lookup_event.sh --email-id "$EMAIL_ID")
EVENT_ID=$(echo "$TRACKED" | jq -r '.[0].event_id // empty')

if [ -n "$EVENT_ID" ]; then
    # 2. Update the calendar event using tracked ID
    gog calendar update "$CALENDAR_ID" "$EVENT_ID" \
        --summary "Updated Title" \
        --description "Updated details"

    # 3. Update tracking metadata
    ./scripts/update_tracked_event.sh --event-id "$EVENT_ID" --summary "Updated Title"
fi
```

### Workflow for Deletions

When an email indicates an event is cancelled:

```bash
# 1. Look up by email_id or summary
TRACKED=$(./scripts/lookup_event.sh --email-id "$EMAIL_ID")
EVENT_ID=$(echo "$TRACKED" | jq -r '.[0].event_id // empty')
CALENDAR_ID=$(echo "$TRACKED" | jq -r '.[0].calendar_id // "primary"')

if [ -n "$EVENT_ID" ]; then
    # 2. Delete from calendar
    gog calendar delete "$CALENDAR_ID" "$EVENT_ID"

    # 3. Remove from tracking
    ./scripts/delete_tracked_event.sh --event-id "$EVENT_ID"
fi
```

## Example Usage

**User forwards email with multi-day event:**
> Fwd: Weekly Update
> ...
> Feb 2-6: Team Offsite
> Feb 11: Valentine's Day Celebrations
> Feb 19: Monthly Meeting 7 PM

**Your response:**
1. Check if email was already processed (Step 0)
2. Read email body using `gog gmail get <messageId>`
3. Extract items:
   - Event: "Team Offsite" - Feb 2-6 (5 days)
   - Event: "Valentine's Day Celebrations" - Feb 11 (single day)
   - Event: "Monthly Meeting" - Feb 19 at 7 PM
4. **Present to user and WAIT for confirmation** (Step 5)
5. Check calendar for duplicates (Step 6)
6. Create events (Step 7)
7. Handle processed email (Step 9)

```bash
# Read config
CONFIG_FILE="$HOME/.config/email-to-calendar/config.json"
CALENDAR_ID=$(jq -r '.calendar_id' "$CONFIG_FILE")
ATTENDEE_EMAILS=$(jq -r '.attendees.emails | join(",")' "$CONFIG_FILE")

# Multi-day event (Feb 2-6 = 5 days)
gog calendar create "$CALENDAR_ID" \
    --summary "Team Offsite" \
    --from "2026-02-02T09:00:00" \
    --to "2026-02-02T17:00:00" \
    --rrule "RRULE:FREQ=DAILY;COUNT=5" \
    --attendees "$ATTENDEE_EMAILS" \
    --send-updates all

# Single-day event
gog calendar create "$CALENDAR_ID" \
    --summary "Valentine's Day Celebrations" \
    --from "2026-02-11T09:00:00" \
    --to "2026-02-11T17:00:00" \
    --attendees "$ATTENDEE_EMAILS" \
    --send-updates all

# Event with specific time
gog calendar create "$CALENDAR_ID" \
    --summary "Monthly Meeting" \
    --from "2026-02-19T19:00:00" \
    --to "2026-02-19T20:00:00" \
    --attendees "$ATTENDEE_EMAILS" \
    --send-updates all
```

## References

- **Extraction Patterns**: See [references/extraction-patterns.md](references/extraction-patterns.md) for detailed documentation on date/time parsing, event detection, and edge cases.
- **Workflow Example**: See [references/workflow-example.md](references/workflow-example.md) for a complete step-by-step example with sample email and outputs.
- **RRULE Syntax**: https://icalendar.org/iCalendar-RFC-5545/3-8-5-3-recurrence-rule.html

## Notes

### Date Parsing
The extraction script handles most common date formats including:
- January 15, 2026 (with year)
- Wednesday January 15 (without year, defaults to current year)
- 01/15/2026 and 15/01/2026 (numeric formats)
- Relative dates like "next Tuesday" (limited support)
- Date ranges like "Feb 2-6" (extract as multi-day event)

### Time Zones
All times are assumed to be in the local timezone. Time zone information in emails is preserved in descriptions but not used for conversion.

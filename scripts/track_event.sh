#!/bin/bash
# Track a created calendar event for future updates/deletions
# Usage: track_event.sh --event-id <id> --calendar-id <cal_id> --email-id <email_id> --summary <title> --start <datetime>
#
# This stores event metadata in events.json so we can:
# - Find existing events by email_id (for duplicate detection)
# - Update or delete events without searching the calendar
# - Track event history

EVENTS_FILE="$HOME/.openclaw/workspace/memory/email-to-calendar/events.json"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --event-id)
            EVENT_ID="$2"
            shift 2
            ;;
        --calendar-id)
            CALENDAR_ID="$2"
            shift 2
            ;;
        --email-id)
            EMAIL_ID="$2"
            shift 2
            ;;
        --summary)
            SUMMARY="$2"
            shift 2
            ;;
        --start)
            START="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

if [ -z "$EVENT_ID" ]; then
    echo "Error: --event-id is required" >&2
    exit 1
fi

# Ensure events file exists
if [ ! -f "$EVENTS_FILE" ]; then
    mkdir -p "$(dirname "$EVENTS_FILE")"
    echo '{"events": []}' > "$EVENTS_FILE"
fi

# Add event to tracking using jq
CREATED_AT=$(date -Iseconds)

python3 << EOF
import json
import os

events_file = "$EVENTS_FILE"
event_id = "$EVENT_ID"
calendar_id = "${CALENDAR_ID:-primary}"
email_id = "$EMAIL_ID"
summary = "$SUMMARY"
start = "$START"
created_at = "$CREATED_AT"

# Load existing events
try:
    with open(events_file, 'r') as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = {"events": []}

# Check if event already tracked (by event_id)
existing = next((e for e in data['events'] if e['event_id'] == event_id), None)
if existing:
    # Update existing entry
    existing['summary'] = summary
    existing['start'] = start
    existing['updated_at'] = created_at
    if email_id:
        existing['email_id'] = email_id
else:
    # Add new entry
    new_event = {
        "event_id": event_id,
        "calendar_id": calendar_id,
        "email_id": email_id if email_id else None,
        "summary": summary,
        "start": start,
        "created_at": created_at,
        "updated_at": None
    }
    data['events'].append(new_event)

# Save
with open(events_file, 'w') as f:
    json.dump(data, f, indent=2)

print(f"Tracked event: {event_id}")
EOF

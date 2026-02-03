#!/bin/bash
# Update the status of a pending invite event
#
# Usage: update_invite_status.sh --invite-id <id> --event-title <title> --status <status> [--event-id <cal_event_id>]
#        update_invite_status.sh --email-id <email_id> --event-title <title> --status <status> [--event-id <cal_event_id>]
#
# Status values: pending, created, dismissed, expired
#
# Examples:
#   update_invite_status.sh --invite-id inv_20260201_001 --event-title "Valentine's Day" --status created --event-id abc123
#   update_invite_status.sh --email-id 19c1c86dcc389443 --event-title "Staff Development" --status dismissed

PENDING_FILE="$HOME/.openclaw/workspace/memory/email-to-calendar/pending_invites.json"

INVITE_ID=""
EMAIL_ID=""
EVENT_TITLE=""
NEW_STATUS=""
CALENDAR_EVENT_ID=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --invite-id)
            INVITE_ID="$2"
            shift 2
            ;;
        --email-id)
            EMAIL_ID="$2"
            shift 2
            ;;
        --event-title)
            EVENT_TITLE="$2"
            shift 2
            ;;
        --status)
            NEW_STATUS="$2"
            shift 2
            ;;
        --event-id)
            CALENDAR_EVENT_ID="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

# Validate inputs
if [ -z "$EVENT_TITLE" ] || [ -z "$NEW_STATUS" ]; then
    echo "Error: --event-title and --status are required" >&2
    echo "Usage: update_invite_status.sh --invite-id <id> --event-title <title> --status <status>" >&2
    exit 1
fi

if [ -z "$INVITE_ID" ] && [ -z "$EMAIL_ID" ]; then
    echo "Error: Either --invite-id or --email-id is required" >&2
    exit 1
fi

# Validate status
case "$NEW_STATUS" in
    pending|created|dismissed|expired)
        ;;
    *)
        echo "Error: Invalid status. Must be: pending, created, dismissed, expired" >&2
        exit 1
        ;;
esac

# Check if file exists
if [ ! -f "$PENDING_FILE" ]; then
    echo "Error: No pending invites file found" >&2
    exit 1
fi

# Update the status
python3 << EOF
import json
import sys
from datetime import datetime

pending_file = "$PENDING_FILE"
invite_id = "$INVITE_ID"
email_id = "$EMAIL_ID"
event_title = "$EVENT_TITLE"
new_status = "$NEW_STATUS"
calendar_event_id = "$CALENDAR_EVENT_ID"

try:
    with open(pending_file, 'r') as f:
        data = json.load(f)
except Exception as e:
    print(f"Error reading file: {e}", file=sys.stderr)
    sys.exit(1)

updated = False
for invite in data.get('invites', []):
    # Match by invite_id or email_id
    if invite_id and invite.get('id') != invite_id:
        continue
    if email_id and invite.get('email_id') != email_id:
        continue

    # Find and update the event
    for event in invite.get('events', []):
        # Match by exact title or partial match
        if event.get('title') == event_title or event_title.lower() in event.get('title', '').lower():
            event['status'] = new_status
            if calendar_event_id:
                event['event_id'] = calendar_event_id
            event['updated_at'] = datetime.now().isoformat()
            updated = True
            print(f"Updated '{event.get('title')}' to status: {new_status}")
            break

    if updated:
        break

if not updated:
    print(f"Warning: No matching event found for '{event_title}'", file=sys.stderr)
    sys.exit(1)

# Write back
try:
    with open(pending_file, 'w') as f:
        json.dump(data, f, indent=2)
except Exception as e:
    print(f"Error writing file: {e}", file=sys.stderr)
    sys.exit(1)
EOF

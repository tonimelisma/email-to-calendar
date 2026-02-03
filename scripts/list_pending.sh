#!/bin/bash
# List all pending invites that haven't been actioned
# Returns JSON array of pending events with their details
#
# Usage: list_pending.sh [options]
#   --summary           Output a human-readable summary instead of JSON
#   --update-reminded   Update last_reminded timestamp and increment reminder_count
#   --auto-dismiss      Auto-dismiss events that have been reminded 3+ times without response
#
# Features:
#   - Shows day-of-week for verification
#   - Tracks reminder_count and last_reminded
#   - Auto-dismisses after 3 ignored reminders
#   - Batched presentation format
#
# Logs to ~/.openclaw/workspace/memory/email-to-calendar/pending_invites.json

PENDING_FILE="$HOME/.openclaw/workspace/memory/email-to-calendar/pending_invites.json"
TODAY=$(date +%Y-%m-%d)
SUMMARY_MODE=false
UPDATE_REMINDED=false
AUTO_DISMISS=false
MAX_REMINDERS=3

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --summary)
            SUMMARY_MODE=true
            shift
            ;;
        --update-reminded)
            UPDATE_REMINDED=true
            shift
            ;;
        --auto-dismiss)
            AUTO_DISMISS=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# Check if file exists
if [ ! -f "$PENDING_FILE" ]; then
    if [ "$SUMMARY_MODE" = true ]; then
        echo "No pending invites found."
    else
        echo "[]"
    fi
    exit 0
fi

if [ "$SUMMARY_MODE" = true ]; then
    # Human-readable summary with day-of-week
    python3 << EOF
import json
import sys
from datetime import datetime, timedelta

today = "$TODAY"
update_reminded = "$UPDATE_REMINDED" == "true"
auto_dismiss = "$AUTO_DISMISS" == "true"
max_reminders = $MAX_REMINDERS
pending_file = "$PENDING_FILE"

def get_day_of_week(date_str):
    """Get day of week name from date string."""
    try:
        dt = datetime.strptime(date_str, '%Y-%m-%d')
        return dt.strftime('%A')
    except:
        return ""

try:
    with open(pending_file, 'r') as f:
        data = json.load(f)
except:
    print("No pending invites found.")
    sys.exit(0)

pending_events = []
auto_dismissed_count = 0
modified = False

for invite in data.get('invites', []):
    email_subject = invite.get('email_subject', 'Unknown source')
    email_id = invite.get('email_id', '')
    reminder_count = invite.get('reminder_count', 0)
    last_reminded = invite.get('last_reminded')

    # Check if this invite should be auto-dismissed (3+ reminders with no action)
    if auto_dismiss and reminder_count >= max_reminders:
        # Mark all pending events in this invite as auto_dismissed
        for event in invite.get('events', []):
            if event.get('status') == 'pending':
                event['status'] = 'auto_dismissed'
                event['auto_dismissed_at'] = datetime.now().isoformat()
                auto_dismissed_count += 1
                modified = True
        continue

    for event in invite.get('events', []):
        event_date = event.get('date', '')
        if event.get('status') == 'pending' and event_date >= today:
            day_of_week = get_day_of_week(event_date)
            pending_events.append({
                'title': event.get('title', 'Untitled'),
                'date': event_date,
                'day': day_of_week,
                'time': event.get('time', ''),
                'source': email_subject,
                'email_id': email_id,
                'reminder_count': reminder_count
            })

# Update reminder tracking if requested
if update_reminded and pending_events:
    now_iso = datetime.now().isoformat()
    seen_invites = set()
    for invite in data.get('invites', []):
        email_id = invite.get('email_id', '')
        if email_id in [e['email_id'] for e in pending_events] and email_id not in seen_invites:
            invite['last_reminded'] = now_iso
            invite['reminder_count'] = invite.get('reminder_count', 0) + 1
            seen_invites.add(email_id)
            modified = True

# Save if modified
if modified:
    with open(pending_file, 'w') as f:
        json.dump(data, f, indent=2)

if auto_dismissed_count > 0:
    print(f"({auto_dismissed_count} event(s) auto-dismissed after {max_reminders} ignored reminders)\n")

if not pending_events:
    print("No pending invites found.")
else:
    print(f"You have {len(pending_events)} pending calendar invite(s):\n")
    for i, evt in enumerate(pending_events, 1):
        time_str = f" at {evt['time']}" if evt['time'] else ""
        day_str = f" ({evt['day']})" if evt['day'] else ""
        reminder_marker = f" [reminded {evt['reminder_count']}x]" if evt['reminder_count'] > 0 else ""

        print(f"{i}. {evt['title']} - {evt['date']}{day_str}{time_str}{reminder_marker}")
        print(f"   From: {evt['source']}")

    print("\nReply with numbers to create (e.g., '1, 2'), 'all', or 'none' to dismiss.")
EOF
else
    # JSON output for programmatic use
    python3 << EOF
import json
import sys
from datetime import datetime

today = "$TODAY"
update_reminded = "$UPDATE_REMINDED" == "true"
auto_dismiss = "$AUTO_DISMISS" == "true"
max_reminders = $MAX_REMINDERS
pending_file = "$PENDING_FILE"

def get_day_of_week(date_str):
    """Get day of week name from date string."""
    try:
        dt = datetime.strptime(date_str, '%Y-%m-%d')
        return dt.strftime('%A')
    except:
        return ""

try:
    with open(pending_file, 'r') as f:
        data = json.load(f)
except:
    print("[]")
    sys.exit(0)

pending_events = []
modified = False

for invite in data.get('invites', []):
    invite_id = invite.get('id', '')
    email_subject = invite.get('email_subject', '')
    email_id = invite.get('email_id', '')
    reminder_count = invite.get('reminder_count', 0)
    last_reminded = invite.get('last_reminded')

    # Check if this invite should be auto-dismissed
    if auto_dismiss and reminder_count >= max_reminders:
        for event in invite.get('events', []):
            if event.get('status') == 'pending':
                event['status'] = 'auto_dismissed'
                event['auto_dismissed_at'] = datetime.now().isoformat()
                modified = True
        continue

    for event in invite.get('events', []):
        event_date = event.get('date', '')
        if event.get('status') == 'pending' and event_date >= today:
            pending_events.append({
                'invite_id': invite_id,
                'email_id': email_id,
                'email_subject': email_subject,
                'title': event.get('title', ''),
                'date': event_date,
                'day_of_week': get_day_of_week(event_date),
                'time': event.get('time', ''),
                'reminder_count': reminder_count,
                'last_reminded': last_reminded
            })

# Update reminder tracking if requested
if update_reminded and pending_events:
    now_iso = datetime.now().isoformat()
    seen_invites = set()
    for invite in data.get('invites', []):
        email_id = invite.get('email_id', '')
        if email_id in [e['email_id'] for e in pending_events] and email_id not in seen_invites:
            invite['last_reminded'] = now_iso
            invite['reminder_count'] = invite.get('reminder_count', 0) + 1
            seen_invites.add(email_id)
            modified = True

# Save if modified
if modified:
    with open(pending_file, 'w') as f:
        json.dump(data, f, indent=2)

print(json.dumps(pending_events, indent=2))
EOF
fi

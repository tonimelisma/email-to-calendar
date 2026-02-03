#!/bin/bash
# List all pending invites that haven't been actioned
# Returns JSON array of pending events with their details
#
# Usage: list_pending.sh [--summary]
#   --summary: Output a human-readable summary instead of JSON

PENDING_FILE="$HOME/.openclaw/workspace/memory/email-to-calendar/pending_invites.json"
TODAY=$(date +%Y-%m-%d)
SUMMARY_MODE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --summary)
            SUMMARY_MODE=true
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
    # Human-readable summary
    python3 << EOF
import json
import sys
from datetime import datetime

today = "$TODAY"

try:
    with open("$PENDING_FILE", 'r') as f:
        data = json.load(f)
except:
    print("No pending invites found.")
    sys.exit(0)

pending_events = []
for invite in data.get('invites', []):
    email_subject = invite.get('email_subject', 'Unknown source')
    for event in invite.get('events', []):
        if event.get('status') == 'pending' and event.get('date', '') >= today:
            pending_events.append({
                'title': event.get('title', 'Untitled'),
                'date': event.get('date', 'Unknown date'),
                'time': event.get('time', ''),
                'source': email_subject
            })

if not pending_events:
    print("No pending invites found.")
else:
    print(f"You have {len(pending_events)} pending calendar invite(s):\n")
    for i, evt in enumerate(pending_events, 1):
        time_str = f" at {evt['time']}" if evt['time'] else ""
        print(f"{i}. {evt['title']} - {evt['date']}{time_str}")
        print(f"   From: {evt['source']}")
    print("\nReply with numbers to create, 'all', or 'dismiss' to clear them.")
EOF
else
    # JSON output for programmatic use
    python3 << EOF
import json
import sys

today = "$TODAY"

try:
    with open("$PENDING_FILE", 'r') as f:
        data = json.load(f)
except:
    print("[]")
    sys.exit(0)

pending_events = []
for invite in data.get('invites', []):
    invite_id = invite.get('id', '')
    email_subject = invite.get('email_subject', '')
    email_id = invite.get('email_id', '')
    for event in invite.get('events', []):
        if event.get('status') == 'pending' and event.get('date', '') >= today:
            pending_events.append({
                'invite_id': invite_id,
                'email_id': email_id,
                'email_subject': email_subject,
                'title': event.get('title', ''),
                'date': event.get('date', ''),
                'time': event.get('time', '')
            })

print(json.dumps(pending_events, indent=2))
EOF
fi

#!/bin/bash
# Update a tracked event's metadata after a calendar update
# Usage: update_tracked_event.sh --event-id <id> [--summary <new_summary>] [--start <new_start>]
#
# Updates the tracked event's metadata to reflect calendar changes

EVENTS_FILE="$HOME/.openclaw/workspace/memory/email-to-calendar/events.json"

# Parse arguments
EVENT_ID=""
NEW_SUMMARY=""
NEW_START=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --event-id)
            EVENT_ID="$2"
            shift 2
            ;;
        --summary)
            NEW_SUMMARY="$2"
            shift 2
            ;;
        --start)
            NEW_START="$2"
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

if [ ! -f "$EVENTS_FILE" ]; then
    echo "Error: No events file found" >&2
    exit 1
fi

python3 << EOF
import json
import sys
from datetime import datetime

events_file = "$EVENTS_FILE"
event_id = "$EVENT_ID"
new_summary = "$NEW_SUMMARY"
new_start = "$NEW_START"

try:
    with open(events_file, 'r') as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    print("Error: Could not read events file", file=sys.stderr)
    sys.exit(1)

# Find and update the event
found = False
for event in data.get('events', []):
    if event.get('event_id') == event_id:
        if new_summary:
            event['summary'] = new_summary
        if new_start:
            event['start'] = new_start
        event['updated_at'] = datetime.now().isoformat()
        found = True
        break

if not found:
    print(f"Warning: Event {event_id} not found in tracking", file=sys.stderr)
    sys.exit(1)

# Save
with open(events_file, 'w') as f:
    json.dump(data, f, indent=2)

print(f"Updated tracked event: {event_id}")
EOF

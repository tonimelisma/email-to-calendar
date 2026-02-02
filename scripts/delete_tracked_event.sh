#!/bin/bash
# Delete a tracked event from the tracking file (after deleting from calendar)
# Usage: delete_tracked_event.sh --event-id <id>
#
# This removes the event from events.json tracking

EVENTS_FILE="$HOME/.openclaw/workspace/memory/email-to-calendar/events.json"

# Parse arguments
EVENT_ID=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --event-id)
            EVENT_ID="$2"
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
    echo "Warning: No events file found" >&2
    exit 0
fi

python3 << EOF
import json
import sys

events_file = "$EVENTS_FILE"
event_id = "$EVENT_ID"

try:
    with open(events_file, 'r') as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    print("Warning: Could not read events file", file=sys.stderr)
    sys.exit(0)

# Find and remove the event
original_count = len(data.get('events', []))
data['events'] = [e for e in data.get('events', []) if e.get('event_id') != event_id]
new_count = len(data['events'])

if original_count == new_count:
    print(f"Warning: Event {event_id} not found in tracking", file=sys.stderr)
else:
    # Save
    with open(events_file, 'w') as f:
        json.dump(data, f, indent=2)
    print(f"Deleted tracked event: {event_id}")
EOF

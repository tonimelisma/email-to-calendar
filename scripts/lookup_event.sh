#!/bin/bash
# Look up a tracked event by email_id, event_id, or summary
# Usage: lookup_event.sh --email-id <id> | --event-id <id> | --summary <text>
#
# Returns JSON with the event details if found, or empty if not

EVENTS_FILE="$HOME/.openclaw/workspace/memory/email-to-calendar/events.json"

# Parse arguments
SEARCH_TYPE=""
SEARCH_VALUE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --email-id)
            SEARCH_TYPE="email_id"
            SEARCH_VALUE="$2"
            shift 2
            ;;
        --event-id)
            SEARCH_TYPE="event_id"
            SEARCH_VALUE="$2"
            shift 2
            ;;
        --summary)
            SEARCH_TYPE="summary"
            SEARCH_VALUE="$2"
            shift 2
            ;;
        --list)
            SEARCH_TYPE="list"
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Usage: lookup_event.sh --email-id <id> | --event-id <id> | --summary <text> | --list" >&2
            exit 1
            ;;
    esac
done

if [ -z "$SEARCH_TYPE" ]; then
    echo "Error: Must specify --email-id, --event-id, --summary, or --list" >&2
    exit 1
fi

if [ ! -f "$EVENTS_FILE" ]; then
    echo "[]"
    exit 0
fi

python3 << EOF
import json
import sys

events_file = "$EVENTS_FILE"
search_type = "$SEARCH_TYPE"
search_value = "$SEARCH_VALUE"

try:
    with open(events_file, 'r') as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    print("[]")
    sys.exit(0)

events = data.get('events', [])

if search_type == "list":
    # Return all events
    print(json.dumps(events, indent=2))
elif search_type == "email_id":
    # Find by email_id (exact match)
    results = [e for e in events if e.get('email_id') == search_value]
    print(json.dumps(results, indent=2))
elif search_type == "event_id":
    # Find by event_id (exact match)
    results = [e for e in events if e.get('event_id') == search_value]
    print(json.dumps(results, indent=2))
elif search_type == "summary":
    # Find by summary (case-insensitive partial match)
    search_lower = search_value.lower()
    results = [e for e in events if search_lower in e.get('summary', '').lower()]
    print(json.dumps(results, indent=2))
else:
    print("[]")
EOF

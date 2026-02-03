#!/bin/bash
# Look up a tracked event by email_id, event_id, or summary
# Usage: lookup_event.sh --email-id <id> | --event-id <id> | --summary <text> | --list [--validate]
#
# Options:
#   --validate    Check if the calendar event still exists, remove orphaned entries
#
# Returns JSON with the event details if found, or empty array [] if not

SCRIPT_DIR="$(dirname "$0")"
EVENTS_FILE="$HOME/.openclaw/workspace/memory/email-to-calendar/events.json"

# Parse arguments
SEARCH_TYPE=""
SEARCH_VALUE=""
VALIDATE=false

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
        --validate)
            VALIDATE=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Usage: lookup_event.sh --email-id <id> | --event-id <id> | --summary <text> | --list [--validate]" >&2
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

# Function to validate an event still exists in the calendar
validate_event() {
    local event_id="$1"
    local calendar_id="$2"

    # Try to get the event from the calendar
    RESULT=$(gog calendar events "$calendar_id" --json 2>&1 | jq -r --arg id "$event_id" '.[] | select(.id == $id) | .id' 2>/dev/null)

    if [ -z "$RESULT" ]; then
        # Event not found, it's orphaned
        echo "Orphaned event detected: $event_id - removing from tracking" >&2
        "$SCRIPT_DIR/delete_tracked_event.sh" --event-id "$event_id" 2>/dev/null || true
        return 1
    fi
    return 0
}

python3 << EOF
import json
import sys
import subprocess
import os

events_file = "$EVENTS_FILE"
search_type = "$SEARCH_TYPE"
search_value = "$SEARCH_VALUE"
validate = "$VALIDATE" == "true"
script_dir = "$SCRIPT_DIR"

try:
    with open(events_file, 'r') as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    print("[]")
    sys.exit(0)

events = data.get('events', [])

if search_type == "list":
    results = events
elif search_type == "email_id":
    results = [e for e in events if e.get('email_id') == search_value]
elif search_type == "event_id":
    results = [e for e in events if e.get('event_id') == search_value]
elif search_type == "summary":
    search_lower = search_value.lower()
    results = [e for e in events if search_lower in e.get('summary', '').lower()]
else:
    results = []

# If validation requested, check each result and remove orphans
if validate and results:
    valid_results = []
    for event in results:
        event_id = event.get('event_id')
        calendar_id = event.get('calendar_id', 'primary')

        # Quick check via gog - see if event exists
        try:
            # Use a targeted date range search for efficiency
            start = event.get('start', '')
            if start:
                # Extract date from start time
                date_part = start.split('T')[0]
                cmd = f'gog calendar events "{calendar_id}" --from "{date_part}T00:00:00" --to "{date_part}T23:59:59" --json 2>/dev/null'
                result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
                if result.returncode == 0:
                    cal_events = json.loads(result.stdout) if result.stdout else []
                    found = any(e.get('id') == event_id for e in cal_events)
                    if found:
                        valid_results.append(event)
                    else:
                        # Event not found in calendar - orphaned
                        print(f"Orphaned event detected: {event_id} - removing from tracking", file=sys.stderr)
                        subprocess.run(
                            f'{script_dir}/delete_tracked_event.sh --event-id "{event_id}"',
                            shell=True, capture_output=True
                        )
                else:
                    # API call failed, keep the event (don't delete on error)
                    valid_results.append(event)
            else:
                # No start date, can't validate, keep it
                valid_results.append(event)
        except Exception as e:
            # On error, keep the event
            valid_results.append(event)

    results = valid_results

print(json.dumps(results, indent=2))
EOF

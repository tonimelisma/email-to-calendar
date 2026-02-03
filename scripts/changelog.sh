#!/bin/bash
# Record event changes for audit trail and undo support
# Usage: changelog.sh <action> [options]
#
# Actions:
#   log-create --event-id <id> --calendar-id <cal> --summary <s> --start <t> --end <t> [--email-id <id>]
#   log-update --event-id <id> --calendar-id <cal> --before-json <json> --after-json <json> [--email-id <id>]
#   log-delete --event-id <id> --calendar-id <cal> --before-json <json>
#   list [--last N]            List recent changes (default: 10)
#   get --change-id <id>       Get details of a specific change
#   can-undo --change-id <id>  Check if a change can still be undone
#
# Logs to ~/.openclaw/workspace/memory/email-to-calendar/changelog.json
# Changes older than 24 hours have can_undo=false

CHANGELOG_FILE="$HOME/.openclaw/workspace/memory/email-to-calendar/changelog.json"
UNDO_WINDOW_HOURS=24

# Ensure directory exists
mkdir -p "$(dirname "$CHANGELOG_FILE")"

# Parse action
ACTION="${1:-}"
shift 2>/dev/null || true

# Parse arguments
EVENT_ID=""
CALENDAR_ID=""
SUMMARY=""
START_TIME=""
END_TIME=""
EMAIL_ID=""
BEFORE_JSON=""
AFTER_JSON=""
CHANGE_ID=""
LAST_N=10

while [[ $# -gt 0 ]]; do
    case "$1" in
        --event-id)
            EVENT_ID="$2"
            shift 2
            ;;
        --calendar-id)
            CALENDAR_ID="$2"
            shift 2
            ;;
        --summary)
            SUMMARY="$2"
            shift 2
            ;;
        --start)
            START_TIME="$2"
            shift 2
            ;;
        --end)
            END_TIME="$2"
            shift 2
            ;;
        --email-id)
            EMAIL_ID="$2"
            shift 2
            ;;
        --before-json)
            BEFORE_JSON="$2"
            shift 2
            ;;
        --after-json)
            AFTER_JSON="$2"
            shift 2
            ;;
        --change-id)
            CHANGE_ID="$2"
            shift 2
            ;;
        --last)
            LAST_N="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

case "$ACTION" in
    log-create)
        if [ -z "$EVENT_ID" ] || [ -z "$SUMMARY" ]; then
            echo "Error: --event-id and --summary are required for log-create" >&2
            exit 1
        fi
        python3 << EOF
import json
import os
from datetime import datetime

changelog_file = os.path.expanduser("~/.openclaw/workspace/memory/email-to-calendar/changelog.json")
os.makedirs(os.path.dirname(changelog_file), exist_ok=True)

event_id = "$EVENT_ID"
calendar_id = "$CALENDAR_ID" or "primary"
summary = "$SUMMARY"
start_time = "$START_TIME"
end_time = "$END_TIME"
email_id = "$EMAIL_ID"

# Load existing changelog
try:
    with open(changelog_file, 'r') as f:
        changelog = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    changelog = {"changes": []}

# Generate change ID
now = datetime.now()
change_id = f"chg_{now.strftime('%Y%m%d_%H%M%S')}_{len(changelog['changes']) + 1:03d}"

change = {
    "id": change_id,
    "timestamp": now.isoformat(),
    "action": "create",
    "event_id": event_id,
    "calendar_id": calendar_id,
    "before": None,
    "after": {
        "summary": summary,
        "start": start_time,
        "end": end_time
    },
    "source_email_id": email_id if email_id else None,
    "can_undo": True
}

changelog['changes'].append(change)

# Keep only last 100 changes
changelog['changes'] = changelog['changes'][-100:]

with open(changelog_file, 'w') as f:
    json.dump(changelog, f, indent=2)

print(change_id)
EOF
        ;;

    log-update)
        if [ -z "$EVENT_ID" ]; then
            echo "Error: --event-id is required for log-update" >&2
            exit 1
        fi
        python3 << EOF
import json
import os
from datetime import datetime

changelog_file = os.path.expanduser("~/.openclaw/workspace/memory/email-to-calendar/changelog.json")
os.makedirs(os.path.dirname(changelog_file), exist_ok=True)

event_id = "$EVENT_ID"
calendar_id = "$CALENDAR_ID" or "primary"
before_json = '''$BEFORE_JSON'''
after_json = '''$AFTER_JSON'''
email_id = "$EMAIL_ID"

# Parse before/after JSON
try:
    before = json.loads(before_json) if before_json else None
except:
    before = None

try:
    after = json.loads(after_json) if after_json else None
except:
    after = None

# Load existing changelog
try:
    with open(changelog_file, 'r') as f:
        changelog = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    changelog = {"changes": []}

# Generate change ID
now = datetime.now()
change_id = f"chg_{now.strftime('%Y%m%d_%H%M%S')}_{len(changelog['changes']) + 1:03d}"

change = {
    "id": change_id,
    "timestamp": now.isoformat(),
    "action": "update",
    "event_id": event_id,
    "calendar_id": calendar_id,
    "before": before,
    "after": after,
    "source_email_id": email_id if email_id else None,
    "can_undo": True
}

changelog['changes'].append(change)

# Keep only last 100 changes
changelog['changes'] = changelog['changes'][-100:]

with open(changelog_file, 'w') as f:
    json.dump(changelog, f, indent=2)

print(change_id)
EOF
        ;;

    log-delete)
        if [ -z "$EVENT_ID" ]; then
            echo "Error: --event-id is required for log-delete" >&2
            exit 1
        fi
        python3 << EOF
import json
import os
from datetime import datetime

changelog_file = os.path.expanduser("~/.openclaw/workspace/memory/email-to-calendar/changelog.json")
os.makedirs(os.path.dirname(changelog_file), exist_ok=True)

event_id = "$EVENT_ID"
calendar_id = "$CALENDAR_ID" or "primary"
before_json = '''$BEFORE_JSON'''

# Parse before JSON
try:
    before = json.loads(before_json) if before_json else None
except:
    before = None

# Load existing changelog
try:
    with open(changelog_file, 'r') as f:
        changelog = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    changelog = {"changes": []}

# Generate change ID
now = datetime.now()
change_id = f"chg_{now.strftime('%Y%m%d_%H%M%S')}_{len(changelog['changes']) + 1:03d}"

change = {
    "id": change_id,
    "timestamp": now.isoformat(),
    "action": "delete",
    "event_id": event_id,
    "calendar_id": calendar_id,
    "before": before,
    "after": None,
    "source_email_id": None,
    "can_undo": True
}

changelog['changes'].append(change)

# Keep only last 100 changes
changelog['changes'] = changelog['changes'][-100:]

with open(changelog_file, 'w') as f:
    json.dump(changelog, f, indent=2)

print(change_id)
EOF
        ;;

    list)
        python3 << EOF
import json
import os
import sys
from datetime import datetime, timedelta

changelog_file = os.path.expanduser("~/.openclaw/workspace/memory/email-to-calendar/changelog.json")
last_n = int("$LAST_N")
undo_window = timedelta(hours=$UNDO_WINDOW_HOURS)

try:
    with open(changelog_file, 'r') as f:
        changelog = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    print("No changes recorded yet.")
    sys.exit(0)

changes = changelog.get('changes', [])
if not changes:
    print("No changes recorded yet.")
    sys.exit(0)

# Get last N changes (most recent first)
recent = list(reversed(changes[-last_n:]))
now = datetime.now()

print(f"Recent changes (last {len(recent)}):\n")

for change in recent:
    change_id = change.get('id', 'unknown')
    ts = change.get('timestamp', '')
    action = change.get('action', 'unknown')
    event_id = change.get('event_id', '')

    # Check if still within undo window
    try:
        change_time = datetime.fromisoformat(ts)
        can_undo = (now - change_time) < undo_window and change.get('can_undo', False)
    except:
        can_undo = False

    undo_marker = " [can undo]" if can_undo else ""

    # Format timestamp
    try:
        dt = datetime.fromisoformat(ts)
        ts_str = dt.strftime('%Y-%m-%d %H:%M')
    except:
        ts_str = ts

    # Get summary from before or after
    if action == 'create':
        summary = change.get('after', {}).get('summary', 'Unknown')
    elif action == 'update':
        summary = change.get('after', {}).get('summary') or change.get('before', {}).get('summary', 'Unknown')
    else:  # delete
        summary = change.get('before', {}).get('summary', 'Unknown')

    print(f"{change_id}: {action.upper()} \"{summary}\"{undo_marker}")
    print(f"  Time: {ts_str}")
    print(f"  Event ID: {event_id}")

    if action == 'update':
        before = change.get('before', {})
        after = change.get('after', {})
        changes_made = []
        if before.get('summary') != after.get('summary'):
            changes_made.append(f"title: \"{before.get('summary')}\" -> \"{after.get('summary')}\"")
        if before.get('start') != after.get('start'):
            changes_made.append(f"start: {before.get('start')} -> {after.get('start')}")
        if changes_made:
            print(f"  Changes: {'; '.join(changes_made)}")

    print()
EOF
        ;;

    get)
        if [ -z "$CHANGE_ID" ]; then
            echo "Error: --change-id is required for get" >&2
            exit 1
        fi
        python3 << EOF
import json
import os
import sys

changelog_file = os.path.expanduser("~/.openclaw/workspace/memory/email-to-calendar/changelog.json")
change_id = "$CHANGE_ID"

try:
    with open(changelog_file, 'r') as f:
        changelog = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    print("No changes recorded.", file=sys.stderr)
    sys.exit(1)

for change in changelog.get('changes', []):
    if change.get('id') == change_id:
        print(json.dumps(change, indent=2))
        sys.exit(0)

print(f"Change {change_id} not found", file=sys.stderr)
sys.exit(1)
EOF
        ;;

    can-undo)
        if [ -z "$CHANGE_ID" ]; then
            echo "Error: --change-id is required for can-undo" >&2
            exit 1
        fi
        python3 << EOF
import json
import os
import sys
from datetime import datetime, timedelta

changelog_file = os.path.expanduser("~/.openclaw/workspace/memory/email-to-calendar/changelog.json")
change_id = "$CHANGE_ID"
undo_window = timedelta(hours=$UNDO_WINDOW_HOURS)

try:
    with open(changelog_file, 'r') as f:
        changelog = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    print("false")
    sys.exit(1)

now = datetime.now()

for change in changelog.get('changes', []):
    if change.get('id') == change_id:
        if not change.get('can_undo', False):
            print("false")
            sys.exit(0)

        try:
            change_time = datetime.fromisoformat(change.get('timestamp', ''))
            if (now - change_time) < undo_window:
                print("true")
                sys.exit(0)
        except:
            pass

        print("false")
        sys.exit(0)

print("false")
sys.exit(1)
EOF
        ;;

    *)
        echo "Usage: changelog.sh <action> [options]"
        echo ""
        echo "Actions:"
        echo "  log-create --event-id <id> --calendar-id <cal> --summary <s> --start <t> --end <t>"
        echo "  log-update --event-id <id> --calendar-id <cal> --before-json <json> --after-json <json>"
        echo "  log-delete --event-id <id> --calendar-id <cal> --before-json <json>"
        echo "  list [--last N]            List recent changes (default: 10)"
        echo "  get --change-id <id>       Get details of a specific change"
        echo "  can-undo --change-id <id>  Check if a change can still be undone"
        exit 1
        ;;
esac

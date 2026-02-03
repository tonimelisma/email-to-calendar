#!/bin/bash
# Record activity for silent audit trail
# Usage: activity_log.sh <action> [options]
#
# Actions:
#   start-session              Start a new processing session
#   log-skip --email-id <id> --subject <sub> --reason <reason>
#   log-event --email-id <id> --title <title> --action <created|auto_ignored|pending>
#   end-session                Finalize the current session
#   show [--last N]            Show recent activity (default: last session)
#
# Logs to ~/.openclaw/workspace/memory/email-to-calendar/activity.json
# This creates a silent audit trail - use 'show' to display on request

ACTIVITY_FILE="$HOME/.openclaw/workspace/memory/email-to-calendar/activity.json"
CURRENT_SESSION_FILE="$HOME/.openclaw/workspace/memory/email-to-calendar/.current_session.json"

# Ensure directory exists
mkdir -p "$(dirname "$ACTIVITY_FILE")"

# Parse action
ACTION="${1:-}"
shift 2>/dev/null || true

# Parse remaining arguments
EMAIL_ID=""
SUBJECT=""
TITLE=""
REASON=""
EVENT_ACTION=""
LAST_N=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --email-id)
            EMAIL_ID="$2"
            shift 2
            ;;
        --subject)
            SUBJECT="$2"
            shift 2
            ;;
        --title)
            TITLE="$2"
            shift 2
            ;;
        --reason)
            REASON="$2"
            shift 2
            ;;
        --action)
            EVENT_ACTION="$2"
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
    start-session)
        # Create new session
        python3 << 'EOF'
import json
import os
from datetime import datetime

session_file = os.path.expanduser("~/.openclaw/workspace/memory/email-to-calendar/.current_session.json")
os.makedirs(os.path.dirname(session_file), exist_ok=True)

session = {
    "timestamp": datetime.now().isoformat(),
    "emails_scanned": 0,
    "emails_with_events": 0,
    "skipped": [],
    "events_extracted": []
}

with open(session_file, 'w') as f:
    json.dump(session, f, indent=2)

print("Session started")
EOF
        ;;

    log-skip)
        if [ -z "$EMAIL_ID" ] || [ -z "$REASON" ]; then
            echo "Error: --email-id and --reason are required for log-skip" >&2
            exit 1
        fi
        python3 << EOF
import json
import os

session_file = os.path.expanduser("~/.openclaw/workspace/memory/email-to-calendar/.current_session.json")
email_id = "$EMAIL_ID"
subject = "$SUBJECT"
reason = "$REASON"

try:
    with open(session_file, 'r') as f:
        session = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    print("No active session. Call start-session first.", file=__import__('sys').stderr)
    __import__('sys').exit(1)

session['emails_scanned'] = session.get('emails_scanned', 0) + 1
session['skipped'].append({
    "email_id": email_id,
    "subject": subject,
    "reason": reason
})

with open(session_file, 'w') as f:
    json.dump(session, f, indent=2)
EOF
        ;;

    log-event)
        if [ -z "$EMAIL_ID" ] || [ -z "$TITLE" ]; then
            echo "Error: --email-id and --title are required for log-event" >&2
            exit 1
        fi
        python3 << EOF
import json
import os

session_file = os.path.expanduser("~/.openclaw/workspace/memory/email-to-calendar/.current_session.json")
email_id = "$EMAIL_ID"
title = "$TITLE"
event_action = "$EVENT_ACTION" or "pending"
reason = "$REASON"

try:
    with open(session_file, 'r') as f:
        session = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    print("No active session. Call start-session first.", file=__import__('sys').stderr)
    __import__('sys').exit(1)

# Only increment emails_with_events once per email
existing_emails = set(e.get('email_id') for e in session.get('events_extracted', []))
if email_id not in existing_emails:
    session['emails_with_events'] = session.get('emails_with_events', 0) + 1

entry = {
    "email_id": email_id,
    "title": title,
    "action": event_action
}
if reason:
    entry["reason"] = reason

session['events_extracted'].append(entry)

with open(session_file, 'w') as f:
    json.dump(session, f, indent=2)
EOF
        ;;

    end-session)
        # Finalize session and append to activity log
        python3 << 'EOF'
import json
import os
from datetime import datetime

session_file = os.path.expanduser("~/.openclaw/workspace/memory/email-to-calendar/.current_session.json")
activity_file = os.path.expanduser("~/.openclaw/workspace/memory/email-to-calendar/activity.json")

try:
    with open(session_file, 'r') as f:
        session = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    print("No active session to end.")
    import sys
    sys.exit(0)

# Load existing activity log
try:
    with open(activity_file, 'r') as f:
        activity = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    activity = {"sessions": []}

# Add session to log
activity['sessions'].append(session)

# Keep only last 50 sessions to prevent file bloat
activity['sessions'] = activity['sessions'][-50:]

# Save activity log
with open(activity_file, 'w') as f:
    json.dump(activity, f, indent=2)

# Remove current session file
try:
    os.remove(session_file)
except:
    pass

print(f"Session ended: {session.get('emails_scanned', 0)} scanned, {session.get('emails_with_events', 0)} with events, {len(session.get('skipped', []))} skipped")
EOF
        ;;

    show)
        # Show recent activity
        python3 << EOF
import json
import os
import sys
from datetime import datetime

activity_file = os.path.expanduser("~/.openclaw/workspace/memory/email-to-calendar/activity.json")
last_n = int("$LAST_N")

try:
    with open(activity_file, 'r') as f:
        activity = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    print("No activity recorded yet.")
    sys.exit(0)

sessions = activity.get('sessions', [])
if not sessions:
    print("No activity recorded yet.")
    sys.exit(0)

# Get last N sessions
recent = sessions[-last_n:]

for session in recent:
    ts = session.get('timestamp', 'Unknown time')
    try:
        dt = datetime.fromisoformat(ts)
        ts = dt.strftime('%Y-%m-%d %H:%M')
    except:
        pass

    print(f"\n=== Session: {ts} ===")
    print(f"Emails scanned: {session.get('emails_scanned', 0)}")
    print(f"Emails with events: {session.get('emails_with_events', 0)}")

    skipped = session.get('skipped', [])
    if skipped:
        print(f"\nSkipped ({len(skipped)}):")
        for s in skipped:
            subj = s.get('subject', 'Unknown')[:50]
            reason = s.get('reason', 'Unknown reason')
            print(f"  - {subj}")
            print(f"    Reason: {reason}")

    events = session.get('events_extracted', [])
    if events:
        print(f"\nEvents ({len(events)}):")
        for e in events:
            title = e.get('title', 'Untitled')
            action = e.get('action', 'unknown')
            reason = e.get('reason', '')
            print(f"  - {title}")
            print(f"    Action: {action}" + (f" ({reason})" if reason else ""))
EOF
        ;;

    *)
        echo "Usage: activity_log.sh <action> [options]"
        echo ""
        echo "Actions:"
        echo "  start-session              Start a new processing session"
        echo "  log-skip --email-id <id> --subject <sub> --reason <reason>"
        echo "  log-event --email-id <id> --title <title> --action <action> [--reason <reason>]"
        echo "  end-session                Finalize the current session"
        echo "  show [--last N]            Show recent activity (default: last session)"
        exit 1
        ;;
esac

# email-to-calendar Skill Bootstrap

This file contains instructions for self-bootstrapping the skill when installed via ClawHub.

## On First Activation

When this skill is first used, check if the heartbeat includes pending invite checks:

1. Read `~/.openclaw/workspace/HEARTBEAT.md`
2. If it doesn't contain a "Pending Calendar Invites" section, add one

## Heartbeat Section to Add

If the following section is not present in HEARTBEAT.md, add it:

```markdown
## Pending Calendar Invites (email-to-calendar skill)
If pending invites exist (check during email check cycle):
1. Run: `~/.openclaw/workspace/skills/email-to-calendar/scripts/list_pending.sh --summary`
2. If pending invites found with status "pending" and future dates:
   - List them to the user: "You have X pending calendar invite(s) that need your decision:"
   - Present each with: title, date, source email
   - Ask: "Reply with numbers to create, 'all', or 'dismiss' to clear them"
3. Based on user response:
   - Selected numbers: Create events using create_event.sh, update status to "created"
   - 'all': Create all pending events
   - 'dismiss': Update all to status "dismissed"
   - No response: Leave as "pending" for next heartbeat
```

## Self-Check Commands

```bash
# Check if pending invites file exists
PENDING_FILE="$HOME/.openclaw/workspace/memory/email-to-calendar/pending_invites.json"
if [ ! -f "$PENDING_FILE" ]; then
    mkdir -p "$(dirname "$PENDING_FILE")"
    echo '{"invites": []}' > "$PENDING_FILE"
fi

# Check if HEARTBEAT.md includes pending invites section
if ! grep -q "Pending Calendar Invites" "$HOME/.openclaw/workspace/HEARTBEAT.md" 2>/dev/null; then
    echo "HEARTBEAT.md needs pending invites section"
fi
```

## Memory Directories

Ensure these directories exist:
- `~/.openclaw/workspace/memory/email-to-calendar/` - For pending_invites.json and events.json
- `~/.openclaw/workspace/memory/email-extractions/` - For extraction files and index.json

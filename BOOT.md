# email-to-calendar Skill Bootstrap

This file contains instructions for self-bootstrapping the skill when installed via ClawHub.

## On First Activation

When this skill is first used:

### 1. Verify Capabilities

Verify the agent can:
- Read emails (list unread, get message body)
- Create calendar events
- Update/delete calendar events

If any capability is missing, inform the user:
> "This skill requires email and calendar access. Please ensure you have
> the necessary tools configured (e.g., gog CLI, or an MCP server)."

### 2. Check Heartbeat Integration

Read `~/.openclaw/workspace/HEARTBEAT.md` and ensure it contains both:
- "Email Scanning" section
- "Pending Calendar Invites" section

## Heartbeat Sections to Add

If the following sections are not present in HEARTBEAT.md, add them:

```markdown
## Email Scanning (email-to-calendar skill)
During email check cycle (every 4-8 hours):
1. Check for unread emails with event indicators (dates, times, meeting keywords)
2. If events found, extract and present to user for selection
3. Created events are tracked; user can undo within 24 hours
4. Log all scanning activity silently for audit trail
```

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

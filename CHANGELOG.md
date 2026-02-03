# Changelog

## [1.6.0] - 2026-02-02

### Added
- **Smart Onboarding**: Auto-detects Gmail accounts and calendars, presents all 9 settings with smart defaults. User can accept all with Enter or change specific items by number.
- **Silent Activity Log**: All processing activity logged to `activity.json`. Users can ask "what did you skip?" or "show me activity" to see what happened. New script `activity_log.sh`.
- **Event Changelog with Undo**: All calendar changes logged to `changelog.json`. Changes can be undone within 24 hours. New scripts `changelog.sh` and `undo.sh`.
- **Day-of-Week Display**: Events now show day of week for verification (e.g., "Feb 12, Wednesday").
- **LLM-Based Duplicate Matching**: Semantic matching for duplicates instead of simple keyword matching. Explains updates to user.
- **Recurring Event Detection**: Detects patterns like "Every Tuesday at 3pm" and creates appropriate RRULE.
- **Batched Reminders with Dismissal Tracking**: Pending invites are batched, track reminder_count, auto-dismiss after 3 ignored reminders.
- **Orphaned Event Cleanup**: `--validate` flag on `lookup_event.sh` checks if events still exist in calendar and removes orphaned tracking entries.

### Changed
- **Email Search Strategy**: Removed `newer_than:1d` filter to catch stale forwards (old emails forwarded today). Now processes all unread emails and relies on "already processed" check.
- **create_event.sh**: Now logs changes to changelog.json for undo support, captures before/after state for updates.
- **lookup_event.sh**: Added `--validate` flag for orphan cleanup on 404/410.
- **list_pending.sh**: Added `--update-reminded` and `--auto-dismiss` flags, shows day-of-week, tracks reminder_count.
- **SKILL.md**: Major rewrite with smart onboarding flow, activity logging, changelog/undo documentation, LLM matching guidance, recurring event detection.
- **SETUP.md**: Simplified to reflect smart defaults approach.

### Fixed
- Stale forward handling: Old emails forwarded today are now properly processed.
- Orphaned events: Events deleted in Google Calendar are now automatically removed from tracking.

## [1.5.0] - 2026-02-02

### Added
- **Pending Invites Reminder System**: Events that aren't actioned immediately are tracked and resurfaced during heartbeat cycles
- **pending_invites.json**: New tracking file for undispositioned events with status tracking (pending/created/dismissed/expired)
- **list_pending.sh**: Script to list all pending invites (JSON or human-readable summary)
- **update_invite_status.sh**: Script to update event status after user decisions
- **BOOT.md**: Self-bootstrapping instructions for ClawHub installations
- **HEARTBEAT.md integration**: Pending invites are checked during heartbeat cycles

### Changed
- **create_event.sh**: Now automatically updates pending_invites.json when creating events
- **SKILL.md**: Added Steps 5.1 and 5.2 for recording and updating pending invites

## [1.4.0] - 2026-02-02

### Added
- **Selective Selection**: Users can now cherry-pick events by number (e.g., '1, 2, 3'), 'all', or 'none' instead of binary yes/no confirmation
- **Self-Healing Tracking**: When updating an event that was deleted externally (404/410), automatically removes stale tracking entry and creates a new event

### Removed
- **extract_events.py**: Deleted Python extraction script - Agent now extracts events directly using natural language understanding (better accuracy for phrases like "next Tuesday, not this one")

### Changed
- Step 3 (Extract Events) now instructs Agent to extract directly instead of using regex-based script
- Step 5 (Present Items) uses numbered selection UI for better user control

## [1.3.0] - 2026-02-01

### Added
- Event tracking system with `events.json` for efficient updates/deletions
- Tracking scripts: `track_event.sh`, `lookup_event.sh`, `update_tracked_event.sh`, `delete_tracked_event.sh`
- `create_event.sh` now automatically tracks created events
- Email ID tracking to prevent duplicate processing

### Changed
- Duplicate detection now checks local tracking before calendar search

## [1.2.0] - 2026-01-31

### Added
- Direct inbox monitoring mode (scans all emails for events)
- Forwarded email mode (processes forwarded emails only)
- `--send-updates all` flag support for attendee notifications (tonimelisma fork)
- Email handling options (mark read, archive)

## [1.1.0] - 2026-01-30

### Added
- Auto-create and ignore patterns in config
- Multi-day event support with RRULE recurrence
- Attendee support with configurable email list

## [1.0.0] - 2026-01-29

### Added
- Initial release
- Email parsing and event extraction
- Google Calendar integration via gog CLI
- Duplicate detection
- Configuration wizard

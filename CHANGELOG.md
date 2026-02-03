# Changelog

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

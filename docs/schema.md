# Punchcard data format

This is the contract between the macOS app and the planned Tauri app for Windows and Linux.
Both apps read and write the same SQLite file layout, created by the same migration files,
using the same algorithm. Every change to the schema updates this document.

## Location

| OS | Path |
| --- | --- |
| macOS | `~/Library/Application Support/Punchcard/punchcard.sqlite` |
| Linux | `~/.local/share/punchcard/punchcard.sqlite` |
| Windows | `%APPDATA%\Punchcard\punchcard.sqlite` |

SQLite keeps `-wal` and `-shm` files next to it while the database is open.
On macOS both apps use the same path, so they share one file.

## Connection pragmas

Set on every connection, in this order:

```sql
PRAGMA busy_timeout = 2000;
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;
```

Switching a new file to WAL can fail at once with `SQLITE_BUSY` while another connection is
opening it, without waiting on `busy_timeout`. Retry `journal_mode = WAL` on `SQLITE_BUSY`
until the busy timeout has passed.

`foreign_keys` is off by default in SQLite. Without it, a client that has entries can be deleted.

## Migrations

The schema is built by the numbered files in
[`Sources/PunchcardCore/Resources/Migrations`](../Sources/PunchcardCore/Resources/Migrations).
The Tauri app embeds the same files and applies them with the same algorithm.

- Files are named `NNNN_name.sql`: four digits, numbered 1, 2, 3 and so on with no gaps.
  A file never changes once it has been released; later changes go in a new file.
- `PRAGMA user_version` holds the number of the last applied file. It is the only record of
  migration progress. There is no migrations table.
- On open, read `user_version`. If it is higher than the newest file the app knows, refuse to
  open the database ("This database was created by a newer version of Punchcard") and do not
  write to it.
- Otherwise apply each file numbered above `user_version`, in order. Each file runs in its own
  `BEGIN IMMEDIATE` transaction, which also sets `user_version` to the file's number before it
  commits. The files themselves do not set `user_version`.
- Read `user_version` inside that transaction, and skip the file if it is already at or above
  the file's number. Another process opening the same new file at the same time may have applied
  it first.

## Tables (schema version 1)

[`0001_initial.sql`](../Sources/PunchcardCore/Resources/Migrations/0001_initial.sql) is the
exact definition.

All timestamps are UTC instants stored as integer Unix seconds. No time zone is stored.
Grouping by day, week and month uses the viewing computer's calendar and time zone when the
totals are shown. An entry that crosses midnight is stored whole and split when totals are shown.

### `clients`

| Column | Type | Notes |
| --- | --- | --- |
| `id` | INTEGER PRIMARY KEY | |
| `name` | TEXT NOT NULL | Unique ignoring case; must not be blank. See [Client names](#client-names) |
| `archived_at` | INTEGER | When the client was archived; NULL while active |
| `created_at` | INTEGER NOT NULL | |

Migration 1 seeds one client named `Default`.

#### Client names

SQLite's `COLLATE NOCASE` and `trim()` only handle ASCII, so the schema is just a backstop.
Every app must apply this rule before inserting or renaming a client:

1. Trim leading and trailing Unicode whitespace and newlines (`White_Space` characters,
   including tab and no-break space).
2. Normalize to Unicode NFC. Store this result.
3. Refuse the name as blank if it is empty.
4. Refuse the name as a duplicate if it equals the name of any other client under Unicode
   case-insensitive comparison (full case folding of both names, compared as canonically
   equivalent strings). When renaming, the client being renamed does not count, so it can
   change only the case of its own name.

### `entries`

| Column | Type | Notes |
| --- | --- | --- |
| `id` | INTEGER PRIMARY KEY | |
| `client_id` | INTEGER NOT NULL | References `clients(id)`; `ON DELETE RESTRICT` |
| `started_at` | INTEGER NOT NULL | |
| `ended_at` | INTEGER | NULL while the clock runs; never before `started_at` |
| `note` | TEXT NOT NULL | Optional free text, `''` when unused |
| `created_at` | INTEGER NOT NULL | |
| `updated_at` | INTEGER NOT NULL | |
| `is_running` | INTEGER | Generated: `ended_at IS NULL`. Never written |

Rules the database enforces, so neither app re-implements them:

- **One clock at a time.** The partial unique index `entries_one_running` on `is_running` allows
  at most one row with `ended_at IS NULL`. To switch clients, end the running entry and start the
  new one in the same transaction, at the same instant.
- **No negative entries.** A `CHECK` rejects `ended_at < started_at`.
- **No orphaned time.** A client that has entries cannot be deleted; archive it instead.

Indexes: `entries_started_at (started_at)` and `entries_client_started (client_id, started_at)`.

### `settings`

A key/value table: `key TEXT PRIMARY KEY`, `value TEXT NOT NULL`. Every value is text.
A missing key, or a value that does not parse or is out of range, means the default,
so the table only holds settings the user changed.

| Key | Values | Default |
| --- | --- | --- |
| `week_start_day` | `1`..`7`, ISO numbering, 1 = Monday | `1` (Monday) |
| `idle_threshold_seconds` | integer, `60`..`7200`; idle or asleep at least this long asks "keep or drop?" | `600` (10 minutes) |
| `menu_bar_style` | `time` (running time, e.g. `● 1:42`) or `icon` | `time` |
| `onboarded_at` | Unix seconds; set once first-launch tasks have run | absent |

Not stored in the database, on purpose:

- **Launch at login** (on by default). The operating system is the source of truth. The app
  turns it on during first-launch tasks, recorded by `onboarded_at`, and afterwards reads and
  changes it through the OS.
- **The global start/stop shortcut.** It is specific to each platform and kept in that app's own
  preferences.

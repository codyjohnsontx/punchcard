-- Punchcard schema v1. Immutable once released; see docs/schema.md.
-- The migrator runs this file in one transaction and then sets user_version = 1.

CREATE TABLE clients (
  id          INTEGER PRIMARY KEY,
  name        TEXT    NOT NULL UNIQUE COLLATE NOCASE CHECK (length(trim(name)) > 0),
  archived_at INTEGER,                      -- unix seconds; NULL = active
  created_at  INTEGER NOT NULL              -- unix seconds
);

CREATE TABLE entries (
  id          INTEGER PRIMARY KEY,
  client_id   INTEGER NOT NULL REFERENCES clients(id) ON DELETE RESTRICT,
  started_at  INTEGER NOT NULL,             -- unix seconds, UTC instant
  ended_at    INTEGER,                      -- NULL while running
  note        TEXT    NOT NULL DEFAULT '',
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL,
  is_running  INTEGER GENERATED ALWAYS AS (ended_at IS NULL) VIRTUAL,
  CHECK (ended_at IS NULL OR ended_at >= started_at)
);
CREATE INDEX entries_started_at     ON entries(started_at);
CREATE INDEX entries_client_started ON entries(client_id, started_at);
CREATE UNIQUE INDEX entries_one_running ON entries(is_running) WHERE is_running = 1;

CREATE TABLE settings (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

INSERT INTO clients (name, created_at) VALUES ('Default', CAST(strftime('%s','now') AS INTEGER));

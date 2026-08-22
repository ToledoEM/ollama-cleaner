#!/usr/bin/env bash
set -euo pipefail

# Ollama GUI chat-history wipe script (macOS)
# Deletes ONLY chat data (chats/messages/tool_calls/attachments)
# Keeps settings, users, models intact
# Requires typing DELETE to confirm (OLLAMA_FORCE=yes skips the prompt)
# Optional backup (default: backup created)
# script commented by GPT5.3-Codex

# Detect runtime OS once and reuse it.
OS="$(uname -s)"

# Log helper writes to stderr for visibility.
log() { printf '%s\n' "$*" >&2; }

default_db_path() {
  case "$OS" in
    Darwin)
      # Prefer known macOS desktop paths; use the first existing one.
      local candidates=(
        "$HOME/Library/Application Support/Ollama/db.sqlite"
        "$HOME/Library/Containers/com.ollama.app/Data/Library/Application Support/Ollama/db.sqlite"
      )
      local c
      for c in "${candidates[@]}"; do
        if [[ -f "$c" ]]; then
          printf '%s\n' "$c"
          return 0
        fi
      done
      # Fall back to the primary documented path.
      printf '%s\n' "${candidates[0]}"
      ;;
    *)
      log "ERROR: unsupported OS: $OS. This script supports macOS only."
      log "Set OLLAMA_DB=/full/path/to/db.sqlite to override."
      exit 1
      ;;
  esac
}

# Resolve DB path from env override or OS default.
DB="${OLLAMA_DB:-$(default_db_path)}"

should_create_backup() {
  # OLLAMA_BACKUP lets automation skip interactive prompt.
  local choice="${OLLAMA_BACKUP:-}"
  local normalized=""

  if [[ -n "$choice" ]]; then
    # Normalize input so Yes/YES/yes work the same.
    normalized="$(printf '%s' "$choice" | tr '[:upper:]' '[:lower:]')"
    case "$normalized" in
      1|y|yes|true)
        return 0
        ;;
      0|n|no|false)
        return 1
        ;;
      *)
        log "ERROR: OLLAMA_BACKUP must be one of: 1,0,yes,no,true,false"
        exit 1
        ;;
    esac
  fi

  # Ask only when stdin is interactive. Empty answer keeps the safe default (yes).
  if [[ -t 0 ]]; then
    local answer
    printf 'Create DB backup before deleting chats? [Y/n]: ' >&2
    if ! read -r answer; then
      answer=""
    fi
    normalized="$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')"
    case "$normalized" in
      n|no) return 1 ;;
      *) return 0 ;;
    esac
  fi

  # Non-interactive mode defaults to creating a backup.
  return 0
}

confirm_wipe() {
  # OLLAMA_FORCE=1 skips the prompt for automation.
  case "$(printf '%s' "${OLLAMA_FORCE:-}" | tr '[:upper:]' '[:lower:]')" in
    1|y|yes|true) return 0 ;;
  esac

  if [[ ! -t 0 ]]; then
    log "ERROR: refusing to wipe non-interactively. Set OLLAMA_FORCE=yes to proceed."
    exit 1
  fi

  local chats
  chats="$(sqlite3 "$DB" "SELECT COUNT(*) FROM chats;")"
  log "About to permanently delete $chats chat(s) and all their messages from:"
  log "  $DB"
  printf 'Type DELETE to confirm: ' >&2
  local answer
  read -r answer || answer=""
  [[ "$answer" == "DELETE" ]]
}

# ---- Validate DB path ----
if [[ -z "${DB// }" ]]; then
  log "ERROR: database path is empty."
  exit 1
fi

log "OS detected: $OS"
log "Using DB path: $DB"

# ---- Check DB exists ----
if [[ ! -f "$DB" ]]; then
  log "ERROR: db not found: $DB"
  log "If your db is elsewhere, run like:"
  log "  OLLAMA_DB=\"/full/path/to/db.sqlite\" $0"
  exit 1
fi

# ---- Check sqlite3 installed ----
if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "sqlite3 not found."
  echo
  echo "Install sqlite3 with:"
  echo "  macOS  : brew install sqlite"
  exit 1
fi

# ---- Quit Ollama safely ----
# Ignore stop errors if Ollama is already closed.
if [[ "$OS" == "Darwin" ]] && command -v osascript >/dev/null 2>&1; then
  osascript -e 'quit app "Ollama"' >/dev/null 2>&1 || true
  pkill -x Ollama >/dev/null 2>&1 || true
fi
pkill -x ollama >/dev/null 2>&1 || true

# Wait for every Ollama process to actually exit (up to 10s) before touching the DB.
ollama_running() {
  pgrep -x Ollama >/dev/null 2>&1 || pgrep -x ollama >/dev/null 2>&1
}

waited=0
while ollama_running && (( waited < 10 )); do
  sleep 1
  waited=$(( waited + 1 ))
done

if ollama_running; then
  log "ERROR: Ollama is still running. Quit it manually and re-run."
  exit 1
fi

# ---- Validate expected tables ----
# Runs before the confirmation prompt so a malformed DB fails without asking,
# and so the chat count in the prompt is safe to read.
tables="$(sqlite3 "$DB" "SELECT name FROM sqlite_master WHERE type='table';")"

need_table() {
  local t="$1"
  if ! grep -Fqx "$t" <<<"$tables"; then
    log "ERROR: expected table '$t' not found."
    log "Tables present:"
    log "$tables"
    exit 1
  fi
}

for t in chats messages tool_calls attachments; do
  need_table "$t"
done

# ---- Confirm the wipe ----
# Asked before the backup prompt so cancelling costs nothing.
confirm_wipe || { log "Cancelled. Nothing deleted."; exit 0; }

# ---- Optional backup DB ----
if should_create_backup; then
  ts="$(date +%Y%m%d-%H%M%S)"
  bak="${DB}.bak.${ts}"
  cp "$DB" "$bak"
  log "Backup created: $bak"
else
  log "Skipping backup."
fi

# ---- Delete chat history only ----
# Try strict transactional mode first; fall back to compatibility mode if needed.
if ! sqlite3 "$DB" <<'EOF'
PRAGMA foreign_keys=ON;
BEGIN IMMEDIATE;
DELETE FROM attachments;
DELETE FROM tool_calls;
DELETE FROM messages;
DELETE FROM chats;
COMMIT;
EOF
then
  log "WARN: strict delete failed; retrying compatibility delete."
  sqlite3 "$DB" <<'EOF'
DELETE FROM attachments;
DELETE FROM tool_calls;
DELETE FROM messages;
DELETE FROM chats;
EOF
fi

# Keep VACUUM separate for compatibility with more sqlite build/runtime combinations.
# WAL/SHM cleanup only runs if VACUUM succeeded — removing an active WAL that
# still holds committed data would lose it.
if sqlite3 "$DB" "VACUUM;"; then
  for f in "${DB}-wal" "${DB}-shm"; do
    if [[ -e "$f" ]] && ! rm -f "$f"; then
      log "WARN: could not remove $f (still locked) - safe to ignore, SQLite will clean it on next open."
    fi
  done
else
  log "WARN: VACUUM failed; DB is still valid. Leaving WAL/SHM files in place."
fi

log "Done. Chat history wiped from: $DB"
